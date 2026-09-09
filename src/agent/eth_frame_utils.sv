// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— 帧级 <-> XGMII 拍级转换工具
// 职责：
//   1. IEEE 802.3 CRC32（FCS）计算 —— net_packet 的 raw_data 不含 FCS，
//      由本层在发送前追加、接收后校验；
//   2. 帧字节流 -> XGMII 拍序列（preamble/SFD、S 对齐 lane0、T、IPG 填充）；
//   3. 帧装配器 frame_assembler_c：从 XGMII 拍流中还原帧字节并校验
//      preamble/SFD 与 FCS，供 monitor 使用。
// 依赖：pcs_types.sv（xgmii64_t 与控制字符）。
// 所有权：crc32/frame_to_words 为纯函数；frame_assembler_c 每监听方向一个
//         实例，由 monitor 创建并随其存续。
// -----------------------------------------------------------------------------

// 为什么单独一层：帧时序规则（preamble、lane0 对齐、最小 IPG）与 66b 编码
// 正交，两侧（driver 发、monitor 收）必须共享同一实现，否则任何一侧笔误
// 都会以"环回通过但协议错误"的方式漏过检查。

// 以太网帧前导：7 字节 0x55 + 1 字节 SFD 0xD5；线路上首字节被 S 替换
localparam byte unsigned ETH_PREAMBLE = 8'h55;
localparam byte unsigned ETH_SFD      = 8'hd5;

// 最小帧间隙（字节）
localparam int ETH_MIN_IPG = 12;

// IEEE 802.3 CRC32（反射算法，init/xorout 均为 0xFFFFFFFF）。
// 输入为不含 FCS 的帧字节；返回值按 LSB 字节在前追加到帧尾。
function automatic logic [31:0] eth_crc32(byte unsigned data[$]);
  logic [31:0] crc = 32'hffff_ffff;
  foreach (data[i]) begin
    crc ^= {24'h0, data[i]};
    repeat (8) begin
      if (crc[0]) crc = (crc >> 1) ^ 32'hedb8_8320;
      else        crc = (crc >> 1);
    end
  end
  return ~crc;
endfunction

// 帧字节（不含 FCS）-> XGMII 拍序列。
// 输出拍包含：S(lane0)+preamble+SFD、数据与追加的 FCS、T、以及补齐到
// 拍边界的 IDLE；不含额外 IPG 拍（由 BFM 空闲时自然生成）。
// 边界条件：frame 为空时仍产生合法的 preamble+FCS 空帧（调用方通常不会
// 这么用，但保证输出永远是合法码流）。
function automatic void eth_frame_to_words(byte unsigned frame[$],
                                           ref xgmii64_t words[$]);
  byte unsigned line_bytes[$];
  logic [31:0]  fcs;
  int           total;

  // 线路字节序列：S 由第一拍单独处理，此处从 preamble 第 2 字节起
  for (int i = 0; i < 6; i++) line_bytes.push_back(ETH_PREAMBLE);
  line_bytes.push_back(ETH_SFD);
  foreach (frame[i]) line_bytes.push_back(frame[i]);

  fcs = eth_crc32(frame);
  for (int i = 0; i < 4; i++) line_bytes.push_back(fcs[i*8 +: 8]);

  // 第一拍：S + 前 7 个线路字节
  begin
    xgmii64_t w;
    w.ctl = 8'h01;
    w.data[7:0] = XGMII_START;
    for (int i = 0; i < 7; i++) w.data[8 + i*8 +: 8] = line_bytes[i];
    words.push_back(w);
  end

  // 后续拍：8 字节一组，尾拍放 T 并补 IDLE
  total = line_bytes.size();
  begin
    int pos = 7;
    while (pos < total) begin
      xgmii64_t w = xgmii_all_idle();
      int lane = 0;
      while (lane < 8 && pos < total) begin
        w.ctl[lane] = 1'b0;
        w.data[lane*8 +: 8] = line_bytes[pos];
        pos++; lane++;
      end
      if (pos >= total && lane < 8) begin
        // T 紧跟最后一个数据字节
        w.data[lane*8 +: 8] = XGMII_TERM;
        words.push_back(w);
      end
      else if (pos >= total) begin
        // 尾拍恰好填满：T 单独占下一拍 lane0
        xgmii64_t wt = xgmii_all_idle();
        words.push_back(w);
        wt.data[7:0] = XGMII_TERM;
        words.push_back(wt);
      end
      else begin
        words.push_back(w);
      end
    end
  end
endfunction

// 帧装配器：逐拍接收 XGMII，检出帧边界并校验。
// 状态机：IDLE（找 S）-> IN_FRAME（收字节，找 T）。跨拍保存部分帧。
class frame_assembler_c;

  // 一次装配结果：帧字节（不含 preamble/SFD/FCS）+ 各类校验标志
  typedef struct {
    byte unsigned data[$];
    bit crc_ok;
    bit preamble_ok;
  } frame_result_t;

  protected bit           in_frame;
  protected byte unsigned line_bytes[$];   // S 之后、T 之前的全部线路字节

  // 协议完整性统计：monitor 在 check_phase 汇总上报
  int frames_seen;
  int crc_err_count;
  int preamble_err_count;

  function new();
    in_frame = 0;
  endfunction

  // 复位装配状态（统计保留）：链路复位斩断的半帧必须丢弃，否则复位后
  // 首个真帧的字节会被并进残帧、以坏帧形式污染下一段
  function void reset();
    in_frame = 0;
    line_bytes.delete();
  endfunction

  // 推入一拍 XGMII。检出完整帧时返回 1 并填充 res。
  // 失败路径：帧内出现非 T 控制字符（如 ERROR）时丢弃当前帧并复位状态，
  // 计入 CRC 错（线路损伤的统一表现），不中断后续装配。
  function bit push_word(xgmii64_t w, output frame_result_t res);
    for (int lane = 0; lane < 8; lane++) begin
      byte unsigned d = w.data[lane*8 +: 8];
      bit           c = w.ctl[lane];

      if (!in_frame) begin
        // S 允许出现在 lane0 或 lane4（对端 32bit XGMII 内核的两个合法起点）
        if (c && d == XGMII_START && (lane == 0 || lane == 4)) begin
          in_frame = 1;
          line_bytes.delete();
        end
        // 其余字符（IDLE/ERROR/SEQ）在帧外直接忽略
      end
      else begin
        if (!c) begin
          line_bytes.push_back(d);
        end
        else if (d == XGMII_TERM) begin
          bit ok = finalize(res);
          in_frame = 0;
          if (ok) return 1;
          // finalize 失败（帧过短）：res 已带错误标志，同样递交
          return 1;
        end
        else begin
          // 帧内异常控制字符：按损伤帧递交，交由记分板判错
          res.data.delete();
          res.crc_ok      = 0;
          res.preamble_ok = 0;
          frames_seen++;
          crc_err_count++;
          in_frame = 0;
          return 1;
        end
      end
    end
    return 0;
  endfunction

  // 将 line_bytes 拆成 preamble/SFD + 帧 + FCS 并校验。
  // 返回 0 仅当字节数连最小结构都不足（res 仍填充错误标志）。
  protected function bit finalize(output frame_result_t res);
    byte unsigned fcs_bytes[4];
    logic [31:0]  fcs_calc;

    frames_seen++;
    res.data.delete();
    res.preamble_ok = 1;
    res.crc_ok      = 0;

    // 结构下限：6 preamble + SFD + 4 FCS
    if (line_bytes.size() < 11) begin
      res.preamble_ok = 0;
      preamble_err_count++;
      crc_err_count++;
      return 0;
    end

    // preamble/SFD 校验（S 已替换第 1 字节，此处应为 6×0x55 + 0xD5）
    for (int i = 0; i < 6; i++)
      if (line_bytes[i] != ETH_PREAMBLE) res.preamble_ok = 0;
    if (line_bytes[6] != ETH_SFD) res.preamble_ok = 0;
    if (!res.preamble_ok) preamble_err_count++;

    // 帧体与 FCS
    for (int i = 7; i < line_bytes.size() - 4; i++)
      res.data.push_back(line_bytes[i]);
    for (int i = 0; i < 4; i++)
      fcs_bytes[i] = line_bytes[line_bytes.size() - 4 + i];

    fcs_calc  = eth_crc32(res.data);
    res.crc_ok = 1;
    for (int i = 0; i < 4; i++)
      if (fcs_bytes[i] != fcs_calc[i*8 +: 8]) res.crc_ok = 0;
    if (!res.crc_ok) crc_err_count++;

    return 1;
  endfunction

endclass

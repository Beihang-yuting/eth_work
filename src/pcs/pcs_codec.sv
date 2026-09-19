// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 49 64b/66b 编码器与解码器
// 职责：在一拍 XGMII（xgmii64_t）与一个 66b 块（block66_t）之间做无状态
//       双向转换。块型：全数据 / 全 IDLE 控制 / S0 起始 / T0..T7 终止 /
//       序集 0x4B；Clause 49（cl82=0）另有 lane4 起始 0x33、0x66 与序集
//       0x55、0x2D。cl82=1（40G/100G/200G）按 Clause 82：序集 0x4B 的
//       lane4~7 为零数据（ctl 8'h01），Clause 49 专有块型编码为 ERROR 块、
//       解码判非法。其余块型一律解码为 XGMII 错误字符并返回失败。
// 依赖：pcs_types.sv（块类型码与数据结构）。
// 所有权：纯静态函数类，无实例状态；调用方无需管理生命周期。
// -----------------------------------------------------------------------------

// 为什么用无状态静态函数而不是 module：编码规则本身逐块独立，做成纯函数
// 后单元测试可以直接枚举/随机打（XGMII 拍 -> 块 -> XGMII 拍）闭环比对，
// 不需要时钟与复位；时序行为统一放在 phy_bfm 中处理。
class pcs_codec;

  // ---------------- 编码：XGMII 一拍 -> 66b 块 ----------------
  //
  // 输入：w        —— 一拍 64bit XGMII（data + ctl）
  // 输出：返回值   —— 对应的 66b 块
  // 失败路径：无法归入合法模式的组合（如 S 不在 lane0/4、T 后出现数据）
  //           编码为全 ERROR 控制块，不抛断言 —— 保持 BFM 在异常激励下
  //           仍能持续输出码流，错误交由对端解码/记分板暴露。
  static function block66_t encode(xgmii64_t w, bit cl82 = 0);
    block66_t   b;
    int         t_lane;
    logic [3:0] o0, o4;
    bit         lo_idle;

    // 全数据块：8 字节均无控制位
    if (w.ctl == 8'h00) begin
      b.sync    = SYNC_DATA;
      b.payload = w.data;
      return b;
    end

    // 全控制块：8 字节全为控制字符且均为 IDLE
    if (w.ctl == 8'hff) begin
      bit all_idle = 1;
      for (int i = 0; i < 8; i++)
        if (w.data[i*8 +: 8] != XGMII_IDLE) all_idle = 0;
      if (all_idle) begin
        b.sync    = SYNC_CTRL;
        b.payload = {56'h0, BT_CTRL};   // 8 个 CC_IDLE(0) 已隐含为 0
        return b;
      end
    end

    // 帧起始块：lane0 为 START，其余 7 字节为数据
    if (w.ctl == 8'h01 && w.data[7:0] == XGMII_START) begin
      b.sync    = SYNC_CTRL;
      b.payload = {w.data[63:8], BT_START0};
      return b;
    end

    // 序集 lane0 + D1..D3（0x4B）：lane4~7 在 Clause 49 为 IDLE 控制
    //（ctl F1），在 Clause 82 为零数据（ctl 01）；块尾 28bit 均为 0
    b.sync = SYNC_CTRL;
    // Clause 82 只定义 Sequence 有序集（/Q/，O=0），无 /Fsig/
    if (oset_code(w.data[7:0], o0) &&
        (cl82 ? (w.ctl == 8'h01 && w.data[63:32] == 32'h0 && o0 == 4'h0)
              : (w.ctl == 8'hf1 && all_idle(w, 4, 7)))) begin
      b.payload = {28'h0, o0, w.data[31:8], BT_OSET0};
      return b;
    end

    // Clause 49 专有：lane4 起始 / lane4 序集（32bit XGMII 内核的另一起点）
    if (!cl82) begin
      lo_idle = (w.ctl[3:0] == 4'hf) && all_idle(w, 0, 3);
      if (w.ctl == 8'h1f && lo_idle && w.data[39:32] == XGMII_START) begin
        b.payload = {w.data[63:40], 4'h0, 28'h0, BT_START4};           // 0x33
        return b;
      end
      if (w.ctl == 8'h1f && lo_idle && oset_code(w.data[39:32], o4)) begin
        b.payload = {w.data[63:40], o4, 28'h0, BT_OSET4};              // 0x2D
        return b;
      end
      if (w.ctl == 8'h11 && oset_code(w.data[7:0], o0)) begin
        if (w.data[39:32] == XGMII_START) begin
          b.payload = {w.data[63:40], 4'h0, o0, w.data[31:8], BT_OSET0_S4};  // 0x66
          return b;
        end
        if (oset_code(w.data[39:32], o4)) begin
          b.payload = {w.data[63:40], o4, o0, w.data[31:8], BT_OSET2};      // 0x55
          return b;
        end
      end
    end

    // 帧终止块：lane t 为 TERM，之前全数据、之后全 IDLE
    t_lane = -1;
    for (int i = 0; i < 8; i++)
      if (w.ctl[i] && w.data[i*8 +: 8] == XGMII_TERM) begin t_lane = i; break; end

    if (t_lane >= 0) begin
      bit shape_ok = 1;

      // T 之前必须是数据、之后必须是 IDLE 控制字符
      for (int i = 0; i < t_lane; i++)
        if (w.ctl[i]) shape_ok = 0;
      for (int i = t_lane + 1; i < 8; i++)
        if (!w.ctl[i] || w.data[i*8 +: 8] != XGMII_IDLE) shape_ok = 0;

      if (shape_ok) begin
        b.sync    = SYNC_CTRL;
        b.payload = '0;
        b.payload[7:0] = term_bt(t_lane);

        // T 前的数据字节紧跟块类型码放置；T 后 C 码全 0（IDLE），无需填充
        for (int i = 0; i < t_lane; i++)
          b.payload[8 + i*8 +: 8] = w.data[i*8 +: 8];
        return b;
      end
    end

    // 兜底：非法组合编码为全 ERROR 控制块
    return error_block();
  endfunction

  // ---------------- 解码：66b 块 -> XGMII 一拍 ----------------
  //
  // 输入：b         —— 66b 块
  // 输出：w_out     —— 解码出的 XGMII 拍
  // 返回：1 = 块合法；0 = 同步头或块型非法（w_out 置为全 ERROR）。
  //       返回值供 monitor 做协议完整性统计，解码本身不中断。
  // cl82=1：Clause 82 块型集合（无 lane4 起始/序集；0x4B 的 lane4~7 为零数据）
  static function bit decode(block66_t b, output xgmii64_t w_out, input bit cl82 = 0);
    byte unsigned bt;
    int t_lane;
    byte unsigned q0, q4;

    if (b.sync == SYNC_DATA) begin
      w_out.ctl  = 8'h00;
      w_out.data = b.payload;
      return 1;
    end

    if (b.sync != SYNC_CTRL) begin
      w_out = xgmii_all_error();
      return 0;
    end

    bt = b.payload[7:0];

    // 全控制块：仅接受全 IDLE（C 码非 0，含 ERROR C 码，一律按非法块处理）
    if (bt == BT_CTRL) begin
      if (b.payload[63:8] != 56'h0) begin
        w_out = xgmii_all_error();
        return 0;
      end
      w_out = xgmii_all_idle();
      return 1;
    end

    if (bt == BT_START0) begin
      w_out.ctl        = 8'h01;
      w_out.data[7:0]  = XGMII_START;
      w_out.data[63:8] = b.payload[63:8];
      return 1;
    end

    // 序集块（Local/Remote Fault 等）：O 码 0 -> /Q/，F -> /Fsig/（Clause 82 仅 /Q/），其余非法
    if (bt == BT_OSET0) begin
      if (!oset_char(b.payload[35:32], q0) || (cl82 && b.payload[35:32] != 4'h0)) begin
        w_out = xgmii_all_error();
        return 0;
      end
      w_out = xgmii_all_idle();
      w_out.ctl = 8'b1111_0001;
      if (cl82) begin
        w_out.ctl = 8'b0000_0001;
        w_out.data[63:32] = 32'h0;
      end
      w_out.data[7:0]   = q0;
      w_out.data[31:8]  = b.payload[31:8];
      return 1;
    end

    // Clause 49 专有块型（lane4 起始/序集）；Clause 82 下判非法
    if (cl82 && (bt == BT_START4 || bt == BT_OSET4 ||
                 bt == BT_OSET2  || bt == BT_OSET0_S4)) begin
      w_out = xgmii_all_error();
      return 0;
    end

    // 帧起始于 lane4（32bit XGMII 内核对端会交替使用 lane0/lane4 起点）：
    // C0..C3 视为 IDLE，S 落 lane4，D5..D7 取块尾 24bit
    if (bt == BT_START4) begin
      w_out = xgmii_all_idle();
      w_out.ctl = 8'b0001_1111;
      w_out.data[39:32] = XGMII_START;
      w_out.data[63:40] = b.payload[63:40];
      return 1;
    end

    // lane4 序集：C0..C3 视为 IDLE + O4 D5..D7
    if (bt == BT_OSET4) begin
      if (!oset_char(b.payload[39:36], q4)) begin
        w_out = xgmii_all_error();
        return 0;
      end
      w_out = xgmii_all_idle();
      w_out.ctl = 8'b0001_1111;
      w_out.data[39:32] = q4;
      w_out.data[63:40] = b.payload[63:40];
      return 1;
    end

    // O0 D1..D3 + lane4 为 S（0x66）或 O4（0x55），D5..D7 取块尾 24bit
    if (bt == BT_OSET2 || bt == BT_OSET0_S4) begin
      if (!oset_char(b.payload[35:32], q0) ||
          (bt == BT_OSET2 && !oset_char(b.payload[39:36], q4))) begin
        w_out = xgmii_all_error();
        return 0;
      end
      w_out.ctl = 8'b0001_0001;
      w_out.data[7:0]   = q0;
      w_out.data[31:8]  = b.payload[31:8];
      w_out.data[39:32] = (bt == BT_OSET2) ? q4 : XGMII_START;
      w_out.data[63:40] = b.payload[63:40];
      return 1;
    end

    t_lane = term_lane(bt);
    if (t_lane >= 0) begin
      w_out = xgmii_all_idle();
      for (int i = 0; i < t_lane; i++) begin
        w_out.ctl[i]          = 1'b0;
        w_out.data[i*8 +: 8]  = b.payload[8 + i*8 +: 8];
      end
      w_out.data[t_lane*8 +: 8] = XGMII_TERM;
      return 1;
    end

    // 未支持/非法块型
    w_out = xgmii_all_error();
    return 0;
  endfunction

  // ---------------- 内部辅助 ----------------

  // 序集起始字符 -> 4bit O 码（/Q/ -> 0，/Fsig/ -> F）；非序集字符返回 0
  static function bit oset_code(byte unsigned c, output logic [3:0] o);
    o = 4'h0;
    if (c == XGMII_SEQ)  return 1;
    if (c == XGMII_FSIG) begin
      o = 4'hf;
      return 1;
    end
    return 0;
  endfunction

  // 4bit O 码 -> 序集起始字符；保留值返回 0
  static function bit oset_char(logic [3:0] o, output byte unsigned c);
    c = XGMII_ERROR;
    if (o == 4'h0) c = XGMII_SEQ;
    else if (o == 4'hf) c = XGMII_FSIG;
    else return 0;
    return 1;
  endfunction

  // lane lo..hi 全为 IDLE 控制字符
  static function bit all_idle(xgmii64_t w, int lo, int hi);
    for (int i = lo; i <= hi; i++)
      if (!w.ctl[i] || w.data[i*8 +: 8] != XGMII_IDLE) return 0;
    return 1;
  endfunction

  // T 所在 lane -> 块类型码。调用方保证 lane 在 0..7 内。
  static function byte unsigned term_bt(int lane);
    case (lane)
      0: return BT_TERM0;  1: return BT_TERM1;
      2: return BT_TERM2;  3: return BT_TERM3;
      4: return BT_TERM4;  5: return BT_TERM5;
      6: return BT_TERM6;  default: return BT_TERM7;
    endcase
  endfunction

  // 块类型码 -> T 所在 lane；非终止块型返回 -1
  static function int term_lane(byte unsigned bt);
    case (bt)
      BT_TERM0: return 0;  BT_TERM1: return 1;
      BT_TERM2: return 2;  BT_TERM3: return 3;
      BT_TERM4: return 4;  BT_TERM5: return 5;
      BT_TERM6: return 6;  BT_TERM7: return 7;
      default:  return -1;
    endcase
  endfunction

  // 全 ERROR 控制块（编码侧兜底输出；解码侧会将其判为非法块并计数）
  static function block66_t error_block();
    block66_t b;
    b.sync    = SYNC_CTRL;
    b.payload = {56'h0, BT_CTRL};
    for (int i = 0; i < 8; i++)
      b.payload[8 + i*7 +: 7] = CC_ERROR;
    return b;
  endfunction

  // 全 ERROR XGMII 拍（解码侧兜底输出）
  static function xgmii64_t xgmii_all_error();
    xgmii64_t w;
    w.ctl = 8'hff;
    for (int i = 0; i < 8; i++) w.data[i*8 +: 8] = XGMII_ERROR;
    return w;
  endfunction

endclass

// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 36 PCS（1000BASE-X / 2.5GBASE-X）
// 职责：
//   basex_tx_c：每 GMII 字节时钟吐一个 10bit 码组。帧外发 idle 有序集
//     /I/（K28.5 + D16.2，RD+ 时首个用 /I1/=K28.5+D5.6 把 RD 拉回负）；
//     tx_en 上升沿以 /S/(K27.7) 替换首个前导字节；帧内 /D/，tx_er 时 /V/
//     (K30.7)；tx_en 下降后 /T/(K29.7) /R/(K23.7)，必要时再补一个 /R/
//     让后续 idle 落在偶数码组位。
//   basex_rx_c：逐 bit 搜逗号（0011111/1100000）确定码组边界，同步 FSM
//     确认链路后逐码组解码，恢复 GMII 字节流（/S/ 还原为 0x55 前导）。
// 依赖：pcs_8b10b.sv（enc_8b10b / pcs_8b10b_dec_c）。
// 所有权：BFM 在 basex 模式下 TX/RX 各持一个实例；reset() 清状态。
// 偶数位约束的实现（为什么要字节队列）：/S/ 与 /I/ 只能落偶数码组位。
//   tx_en 恰在奇数位拉起时须先补完 idle 的第二个码组，首字节顺延一拍 ——
//   用一个小队列承接顺延，帧后 IPG 的 idle 字节直接丢弃即可吸收掉。
// 简化说明（记 TODO）：Clause 37 自协商（/C/ 配置有序集交换）未实现，
//   上电直接进数据态；同步 FSM 按"3 个无错逗号码组得同步、4 个连续
//   无效码组失同步"简化，未实现规范的 good_cgs 回升计数细节。
// -----------------------------------------------------------------------------

typedef struct packed {
  logic       en;
  logic       er;
  logic [7:0] d;
} gmii_byte_t;

localparam byte unsigned GMII_PREAMBLE = 8'h55;
localparam byte unsigned D16_2 = 8'h50;   // /I2/ 第二码组（保持 RD）
localparam byte unsigned D5_6  = 8'hC5;   // /I1/ 第二码组（纠正 RD）

// ---------------- TX ----------------

class basex_tx_c;

  typedef enum { TX_IDLE, TX_DATA, TX_EPD_R, TX_EPD_R2 } tx_state_e;

  // 统计
  int frames_tx;
  int idle_del_count;

  protected tx_state_e    st;
  protected bit           rd;          // 0 = RD-
  protected bit           odd;         // 当前待发码组位是否为奇数
  protected byte unsigned idle_2nd;    // 本 /I/ 的第二码组（偶数位时决定）
  protected gmii_byte_t   q[$];
  protected int           del_left;    // 剩余要删除（不发）的 idle 码组数

  function new();
    reset();
  endfunction

  function void reset();
    st       = TX_IDLE;
    rd       = 0;
    odd      = 0;
    idle_2nd = D16_2;
    del_left = 0;
    q.delete();
  endfunction

  // 弹性删除请求：仅在帧外、偶数位时删除一整个 /I/（2 个码组）
  function void request_idle_delete();
    if (st == TX_IDLE && !odd && del_left == 0 &&
        !(q.size() > 0 && q[0].en)) begin
      del_left = 2;
      idle_del_count++;
    end
  endfunction

  // 每 GMII 字节时钟调用一次。valid=0 表示本拍被弹性删除（不出码组）。
  function void tick(gmii_byte_t in, output logic [9:0] cg, output bit valid);
    gmii_byte_t b;
    q.push_back(in);
    valid = 1;
    cg    = '0;

    if (del_left > 0) begin
      // 删除中：帧外 idle 字节照常丢弃，不出码组、不推进奇偶
      while (q.size() > 0 && !q[0].en) void'(q.pop_front());
      del_left--;
      valid = 0;
      return;
    end

    case (st)
      TX_IDLE: begin
        while (q.size() > 0 && !q[0].en) void'(q.pop_front());   // 帧外字节
        if (q.size() > 0 && q[0].en && !odd) begin
          void'(q.pop_front());                 // 首个前导字节被 /S/ 替换
          cg = enc_8b10b(K27_7, 1, rd);
          st = TX_DATA;
          frames_tx++;
        end
        else if (!odd) begin
          // /I/ 首码组；RD+ 时本组用 /I1/ 纠回 RD-
          idle_2nd = rd ? D5_6 : D16_2;
          cg = enc_8b10b(K28_5, 1, rd);
        end
        else begin
          cg = enc_8b10b(idle_2nd, 0, rd);
        end
      end

      TX_DATA: begin
        b = q.pop_front();
        if (b.en)
          cg = b.er ? enc_8b10b(K30_7, 1, rd) : enc_8b10b(b.d, 0, rd);
        else begin
          cg = enc_8b10b(K29_7, 1, rd);         // /T/
          st = TX_EPD_R;
        end
      end

      TX_EPD_R: begin
        cg = enc_8b10b(K23_7, 1, rd);           // /R/
        // /T//R/ 之后下一位若为奇数，再补一个 /R/ 让 idle 落偶数位
        st = odd ? TX_IDLE : TX_EPD_R2;
      end

      TX_EPD_R2: begin
        cg = enc_8b10b(K23_7, 1, rd);
        st = TX_IDLE;
      end
    endcase

    odd = ~odd;
  endfunction

endclass

// ---------------- RX ----------------

class basex_rx_c;

  localparam int SYNC_COMMAS = 3;   // 得同步所需的无错逗号码组数
  localparam int LOSS_ERRS   = 4;   // 连续无效码组数达此失同步

  // 统计
  int code_err_count;
  int disp_err_count;
  int realign_count;
  int frames_rx;

  protected logic [9:0] win;          // 最近 10 bit（win[9] 最早）
  protected bit         aligned;
  protected int         bitcnt;       // 对齐后码组内 bit 计数
  protected bit         synced;
  protected int         comma_cnt;
  protected int         bad_run;
  protected bit         rd;
  protected bit         in_frame;

  function new();
    reset();
  endfunction

  function void reset();
    win       = '0;
    aligned   = 0;
    bitcnt    = 0;
    synced    = 0;
    comma_cnt = 0;
    bad_run   = 0;
    rd        = 0;
    in_frame  = 0;
  endfunction

  function bit is_synced();
    return synced;
  endfunction

  // 逐 bit 输入；每解出一个码组返回 1 并给出对应 GMII 字节
  //（同步前的码组只用于建同步，输出恒为帧外）。
  function bit push_bit(logic b, output gmii_byte_t out);
    bit comma_here;

    win = {win[8:0], b};
    comma_here = (win[9:3] == 7'b0011111) || (win[9:3] == 7'b1100000);
    out = '{en:0, er:0, d:8'h00};

    // 逗号出现在当前对齐之外的相位 -> 重新对齐（逗号定码组边界）
    if (comma_here && (!aligned || bitcnt != 9)) begin
      if (aligned) realign_count++;
      aligned = 1;
      bitcnt  = 9;                // 当前窗口恰为一个完整码组
    end

    if (!aligned) return 0;

    if (bitcnt != 9) begin
      bitcnt++;
      return 0;
    end
    bitcnt = 0;

    return decode_cg(win, comma_here, out);
  endfunction

  protected function bit decode_cg(logic [9:0] cg, bit is_comma,
                                   output gmii_byte_t out);
    byte unsigned d;
    bit k, ce, de;

    pcs_8b10b_dec_c::decode(cg, rd, d, k, ce, de);
    out = '{en:0, er:0, d:8'h00};

    if (ce) code_err_count++;
    if (de) disp_err_count++;

    // --- 同步 FSM（简化）---
    if (ce || de) begin
      bad_run++;
      comma_cnt = 0;
      if (bad_run >= LOSS_ERRS) begin
        synced   = 0;
        in_frame = 0;
      end
    end
    else begin
      bad_run = 0;
      if (is_comma && !synced) begin
        comma_cnt++;
        if (comma_cnt >= SYNC_COMMAS) synced = 1;
      end
    end

    if (!synced) return 1;

    // --- 有序集 -> GMII ---
    if (k && d == K27_7) begin
      in_frame = 1;
      out = '{en:1, er:0, d:GMII_PREAMBLE};     // /S/ 还原首个前导字节
    end
    else if (in_frame && !k && !ce) begin
      out = '{en:1, er:de, d:d};
    end
    else if (in_frame && k && d == K30_7) begin
      out = '{en:1, er:1, d:8'h00};             // /V/ 错误传播
    end
    else if (in_frame && k && (d == K29_7 || d == K23_7)) begin
      in_frame = 0;                              // /T/ /R/ 帧结束
      frames_rx++;
    end
    else if (in_frame && (ce || (k && d == K28_5))) begin
      out      = '{en:1, er:1, d:8'h00};         // 帧内损伤：以 rx_er 暴露
      in_frame = 0;
    end
    return 1;
  endfunction

endclass

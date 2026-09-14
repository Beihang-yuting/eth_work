// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 119 PCS（200GBASE-R，8 lane）
// 职责：66b 块流 <-> 8 条 PCS lane 比特流。
//   TX：4 块 -> 256B/257B 转码 -> x^58+x^39+1 自同步加扰（覆盖全部 257bit、
//       跨块连续）-> 每 AM 周期 8 个码字对：首对信息区 = 8×120bit AM +
//       68bit PRBS9 填充 + 36 块，其余每对 40 块 -> RS(544,514) 码字 A/B
//       （信息符号逐个交替）-> 10bit 符号按 (k+l) 奇偶分到 8 lane。
//   RX：各 lane 逐 bit 搜 AM 锁定并识别 lane -> 去偏斜 -> 按对重组 A/B ->
//       RS 纠错 -> 去 AM/填充 -> 解扰 -> 反转码 -> 66b 块。
// 标定来源：以下全部布局均由 svt VIP ETH_200G_SERIAL 实抓码流逐层逆向并
//   验证（RS 伴随式全零、VIP 码字校验位 30/30 复现、解扰后 idle 257bit
//   周期 100% 重复、填充 PRBS9 递推全吻合），不是凭规范记忆：
//   · 10bit 符号 LSB 先上线；lane l 第 k 个符号属码字 A 当且仅当 (k+l)
//     为偶，A/B 各自按"轮次优先、lane 次之"排序：idx = 4k + (l>>1)；
//   · AM 周期 = 16 码字（VIP ccbi_rs_fec_mode_align_timer 默认 16），
//     每 lane 10880bit；AM 为 120bit（CM0-2|UP0|CM3-5|UP1|UM0-2|UP2|UM3-5）；
//   · 68bit 填充 = 连续 PRBS9(x^9+x^5+1) 流，每周期推进 65bit；
//   · 转码：块头位 0=含控制块；4 标志位 1=数据 0=控制；仅第一个控制块的
//     8bit 块类型压成低 4 位（Clause 49 各块类型低半字节唯一）原位替换。
//     "原位替换"已由 svt_200g 交叉证实：VIP 发来 500 个随机长度帧（必含
//     首个控制块位于组内第 2~4 块的组合）全部无损接收。
// 依赖：pcs_types.sv（block66_t）、rs_fec_cl91.sv（rs544_encoder/decoder）。
// 所有权：BFM 在 cl119 模式下 TX/RX 各持一个实例；reset() 清状态。
// -----------------------------------------------------------------------------

localparam int C119_LANES      = 8;
localparam int C119_PAIR_BITS  = 10280;           // 每码字对信息 bit
localparam int C119_LANE_PAIR  = 1360;            // 每码字对每 lane bit
localparam int C119_PAIRS      = 8;               // 每 AM 周期码字对数
localparam int C119_PERIOD     = C119_LANE_PAIR * C119_PAIRS;   // 10880
localparam int C119_HDR_BITS   = 1028;            // 首对 AM 960 + 填充 68

// 各 lane 120bit AM（bit0 = 首个上线位）
localparam logic [119:0] C119_AM[C119_LANES] = '{
  120'h733F4C298CC0B3D6D9B56505264A9A,
  120'h8121A5987EDE5A67D9B56504264A9A,
  120'hA90CC10156F33EFED9B56546264A9A,
  120'h2F7F797BD0808684D9B5655A264A9A,
  120'h0DAED5E6F2512A19D9B565E1264A9A,
  120'h2EB0EDB1D14F124ED9B565F2264A9A,
  120'h5E63BD11A19C42EED9B5653D264A9A,
  120'hA48929CD5B76D632D9B56522264A9A };

// A/B 码字第 i 个符号所在逻辑 lane（k = i>>2；A 在 (k+l) 为偶的 lane）
function automatic int c119_lane_of(bit is_b, int i);
  int k;
  k = i >> 2;
  return 2 * (i & 3) + ((k & 1) ^ is_b);
endfunction

// ---------------- 257b 转码 ----------------

function automatic void c119_transcode_enc(input block66_t b[4],
                                           output logic [256:0] t);
  logic [3:0] is_data;
  int pos, first_c;
  t = '0;
  for (int i = 0; i < 4; i++) is_data[i] = (b[i].sync == SYNC_DATA);
  if (&is_data) begin
    t[0] = 1'b1;
    for (int i = 0; i < 4; i++) t[1 + 64*i +: 64] = b[i].payload;
    return;
  end
  t[0]    = 1'b0;
  t[4:1]  = is_data;
  first_c = -1;
  for (int i = 0; i < 4; i++) if (!is_data[i] && first_c < 0) first_c = i;
  pos = 5;
  for (int i = 0; i < 4; i++) begin
    if (i == first_c) begin
      t[pos +: 4]    = b[i].payload[3:0];      // 块类型低半字节
      t[pos+4 +: 56] = b[i].payload[63:8];
      pos += 60;
    end
    else begin
      t[pos +: 64] = b[i].payload;
      pos += 64;
    end
  end
endfunction

// 块类型低半字节 -> 完整 8bit 块类型（Clause 49 合法类型低半字节唯一）
function automatic byte unsigned c119_bt_from_nibble(logic [3:0] n);
  case (n)
    4'hE: return 8'h1E;  4'hD: return 8'h2D;  4'h3: return 8'h33;
    4'h6: return 8'h66;  4'h5: return 8'h55;  4'h8: return 8'h78;
    4'hB: return 8'h4B;  4'h7: return 8'h87;  4'h9: return 8'h99;
    4'hA: return 8'hAA;  4'h4: return 8'hB4;  4'hC: return 8'hCC;
    4'h2: return 8'hD2;  4'h1: return 8'hE1;  4'hF: return 8'hFF;
    default: return 8'h00;
  endcase
endfunction

function automatic void c119_transcode_dec(input logic [256:0] t,
                                           output block66_t b[4]);
  logic [3:0] is_data;
  int pos, first_c;
  if (t[0]) begin
    for (int i = 0; i < 4; i++) begin
      b[i].sync    = SYNC_DATA;
      b[i].payload = t[1 + 64*i +: 64];
    end
    return;
  end
  is_data = t[4:1];
  first_c = -1;
  for (int i = 0; i < 4; i++) if (!is_data[i] && first_c < 0) first_c = i;
  pos = 5;
  for (int i = 0; i < 4; i++) begin
    b[i].sync = is_data[i] ? SYNC_DATA : SYNC_CTRL;
    if (i == first_c) begin
      b[i].payload = {t[pos+4 +: 56], c119_bt_from_nibble(t[pos +: 4])};
      pos += 60;
    end
    else begin
      b[i].payload = t[pos +: 64];
      pos += 64;
    end
  end
endfunction

// ---------------- 257b 自同步加扰（x^58+x^39+1，逐 bit）----------------

class c119_scrambler_c;
  protected logic [57:0] st;   // st[0] = 最近一位加扰输出
  function new(); st = '1; endfunction
  function void reset(); st = '1; endfunction
  function logic [256:0] scramble(logic [256:0] d);
    logic [256:0] o;
    for (int i = 0; i < 257; i++) begin
      o[i] = d[i] ^ st[38] ^ st[57];
      st   = {st[56:0], o[i]};
    end
    return o;
  endfunction
  function logic [256:0] descramble(logic [256:0] s);
    logic [256:0] o;
    for (int i = 0; i < 257; i++) begin
      o[i] = s[i] ^ st[38] ^ st[57];
      st   = {st[56:0], s[i]};
    end
    return o;
  endfunction
endclass

// ---------------- TX ----------------

class c119_tx_c;

  // 输出：各逻辑 lane 本次产出的比特（BFM 取走入串行队列）
  logic out_bits[C119_LANES][$];

  int pairs_tx;

  protected block66_t        grp[$];
  protected logic            msg[$];        // 当前码字对的信息 bit
  protected int              pair_idx;      // 0..7（0 = 带 AM 的首对）
  protected logic [8:0]      prbs9;
  protected c119_scrambler_c scr;
  protected rs544_encoder_c  enc;

  function new();
    scr = new();
    enc = new();
    reset();
  endfunction

  function void reset();
    grp.delete();
    msg.delete();
    pair_idx = 0;
    prbs9    = 9'h1FF;
    scr.reset();
    foreach (out_bits[l]) out_bits[l].delete();
    start_pair();
  endfunction

  // 首对开头放 AM（按 A/B 交替 + lane 映射排进信息区）与 68bit PRBS9
  protected function void start_pair();
    rs91_sym_t  sym;
    logic [8:0] p;
    logic       fb;
    bit         is_b;
    int         i, k, l;
    msg.delete();
    if (pair_idx != 0) return;
    for (int s = 0; s < 96; s++) begin
      is_b = s & 1;
      i    = s >> 1;
      k    = i >> 2;
      l    = c119_lane_of(is_b, i);
      sym  = C119_AM[l][10*k +: 10];
      for (int j = 0; j < 10; j++) msg.push_back(sym[j]);
    end
    p = prbs9;
    for (int j = 0; j < 68; j++) begin
      fb = p[8] ^ p[4];
      msg.push_back(p[8]);
      p = {p[7:0], fb};
      if (j == 64) prbs9 = p;          // 每周期推进 65bit
    end
  endfunction

  // 输入一个 66b 块（未加扰）。凑满 4 块转码；信息区满一对即编码分发，
  // 返回 1 表示 out_bits 有新产出。
  function bit push_block(block66_t b);
    block66_t     g4[4];
    logic [256:0] t;
    grp.push_back(b);
    if (grp.size() < 4) return 0;
    for (int i = 0; i < 4; i++) g4[i] = grp[i];
    grp.delete();
    c119_transcode_enc(g4, t);
    t = scr.scramble(t);
    for (int i = 0; i < 257; i++) msg.push_back(t[i]);
    if (msg.size() < C119_PAIR_BITS) return 0;
    emit_pair();
    return 1;
  endfunction

  protected function void emit_pair();
    rs91_sym_t da[514], db[514], ca[544], cb[544], sym, va, vb;
    int        idx;
    for (int i = 0; i < 514; i++) begin
      for (int j = 0; j < 10; j++) begin
        va[j] = msg[(2*i)*10 + j];
        vb[j] = msg[(2*i+1)*10 + j];
      end
      da[i] = va;
      db[i] = vb;
    end
    enc.encode(da, ca);
    enc.encode(db, cb);
    for (int l = 0; l < C119_LANES; l++)
      for (int k = 0; k < 136; k++) begin
        idx = 4*k + (l >> 1);
        sym = ((k + l) % 2 == 0) ? ca[idx] : cb[idx];
        for (int j = 0; j < 10; j++) out_bits[l].push_back(sym[j]);
      end
    pairs_tx++;
    pair_idx = (pair_idx + 1) % C119_PAIRS;
    start_pair();
  endfunction

endclass

// ---------------- RX ----------------

class c119_rx_c;

  // 统计
  int am_locks;
  int rs_uncorrectable;
  int realign_count;

  protected logic            win[C119_LANES][$];  // 各物理 lane 最近 120bit
  protected bit              lane_lock[C119_LANES];
  protected int              lane_id[C119_LANES]; // 物理 lane -> 逻辑 lane
  protected logic            q[C119_LANES][$];    // 锁定后自 AM 起的比特
  protected bit              aligned;
  protected int              pair_idx;
  protected block66_t        out_q[$];
  protected c119_scrambler_c descr;
  protected rs544_decoder_c  dec;
  protected bit              warm;          // 对齐后首个 257b 组待丢弃
  int                        dbg_left = 0;   // >0 时打印前 N 对的 RS 结果

  function new();
    descr = new();
    dec   = new();
    reset();
  endfunction

  function void reset();
    foreach (win[l]) win[l].delete();
    foreach (q[l]) q[l].delete();
    foreach (lane_lock[l]) lane_lock[l] = 0;
    foreach (lane_id[l]) lane_id[l] = -1;
    aligned  = 0;
    pair_idx = 0;
    out_q.delete();
    descr.reset();
  endfunction

  function bit is_aligned();
    return aligned;
  endfunction

  function int rs_corrected();
    return dec.corrected_count;
  endfunction

  // 窗口是否为某 lane 的 AM；返回逻辑 lane 或 -1
  protected function int match_am(int pl);
    logic [119:0] w;
    for (int i = 0; i < 120; i++) w[i] = win[pl][i];
    for (int l = 0; l < C119_LANES; l++) if (w == C119_AM[l]) return l;
    return -1;
  endfunction

  // 物理 lane pl 收到 1 bit
  function void push_bit(int pl, logic b);
    int id;
    if (!lane_lock[pl]) begin
      win[pl].push_back(b);
      if (win[pl].size() > 120) void'(win[pl].pop_front());
      if (win[pl].size() == 120) begin
        id = match_am(pl);
        if (id >= 0) begin
          lane_lock[pl] = 1;
          lane_id[pl]   = id;
          q[pl].delete();
          foreach (win[pl][i]) q[pl].push_back(win[pl][i]);   // 自 AM 起
          win[pl].delete();
          am_locks++;
          try_align();
        end
      end
      return;
    end
    q[pl].push_back(b);
    if (aligned) pump();
  endfunction

  // 全 lane 锁定后去偏斜：各 lane 队列都从 AM 起，比最短者长出半周期
  // 以上的 lane 锚在了更早的 AM，丢弃整周期直至全部落在同一周期
  protected function void try_align();
    int mn, mx;
    foreach (lane_lock[l]) if (!lane_lock[l]) return;
    forever begin
      mn = q[0].size();
      mx = mn;
      foreach (q[l]) begin
        if (q[l].size() < mn) mn = q[l].size();
        if (q[l].size() > mx) mx = q[l].size();
      end
      if (mx - mn < C119_PERIOD / 2) break;
      foreach (q[l])
        if (q[l].size() - mn >= C119_PERIOD / 2)
          repeat (C119_PERIOD) void'(q[l].pop_front());
    end
    aligned  = 1;
    pair_idx = 0;
    warm     = 1;       // 解扰器状态须先吃进 58bit，首组必为乱码
    descr.reset();
    pump();
  endfunction

  // 周期起点核对：各 lane 队首 120bit 应为本 lane AM；不符说明滑位，
  // 整体重锁（在途数据丢弃，由上层按丢帧暴露）
  protected function bit check_am_boundary();
    logic [119:0] w;
    for (int pl = 0; pl < C119_LANES; pl++) begin
      for (int i = 0; i < 120; i++) w[i] = q[pl][i];
      if (w != C119_AM[lane_id[pl]]) return 0;
    end
    return 1;
  endfunction

  // 各 lane 均攒够一对（1360bit）即解一对
  protected function void pump();
    forever begin
      foreach (q[l]) if (q[l].size() < C119_LANE_PAIR) return;
      if (pair_idx == 0 && !check_am_boundary()) begin
        realign_count++;
        foreach (win[l]) win[l].delete();
        foreach (q[l]) q[l].delete();
        foreach (lane_lock[l]) lane_lock[l] = 0;
        aligned = 0;
        return;
      end
      decode_pair();
    end
  endfunction

  protected function void decode_pair();
    rs91_sym_t    ca[544], cb[544], sym;
    logic         msg[C119_PAIR_BITS];
    int           lid, idx, start;
    logic [256:0] t;
    block66_t     g4[4];
    bit           oka, okb;

    for (int pl = 0; pl < C119_LANES; pl++) begin
      lid = lane_id[pl];
      for (int k = 0; k < 136; k++) begin
        for (int j = 0; j < 10; j++) sym[j] = q[pl].pop_front();
        idx = 4*k + (lid >> 1);
        if ((k + lid) % 2 == 0) ca[idx] = sym;
        else                    cb[idx] = sym;
      end
    end

    oka = dec.decode(ca);
    okb = dec.decode(cb);
    if (!(oka && okb)) rs_uncorrectable++;
    if (dbg_left > 0) begin
      dbg_left--;
      $display("[C119_RX] @%0t pair=%0d rsA=%0b rsB=%0b lane_id=%p", $time,
               pair_idx, oka, okb, lane_id);
    end

    for (int i = 0; i < 514; i++)
      for (int j = 0; j < 10; j++) begin
        msg[(2*i)*10 + j]   = ca[i][j];
        msg[(2*i+1)*10 + j] = cb[i][j];
      end

    start = (pair_idx == 0) ? C119_HDR_BITS : 0;
    for (int b = start; b + 257 <= C119_PAIR_BITS; b += 257) begin
      for (int i = 0; i < 257; i++) t[i] = msg[b + i];
      t = descr.descramble(t);
      if (warm) begin
        warm = 0;
        continue;
      end
      c119_transcode_dec(t, g4);
      for (int i = 0; i < 4; i++) out_q.push_back(g4[i]);
    end
    pair_idx = (pair_idx + 1) % C119_PAIRS;
  endfunction

  function bit pop_block(output block66_t b);
    if (out_q.size() == 0) return 0;
    b = out_q.pop_front();
    return 1;
  endfunction

endclass

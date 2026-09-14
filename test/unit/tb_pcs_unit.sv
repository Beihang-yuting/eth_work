// -----------------------------------------------------------------------------
// 所属：eth_work/test/unit —— PCS/FEC/帧工具 非 UVM 自校验单元测试
// 职责：不经时钟接口，直接调用各层纯函数/类验证：
//   1. 64b/66b 编码->解码闭环（idle/start/data/各 T 位置）
//   2. 扰码->解扰闭环
//   3. 块同步：任意 bit 相位下锁定并还原块流
//   4. FEC：编码->注 burst（<=11bit 可纠 / >11bit 不可纠）->解码
//   5. 帧 -> XGMII 拍 -> 帧装配闭环（含 CRC 校验）
// 失败即 $fatal；全部通过打印 UNIT_TEST_PASS 供 Makefile 判定。
// 依赖：eth_pcs_pkg。
// 所有权：独立仿真 top，进程级生命周期。
// -----------------------------------------------------------------------------

module tb_pcs_unit;

  import uvm_pkg::*;
  import eth_pcs_pkg::*;

  int test_count = 0;

  // 统一判定：失败立刻终止，保留现场信息
  task automatic check(string name, bit cond);
    test_count++;
    if (!cond) $fatal(1, "[FAIL] %s", name);
  endtask

  // 生成一个合法的随机 XGMII 拍（供编码闭环测试）
  function automatic xgmii64_t random_legal_word();
    xgmii64_t w;
    int kind = $urandom_range(0, 3);

    case (kind)
      0: w = xgmii_all_idle();
      1: begin // 起始拍
        w.ctl = 8'h01;
        w.data[7:0] = XGMII_START;
        for (int i = 1; i < 8; i++) w.data[i*8 +: 8] = $urandom;
      end
      2: begin // 全数据拍
        w.ctl = 8'h00;
        w.data = {$urandom, $urandom};
      end
      default: begin // 终止拍，T 位置随机
        int t = $urandom_range(0, 7);
        w = xgmii_all_idle();
        for (int i = 0; i < t; i++) begin
          w.ctl[i] = 1'b0;
          w.data[i*8 +: 8] = $urandom;
        end
        w.data[t*8 +: 8] = XGMII_TERM;
      end
    endcase
    return w;
  endfunction

  // 1. 编码闭环
  task automatic test_codec();
    repeat (2000) begin
      xgmii64_t w_in = random_legal_word();
      xgmii64_t w_out;
      block66_t b = pcs_codec::encode(w_in);
      check("codec: decode ok", pcs_codec::decode(b, w_out));
      check("codec: roundtrip", w_out == w_in);
    end
    $display("[OK] codec roundtrip x2000");
  endtask

  // 2. 扰码闭环
  task automatic test_scrambler();
    scrambler_c   s = new();
    descrambler_c d = new();
    repeat (1000) begin
      logic [63:0] din = {$urandom, $urandom};
      check("scrambler: roundtrip", d.descramble(s.scramble(din)) == din);
    end
    $display("[OK] scrambler roundtrip x1000");
  endtask

  // 3. 块同步：随机相位前缀 + 扰码 idle/data 流，锁定后块须逐一还原
  task automatic test_block_sync();
    scrambler_c  s = new();
    block_sync_c bs = new();
    block66_t    sent[$];
    block66_t    got[$];
    int          prefix = $urandom_range(1, 65);

    // 随机前缀 bit（模拟任意起始相位）
    begin
      block66_t dummy;
      repeat (prefix) void'(bs.push_bit($urandom_range(0, 1), dummy));
    end

    // 500 个扰码后的块
    repeat (500) begin
      xgmii64_t w = ($urandom_range(0, 1)) ? xgmii_all_idle()
                                           : '{ctl: 8'h00, data: {$urandom, $urandom}};
      block66_t b = pcs_codec::encode(w);
      b.payload = s.scramble(b.payload);
      sent.push_back(b);

      // 同步头发送顺序与 phy_bfm 一致：先 sync[1] 后 sync[0]
      for (int i = 1; i >= 0; i--) begin
        block66_t ob;
        if (bs.push_bit(b.sync[i], ob) && bs.is_locked()) got.push_back(ob);
      end
      for (int i = 0; i < 64; i++) begin
        block66_t ob;
        if (bs.push_bit(b.payload[i], ob) && bs.is_locked()) got.push_back(ob);
      end
    end

    check("bsync: locked", bs.is_locked());
    check("bsync: delivered blocks", got.size() > 300);

    // 锁定后交付的块必须是 sent 的连续子序列：找到首块对齐点逐一比对
    begin
      int base = -1;
      foreach (sent[i])
        if (sent[i] == got[0]) begin base = i; break; end
      check("bsync: alignment found", base >= 0);
      for (int i = 0; i < got.size() && (base + i) < sent.size(); i++)
        check("bsync: block match", got[i] == sent[base + i]);
    end
    $display("[OK] block sync, prefix=%0d slips=%0d", prefix, bs.slip_count);
  endtask

  // 4. FEC：干净锁定 -> 可纠 burst -> 不可纠 burst
  task automatic test_fec();
    fec_cl74_encoder_c enc = new();
    fec_cl74_decoder_c dec = new();
    scrambler_c        s   = new();
    block66_t          sent[$];
    block66_t          got[$];
    logic              cw[FEC_N];
    block66_t          blks[FEC_BLOCKS];

    // 3 个干净码字：前 2 个用于锁定，第 3 个验证透传
    repeat (3 * FEC_BLOCKS) begin
      xgmii64_t w = ($urandom_range(0, 1)) ? xgmii_all_idle()
                                           : '{ctl: 8'h00, data: {$urandom, $urandom}};
      block66_t b = pcs_codec::encode(w);
      b.payload = s.scramble(b.payload);
      sent.push_back(b);
      if (enc.push_block(b, cw))
        for (int i = 0; i < FEC_N; i++)
          if (dec.push_bit(cw[i], blks))
            for (int k = 0; k < FEC_BLOCKS; k++) got.push_back(blks[k]);
    end

    check("fec: locked after clean codewords", dec.is_locked());
    check("fec: clean blocks count", got.size() == sent.size());
    foreach (sent[i]) check("fec: clean block match", got[i] == sent[i]);

    // 可纠：burst <= 11bit
    repeat (5) begin
      int burst_len = $urandom_range(2, FEC_BURST);
      int pos = $urandom_range(0, FEC_N - burst_len);
      int corr_before = dec.corrected_count;
      block66_t sent2[$];

      got.delete();
      repeat (FEC_BLOCKS) begin
        xgmii64_t w = '{ctl: 8'h00, data: {$urandom, $urandom}};
        block66_t b = pcs_codec::encode(w);
        b.payload = s.scramble(b.payload);
        sent2.push_back(b);
        void'(enc.push_block(b, cw));
      end

      // 注入连续 burst（首尾必错，中间随机）
      cw[pos] = ~cw[pos];
      cw[pos + burst_len - 1] = ~cw[pos + burst_len - 1];
      for (int i = 1; i < burst_len - 1; i++)
        if ($urandom_range(0, 1)) cw[pos + i] = ~cw[pos + i];

      for (int i = 0; i < FEC_N; i++)
        if (dec.push_bit(cw[i], blks))
          for (int k = 0; k < FEC_BLOCKS; k++) got.push_back(blks[k]);

      check("fec: corrected", dec.corrected_count == corr_before + 1);
      check("fec: corrected size", got.size() == sent2.size());
      foreach (sent2[i]) check("fec: corrected block match", got[i] == sent2[i]);
    end

    // 不可纠：两个远距 burst（等效长度 > 11）
    begin
      int uncorr_before = dec.uncorrectable_count;
      repeat (FEC_BLOCKS) begin
        xgmii64_t w = '{ctl: 8'h00, data: {$urandom, $urandom}};
        block66_t b = pcs_codec::encode(w);
        b.payload = s.scramble(b.payload);
        void'(enc.push_block(b, cw));
      end
      cw[100] = ~cw[100];
      cw[101] = ~cw[101];
      cw[1500] = ~cw[1500];
      cw[1501] = ~cw[1501];
      for (int i = 0; i < FEC_N; i++)
        if (dec.push_bit(cw[i], blks)) ;
      check("fec: uncorrectable detected",
            dec.uncorrectable_count == uncorr_before + 1);
    end

    $display("[OK] fec encode/correct/uncorrectable");
  endtask

  // 5. 帧 <-> XGMII 闭环
  task automatic test_frame_utils();
    frame_assembler_c asm = new();
    repeat (50) begin
      byte unsigned frame[$];
      xgmii64_t     words[$];
      frame_assembler_c::frame_result_t tmp;
      frame_assembler_c::frame_result_t res;
      bit           got_frame = 0;
      int           len = $urandom_range(60, 1518);

      frame.delete();
      repeat (len) frame.push_back($urandom);

      eth_frame_to_words(frame, words);
      words.push_back(xgmii_all_idle());   // 帧后 IPG

      // 注意：output 参数每次调用都会拷出，返回 0 的调用会覆盖 tmp，
      // 因此命中时必须立即另存
      foreach (words[i])
        if (asm.push_word(words[i], tmp)) begin
          got_frame = 1;
          res = tmp;
        end

      check("frame: assembled", got_frame);
      check("frame: crc ok", res.crc_ok);
      check("frame: preamble ok", res.preamble_ok);
      check("frame: len", res.data.size() == len);
      foreach (frame[i]) check("frame: byte match", res.data[i] == frame[i]);
    end
    $display("[OK] frame utils roundtrip x50");
  endtask

  // 6. MLD：4 lane 分发 -> 注入偏斜 + 物理乱接 -> 识别/去偏/重组闭环
  task automatic test_mld();
    localparam int LANES = 4;
    localparam int SPACING = 64;

    mld_tx_c tx = new(LANES, SPACING);
    mld_rx_c rx = new(LANES, SPACING);

    block66_t sent[$];
    block66_t got[$];
    block66_t lane_stream[LANES][$];
    int       perm[LANES] = '{2, 0, 3, 1};   // 逻辑->物理乱接映射
    int       skew[LANES] = '{0, 3, 7, 12};  // 各物理 lane 起始偏斜（块）
    int       cursor[LANES];
    int       remaining;

    // TX：2000 个随机块经分发（AM 由 TX 自插）
    repeat (2000) begin
      block66_t b;
      int lane;
      bit am_v;
      block66_t am_b;

      b.sync    = ($urandom_range(0, 1)) ? SYNC_DATA : SYNC_CTRL;
      b.payload = {$urandom, $urandom};
      // 规避随机控制块撞 AM 图案（低 24bit 置固定非 AM 值）
      if (b.sync == SYNC_CTRL) b.payload[23:0] = 24'h5A5A5A;

      sent.push_back(b);
      tx.push_block(b, lane, am_v, am_b);
      if (am_v) lane_stream[perm[lane]].push_back(am_b);
      lane_stream[perm[lane]].push_back(b);
    end

    // 投递：lane p 在全网累计投出 < skew[p] 块前按兵不动（起始偏斜），
    // 之后各 lane 随机交错推进 —— 模拟去偏斜必须处理的到达差
    foreach (cursor[i]) cursor[i] = 0;
    remaining = 0;
    foreach (lane_stream[i]) remaining += lane_stream[i].size();

    while (remaining > 0) begin
      int p = $urandom_range(0, LANES - 1);
      int total_delivered = 0;
      block66_t ob;

      for (int j = 0; j < LANES; j++) total_delivered += cursor[j];
      if (total_delivered < skew[p]) continue;
      if (cursor[p] >= lane_stream[p].size()) continue;

      rx.push_block(p, lane_stream[p][cursor[p]]);
      cursor[p]++;
      remaining--;

      while (rx.pop_block(ob)) got.push_back(ob);
    end

    begin
      block66_t ob;
      while (rx.pop_block(ob)) got.push_back(ob);
    end

    check("mld: aligned", rx.is_aligned());
    check("mld: no realign", rx.realign_count == 0);
    check("mld: bip clean", rx.bip_err_count == 0);
    check("mld: got count", got.size() == sent.size());
    foreach (got[i]) check("mld: block order", got[i] == sent[i]);
    $display("[OK] mld distribute/deskew/reassemble x%0d (skew+lane-swap)",
             sent.size());
  endtask

  // 6b. MLD 100G：20 lane（表 82-3 AM）+ 随机物理乱接 + 随机偏斜闭环
  task automatic test_mld100();
    localparam int LANES = 20;
    localparam int SPACING = 64;

    mld_tx_c tx = new(LANES, SPACING);
    mld_rx_c rx = new(LANES, SPACING);

    block66_t sent[$];
    block66_t got[$];
    block66_t lane_stream[LANES][$];
    int       perm[LANES];
    int       skew[LANES];
    int       cursor[LANES];
    int       remaining, total_delivered, p, lane, j, k, tmp;
    bit       am_v;
    block66_t b, am_b, ob;

    // 随机置换（Fisher-Yates）+ 随机起始偏斜
    for (j = 0; j < LANES; j++) perm[j] = j;
    for (j = LANES - 1; j > 0; j--) begin
      k = $urandom_range(0, j);
      tmp = perm[j]; perm[j] = perm[k]; perm[k] = tmp;
    end
    for (j = 0; j < LANES; j++) skew[j] = $urandom_range(0, 30);

    repeat (8000) begin
      b.sync    = ($urandom_range(0, 1)) ? SYNC_DATA : SYNC_CTRL;
      b.payload = {$urandom, $urandom};
      if (b.sync == SYNC_CTRL) b.payload[23:0] = 24'h5A5A5A;
      sent.push_back(b);
      tx.push_block(b, lane, am_v, am_b);
      if (am_v) lane_stream[perm[lane]].push_back(am_b);
      lane_stream[perm[lane]].push_back(b);
    end

    foreach (cursor[i]) cursor[i] = 0;
    remaining = 0;
    foreach (lane_stream[i]) remaining += lane_stream[i].size();

    while (remaining > 0) begin
      p = $urandom_range(0, LANES - 1);
      total_delivered = 0;
      for (j = 0; j < LANES; j++) total_delivered += cursor[j];
      if (total_delivered < skew[p]) continue;
      if (cursor[p] >= lane_stream[p].size()) continue;
      rx.push_block(p, lane_stream[p][cursor[p]]);
      cursor[p]++;
      remaining--;
      while (rx.pop_block(ob)) got.push_back(ob);
    end
    while (rx.pop_block(ob)) got.push_back(ob);

    check("mld100: aligned", rx.is_aligned());
    check("mld100: no realign", rx.realign_count == 0);
    check("mld100: bip clean", rx.bip_err_count == 0);
    check("mld100: got count", got.size() == sent.size());
    foreach (got[i]) check("mld100: block order", got[i] == sent[i]);
    $display("[OK] mld100 20 lane distribute/deskew/reassemble x%0d (随机乱接+偏斜)",
             sent.size());
  endtask

  // AN cl73 DME：TX 生成的电平序列经 RX 解回原页（含随机页内容）；
  // 再验仲裁 FSM 在两实例对打下双向进入 DONE
  task test_an73();
    an73_dme_tx_c tx = new();
    an73_dme_rx_c rx = new();
    logic [47:0] pages[$];
    logic [47:0] got[$];
    logic [47:0] pg;
    an73_engine_c ea = new();
    an73_engine_c eb = new();
    logic lvl;
    logic la, lb, na, nb;
    int guard;

    // --- DME 自环：连发 6 页随机内容 ---
    for (int p = 0; p < 6; p++) begin
      logic [47:0] v = {$urandom, $urandom} & 48'hFFFF_FFFF_FFFF;
      pages.push_back(v);
    end

    // 注意：module 内 task 默认 static，循环体内"声明带初值"只在 0 时刻
    // 求值一次（曾因此让 tx_tick 全程只被调用 3 次）—— 声明与赋值必须分开
    foreach (pages[p]) begin
      tx.page = pages[p];
      for (int t = 0; t < AN73_PAGE_TICKS; t++) begin
        lvl = tx.tx_tick();
        if (rx.rx_tick(lvl, pg)) got.push_back(pg);
      end
    end

    // 首页可能因起始定界未建立而漏解，其余必须逐位还原
    check("an73: dme pages decoded", got.size() >= pages.size() - 2);
    begin
      int off = pages.size() - got.size();
      for (int i = 0; i < got.size(); i++)
        check("an73: dme page content", got[i] == pages[off + i]);
    end
    $display("[OK] an73 DME roundtrip x%0d pages", got.size());

    // --- 仲裁对打：A/B 两实例线上互连，等双方 DONE ---
    ea.nonce = 5'h05;
    eb.nonce = 5'h12;
    ea.reset();
    eb.reset();
    la = 0;
    lb = 0;
    guard = 0;
    while (!(ea.is_done() && eb.is_done()) && guard < AN73_PAGE_TICKS * 80) begin
      na = ea.tx_tick();
      nb = eb.tx_tick();
      ea.rx_tick(lb);
      eb.rx_tick(la);
      la = na;
      lb = nb;
      guard++;
    end
    check("an73: A done", ea.is_done());
    check("an73: B done", eb.is_done());
    $display("[OK] an73 arbitration A=%s B=%s pages=%0d/%0d",
             ea.state_name(), eb.state_name(), ea.pages_seen, eb.pages_seen);
  endtask

  // Clause 72 链路训练：训练帧字段自环 + 双引擎对训收敛
  task test_lt72();
    lt72_frame_tx_c ftx = new();
    lt72_frame_rx_c frx = new();
    lt72_engine_c   ea  = new();
    lt72_engine_c   eb  = new();
    logic [15:0] upd_v, sts_v;
    logic lvl, na, nb, la, lb;
    int  guard, got_frames;

    // --- 帧层自环：字段逐帧还原 ---
    upd_v = 16'h0015;
    sts_v = 16'h802A;
    ftx.coeff_update  = upd_v;
    ftx.status_report = sts_v;
    got_frames = 0;
    for (int f = 0; f < 4; f++) begin
      for (int t = 0; t < LT72_FRAME_BITS; t++) begin
        lvl = ftx.tx_tick();
        if (frx.rx_tick(lvl)) begin
          got_frames++;
          if (got_frames > 1) begin   // 首帧用于建立同步
            check("lt72: coeff_update", frx.coeff_update == upd_v);
            check("lt72: status_report", frx.status_report == sts_v);
          end
        end
      end
    end
    check("lt72: frames decoded", got_frames >= 3);
    $display("[OK] lt72 frame roundtrip x%0d frames", got_frames);

    // --- 双引擎对训：三抽头收敛 + 双方 ready ---
    la = 0;
    lb = 0;
    guard = 0;
    while (!(ea.is_done() && eb.is_done()) && guard < LT72_FRAME_BITS * 40)
    begin
      na = ea.tx_tick();
      nb = eb.tx_tick();
      ea.rx_tick(lb);
      eb.rx_tick(la);
      la = na;
      lb = nb;
      guard++;
    end
    check("lt72: A done", ea.is_done());
    check("lt72: B done", eb.is_done());
    check("lt72: A taps", ea.tap_done == 3);
    check("lt72: B taps", eb.tap_done == 3);
    $display("[OK] lt72 training A=%s(taps=%0d) B=%s(taps=%0d) frames=%0d/%0d",
             ea.state_name(), ea.tap_done, eb.state_name(), eb.tap_done,
             ea.frames_seen, eb.frames_seen);
  endtask

  // RS-FEC cl91：GF 域自洽 + 编码/纠错/超能力判定
  task test_rs91();
    rs91_encoder_c enc = new();
    rs91_decoder_c dec = new();
    rs91_sym_t data[RS91_K];
    rs91_sym_t cw[RS91_N];
    rs91_sym_t orig[RS91_N];
    rs91_sym_t a, b;
    int pos, nerr, ok_cnt, unc_cnt;
    bit ok;

    // --- GF(2^10) 自洽：a*inv(a)=1、a*b/b=a ---
    for (int i = 0; i < 200; i++) begin
      a = $urandom_range(1, 1023);
      b = $urandom_range(1, 1023);
      check("rs91: gf div-mul", rs91_gf_c::div(rs91_gf_c::mul(a, b), b) == a);
    end

    // --- 无错码字：伴随式全零直接通过 ---
    for (int i = 0; i < RS91_K; i++) data[i] = $urandom_range(0, 1023);
    enc.encode(data, cw);
    foreach (cw[i]) orig[i] = cw[i];
    ok = dec.decode(cw);
    check("rs91: clean codeword", ok);
    foreach (cw[i]) check("rs91: clean unchanged", cw[i] == orig[i]);

    // --- 可纠：随机注入 1..7 个符号错，必须全部纠回 ---
    ok_cnt = 0;
    for (int trial = 0; trial < 20; trial++) begin
      for (int i = 0; i < RS91_K; i++) data[i] = $urandom_range(0, 1023);
      enc.encode(data, cw);
      foreach (cw[i]) orig[i] = cw[i];
      nerr = $urandom_range(1, RS91_T);
      for (int e = 0; e < nerr; e++) begin
        pos     = $urandom_range(0, RS91_N-1);
        cw[pos] = cw[pos] ^ 10'($urandom_range(1, 1023));
      end
      ok = dec.decode(cw);
      if (ok) begin
        bit same = 1;
        foreach (cw[i]) if (cw[i] != orig[i]) same = 0;
        check("rs91: corrected exactly", same);
        ok_cnt++;
      end
      else check("rs91: correctable must succeed", 0);
    end
    check("rs91: all correctable trials ok", ok_cnt == 20);

    // --- 超能力：注入 12 个符号错，须判不可纠（或纠错但不误判为正确）---
    unc_cnt = 0;
    for (int trial = 0; trial < 10; trial++) begin
      for (int i = 0; i < RS91_K; i++) data[i] = $urandom_range(0, 1023);
      enc.encode(data, cw);
      foreach (cw[i]) orig[i] = cw[i];
      for (int e = 0; e < 12; e++) begin
        pos     = e * 40;
        cw[pos] = cw[pos] ^ 10'($urandom_range(1, 1023));
      end
      ok = dec.decode(cw);
      if (!ok) unc_cnt++;
    end
    check("rs91: uncorrectable detected", unc_cnt >= 8);

    // --- 256B/257B 转码：任意数据/控制块组合双向无损 ---
    begin
      block66_t tb[4], rb[4];
      logic [256:0] t257;
      byte unsigned bts[13];
      bts = '{BT_CTRL, BT_START0, BT_START4, BT_OSET0, BT_OSET2,
              BT_TERM0, BT_TERM1, BT_TERM2, BT_TERM3, BT_TERM4,
              BT_TERM5, BT_TERM6, BT_TERM7};
      for (int trial = 0; trial < 300; trial++) begin
        for (int i = 0; i < 4; i++) begin
          if ($urandom_range(0, 1)) begin
            tb[i].sync    = SYNC_DATA;
            tb[i].payload = {$urandom, $urandom};
          end
          else begin
            tb[i].sync    = SYNC_CTRL;
            tb[i].payload = {$urandom, $urandom};
            tb[i].payload[7:0] = bts[$urandom_range(0, 12)];
          end
        end
        rs91_transcode_enc(tb, t257);
        rs91_transcode_dec(t257, rb);
        for (int i = 0; i < 4; i++) begin
          check("rs91: transcode sync", rb[i].sync == tb[i].sync);
          check("rs91: transcode payload", rb[i].payload == tb[i].payload);
        end
      end
      $display("[OK] rs91 256B/257B 转码 x300 组（数据/控制混合）");
    end

    // --- 码流封装：80 块 -> 码字 -> 比特流 -> 还原（含注错纠正）---
    begin
      rs91_fec_encoder_c fenc91 = new();
      rs91_fec_decoder_c fdec91 = new();
      block66_t sent[$], gotb[RS91_BLOCKS];
      logic cwbits[RS91_CW_BITS];
      block66_t tb2;
      // 解码器锁定阶段吞掉 LOCK_CLEAN(=2) 个码字不交付，故比对起点
      // 从第 3 个码字对应的块开始
      int deliver = 0, sent_idx = 2 * RS91_BLOCKS;
      bit produced;

      for (int r = 0; r < 4; r++) begin
        // 灌 80 块
        for (int i = 0; i < RS91_BLOCKS; i++) begin
          if ($urandom_range(0, 3) == 0) begin
            tb2.sync    = SYNC_CTRL;
            tb2.payload = {$urandom, $urandom};
            tb2.payload[7:0] = BT_CTRL;
          end
          else begin
            tb2.sync    = SYNC_DATA;
            tb2.payload = {$urandom, $urandom};
          end
          sent.push_back(tb2);
          produced = fenc91.push_block(tb2, cwbits);
          if (produced) begin
            // 每个码字注入 5 个符号错（在纠错能力 7 内）
            for (int e = 0; e < 5; e++)
              cwbits[e*370 + 3] = ~cwbits[e*370 + 3];
            for (int k = 0; k < RS91_CW_BITS; k++)
              if (fdec91.push_bit(cwbits[k], gotb)) begin
                for (int q = 0; q < RS91_BLOCKS; q++) begin
                  check("rs91: stream sync",
                        gotb[q].sync == sent[sent_idx + q].sync);
                  check("rs91: stream payload",
                        gotb[q].payload == sent[sent_idx + q].payload);
                end
                sent_idx += RS91_BLOCKS;
                deliver++;
              end
          end
        end
      end
      check("rs91: stream locked", fdec91.is_locked());
      check("rs91: stream delivered", deliver >= 1);
      $display("[OK] rs91 码流封装：交付 %0d 码字（每字注 5 符号错全纠）, slip=%0d",
               deliver, fdec91.slip_count);
    end

    $display("[OK] rs91 RS(528,514) 纠错 %0d 码字/%0d 符号, 不可纠 %0d",
             dec.corrected_count, dec.sym_err_corrected,
             dec.uncorrectable_count);
  endtask

  // 8b/10b：已知向量 + 全码表往返 + RD 约束 + 游程 + 逗号唯一性
  task test_8b10b();
    bit          rd, rd2, ke, ce, de;
    logic [9:0]  c;
    byte unsigned dout;
    byte unsigned ks[5];
    logic        bits[$];
    int          run, maxrun, dsp, comma_hits;

    // --- 已知向量（标准表）---
    rd = 0; c = enc_8b10b(K28_5, 1, rd);
    check("8b10b: K28.5 RD-", c == 10'b0011111010 && rd == 1);
    rd = 1; c = enc_8b10b(K28_5, 1, rd);
    check("8b10b: K28.5 RD+", c == 10'b1100000101 && rd == 0);
    rd = 0; c = enc_8b10b(8'h00, 0, rd);
    check("8b10b: D0.0 RD-", c == 10'b1001110100);
    rd = 0; c = enc_8b10b(8'hB5, 0, rd);            // D21.5 均衡且单形
    check("8b10b: D21.5", c == 10'b1010101010 && rd == 0);
    rd = 0; c = enc_8b10b(K27_7, 1, rd);
    check("8b10b: K27.7 RD-", c == 10'b1101101000);

    // --- 全码表往返：256 D + 5 K × 两种入口 RD ---
    ks = '{K28_5, K27_7, K29_7, K23_7, K30_7};
    for (int r = 0; r < 2; r++) begin
      for (int v = 0; v < 256; v++) begin
        rd  = r;
        c   = enc_8b10b(v[7:0], 0, rd);
        rd2 = r;
        pcs_8b10b_dec_c::decode(c, rd2, dout, ke, ce, de);
        check("8b10b: D roundtrip", dout == v[7:0] && !ke && !ce && !de);
        check("8b10b: D rd track", rd2 == rd);
      end
      foreach (ks[i]) begin
        rd  = r;
        c   = enc_8b10b(ks[i], 1, rd);
        rd2 = r;
        pcs_8b10b_dec_c::decode(c, rd2, dout, ke, ce, de);
        check("8b10b: K roundtrip", dout == ks[i] && ke && !ce && !de);
      end
    end

    // --- 随机长流：码组不均等性合规、游程 <= 5、D 流中无逗号 ---
    rd = 0;
    maxrun = 0;
    for (int n = 0; n < 4000; n++) begin
      c   = enc_8b10b($urandom_range(0, 255), 0, rd);
      dsp = 0;
      for (int i = 9; i >= 0; i--) begin
        bits.push_back(c[i]);
        dsp += c[i] ? 1 : -1;
      end
      check("8b10b: code disparity in {0,+-2}",
            dsp == 0 || dsp == 2 || dsp == -2);
    end
    run = 1;
    for (int i = 1; i < bits.size(); i++) begin
      if (bits[i] == bits[i-1]) run++;
      else run = 1;
      if (run > maxrun) maxrun = run;
    end
    check("8b10b: run length <= 5", maxrun <= 5);
    comma_hits = 0;
    for (int i = 0; i + 7 <= bits.size(); i++) begin
      logic [6:0] w;
      for (int j = 0; j < 7; j++) w[6-j] = bits[i+j];
      if (w == 7'b0011111 || w == 7'b1100000) comma_hits++;
    end
    check("8b10b: no comma in pure data stream", comma_hits == 0);

    $display("[OK] 8b10b 全码表往返(256D+5K x2RD) 游程max=%0d 逗号误现=%0d",
             maxrun, comma_hits);
  endtask

  // Clause 36 PCS：随机帧 + 随机 IPG（覆盖奇/偶位起帧）+ 随机弹性删除，
  // GMII -> 码组 -> 比特流 -> 逗号对齐/同步/解码 -> GMII -> 帧装配比对
  task test_basex();
    basex_tx_c        tx = new();
    basex_rx_c        rx = new();
    frame_assembler_c asm = new();
    frame_assembler_c::frame_result_t res;
    byte unsigned     frames[$][$];
    byte unsigned     gb[$];
    byte unsigned     fr[$];
    gmii_byte_t       in, out;
    logic [9:0]       cg;
    bit               valid;
    int               nframes = 40, got = 0, bad = 0, ipg;

    // 构造随机帧（长度 60..200）
    for (int f = 0; f < nframes; f++) begin
      fr.delete();
      for (int i = 0; i < $urandom_range(60, 200); i++)
        fr.push_back($urandom_range(0, 255));
      frames.push_back(fr);
    end

    // 先发一段纯 idle 建同步
    for (int n = 0; n < 40; n++) begin
      in = '{en:0, er:0, d:8'h07};
      tx.tick(in, cg, valid);
      if (valid) feed_cg(rx, asm, cg, got, bad, frames);
    end

    foreach (frames[f]) begin
      gb.delete();
      eth_frame_to_gmii(frames[f], gb);
      foreach (gb[i]) begin
        in = '{en:1, er:0, d:gb[i]};
        tx.tick(in, cg, valid);
        if (valid) feed_cg(rx, asm, cg, got, bad, frames);
      end
      ipg = $urandom_range(12, 21);            // 奇偶两种 IPG 都会出现
      for (int n = 0; n < ipg; n++) begin
        in = '{en:0, er:0, d:8'h07};
        if ($urandom_range(0, 3) == 0) tx.request_idle_delete();
        tx.tick(in, cg, valid);
        if (valid) feed_cg(rx, asm, cg, got, bad, frames);
      end
    end
    // 尾部 idle 冲出最后一帧
    for (int n = 0; n < 20; n++) begin
      in = '{en:0, er:0, d:8'h07};
      tx.tick(in, cg, valid);
      if (valid) feed_cg(rx, asm, cg, got, bad, frames);
    end

    check("basex: synced", rx.is_synced());
    check("basex: all frames", got == nframes);
    check("basex: no bad frames", bad == 0);
    check("basex: no code err after sync", rx.code_err_count == 0);
    $display("[OK] basex PCS 往返 %0d 帧（随机 IPG 奇偶起帧 + 删除 %0d 次 /I/）",
             got, tx.idle_del_count);
  endtask

  // 码组 MSB 先上线逐 bit 喂 RX；解出字节交装配器，出帧即与期望比对
  task automatic feed_cg(basex_rx_c rx, frame_assembler_c asm, logic [9:0] cg,
                         ref int got, ref int bad,
                         ref byte unsigned frames[$][$]);
    gmii_byte_t o;
    frame_assembler_c::frame_result_t r;
    for (int i = 9; i >= 0; i--) begin
      if (rx.push_bit(cg[i], o)) begin
        if (asm.push_gmii(o.en, o.er, o.d, r)) begin
          if (got < frames.size() && r.crc_ok && r.preamble_ok &&
              r.data == frames[got])
            got++;
          else
            bad++;
        end
      end
    end
  endtask

  // RS(544,514)（200G KP4）：VIP 实抓黄金码字的校验符号逐位复现 +
  // 随机纠错（t=15）与超能力判定
  task test_rs544();
    rs544_encoder_c enc = new();
    rs544_decoder_c dec = new();
    // VIP 200G（ETH_200G_SERIAL）探针实抓码字 A（544 符号）
    rs91_sym_t gold[544] = '{
      10'h0EC, 10'h1B7, 10'h1CC, 10'h280, 10'h18B, 10'h033, 10'h365, 10'h17B, 10'h3BE, 10'h164, 10'h081, 10'h35D, 10'h319, 10'h3A2, 10'h253, 10'h217,
      10'h2ED, 10'h21F, 10'h0F3, 10'h274, 10'h0FE, 10'h306, 10'h3E2, 10'h1BC, 10'h330, 10'h226, 10'h0F2, 10'h0DE, 10'h0F0, 10'h276, 10'h25F, 10'h007,
      10'h2EA, 10'h194, 10'h374, 10'h2F0, 10'h0DF, 10'h3A5, 10'h1D3, 10'h1E5, 10'h100, 10'h186, 10'h1FD, 10'h181, 10'h09F, 10'h1F4, 10'h30F, 10'h1DD,
      10'h24A, 10'h32D, 10'h252, 10'h304, 10'h2E2, 10'h116, 10'h0B0, 10'h233, 10'h11D, 10'h335, 10'h10B, 10'h1D9, 10'h248, 10'h338, 10'h312, 10'h30E,
      10'h147, 10'h343, 10'h160, 10'h3F0, 10'h060, 10'h1A0, 10'h2CC, 10'h3C9, 10'h00E, 10'h057, 10'h0E7, 10'h220, 10'h066, 10'h1A9, 10'h1BB, 10'h0CD,
      10'h137, 10'h008, 10'h2A8, 10'h249, 10'h056, 10'h08E, 10'h2B9, 10'h050, 10'h17E, 10'h186, 10'h21B, 10'h2BC, 10'h16C, 10'h268, 10'h119, 10'h26F,
      10'h016, 10'h071, 10'h190, 10'h23D, 10'h1D4, 10'h37A, 10'h065, 10'h1DE, 10'h2E8, 10'h2F6, 10'h195, 10'h281, 10'h377, 10'h145, 10'h31B, 10'h27F,
      10'h2DC, 10'h1F9, 10'h2F1, 10'h04B, 10'h104, 10'h399, 10'h190, 10'h19F, 10'h326, 10'h2AB, 10'h3D8, 10'h11C, 10'h046, 10'h0B8, 10'h364, 10'h34D,
      10'h19C, 10'h17F, 10'h01D, 10'h2D8, 10'h153, 10'h26A, 10'h11F, 10'h144, 10'h105, 10'h3E5, 10'h38B, 10'h3B3, 10'h23C, 10'h33B, 10'h2F2, 10'h012,
      10'h1B7, 10'h2B5, 10'h1DF, 10'h237, 10'h046, 10'h16E, 10'h2AE, 10'h0ED, 10'h02C, 10'h3DD, 10'h32D, 10'h1E5, 10'h061, 10'h139, 10'h249, 10'h284,
      10'h26A, 10'h0D0, 10'h094, 10'h0F2, 10'h077, 10'h058, 10'h207, 10'h0F1, 10'h195, 10'h0F9, 10'h236, 10'h319, 10'h325, 10'h201, 10'h054, 10'h3C9,
      10'h0AA, 10'h2F0, 10'h3A7, 10'h252, 10'h337, 10'h1D0, 10'h30F, 10'h27D, 10'h1F3, 10'h2FD, 10'h1E6, 10'h202, 10'h34C, 10'h378, 10'h226, 10'h16F,
      10'h2CD, 10'h035, 10'h13F, 10'h1A9, 10'h0D9, 10'h3BB, 10'h206, 10'h05B, 10'h2ED, 10'h1AC, 10'h160, 10'h26D, 10'h0DB, 10'h16E, 10'h0F7, 10'h081,
      10'h220, 10'h274, 10'h034, 10'h0B2, 10'h111, 10'h014, 10'h2A4, 10'h02E, 10'h057, 10'h2BE, 10'h220, 10'h34A, 10'h3BF, 10'h12D, 10'h30C, 10'h079,
      10'h3CD, 10'h3ED, 10'h1F0, 10'h005, 10'h32F, 10'h1FE, 10'h396, 10'h134, 10'h1B4, 10'h07F, 10'h397, 10'h152, 10'h0D4, 10'h04C, 10'h33C, 10'h212,
      10'h38D, 10'h2E3, 10'h152, 10'h392, 10'h311, 10'h19D, 10'h36C, 10'h30A, 10'h0D1, 10'h05E, 10'h1AA, 10'h01B, 10'h1C2, 10'h367, 10'h0E3, 10'h3C1,
      10'h2A8, 10'h0B8, 10'h0E4, 10'h0F6, 10'h23C, 10'h142, 10'h223, 10'h12E, 10'h341, 10'h21F, 10'h3EB, 10'h3DF, 10'h172, 10'h015, 10'h162, 10'h05E,
      10'h0B4, 10'h25B, 10'h3CD, 10'h000, 10'h2B0, 10'h3F3, 10'h158, 10'h255, 10'h050, 10'h17C, 10'h3BD, 10'h3AF, 10'h080, 10'h038, 10'h28E, 10'h02C,
      10'h349, 10'h0ED, 10'h2AF, 10'h1A4, 10'h0EC, 10'h079, 10'h31F, 10'h207, 10'h091, 10'h2C4, 10'h1C9, 10'h342, 10'h357, 10'h2D3, 10'h230, 10'h19C,
      10'h1AC, 10'h1F2, 10'h0B1, 10'h392, 10'h324, 10'h0E5, 10'h076, 10'h3BB, 10'h102, 10'h2C0, 10'h16F, 10'h029, 10'h103, 10'h04F, 10'h31D, 10'h127,
      10'h19D, 10'h154, 10'h287, 10'h1CD, 10'h316, 10'h047, 10'h0F8, 10'h1E6, 10'h06C, 10'h1CD, 10'h14F, 10'h1EF, 10'h2DC, 10'h3A4, 10'h295, 10'h165,
      10'h0A3, 10'h097, 10'h008, 10'h263, 10'h021, 10'h233, 10'h088, 10'h111, 10'h2CA, 10'h3AB, 10'h121, 10'h3D7, 10'h25A, 10'h0A3, 10'h068, 10'h0C7,
      10'h31C, 10'h079, 10'h2BF, 10'h0FB, 10'h041, 10'h3D2, 10'h01E, 10'h3F9, 10'h3ED, 10'h1FF, 10'h008, 10'h192, 10'h33B, 10'h1CB, 10'h399, 10'h22B,
      10'h0BE, 10'h3F3, 10'h3D5, 10'h3D6, 10'h216, 10'h31C, 10'h0FE, 10'h30B, 10'h0AA, 10'h1B2, 10'h297, 10'h3DF, 10'h1A7, 10'h24A, 10'h3E4, 10'h04C,
      10'h160, 10'h2DF, 10'h3A3, 10'h237, 10'h066, 10'h3F1, 10'h1BF, 10'h3E1, 10'h306, 10'h28F, 10'h17B, 10'h3DE, 10'h01E, 10'h1B1, 10'h3F8, 10'h1DF,
      10'h090, 10'h011, 10'h03F, 10'h22C, 10'h31B, 10'h21D, 10'h304, 10'h2C8, 10'h34E, 10'h085, 10'h115, 10'h091, 10'h1AB, 10'h10D, 10'h2F1, 10'h3EC,
      10'h23B, 10'h04A, 10'h3E6, 10'h3AB, 10'h1E1, 10'h225, 10'h21E, 10'h26A, 10'h046, 10'h332, 10'h2B9, 10'h048, 10'h390, 10'h38A, 10'h1DA, 10'h321,
      10'h10F, 10'h2E6, 10'h34E, 10'h330, 10'h21E, 10'h313, 10'h1D3, 10'h30E, 10'h275, 10'h0F3, 10'h0F9, 10'h064, 10'h340, 10'h20C, 10'h3B9, 10'h3D6,
      10'h15F, 10'h205, 10'h351, 10'h357, 10'h229, 10'h234, 10'h2E1, 10'h090, 10'h24D, 10'h2F0, 10'h002, 10'h1EB, 10'h0BD, 10'h0F5, 10'h124, 10'h054,
      10'h2AF, 10'h263, 10'h04B, 10'h29E, 10'h0BD, 10'h0CB, 10'h3B9, 10'h14A, 10'h08E, 10'h24B, 10'h315, 10'h106, 10'h018, 10'h246, 10'h04D, 10'h024,
      10'h2B7, 10'h201, 10'h140, 10'h1A5, 10'h120, 10'h3AE, 10'h079, 10'h29F, 10'h0D7, 10'h151, 10'h2CC, 10'h29D, 10'h232, 10'h0FD, 10'h2BE, 10'h1F0,
      10'h261, 10'h057, 10'h069, 10'h0A3, 10'h021, 10'h34B, 10'h138, 10'h0AD, 10'h04E, 10'h118, 10'h20C, 10'h29F, 10'h140, 10'h0CC, 10'h307, 10'h332,
      10'h0B2, 10'h258, 10'h233, 10'h029, 10'h353, 10'h17E, 10'h145, 10'h1E0, 10'h282, 10'h04A, 10'h0A9, 10'h026, 10'h075, 10'h2CE, 10'h313, 10'h3FB,
      10'h189, 10'h162, 10'h3BE, 10'h179, 10'h3FC, 10'h2B5, 10'h0EB, 10'h2EC, 10'h3BF, 10'h2FC, 10'h056, 10'h268, 10'h014, 10'h295, 10'h3CD, 10'h1BB
    };    rs91_sym_t data[514];
    rs91_sym_t cw[544];
    rs91_sym_t orig[544];
    int pos, nerr, ok_cnt, unc_cnt, par_match;
    bit ok, same;

    // --- 黄金向量：我方编码 VIP 的信息符号，校验符号须与 VIP 完全一致 ---
    for (int i = 0; i < 514; i++) data[i] = gold[i];
    enc.encode(data, cw);
    par_match = 0;
    for (int i = 514; i < 544; i++) if (cw[i] == gold[i]) par_match++;
    check("rs544: VIP golden parity", par_match == 30);
    ok = dec.decode(gold);
    check("rs544: VIP golden codeword valid", ok);

    // --- 可纠：随机 1..15 个符号错 ---
    ok_cnt = 0;
    for (int trial = 0; trial < 12; trial++) begin
      for (int i = 0; i < 514; i++) data[i] = $urandom_range(0, 1023);
      enc.encode(data, cw);
      foreach (cw[i]) orig[i] = cw[i];
      nerr = $urandom_range(1, 15);
      for (int e = 0; e < nerr; e++) begin
        pos     = $urandom_range(0, 543);
        cw[pos] = cw[pos] ^ 10'($urandom_range(1, 1023));
      end
      ok = dec.decode(cw);
      same = 1;
      foreach (cw[i]) if (cw[i] != orig[i]) same = 0;
      if (ok && same) ok_cnt++;
    end
    check("rs544: correctable trials", ok_cnt == 12);

    // --- 超能力：注 24 个符号错须判不可纠 ---
    unc_cnt = 0;
    for (int trial = 0; trial < 6; trial++) begin
      for (int i = 0; i < 514; i++) data[i] = $urandom_range(0, 1023);
      enc.encode(data, cw);
      for (int e = 0; e < 24; e++) cw[e*22] = cw[e*22] ^ 10'($urandom_range(1, 1023));
      if (!dec.decode(cw)) unc_cnt++;
    end
    check("rs544: uncorrectable detected", unc_cnt >= 5);
    $display("[OK] rs544 RS(544,514) VIP 黄金码字校验位 %0d/30 一致, 纠错 %0d/12, 不可纠 %0d/6",
             par_match, ok_cnt, unc_cnt);
  endtask

  // Clause 119（200G）：随机块流 TX -> 8 lane（随机偏斜 + 物理乱接）-> RX
  task automatic test_cl119();
    c119_tx_c tx = new();
    c119_rx_c rx = new();
    block66_t sent[$], got[$], b, ob;
    logic     lane_bits[C119_LANES][$];
    int       perm[C119_LANES], skew[C119_LANES], cur[C119_LANES];
    byte unsigned bts[8];
    int       j, k, tmp, remaining, first, match, nblk;

    bts = '{8'h1E, 8'h78, 8'h87, 8'hFF, 8'h4B, 8'h99, 8'hB4, 8'h33};
    nblk = 1264 * 4;                 // 4 个 AM 周期
    for (int n = 0; n < nblk; n++) begin
      if ($urandom_range(0, 2) == 0) begin
        b.sync    = SYNC_CTRL;
        b.payload = {$urandom, $urandom};
        b.payload[7:0] = bts[$urandom_range(0, 7)];
      end
      else begin
        b.sync    = SYNC_DATA;
        b.payload = {$urandom, $urandom};
      end
      sent.push_back(b);
      if (tx.push_block(b))
        for (int l = 0; l < C119_LANES; l++) begin
          while (tx.out_bits[l].size() > 0)
            lane_bits[l].push_back(tx.out_bits[l].pop_front());
        end
    end

    // 物理乱接 + 各 lane 前置随机偏斜（随机垃圾比特）
    for (j = 0; j < C119_LANES; j++) perm[j] = j;
    for (j = C119_LANES - 1; j > 0; j--) begin
      k = $urandom_range(0, j);
      tmp = perm[j]; perm[j] = perm[k]; perm[k] = tmp;
    end
    for (j = 0; j < C119_LANES; j++) begin
      skew[j] = $urandom_range(0, 400);
      cur[j]  = 0;
    end

    remaining = 0;
    foreach (lane_bits[l]) remaining += lane_bits[l].size();
    // 逐 bit 交错投递（物理 lane p 承载逻辑 lane perm[p]）
    while (remaining > 0) begin
      for (int p = 0; p < C119_LANES; p++) begin
        int ll = perm[p];
        if (skew[p] > 0) begin
          rx.push_bit(p, $urandom_range(0, 1));
          skew[p]--;
        end
        else if (cur[ll] < lane_bits[ll].size()) begin
          rx.push_bit(p, lane_bits[ll][cur[ll]]);
          cur[ll]++;
          remaining--;
        end
      end
    end
    while (rx.pop_block(ob)) got.push_back(ob);

    // RX 从某个 AM 周期起交付：在发送序列中定位首块后逐一比对
    first = -1;
    for (int i = 0; i + 8 < sent.size() && first < 0; i++) begin
      bit same = 1;
      for (int q = 0; q < 8; q++) if (sent[i+q] != got[q]) same = 0;
      if (same) first = i;
    end
    check("cl119: aligned", rx.is_aligned());
    check("cl119: got blocks", got.size() > 1000);
    check("cl119: locate", first >= 0);
    match = 0;
    for (int i = 0; i < got.size() && first + i < sent.size(); i++)
      if (got[i] == sent[first + i]) match++;
    check("cl119: all blocks match", match == got.size());
    check("cl119: no rs error", rx.rs_uncorrectable == 0);
    $display("[OK] cl119 200G 8 lane TX->RX %0d 块全对（随机乱接+偏斜）, AM锁 %0d",
             match, rx.am_locks);
  endtask

  initial begin
    test_codec();
    test_scrambler();
    test_block_sync();
    test_fec();
    test_frame_utils();
    test_mld();
    test_mld100();
    test_an73();
    test_lt72();
    test_rs91();
    test_rs544();
    test_cl119();
    test_8b10b();
    test_basex();
    $display("UNIT_TEST_PASS (%0d checks)", test_count);
    $finish;
  end

endmodule

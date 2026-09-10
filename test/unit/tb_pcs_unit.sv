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

  initial begin
    test_codec();
    test_scrambler();
    test_block_sync();
    test_fec();
    test_frame_utils();
    test_mld();
    test_an73();
    test_lt72();
    test_rs91();
    $display("UNIT_TEST_PASS (%0d checks)", test_count);
    $finish;
  end

endmodule

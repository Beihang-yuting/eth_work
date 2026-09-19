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

  // 1b. 块型补全：Clause 49 lane4 起始/序集的黄金值（IEEE 图 49-7 位布局）、
  //     Clause 82 序集（lane4~7 零数据）与 Clause 49 专有块型拒收、/Fsig/
  task automatic test_codec_ext();
    logic [7:0]  gc[5] = '{8'h1f, 8'h1f, 8'h11, 8'h11, 8'hf1};
    logic [63:0] gd[5] = '{64'h0100009c_07070707, 64'h555555fb_07070707,
                           64'h555555fb_0100009c, 64'h0100009c_0100009c,
                           64'h07070707_0100009c};
    logic [63:0] gp[5] = '{64'h01000000_0000002d, 64'h55555500_00000033,
                           64'h55555500_01000066, 64'h01000000_01000055,
                           64'h00000000_0100004b};
    xgmii64_t w, wo, w82;
    block66_t b;
    for (int i = 0; i < 5; i++) begin
      w.ctl  = gc[i];
      w.data = gd[i];
      b = pcs_codec::encode(w);
      check("codec ext: sync", b.sync == SYNC_CTRL);
      check("codec ext: golden payload", b.payload == gp[i]);
      check("codec ext: decode ok", pcs_codec::decode(b, wo));
      check("codec ext: roundtrip", wo == w);
      if (gp[i][7:0] != BT_OSET0) begin
        check("codec ext: cl82 rejects cl49-only", !pcs_codec::decode(b, wo, 1));
        check("codec ext: cl82 encodes error", pcs_codec::encode(w, 1) == pcs_codec::error_block());
      end
    end
    // LF：Clause 49 LBLOCK_R 为两个 LF 有序集（0x55 块，即黄金值 gp[3]）；
    // Clause 82 为一个 LF 有序集 + 4 零数据字节（0x4B 零尾块）
    w   = xgmii_local_fault(0);
    w82 = xgmii_local_fault(1);
    b   = pcs_codec::encode(w);
    check("codec ext: cl49 LF = 0x55 x2 /Q/", b.sync == SYNC_CTRL && b.payload == gp[3]);
    b   = pcs_codec::encode(w82, 1);
    check("codec ext: cl82 LF = 0x4B zero tail", b.sync == SYNC_CTRL && b.payload == gp[4]);
    check("codec ext: cl82 LF decode", pcs_codec::decode(b, wo, 1) && wo == w82);
    check("codec ext: cl82 rejects cl49 LF word", pcs_codec::encode(w, 1) == pcs_codec::error_block());
    // /Fsig/ = O 码 F（仅 Clause 49）；保留 O 码判非法
    w.data[7:0] = XGMII_FSIG;
    b = pcs_codec::encode(w);
    check("codec ext: fsig O=F", b.payload[35:32] == 4'hf);
    check("codec ext: fsig roundtrip", pcs_codec::decode(b, wo) && wo == w);
    b.payload[35:32] = 4'h3;
    check("codec ext: reserved O invalid", !pcs_codec::decode(b, wo));
    // Clause 82 无 /Fsig/：编码出 ERROR 块，O=F 的 0x4B 判非法
    w82.data[7:0] = XGMII_FSIG;
    check("codec ext: cl82 fsig encodes error", pcs_codec::encode(w82, 1) == pcs_codec::error_block());
    b = pcs_codec::encode(xgmii_local_fault(1), 1);
    b.payload[35:32] = 4'hf;
    check("codec ext: cl82 fsig block invalid", !pcs_codec::decode(b, wo, 1));
    // Clause 82 模式下 lane0 起始/数据/终止/IDLE 照常闭环
    repeat (2000) begin
      w = random_legal_word();
      check("codec ext: cl82 decode ok", pcs_codec::decode(pcs_codec::encode(w, 1), wo, 1));
      check("codec ext: cl82 roundtrip", wo == w);
    end
    $display("[OK] codec ext: 0x2D/0x33/0x66/0x55/0x4B 黄金值 + Clause 82 序集/拒收/闭环 + Fsig");
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

  // 3b. BER 监视：窗内坏头达上限即 hi_ber；置位窗口结束仍保持，下一个
  //     干净完整窗口结束才清除；坏头不足上限的窗口不置位；reset 立即清
  task automatic test_ber_mon();
    ber_mon_c m = new(16, 100);
    for (int i = 0; i < 100; i++) m.push_sh(i >= 15);
    check("ber: 15/100 not hi_ber", !m.is_hi_ber());
    for (int i = 0; i < 16; i++) m.push_sh(0);
    check("ber: 16 bad -> hi_ber", m.is_hi_ber());
    for (int i = 16; i < 100; i++) m.push_sh(1);
    check("ber: hold through set window", m.is_hi_ber());
    for (int i = 0; i < 99; i++) m.push_sh(1);
    check("ber: hold until clean window ends", m.is_hi_ber());
    m.push_sh(1);
    check("ber: cleared after clean window", !m.is_hi_ber());
    check("ber: count", m.hi_ber_count == 1);
    for (int i = 0; i < 16; i++) m.push_sh(0);
    check("ber: set again", m.is_hi_ber());
    m.reset();
    check("ber: reset clears", !m.is_hi_ber());
    $display("[OK] ber monitor (limit/window/clear/reset)");
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

    // VIP 黄金码字：我方编码器吃进由 VIP 码字反推的 32 块，须逐位复现 VIP
    // 原码字（含 PN-2112 与 T 位约定）；译码器吃 VIP 码字须原样还原 32 块
    begin
      // VIP 10G（ETH_XSBI_SERIAL + enable_fec）探针实抓码字：bit i = 第 i 个
      // 上线位（含 PN）；8 段拼接，首段为最高位
      logic [2111:0] gold_cw = {
        264'hed02116854d6bbbf237546bb79b0c6dd367e94f1bba80773eb3319f88b602cee69,
        264'hfeef8d0502b351a1b79f3fb5da7e408334f705e9cc7929167bd2180b525aa88adf,
        264'h5c713fb3f10320b4ead4312c9f8d45735622e191e38d620b961df6bcc13a3485b9,
        264'hecc81debaf223be8201a7b78b0d7601ec23705f66af693796b2550bf030a70522a,
        264'h856a37f7f734044dc3448d4aa92663a3ae574c4ed2ba5e1d7880ae6d5e867780e2,
        264'h4b9c3096b3153ad57c5f45288a0214109354501bca8c04a64083f7717d6fb85a32,
        264'h7632f0aba951cc817529022ffa3c6d5c67d27c79082285720437502011a0ac76c0,
        264'h5a97f965e2a23af6eaafbdd6580d9577195f24e0e52eb22c83c5abdbee52c870a8 };
      // 由该码字反推的 32 个 66b 块 {sync[1:0], payload[63:0]}
      logic [65:0] gold_blk[32] = '{
        66'h2e380b888d69bc7ab, 66'h2029b9293e1062b20, 66'h200a2eacb004d5109, 66'h2fc2ac32b7f745091,
        66'h2efd2ff72ba9c44a8, 66'h2a35b468a2195c81a, 66'h206045fcb87251265, 66'h267a0fefc2e3371df,
        66'h27447414822c7b385, 66'h2be0c583f012bba8a, 66'h2e8a0aebff828b13f, 66'h26e5c344eadb7fd6d,
        66'h28dc50be616acf8f6, 66'h29b974ae978df40bd, 66'h28f6aa8e66c4609eb, 66'h2628808e42ee56b44,
        66'h2e079d792d6bfe7ef, 66'h25d1ab7ae75b136a1, 66'h291fdb070368d13b5, 66'h20141f6893c020c00,
        66'h2eba37a5a860b4cfb, 66'h2472e9f1cb9a50025, 66'h2f391bedfe7a91a09, 66'h2992ba182b541cbce,
        66'h20287beca9d05c620, 66'h2dbb31f7a6bab7203, 66'h2b1e69810322110a8, 66'h2fa819d38b1848c0e,
        66'h2f1ad1889a0088e3d, 66'h2f3f5ea9af20c66bd, 66'h247718cd3933d7cb6, 66'h2fe53f110f48a9c6e };
      fec_cl74_encoder_c genc = new();
      fec_cl74_decoder_c gdec = new();
      block66_t gb;
      bit       gout;
      int       same_bits, same_blks;

      same_bits = 0;
      same_blks = 0;
      gout      = 0;
      for (int j = 0; j < FEC_BLOCKS; j++) begin
        gb.sync    = gold_blk[j][65:64];
        gb.payload = gold_blk[j][63:0];
        gout = genc.push_block(gb, cw);
      end
      for (int i = 0; i < FEC_N; i++) if (cw[i] == gold_cw[i]) same_bits++;
      for (int i = 0; i < FEC_N; i++)
        if (gdec.push_bit(gold_cw[i], blks))
          for (int k = 0; k < FEC_BLOCKS; k++)
            if ({blks[k].sync, blks[k].payload} == gold_blk[k]) same_blks++;
      check("fec: VIP golden codeword produced", gout);
      check("fec: VIP golden codeword bit-exact", same_bits == FEC_N);
      check("fec: VIP golden blocks recovered", same_blks == FEC_BLOCKS);
      $display("[OK] fec VIP 黄金码字 %0d/%0d bit 一致, 反解 %0d/%0d 块",
               same_bits, FEC_N, same_blks, FEC_BLOCKS);
    end

    $display("[OK] fec encode/correct/uncorrectable");
  endtask

  // 5. 帧 <-> XGMII 闭环
  task automatic test_frame_utils();
    frame_assembler_c asm = new();
    for (int n = 0; n < 50; n++) begin
      byte unsigned frame[$];
      xgmii64_t     words[$];
      frame_assembler_c::frame_result_t tmp;
      frame_assembler_c::frame_result_t res;
      bit           got_frame = 0;
      int           len = $urandom_range(60, 1518);

      frame.delete();
      repeat (len) frame.push_back($urandom);

      // 奇数轮 lane4 起帧；各拍先过 Clause 49 编解码（覆盖 0x33 块）
      eth_frame_to_words(frame, words, n[0]);
      words.push_back(xgmii_all_idle());   // 帧后 IPG
      foreach (words[i]) begin
        xgmii64_t wd;
        check("frame: codec ok", pcs_codec::decode(pcs_codec::encode(words[i]), wd));
        check("frame: codec roundtrip", wd == words[i]);
      end

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
    $display("[OK] frame utils roundtrip x50（含 lane4 起帧 x25，逐拍过编解码）");
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

  // 6c. MLD AM 误码容忍（IEEE Clause 82 am_invld_cnt）：对齐后单个坏 AM 只跳过 ——
  //     不重对齐、数据块一个不丢；同一 lane 连续 4 个坏 AM 才整体重对齐
  task automatic test_mld_am_err();
    localparam int LANES = 4;
    localparam int SPACING = 64;

    for (int scen = 0; scen < 3; scen++) begin
      mld_tx_c  tx = new(LANES, SPACING);
      mld_rx_c  rx = new(LANES, SPACING);
      block66_t sent[$];
      block66_t got[$];
      block66_t lane_stream[LANES][$];
      int       am_idx[LANES][$];
      int       maxlen = 0;

      repeat (4000) begin
        block66_t b, am_b;
        int lane;
        bit am_v;
        b.sync    = SYNC_DATA;
        b.payload = {$urandom, $urandom};
        sent.push_back(b);
        tx.push_block(b, lane, am_v, am_b);
        if (am_v) begin
          am_idx[lane].push_back(lane_stream[lane].size());
          lane_stream[lane].push_back(am_b);
        end
        lane_stream[lane].push_back(b);
      end

      // 场景 0：lane1 第 4 个 AM 单 bit 误码；场景 1：lane2 第 3~6 个 AM 连坏；
      // 场景 2：lane1 对齐后首个 AM（第 2 个）误码且 lane1 先到 —— 落在 AM
      // 间隔学得之前，须在学得间隔时检出该 lane 越位并整体重对齐
      if (scen == 0)
        lane_stream[1][am_idx[1][3]].payload[0] ^= 1'b1;
      else if (scen == 1)
        for (int k = 2; k < 6; k++) lane_stream[2][am_idx[2][k]].payload[0] ^= 1'b1;
      else
        lane_stream[1][am_idx[1][1]].payload[0] ^= 1'b1;

      foreach (lane_stream[p])
        if (lane_stream[p].size() > maxlen) maxlen = lane_stream[p].size();
      for (int k = 0; k < maxlen; k++)
        for (int p = 0; p < LANES; p++) begin
          block66_t ob;
          int       pp = (scen == 2) ? (p + 1) % LANES : p;   // 场景 2 lane1 先到
          if (k < lane_stream[pp].size()) rx.push_block(pp, lane_stream[pp][k]);
          while (rx.pop_block(ob)) got.push_back(ob);
        end

      if (scen == 0) begin
        check("mld am-err: no realign", rx.realign_count == 0);
        check("mld am-err: tolerated", rx.am_bad_count == 1);
        check("mld am-err: got count", got.size() == sent.size());
        foreach (got[i]) check("mld am-err: block order", got[i] == sent[i]);
      end
      else if (scen == 1) begin
        check("mld am-err: 4 bad AMs realign", rx.realign_count == 1);
        check("mld am-err: realigned", rx.is_aligned());
      end
      else begin
        check("mld am-err: missed AM before gap learned -> realign", rx.realign_count == 1);
        check("mld am-err: realigned after missed AM", rx.is_aligned());
      end
    end
    $display("[OK] mld AM error tolerance (1 bad AM skipped, 4 in a row realign, missed AM before gap learned realign)");
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
    // 偏斜按最小值归零：投递循环要求至少一条 lane 起始偏斜为 0，否则
    // 全部 lane 永远等待、死循环（随机种子变化时曾实测挂死）
    tmp = skew[0];
    for (j = 1; j < LANES; j++) if (skew[j] < tmp) tmp = skew[j];
    for (j = 0; j < LANES; j++) skew[j] -= tmp;

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

    // --- nonce 碰撞：两端同 nonce，须检出碰撞、各自随机换 nonce 后完成 ---
    ea.nonce = 5'h07;
    eb.nonce = 5'h07;
    ea.reset();
    eb.reset();
    la = 0;
    lb = 0;
    guard = 0;
    while (!(ea.is_done() && eb.is_done()) && guard < AN73_PAGE_TICKS * 200) begin
      na = ea.tx_tick();
      nb = eb.tx_tick();
      ea.rx_tick(lb);
      eb.rx_tick(la);
      la = na;
      lb = nb;
      guard++;
    end
    check("an73: collision A done", ea.is_done());
    check("an73: collision B done", eb.is_done());
    check("an73: collision restarted", ea.restarts + eb.restarts > 0);
    check("an73: nonces differ", ea.nonce != eb.nonce);
    $display("[OK] an73 nonce collision resolved: restarts=%0d/%0d nonce=%0d/%0d",
             ea.restarts, eb.restarts, ea.nonce, eb.nonce);
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

    // --- 256B/257B 转码（RS-FEC 形态）：加扰块流经转码/反转码无损 ---
    begin
      scrambler_c   s  = new();
      rs91_xdec_c   xd = new();
      block66_t     tb[4], rb[4];
      block66_t     sent_t[$], got_t[$];
      logic [256:0] t257;
      byte unsigned bts[13];
      int           tmatch;
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
          tb[i].payload = s.scramble(tb[i].payload);   // 转码吃加扰后的块
          sent_t.push_back(tb[i]);
        end
        rs91_transcode_enc(tb, t257);
        xd.decode(t257, rb);
        for (int i = 0; i < 4; i++) got_t.push_back(rb[i]);
      end
      // 首组首块可能缺加扰历史（与 BFM 热身块同理），从第 2 组起逐块比对
      tmatch = 0;
      for (int i = 4; i < sent_t.size(); i++) if (got_t[i] == sent_t[i]) tmatch++;
      check("rs91: transcode lossless", tmatch == sent_t.size() - 4);
      $display("[OK] rs91 256B/257B 转码（加扰域）%0d/%0d 块无损", tmatch, sent_t.size() - 4);
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

  // RS-FEC 码流：随机块流 TX -> 1/4 条 FEC lane（物理乱接 + 随机偏斜 +
  // 注符号错）-> RX，块逐一比对
  // am_hit=1（仅 4 lane）：定向去偏斜场景 —— FEC lane 0 的首个 AM 被误码
  // 击中（该 lane 晚一个周期锁定），其余 lane 偏斜更大、锁在更早的 AM 上
  // 且队列不足一整周期；须整体对齐到第二个 AM，首周期丢弃
  task automatic test_rs_stream(int nfl, bit am_hit = 0);
    rs91_tx_c     tx = new(nfl);
    rs91_rx_c     rx = new(nfl);
    scrambler_c   s  = new();
    block66_t     sent[$], got[$], b, ob;
    logic         lane_bits[4][$];
    int           perm[4], skew[4], cur[4];
    int           per, nblk, remaining, match, k, tmp, base;
    byte unsigned bts[8];
    logic         am0;                        // lane0 首 AM 首位原值（am_hit 用）

    bts  = '{8'h1E, 8'h78, 8'h87, 8'hFF, 8'h4B, 8'h99, 8'hB4, 8'h33};
    per  = RS91_CW_BITS / nfl;
    nblk = (nfl == 4 ? 1260 : 1276) * 3;          // 3 个 AM 周期
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
      b.payload = s.scramble(b.payload);
      sent.push_back(b);
      if (tx.push_block(b))
        for (int l = 0; l < nfl; l++)
          while (tx.out_bits[l].size() > 0)
            lane_bits[l].push_back(tx.out_bits[l].pop_front());
    end

    // 注错：每码字每 lane 若干 bit 错（4 lane 各 1、单 lane 5，均 ≤ t=7 符号）
    am0 = lane_bits[0][0];
    for (int l = 0; l < nfl; l++)
      for (int c = 0; (c + 1) * per <= lane_bits[l].size(); c++)
        repeat (nfl == 1 ? 5 : 1) begin
          // AM 码字避开各 lane 前 128bit（RX 逐 bit 搜 AM 的比对窗，比对在
          // RS 纠错前）：随机误码若击中会让该 lane 晚锁一至多个周期，场景
          // 不再确定；"首 AM 被击中"由 am_hit 定向覆盖
          k = c * per + ((c % RS91_AM_CWS == 0) ? $urandom_range(128, per - 1)
                                                : $urandom_range(0, per - 1));
          lane_bits[l][k] = ~lane_bits[l][k];
        end
    // 置为原值取反（不能取当前值反：随机注错恰好命中该位时会被翻回）
    if (am_hit) lane_bits[0][0] = ~am0;

    // 物理乱接 + 各 lane 前置随机偏斜（随机垃圾比特），逐 bit 交错投递
    for (int j = 0; j < nfl; j++) perm[j] = j;
    for (int j = nfl - 1; j > 0; j--) begin
      k = $urandom_range(0, j);
      tmp = perm[j]; perm[j] = perm[k]; perm[k] = tmp;
    end
    remaining = 0;
    for (int j = 0; j < nfl; j++) begin
      skew[j] = am_hit ? ((perm[j] == 0) ? 0 : 600) : $urandom_range(0, 700);
      cur[j]  = 0;
      remaining += lane_bits[j].size();
    end
    while (remaining > 0) begin
      for (int p = 0; p < nfl; p++) begin
        int ll;
        ll = perm[p];
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
      while (rx.pop_block(ob)) got.push_back(ob);
    end

    // TX 从 AM 码字起发，RX 从第一个 AM 起交付：与发送序直接对位
    // 随机注错避开 AM 比对窗，全部 lane 在首个 AM 锁定、全量交付；am_hit
    // 定向场景 lane0 晚一周期锁定，整体从第二个 AM 起交付（丢首周期）
    base  = nblk - got.size();
    match = 0;
    for (int i = 4; i < got.size() && i + base < sent.size(); i++)
      if (got[i] == sent[i + base]) match++;
    check($sformatf("rs stream: aligned (am_hit=%0d got=%0d locks=%0d slip=%0d miss=%0d uncorr=%0d)",
                    am_hit, got.size(), rx.am_locks, rx.slip_count, rx.am_miss_total,
                    rx.rs_uncorrectable), rx.is_aligned());
    check($sformatf("rs stream: delivered from expected AM (am_hit=%0d base=%0d got=%0d locks=%0d slip=%0d uncorr=%0d)",
                    am_hit, base, got.size(), rx.am_locks, rx.slip_count, rx.rs_uncorrectable),
          base == (am_hit ? nblk / 3 : 0));
    check("rs stream: all blocks match", match == got.size() - 4);
    check("rs stream: no uncorrectable", rx.rs_uncorrectable == 0);
    check("rs stream: errors corrected", rx.corrected_count() > 0);
    check("rs stream: single lock", rx.am_locks == 1 && rx.slip_count == 0);
    $display("[OK] rs-fec %0d lane 码流 %0d 块全对（乱接+偏斜+注错%0s），纠错码字 %0d",
             nfl, match, am_hit ? "+首AM误码定向去偏斜" : "", rx.corrected_count());
  endtask

  // RS-FEC VIP 黄金码字：我方转码 + RS 编码须逐位复现 VIP 25G 实抓码字
  task automatic test_rs25_golden();
      // VIP 25G（ETH_25G_SERIAL + IEEE RS-FEC）探针实抓非 AM 码字：bit i = 第 i 个
      // 上线位；20 段拼接，首段为最高位
      logic [5279:0] gold_rs = {
        264'hf16a01f22734a31387b2ef7c241e829c2ee6b887bdd131ebc79b591c1f67f91c4d,
        264'hfdceb860214b1602196e5b2591a133e7e2f503ec905bee6fc48d03b5b28d2d0a82,
        264'he1bd3090ed5017166daee98a89343bb8f636af95f3753c512a21c03ae5481de18b,
        264'hcc3fc2d5ff77df1df41309fdbc9f1f77554fd41e690711f5b1cbb0a337fa9a9321,
        264'hbe4dfa3733632e03f6bff31b0c8cf0bc49e96a5cbd3738b49d4c8486c81e74249d,
        264'ha53206b49d5fb4c2ba99fa6181908ad54225e46b18efd64d73f0b4b28d23c2f884,
        264'h323c2faf354bc7a5b7ff57afbc01db36e48c2b9ea5051919a029d6fc5b99cd1b13,
        264'hd6d83c1d74c56a4d1b43c3caa7ec1d4eebd5f7c345ff3b15121dfa82c09e9d4754,
        264'hd4e23abbe006b935ed0101ac00e2aea1f4805d903319a61e1580aebcd3be15f2a3,
        264'hc1f34cd1ecee956cf7f3559af765f3735abf0dea38c59bceb6beac59e4e9cf303c,
        264'h4911f01849cf068200561903f8c0af79026960b31e3dbdd22fe2693bc0480cd7fb,
        264'h00b1900631356e6e40ec48daafb6c3e7e36ecac734e835e4dd0e2a6dff40ec5e5e,
        264'h0150befa2ce3238e0f261e215f9b08f0a8999dc4d56fe607daa78ae1aab0f420b7,
        264'h66ae0679e8784864accc1aa49906ca0bea47946eb99f15c9735c75c5e3dd8e2766,
        264'hd9dda3c67e588ba02ae07d97a9b01d3cbb98f29c2274cb607f70a8e3d80ea31e08,
        264'h69f9fe4a5b850a7d8e707ef0fe9c80b01c09bd168082fc174dedaeb58569b57e5d,
        264'hc4647c7371b3a586f83fb3d39a9312e46db12d58816fa93e996dd105e1caf39705,
        264'h07fdf846037a24cfba89e2d1e2d30bb4c3a4280c31c36f0884411784522b4c6479,
        264'h66e51c73ca00f66c26889823933be96e8a09d9a5f5cce51b4bd70007933bb4b5d5,
        264'h545d972cc573224e722c0574dd66081acb0204571808e5995d323e6044f56ee202 };
      // 由该码字反推的 80 个（已加扰）66b 块 {sync[1:0], payload[63:0]}
      logic [65:0] gold_rsb[80] = '{
        66'h2991f30227ab771b0, 66'h281022b8c0472ccae, 66'h21602ba6eb3040d65, 66'h22ecb9662b9912739,
        66'h2c001e4ceed2d7595, 66'h276697d733946d2f5, 66'h22608e4cefa5ba282, 66'h2471cf2803d9b09a2,
        66'h2f08a45698c8f2c6d, 66'h20186386de1108822, 66'h25a3c5a6176987485, 66'h208c06f4499f7513c,
        66'h25e1caf3970507f5d, 66'h28816fa93e996dd10, 66'h239a9312e46db12d5, 66'h2371b3a586f83fb3d,
        66'h22b4dabf2ee23238e, 66'h20417e0ba6f6d75ac, 66'h2f4e40580e04de8b4, 66'h2dc2853ec7383f787,
        66'h23a8c7821a7e7f9b2, 66'h2d32d81fdc2a38f60, 66'h2c074f2ee63ca7089, 66'h2622e80ab81f65ea6,
        66'h21c4ecdb3bb478cef, 66'h22b92e6b8eb8bc7bb, 66'h29417d48f28dd733e, 66'h290c959983549320d,
        66'h220b766ae0679e887, 66'h207daa78ae1aab0f4, 66'h2f0a8999dc4d56fe6, 66'h28e0f261e215f9b08,
        66'h22f00a85f7d167129, 66'h26e871536ffa0762f, 66'h2f1b765639a741af2, 66'h22076246d57db61f3,
        66'h2c02c64018c4d5b79, 66'h2f89a4ef0120335fe, 66'h29a582cc78f6f748b, 66'h2158640fe302bde40,
        66'h2223e030939e0d034, 66'h2d58b3c9d39e60789, 66'h2e1bd4718b379d6d7, 66'h26ab35eecbe6e6b57,
        66'h234cd1ecee956cfa7, 66'h2ebcd3be15f2a3c1f, 66'h2d903319a61e1580a, 66'h21ac00e2aea1f4805,
        66'h2d5df0035c9af6800, 66'h21604f4ea3aa6a711, 66'h21a2ff9d8a890efd4, 66'h2553f60ea775eafbe,
        66'h275d315a9346d0fd0, 66'h26e67346c4f5b60f0, 66'h29414646680a75bf1, 66'h2f0076cdb9230ae7a,
        66'h26a978f4b6ffeaf25, 66'h24785f10864785f5e, 66'h2dfac9ae7e169651a, 66'h22115aa844bc8d631,
        66'h25fb4c2ba99fa6128, 66'h274249da53206b49d, 66'h238b49d4c8486c81e, 66'h2f0bc49e96a5cbd37,
        66'h29701fb5ff98d8614, 66'h24990df26fd1b99b1, 66'h2fad8e5d8519bfd4d, 66'h2bbaaa7ea0f348388,
        66'h2c77d04c27f6f275c, 66'h262f30ff0b57fddf7, 66'h24a88700eb9520778, 66'h23d8dabe57cdd4f14,
        66'h2cdb5dd31512687d7, 66'h25c37a6121daa02e2, 66'h291a076b651a5a150, 66'h25ea07d920b7dcdf8,
        66'h296e5b2591a133e67, 66'h2dceb860214b16021, 66'h2b591c1f67f91c4df, 66'h26b887bdd131ebc79 };
    rs91_encoder_c enc = new();
    block66_t      g4[4];
    logic [256:0]  t;
    logic          msg[$];
    rs91_sym_t     data[RS91_K];
    rs91_sym_t     cw[RS91_N];
    int            same;

    for (int g = 0; g < 20; g++) begin
      for (int i = 0; i < 4; i++) begin
        g4[i].sync    = gold_rsb[4*g + i][65:64];
        g4[i].payload = gold_rsb[4*g + i][63:0];
      end
      rs91_transcode_enc(g4, t);
      for (int i = 0; i < 257; i++) msg.push_back(t[i]);
    end
    for (int i = 0; i < RS91_K; i++)
      for (int j = 0; j < RS91_M; j++) data[i][j] = msg[i*RS91_M + j];
    enc.encode(data, cw);
    same = 0;
    for (int i = 0; i < RS91_N; i++)
      for (int j = 0; j < RS91_M; j++)
        if (cw[i][j] == gold_rs[i*RS91_M + j]) same++;
    check("rs25: VIP golden codeword bit-exact", same == RS91_CW_BITS);
    $display("[OK] rs-fec VIP 25G 黄金码字 %0d/%0d bit 一致（转码+RS 编码）",
             same, RS91_CW_BITS);
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
  // am_hit=1：定向场景 —— 逻辑 lane 0 首个 AM 误码（晚一周期锁定）、其余
  // lane 偏斜更大；另在第 3 周期 lane 5 的 AM 上打 1bit（对齐后单个周期
  // 起点 AM 不符须容忍、由 RS 纠正，不得重锁）
  task automatic test_cl119(bit am_hit = 0);
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
      skew[j] = am_hit ? ((perm[j] == 0) ? 0 : 300) : $urandom_range(0, 400);
      cur[j]  = 0;
    end
    if (am_hit) begin
      lane_bits[0][0] = ~lane_bits[0][0];
      lane_bits[5][2 * C119_PERIOD] = ~lane_bits[5][2 * C119_PERIOD];
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
    check("cl119: no realign", rx.realign_count == 0);
    $display("[OK] cl119 200G 8 lane TX->RX %0d 块全对（随机乱接+偏斜%0s）, AM锁 %0d",
             match, am_hit ? "+首AM误码定向去偏斜+周期AM单bit误码" : "", rx.am_locks);
  endtask

  initial begin
    test_codec();
    test_codec_ext();
    test_scrambler();
    test_block_sync();
    test_ber_mon();
    test_fec();
    test_frame_utils();
    test_mld();
    test_mld_am_err();
    test_mld100();
    test_an73();
    test_lt72();
    test_rs91();
    test_rs_stream(1);
    test_rs_stream(4);
    test_rs_stream(4, 1);
    test_rs25_golden();
    test_rs544();
    test_cl119();
    test_cl119(1);
    test_8b10b();
    test_basex();
    $display("UNIT_TEST_PASS (%0d checks)", test_count);
    $finish;
  end

endmodule

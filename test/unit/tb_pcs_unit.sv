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

      for (int i = 0; i < 2; i++) begin
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

  initial begin
    test_codec();
    test_scrambler();
    test_block_sync();
    test_fec();
    test_frame_utils();
    $display("UNIT_TEST_PASS (%0d checks)", test_count);
    $finish;
  end

endmodule

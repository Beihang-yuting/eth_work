// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— PHY 数据通路 BFM（agent 的核心）
// 职责：桥接 XGMII 与串行 bit 流两个边界，内部串联 PCS/FEC 流水线：
//   TX：采样 XGMII 引脚 -> 64b/66b 编码 -> 扰码 ->（FEC 编码）-> 串行发送
//   RX：串行采样 ->（FEC 对齐/纠错 | 块同步）-> 解扰 -> 解码 -> 驱动 XGMII
//       RX 引脚，同时把还原的 XGMII 拍经 mailbox 递交 monitor。
// 依赖：pcs_codec / scrambler / block_sync / fec_cl74 / eth_pcs_cfg。
// 所有权：agent 在 build 阶段创建，run_phase fork run()；流水线子对象由
//         BFM 构造并随其存续。复位（rst_n 拉低）时清空全部流水线状态。
// -----------------------------------------------------------------------------

// 时钟约定：xgmii_if.clk 为字时钟，serial_if.clk 为 66 倍频 bit 时钟，由
// top 保证严格 66:1（Clause 74 经 66b→65b 压缩换出校验位带宽，线速率
// 不变，故 FEC 开关不影响该比值）。TX bit 队列在稳态下深度有界。
class eth_pcs_phy_bfm;

  eth_pcs_cfg cfg;

  // RX 还原出的 XGMII 拍：monitor 从此 mailbox 取流（引脚驱动为另一份）
  mailbox #(xgmii64_t) rx_words;

  // BASE-X 模式：RX 还原出的 GMII 字节（monitor 取流用）
  mailbox #(gmii_byte_t) rx_gmii;

  // 协议完整性统计（记分板/测试 check_phase 汇总）
  int invalid_block_count;   // 解码非法块（坏同步头/未知块型）
  int tx_underrun_count;     // FEC 模式串行队列空（FEC 无法按 bit 插补）

  // 弹性 idle 统计：字时钟与位时钟允许独立（ppm 偏差），速率差由
  // idle 块的插入/删除吸收 —— 真实 PHY 弹性缓冲的等效行为
  int idle_ins_count;        // TX 队列见底时按 bit 流插入的 idle 块数
  int idle_del_count;        // TX 队列超阈值时删除的 idle 块数

  // 弹性垫与删除阈值：启动时预灌 PRIME_BLOCKS 个 idle 块（弹性 FIFO
  // 半满启动），保证突发生产/均匀消费的相位差不会把队列打到 0 —— 队列
  // 见底时插入会落在帧中间毁帧；删除阈值高于垫水位一段裕量，避免与
  // 稳态深度打架
  localparam int PRIME_BLOCKS    = 8;
  localparam int IDLE_DEL_THRESH = 66 * (PRIME_BLOCKS + 2);

  // FEC 模式删除阈值必须按码字粒度：码字整体（2112bit）突发入队，
  // 阈值低于一个码字会导致"每码字后所有 idle 被删 -> fenc 集不满
  // 32 块 -> 码字间断流发 0 -> 对端永不锁定"。取 2 码字深。
  localparam int IDLE_DEL_THRESH_FEC = FEC_N * 2;

  // RS-FEC 同理按码字粒度（5280bit/码字），取 2 个码字深
  localparam int IDLE_DEL_THRESH_RS = RS91_CW_BITS * 2;

  // 任一 FEC 模式（两者互斥）
  function bit any_fec();
    return cfg.fec_enable || cfg.rs_fec_enable;
  endfunction

  // 当前模式的删除阈值
  function int del_thresh();
    if (cfg.rs_fec_enable) return IDLE_DEL_THRESH_RS;
    return cfg.fec_enable ? IDLE_DEL_THRESH_FEC : IDLE_DEL_THRESH;
  endfunction

  // ---------------- 流水线子对象 ----------------

  protected scrambler_c        scr;
  protected descrambler_c      descr;
  protected block_sync_c       bsync;
  protected fec_cl74_encoder_c fenc;
  protected fec_cl74_decoder_c fdec;

  // RS-FEC（cl91）流水线：cfg.rs_fec_enable 时启用
  protected rs91_fec_encoder_c renc;
  protected rs91_fec_decoder_c rdec;

  // 多 lane（Clause 82 MLD）流水线：num_lanes>1 时启用。
  // 每物理 lane 独立 bit 队列与块同步；MLD 负责分发/AM/去偏/重组
  // Clause 73 自协商引擎（cfg.an_enable 时启用）：AN 完成前串行线由它
  // 驱动/采样，完成后 BFM 切回 PCS 数据通路（an_done 恒 1 后不再回退，
  // 复位重新协商）
  protected an73_engine_c an_eng;

  // Clause 72 链路训练引擎（cfg.lt_enable 时启用）：AN 之后、数据模式
  // 之前占用串行线跑训练帧；完成后不再回退（复位重新训练）
  protected lt72_engine_c lt_eng;

  protected mld_tx_c     mtx;
  protected mld_rx_c     mrx;
  protected block_sync_c bsync_l[MLD_MAX_LANES];
  protected logic        txbit_lq[MLD_MAX_LANES][$];

  // TX 串行 bit 队列（编码侧生产、串行侧消费）与 RX XGMII 引脚驱动队列
  protected logic     txbit_q[$];
  protected xgmii64_t rxpin_q[$];

  // BASE-X（8b/10b，Clause 36）流水线：cfg.basex 时启用
  protected basex_tx_c  btx;
  protected basex_rx_c  brx;
  protected gmii_byte_t rxgmii_q[$];
  protected bit         bx_primed;

  // BASE-X 弹性删除阈值：GMII 时钟 +100ppm 使码组生产略快于线路消耗，
  // 队列超过 12 个码组即删一个 /I/（20bit）
  localparam int BASEX_DEL_THRESH = 10 * 12;
  protected bit       tx_started;
  protected bit       tx_primed;   // 弹性垫已预灌标志（复位后重灌）

  // RX 链路是否已完成块/码字/多 lane 对齐（test 在发流前等待）。
  // 直驱模式无串行链路，恒视为已锁 —— 既有测试的等锁流程无需适配
  function bit rx_locked();
    if (cfg.xgmii_direct) return 1;
    if (cfg.basex) return brx.is_synced();
    if (in_an_phase() || in_lt_phase()) return 0;
    if (cfg.num_lanes > 1) return mrx.is_aligned();
    if (cfg.rs_fec_enable) return rdec.is_locked();
    return cfg.fec_enable ? fdec.is_locked() : bsync.is_locked();
  endfunction

  // 建链阶段判定：AN 未完成 -> AN 阶段；AN 完成而 LT 未完成 -> LT 阶段；
  // 都完成（或都未启用）-> 数据模式
  protected function bit in_an_phase();
    return cfg.an_enable && !an_eng.is_done();
  endfunction
  protected function bit in_lt_phase();
    return cfg.lt_enable && !lt_eng.is_done() && !in_an_phase();
  endfunction

  // LT 状态观测
  function bit lt_done();
    return !cfg.lt_enable || lt_eng.is_done();
  endfunction
  function string lt_state();
    return cfg.lt_enable ? lt_eng.state_name() : "LT_OFF";
  endfunction
  function int lt_frames();
    return cfg.lt_enable ? lt_eng.frames_seen : 0;
  endfunction
  function int lt_taps();
    return cfg.lt_enable ? lt_eng.tap_done : 0;
  endfunction

  // AN 状态观测（test 打印/判定用）
  function bit an_done();
    return !cfg.an_enable || an_eng.is_done();
  endfunction
  function string an_state();
    return cfg.an_enable ? an_eng.state_name() : "AN_OFF";
  endfunction
  function int an_pages();
    return cfg.an_enable ? an_eng.pages_seen : 0;
  endfunction

  // 对外暴露 RX 侧对齐器统计的只读视图（多 lane 取各 lane 累计）
  function int get_slip_count();
    if (cfg.num_lanes > 1) begin
      int s = 0;
      for (int i = 0; i < cfg.num_lanes; i++) s += bsync_l[i].slip_count;
      return s;
    end
    if (cfg.rs_fec_enable) return rdec.slip_count;
    return cfg.fec_enable ? fdec.slip_count : bsync.slip_count;
  endfunction

  function int get_fec_corrected();
    return fdec.corrected_count;
  endfunction

  function int get_fec_uncorrectable();
    return fdec.uncorrectable_count;
  endfunction

  function new(eth_pcs_cfg cfg);
    this.cfg  = cfg;
    rx_words  = new();
    rx_gmii   = new();
    btx       = new();
    brx       = new();
    scr       = new();
    descr     = new();
    bsync     = new();
    fenc      = new();
    fdec      = new();
    renc      = new();
    rdec      = new();
    tx_started = 0;

    if (cfg.an_enable) begin
      an_eng = new();
      an_eng.ability = cfg.an_ability;
      an_eng.nonce   = cfg.an_nonce;
      an_eng.reset();
    end

    if (cfg.lt_enable) begin
      lt_eng = new();
      lt_eng.reset();
    end

    if (cfg.num_lanes > 1) begin
      mtx = new(cfg.num_lanes, cfg.am_spacing);
      mrx = new(cfg.num_lanes, cfg.am_spacing);
      foreach (bsync_l[i]) bsync_l[i] = new();
    end
  endfunction

  // 启动全部通路线程；由 agent 的 run_phase fork 调用，永不返回。
  // 多 lane 时串行收发按 lane 各起一个线程
  task run();
    // BASE-X：GMII 采样/驱动 + 单 lane 串行收发（8b/10b 码组流）
    if (cfg.basex) begin
      fork
        basex_tx_loop();
        tx_serial_loop();
        basex_rx_loop();
        basex_rxpin_loop();
      join
    end
    // 直驱模式：只需 XGMII 两个方向的采样/驱动线程，串行线程不起
    //（位钟也已由宏关掉，省掉 10G+ 事件密度 —— 提速的主要来源）
    else if (cfg.xgmii_direct) begin
      fork
        tx_sample_loop();
        rx_pin_drive_loop();
      join
    end
    else if (cfg.num_lanes > 1) begin
      fork
        tx_sample_loop();
        rx_pin_drive_loop();
      join_none
      for (int i = 0; i < cfg.num_lanes; i++) begin
        automatic int li = i;
        fork
          tx_serial_lane_loop(li);
          rx_serial_lane_loop(li);
        join_none
      end
      wait (0);
    end
    else begin
      fork
        tx_sample_loop();
        tx_serial_loop();
        rx_serial_loop();
        rx_pin_drive_loop();
      join
    end
  endtask

  // ---------------- TX：XGMII -> 串行 ----------------

  // 每字时钟采样一拍 XGMII 并压入编码流水线。
  // 复位期间清空流水线并输出无效；未知值（连线未驱动）按全 IDLE 处理，
  // 保证码流连续 —— 真实 PHY 在无数据时同样持续发送 idle 块。
  protected task tx_sample_loop();
    forever begin
      @(cfg.vif_xgmii.phy_cb);

      if (!cfg.vif_xgmii.rst_n) begin
        pipeline_reset();
        continue;
      end

      // 直驱模式：采样对端 MAC 的 TX 拍直接交 monitor（不进编码流水线）
      if (cfg.xgmii_direct) begin
        xgmii64_t w;
        if ($isunknown(cfg.vif_xgmii.phy_cb.txd) ||
            $isunknown(cfg.vif_xgmii.phy_cb.txc))
          w = xgmii_all_idle();
        else begin
          w.data = cfg.vif_xgmii.phy_cb.txd;
          w.ctl  = cfg.vif_xgmii.phy_cb.txc;
        end
        void'(rx_words.try_put(w));
        continue;
      end

      // 首拍先灌弹性垫（经扰码器，保持码流顺序连续）。
      // 多 lane 时垫必须走 MLD 正常分发路径，保证轮转/AM 计数一致
      if (!tx_primed) begin
        if (cfg.num_lanes > 1) begin
          repeat (PRIME_BLOCKS * cfg.num_lanes) begin
            block66_t ib;
            int lane;
            bit amv;
            block66_t amb;
            ib.sync    = SYNC_CTRL;
            ib.payload = scr.scramble({56'h0, BT_CTRL});
            mtx.push_block(ib, lane, amv, amb);
            if (amv) push66(txbit_lq[lane], amb);
            push66(txbit_lq[lane], ib);
          end
        end
        else begin
          repeat (PRIME_BLOCKS) push_idle_block();
          idle_ins_count -= PRIME_BLOCKS;   // 垫不计入弹性插入统计
        end
        tx_primed = 1;
      end

      begin
        xgmii64_t w;
        block66_t blk;

        if ($isunknown(cfg.vif_xgmii.phy_cb.txd) ||
            $isunknown(cfg.vif_xgmii.phy_cb.txc))
          w = xgmii_all_idle();
        else begin
          w.data = cfg.vif_xgmii.phy_cb.txd;
          w.ctl  = cfg.vif_xgmii.phy_cb.txc;
        end

        blk = pcs_codec::encode(w);

        // 调试：前 N 个非 idle 发送块打印（加扰前），供与对端 VIP 比对
        if (tx_dump_left > 0 &&
            !(blk.sync == SYNC_CTRL && blk.payload == {56'h0, BT_CTRL})) begin
          tx_dump_left--;
          $display("[PCS_TX_BLK] @%0t sync=%b btf/first=%02x payload=%016x",
                   $time, blk.sync, blk.payload[7:0], blk.payload);
        end

        // 弹性删除：字时钟快于位时钟/66 时队列会持续增长，删 idle 块
        // 平衡速率（被删块不过扰码器，码流连续性不受影响）
        if (blk.sync == SYNC_CTRL && blk.payload == {56'h0, BT_CTRL} &&
            ((cfg.num_lanes > 1) ? txbit_lq[0].size()
                                 : txbit_q.size()) > del_thresh()) begin
          idle_del_count++;
          continue;
        end

        // RS-FEC 模式不做 66b 级加扰：cl91 的次序是"先 256B/257B 转码
        // 再加扰"，而转码要读未加扰的块类型字段；跳变密度由码字级
        // PN 加扰（rs91_pn_xor）保证。加扰在前会让转码读到乱码块类型，
        // 查表失配 -> 整条码流报废（已实测）。
        if (!cfg.rs_fec_enable) blk.payload = scr.scramble(blk.payload);

        if (cfg.num_lanes > 1) begin
          // MLD 分发：AM 先行入该 lane 队列，数据块随后
          int lane;
          bit amv;
          block66_t amb;
          mtx.push_block(blk, lane, amv, amb);
          if (amv) push66(txbit_lq[lane], amb);
          push66(txbit_lq[lane], blk);
        end
        else if (cfg.rs_fec_enable) begin
          logic rcw[RS91_CW_BITS];
          if (renc.push_block(blk, rcw))
            for (int i = 0; i < RS91_CW_BITS; i++) txbit_q.push_back(rcw[i]);
        end
        else if (cfg.fec_enable) begin
          logic cw[FEC_N];
          if (fenc.push_block(blk, cw))
            for (int i = 0; i < FEC_N; i++) txbit_q.push_back(cw[i]);
        end
        else begin
          push66(txbit_q, blk);
        end
      end
    end
  endtask

  // 每 bit 时钟送出一个线路 bit。
  // 弹性插入：位时钟快于字时钟×66 时队列会见底，非 FEC 模式现场加扰
  // 一个 idle 块补入（真实 PHY 的 idle 插入），码流保持连续合法；
  // FEC 模式无法按 bit 插补（须整码字），队列空计 underrun 并发 0。
  protected task tx_serial_loop();
    forever begin
      @(cfg.vif_serial.tx_cb);

      // AN 阶段：线上是 DME 页波形，不是 PCS 码流
      if (in_an_phase()) begin
        cfg.vif_serial.tx_cb.tx_bit <= an_eng.tx_tick();
        continue;
      end

      // LT 阶段：线上是 cl72 训练帧
      if (in_lt_phase()) begin
        cfg.vif_serial.tx_cb.tx_bit <= lt_eng.tx_tick();
        continue;
      end

      if (txbit_q.size() == 0 && tx_started && !any_fec() && !cfg.basex) begin
        $display("[PCS_TX_INS] @%0t 弹性插入（队列见底）", $time);
        push_idle_block();
      end

      if (txbit_q.size() > 0) begin
        cfg.vif_serial.tx_cb.tx_bit <= txbit_q.pop_front();
        tx_started = 1;
      end
      else begin
        cfg.vif_serial.tx_cb.tx_bit <= 1'b0;
        if (tx_started) tx_underrun_count++;
      end
    end
  endtask

  // ---------------- BASE-X（8b/10b，Clause 36）----------------

  // GMII 每字节时钟：采样一拍 -> Clause 36 TX 出一个码组（MSB 先入队）。
  // 启动预灌 8 个 idle 码组作弹性垫；队列超阈值请求删一个 /I/。
  protected task basex_tx_loop();
    gmii_byte_t in;
    logic [9:0] cg;
    bit         valid;
    forever begin
      @(cfg.vif_gmii.phy_cb);
      if (!cfg.vif_gmii.rst_n) begin
        pipeline_reset();
        continue;
      end

      if (!bx_primed) begin
        repeat (8) begin
          btx.tick('{en:0, er:0, d:8'h07}, cg, valid);
          if (valid) for (int i = 9; i >= 0; i--) txbit_q.push_back(cg[i]);
        end
        bx_primed = 1;
      end

      in.en = (cfg.vif_gmii.phy_cb.tx_en === 1'b1);
      in.er = (cfg.vif_gmii.phy_cb.tx_er === 1'b1);
      in.d  = $isunknown(cfg.vif_gmii.phy_cb.txd) ? 8'h00
                                                   : cfg.vif_gmii.phy_cb.txd;

      if (txbit_q.size() > BASEX_DEL_THRESH) btx.request_idle_delete();
      btx.tick(in, cg, valid);
      if (valid) for (int i = 9; i >= 0; i--) txbit_q.push_back(cg[i]);
    end
  endtask

  // 串行 bit -> 逗号对齐/同步/解码 -> GMII 字节（引脚队列 + monitor）
  protected task basex_rx_loop();
    gmii_byte_t out;
    logic       b;
    forever begin
      @(cfg.vif_serial.rx_cb);
      b = $isunknown(cfg.vif_serial.rx_cb.rx_bit) ? 1'b0
                                                  : cfg.vif_serial.rx_cb.rx_bit;
      if (brx.push_bit(b, out)) begin
        rxgmii_q.push_back(out);
        void'(rx_gmii.try_put(out));
      end
    end
  endtask

  // 每 GMII 字节时钟驱动一拍 RX 引脚；无数据时 rx_dv=0
  protected task basex_rxpin_loop();
    gmii_byte_t o;
    forever begin
      @(cfg.vif_gmii.phy_cb);
      o = (rxgmii_q.size() > 0) ? rxgmii_q.pop_front()
                                : '{en:0, er:0, d:8'h00};
      cfg.vif_gmii.phy_cb.rxd   <= o.d;
      cfg.vif_gmii.phy_cb.rx_dv <= o.en;
      cfg.vif_gmii.phy_cb.rx_er <= o.er;
    end
  endtask

  // 66b 块按线路发送序压入指定 bit 队列。
  // 同步头发送顺序（802.3 惯例，与 svt VIP 实测一致）：数据块 "01"
  // 先发 0、控制块 "10" 先发 1，即先发 sync[1] 再 sync[0]
  protected function void push66(ref logic q[$], input block66_t b);
    q.push_back(b.sync[1]);
    q.push_back(b.sync[0]);
    for (int i = 0; i < 64; i++) q.push_back(b.payload[i]);
  endfunction

  // 多 lane 串行发送线程：每 bit 时钟从本 lane 队列出 1 bit。
  // 多 lane 域约定生产恒盈余（字钟 +100ppm），队列空仅发生在启动
  // 瞬态（发 0，对端搜索期无害）；稳态断流计 underrun 暴露
  protected task tx_serial_lane_loop(int li);
    forever begin
      @(cfg.vif_serial_lanes[li].tx_cb);
      if (txbit_lq[li].size() > 0) begin
        cfg.vif_serial_lanes[li].tx_cb.tx_bit <= txbit_lq[li].pop_front();
        tx_started = 1;
      end
      else begin
        cfg.vif_serial_lanes[li].tx_cb.tx_bit <= 1'b0;
        if (tx_started) tx_underrun_count++;
      end
    end
  endtask

  // 多 lane 串行接收线程：本 lane 块同步 -> 锁定块交 MLD ->
  // 重组出的块走公共交付路径
  protected task rx_serial_lane_loop(int li);
    forever begin
      @(cfg.vif_serial_lanes[li].rx_cb);
      begin
        logic b = $isunknown(cfg.vif_serial_lanes[li].rx_cb.rx_bit)
                  ? 1'b0 : cfg.vif_serial_lanes[li].rx_cb.rx_bit;
        block66_t blk;
        if (bsync_l[li].push_bit(b, blk) && bsync_l[li].is_locked()) begin
          block66_t ob;
          mrx.push_block(li, blk);
          while (mrx.pop_block(ob)) deliver_block(ob);
        end
      end
    end
  endtask

  // 现场生成一个加扰后的 idle 块压入 bit 队列（仅弹性插入路径使用；
  // 与 tx_sample_loop 共用扰码器 —— 事件驱动下两者串行执行，压入顺序
  // 即线路顺序，扰码状态保持连续）
  protected function void push_idle_block();
    block66_t b;
    b.sync    = SYNC_CTRL;
    b.payload = scr.scramble({56'h0, BT_CTRL});
    txbit_q.push_back(b.sync[1]);
    txbit_q.push_back(b.sync[0]);
    for (int i = 0; i < 64; i++) txbit_q.push_back(b.payload[i]);
    idle_ins_count++;
  endfunction

  // ---------------- RX：串行 -> XGMII ----------------

  // 每 bit 时钟采样线路并推进对齐器；产出块后走解扰+解码，把 XGMII 拍
  // 同时写入 monitor mailbox 与引脚驱动队列。
  // 失败路径：解码非法块计数后仍向上递交（表现为 ERROR 字符拍），由
  // 帧装配器按损伤帧处理 —— 保证错误可观测而非静默丢弃。
  protected task rx_serial_loop();
    forever begin
      @(cfg.vif_serial.rx_cb);

      begin
        logic b = $isunknown(cfg.vif_serial.rx_cb.rx_bit)
                  ? 1'b0 : cfg.vif_serial.rx_cb.rx_bit;

        // AN 阶段：采样交仲裁引擎；完成后本拍起走 LT 或 PCS 通路
        if (in_an_phase()) begin
          an_eng.rx_tick(b);
          continue;
        end

        // LT 阶段：采样交训练引擎
        if (in_lt_phase()) begin
          lt_eng.rx_tick(b);
          continue;
        end

        if (cfg.rs_fec_enable) begin
          block66_t rblks[RS91_BLOCKS];
          if (rdec.push_bit(b, rblks))
            for (int k = 0; k < RS91_BLOCKS; k++) deliver_block(rblks[k]);
        end
        else if (cfg.fec_enable) begin
          block66_t blks[FEC_BLOCKS];
          if (fdec.push_bit(b, blks))
            for (int k = 0; k < FEC_BLOCKS; k++) deliver_block(blks[k]);
        end
        else begin
          block66_t blk;
          if (bsync.push_bit(b, blk) && bsync.is_locked())
            deliver_block(blk);
        end
      end
    end
  endtask

  // 调试：前 N 个非法块/非 idle 发送块打印，定位与对端 VIP 的块型差异
  protected int invalid_dump_left = 40;
  protected int tx_dump_left = 60;

  // 调试：+RX_DUMP_FROM_US=<t> 起打印前 N 个非 idle 接收块（解扰后
  // 块型 + 解码出的 XGMII 拍），定位复位后帧损伤的块级现场
  protected int      rx_dump_left = 0;
  protected realtime rx_dump_from = 0;

  // 单块后处理：解扰 -> 解码 -> 双路递交
  protected function void deliver_block(block66_t blk);
    xgmii64_t w;
    // 与 TX 对称：RS-FEC 模式不做 66b 级解扰（见 tx_sample_loop 注释）
    if (!cfg.rs_fec_enable) blk.payload = descr.descramble(blk.payload);
    if (!pcs_codec::decode(blk, w)) begin
      invalid_block_count++;
      if (invalid_dump_left > 0) begin
        invalid_dump_left--;
        $display("[PCS_RX_INVALID] @%0t sync=%b btf=%02x payload=%016x",
                 $time, blk.sync, blk.payload[7:0], blk.payload);
      end
    end
    if (rx_dump_left > 0 && $realtime >= rx_dump_from &&
        !(blk.sync == SYNC_CTRL && blk.payload == {56'h0, BT_CTRL})) begin
      rx_dump_left--;
      $display("[PCS_RX_BLK] @%0t sync=%b btf=%02x payload=%016x ctl=%02x data=%016x",
               $time, blk.sync, blk.payload[7:0], blk.payload, w.ctl, w.data);
    end
    void'(rx_words.try_put(w));
    rxpin_q.push_back(w);
  endfunction

  // 每字时钟从驱动队列取一拍驱动 XGMII RX 引脚；无数据时驱动 IDLE
  //（对接真实 MAC 时它只见连续合法码流）。
  protected task rx_pin_drive_loop();
    forever begin
      @(cfg.vif_xgmii.phy_cb);
      if (rxpin_q.size() > 0) begin
        xgmii64_t w = rxpin_q.pop_front();
        cfg.vif_xgmii.phy_cb.rxd <= w.data;
        cfg.vif_xgmii.phy_cb.rxc <= w.ctl;
      end
      else begin
        xgmii64_t w = xgmii_all_idle();
        cfg.vif_xgmii.phy_cb.rxd <= w.data;
        cfg.vif_xgmii.phy_cb.rxc <= w.ctl;
      end
    end
  endtask

  // 复位：清两方向流水线与队列（统计计数保留，便于跨复位分析）
  // 直驱模式发包入口：driver 把帧的 XGMII 拍压入 RX 引脚驱动队列，
  // rx_pin_drive_loop 按字时钟驱向对端 MAC（队列空自动补 idle，帧间
  // IPG 由 driver 压入的 idle 拍保证）
  function void direct_tx_word(xgmii64_t w);
    rxpin_q.push_back(w);
  endfunction

  // 调试 dump 参数注入（构造后由 agent build 调用一次即可）
  function void arm_rx_dump();
    int from_us;
    if ($value$plusargs("RX_DUMP_FROM_US=%d", from_us)) begin
      rx_dump_from = from_us * 1us;
      rx_dump_left = 120;
    end
  endfunction

  protected function void pipeline_reset();
    scr.reset();
    descr.reset();
    bsync.reset();
    fenc.reset();
    fdec.reset();
    renc.reset();
    rdec.reset();
    txbit_q.delete();
    rxpin_q.delete();
    tx_started = 0;
    tx_primed  = 0;
    if (cfg.an_enable) an_eng.reset();
    if (cfg.lt_enable) lt_eng.reset();
    btx.reset();
    brx.reset();
    rxgmii_q.delete();
    bx_primed = 0;

    if (cfg.num_lanes > 1) begin
      mtx.reset();
      mrx.reset();
      foreach (bsync_l[i]) bsync_l[i].reset();
      foreach (txbit_lq[i]) txbit_lq[i].delete();
    end
  endfunction

endclass

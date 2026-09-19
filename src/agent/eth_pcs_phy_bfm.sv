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

// 时钟约定：xgmii_if.clk 为字时钟，serial_if.clk 为 bit 时钟，两者独立
//（约定字钟 +100ppm），速率差由 TX 弹性 idle 删除/插入与 RX 引脚弹性
// 吸收（Clause 74 经 66b→65b 压缩换出校验位带宽，线速率不变）。TX bit
// 队列在稳态下深度有界。
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

  // 100G RS-FEC（4 条 FEC lane）：每 lane 每码字 1320bit，阈值取 4 码字
  localparam int RS4_DEL_THRESH = RS91_CW_BITS;

  // 任一 FEC 模式（两者互斥）
  function bit any_fec();
    return cfg.fec_enable || cfg.rs_fec_enable;
  endfunction

  // 100GBASE-R + RS-FEC：20 条 PCS lane（AM/BIP）经 RS-FEC 映射到 4 条
  // FEC lane，FEC lane 即物理 lane（无 PMA 复用）
  function bit rs4();
    return cfg.rs_fec_enable && cfg.num_lanes > 1;
  endfunction

  // 当前模式的删除阈值
  function int del_thresh();
    if (cfg.cl400)         return C400_DEL_THRESH;
    if (cfg.cl119)         return C119_DEL_THRESH;
    if (rs4())             return RS4_DEL_THRESH;
    if (cfg.rs_fec_enable) return IDLE_DEL_THRESH_RS;
    return cfg.fec_enable ? IDLE_DEL_THRESH_FEC : IDLE_DEL_THRESH;
  endfunction

  // ---------------- 流水线子对象 ----------------

  protected scrambler_c        scr;
  protected descrambler_c      descr;
  protected block_sync_c       bsync;
  protected fec_cl74_encoder_c fenc;
  protected fec_cl74_decoder_c fdec;

  // RS-FEC 流水线（cl108 单 lane / cl91 4 lane）：cfg.rs_fec_enable 时启用
  protected rs91_tx_c rstx;
  protected rs91_rx_c rsrx;

  // 多 lane（Clause 82 MLD）流水线：num_lanes>1 时启用。
  // 每物理 lane 独立 bit 队列与块同步；MLD 负责分发/AM/去偏/重组
  // Clause 73 自协商引擎（cfg.an_enable 时启用）：AN 完成前串行线由它
  // 驱动/采样，完成后 BFM 切回 PCS 数据通路；复位或数据模式链路失效
  //（见 an_link_supervise）时重新协商
  protected an73_engine_c an_eng;

  // Clause 72 链路训练引擎（cfg.lt_enable 时启用）：AN 之后、数据模式
  // 之前占用串行线跑训练帧；复位或数据模式链路失效重新协商时重新训练
  protected lt72_engine_c lt_eng;

  protected mld_tx_c     mtx;
  protected mld_rx_c     mrx;
  protected block_sync_c bsync_l[MLD_MAX_LANES];
  protected logic        txbit_lq[MLD_MAX_LANES][$];
  protected bit          lane_was_locked[MLD_MAX_LANES];   // 逐 PCS lane 失锁沿检测

  // BER 监视（hi_ber）：所有 64b/66b 模式在交付点按块统计同步头
  protected ber_mon_c    bermon;

  // MLD + Clause 74 FEC 叠加（40GBASE-KR4 / 100GBASE-CR10）：FEC 按 PCS
  // lane 各自一套（AM 也作为普通 66b 块进本 lane 码字），RX 侧取代块同步
  protected fec_cl74_encoder_c fenc_l[MLD_MAX_LANES];
  protected fec_cl74_decoder_c fdec_l[MLD_MAX_LANES];

  // 200G（Clause 119）引擎：cfg.cl119 时启用，取代 MLD
  protected c119_tx_c c119tx;
  protected c119_rx_c c119rx;
  // 400G Clause 119 CDBI engine (16 lanes, four interleaved RS codewords).
  protected c400_tx_c c400tx;
  protected c400_rx_c c400rx;

  // 200G 弹性删除阈值：TX 以码字对为粒度突发产出（每 lane 1360bit，
  // 对应 40 个 257b 组 = 160 块），阈值须不低于 2 对，取 3 对
  localparam int C119_DEL_THRESH = C119_LANE_PAIR * 3;
  localparam int C400_DEL_THRESH = C400_LANE_PAIR * 3;

  // 66b 级是否不加扰：仅 200G（Clause 119 在 257b 层加扰）。RS-FEC
  //（cl91/cl108）照常 66b 加扰，转码直接吃加扰后的块（VIP 实测）
  function bit no66scr();
    return cfg.cl119 || cfg.cl400;
  endfunction

  // 块型集合按 Clause 82（40G/100G/200G 多 lane）：无 lane4 起始/序集，
  // 序集拍 lane4~7 为零数据。单 lane（10G/5G/25G）按 Clause 49
  function bit cl82();
    return cfg.num_lanes > 1;
  endfunction

  // PMA bit 复用轮转指针（每物理 lane 一个；m=1 时恒 0）
  protected int          tx_rot[MLD_MAX_LANES];
  protected int          rx_rot[MLD_MAX_LANES];

  // 物理 lane 数与复用比
  function int nphys();
    return (cfg.num_phys > 0) ? cfg.num_phys : cfg.num_lanes;
  endfunction
  function int mux_ratio();
    if (rs4()) return 1;     // FEC lane 直接上物理 lane
    return cfg.num_lanes / nphys();
  endfunction

  // TX 串行 bit 队列（编码侧生产、串行侧消费）与 RX XGMII 引脚驱动队列
  protected logic     txbit_q[$];
  protected xgmii64_t rxpin_q[$];

  // RX 引脚弹性（形态 A 驱真实 MAC 的 XGMII/GMII RX 的关键）：恢复出的拍
  // 按线速产出、按字/字节时钟驱出，两域有 ppm 差（约定字钟 +100ppm，
  // 真实 DUT 时钟也可能偏慢）；且各模式 RX 按突发交付（cl74 每码字 32 块、
  // RS-FEC 80 块、200G 每码字对 160 块、MLD+cl74 可达 32×lane 数）。插/删
  // 只在帧间：帧间深度低于低水位就补 idle（不出队）攒回水位，高于高水位
  // 删一拍全 idle；帧内见底 = 把填充拍插进帧中间（真实 MAC 判帧损）。
  // 水位按实测最大突发自适应：低 = 最大突发 + 4，高 = 2×低 + 16（固定
  // 4/16 在 FEC 模式下实测帧内见底 23 次）。环回/交叉的 monitor 读 mailbox
  // 看不到引脚，故单独计数 rxpin_midframe_underrun，测试断言为 0
  protected bit rxpin_in_frame;
  protected int rxpin_burst;       // 本字钟周期内新压入的拍数
  protected int rxpin_max_burst;   // 实测最大突发（跨复位保留）
  int rxpin_ins_count;             // 帧间补拍次数
  int rxpin_del_count;             // 帧间删拍次数
  int rxpin_midframe_underrun;     // 帧内见底次数（应为 0）

  protected function int rxpin_low();
    return rxpin_max_burst + 4;
  endfunction
  protected function int rxpin_high();
    return 2 * rxpin_low() + 16;
  endfunction

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

  // RX 链路是否已完成块/码字/多 lane 对齐（不含 hi_ber，见 rx_link_up）。
  // 直驱模式无串行链路，恒视为已锁 —— 既有测试的等锁流程无需适配
  function bit rx_locked();
    if (cfg.xgmii_direct) return 1;
    if (cfg.basex) return brx.is_synced();
    if (in_an_phase() || in_lt_phase()) return 0;
    if (cfg.cl400) return c400rx.is_aligned();
    if (cfg.cl119) return c119rx.is_aligned();
    if (cfg.rs_fec_enable) return rsrx.is_aligned();
    if (cfg.num_lanes > 1) return mrx.is_aligned();
    return cfg.fec_enable ? fdec.is_locked() : bsync.is_locked();
  endfunction

  // 链路可用 = 已锁定/对齐且非 hi_ber（IEEE RX 在两者任一不满足时向
  // MAC 输出 Local Fault）。测试等 link-up 用本函数
  function bit rx_link_up();
    return rx_locked() && !bermon.is_hi_ber();
  endfunction

  function bit is_hi_ber();
    return bermon.is_hi_ber();
  endfunction

  function int get_hi_ber_count();
    return bermon.hi_ber_count;
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
  function int an_restarts();
    return cfg.an_enable ? an_eng.restarts : 0;
  endfunction

  // AN 完成后的链路失效监督（IEEE 73.10.4：AN_GOOD_CHECK/AN_GOOD 下 HCD
  // 链路失效即重新协商）：数据模式 RX 链路持续不可用超过
  // an_link_fail_inhibit 就回到 AN —— 否则对端（如 VIP 开 internal_restart）
  // 已回 AN 发 DME 页，两端永久僵持。链路状态按 IEEE PCS_status =
  // block_lock && !hi_ber（rx_link_up）：DME 在个别 bit 相位下同步头大多
  // 合法，块锁可保持不丢，只看 rx_locked 会漏判。每字时钟调用一次
  protected realtime an_fail_since = -1;

  protected function void an_link_supervise();
    if (!cfg.an_enable || in_an_phase() || in_lt_phase() || rx_link_up()) begin
      an_fail_since = -1;
      return;
    end
    if (an_fail_since < 0) an_fail_since = $realtime;
    else if ($realtime - an_fail_since > cfg.an_link_fail_inhibit) begin
      an_fail_since = -1;
      an_eng.restart();
      if (cfg.lt_enable) lt_eng.reset();
      bsync.reset();
      fdec.reset();
      rsrx.reset();
      bermon.reset();
      rx_warm = 1;
    end
  endfunction

  // 对外暴露 RX 侧对齐器统计的只读视图（多 lane 取各 lane 累计）
  function int get_slip_count();
    if (cfg.rs_fec_enable) return rsrx.slip_count;
    if (cfg.num_lanes > 1) begin
      int s = 0;
      for (int i = 0; i < cfg.num_lanes; i++)
        s += cfg.fec_enable ? fdec_l[i].slip_count : bsync_l[i].slip_count;
      return s;
    end
    return cfg.fec_enable ? fdec.slip_count : bsync.slip_count;
  endfunction

  // FEC 纠错统计（RS-FEC 取码字计数；cl74 MLD 叠加时取各 lane 累计）
  function int get_fec_corrected();
    int s = 0;
    if (cfg.rs_fec_enable) return rsrx.corrected_count();
    if (cfg.num_lanes <= 1) return fdec.corrected_count;
    for (int i = 0; i < cfg.num_lanes; i++) s += fdec_l[i].corrected_count;
    return s;
  endfunction

  function int get_fec_uncorrectable();
    int s = 0;
    if (cfg.rs_fec_enable) return rsrx.rs_uncorrectable;
    if (cfg.num_lanes <= 1) return fdec.uncorrectable_count;
    for (int i = 0; i < cfg.num_lanes; i++) s += fdec_l[i].uncorrectable_count;
    return s;
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
    rstx      = new(rs4() ? 4 : 1);
    rsrx      = new(rs4() ? 4 : 1);
    bermon    = new(cfg.ber_limit, cfg.ber_window_blocks);
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
      foreach (fenc_l[i]) fenc_l[i] = new();
      foreach (fdec_l[i]) fdec_l[i] = new();
    end
    c119tx = new();
    c119rx = new();
    c400tx = new();
    c400rx = new();
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
      for (int i = 0; i < nphys(); i++) begin
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

      // AN/LT 阶段：线上是 DME 页/训练帧，PCS 发送数据丢弃（IEEE 下 AN/LT
      // 占用 PMA，PCS TX 不缓存）。TX 流水线保持空且未预灌，建链完成后从
      // 新垫开始 —— 否则 MAC 此间发的拍（如见 LF 后持续发的 Remote Fault，
      // 非 idle 删不掉）会在 txbit_q 里无界堆积、建链后才迟迟放出
      if (in_an_phase() || in_lt_phase()) begin
        if (tx_primed) begin
          txbit_q.delete();
          fenc.reset();
          rstx.reset();
          tx_primed  = 0;
          tx_started = 0;
        end
        continue;
      end

      // 首拍先灌弹性垫（经扰码器，保持码流顺序连续）。
      // 多 lane 时垫必须走 MLD 正常分发路径，保证轮转/AM 计数一致
      if (!tx_primed) begin
        if (cfg.cl400) begin
          block66_t ib;
          ib.sync    = SYNC_CTRL;
          ib.payload = {56'h0, BT_CTRL};
          // The first CDBI pair carries AM+PRBS overhead (288 source blocks),
          // followed by full 320-block pairs.  Keep three emitted pairs in
          // the elastic queues before the serial consumers start.
          repeat (288 + 320 + 320) if (c400tx.push_block(ib)) c400_drain();
        end
        else if (cfg.cl119) begin
          block66_t ib;
          ib.sync    = SYNC_CTRL;
          ib.payload = {56'h0, BT_CTRL};
          // 预灌 3 个完整码字对（首对 36 组=144 块，其余每对 40 组=160 块）：
          // 首对块数少于后续对，首对发完后生产下一对（160 字钟）慢于 lane
          // 放完一对，须有整对余量垫底，否则断流插 0 毁掉后续码字（已实测）
          repeat (144 + 160 + 160) if (c119tx.push_block(ib)) c119_drain();
        end
        else if (cfg.rs_fec_enable) begin
          // RS-FEC：预灌整码字垫（码字整体突发入队）。周期首码字因 AM 占位
          // 装的块少（4 lane 60 块 / 单 lane 76 块），其后每码字 80 块：
          // 4 lane 灌 3 码字（每 lane 3960bit），单 lane 灌 2 码字（10560bit）
          repeat (rs4() ? (60 + 80 + 80) : (76 + 80)) begin
            block66_t ib;
            ib.sync    = SYNC_CTRL;
            ib.payload = scr.scramble({56'h0, BT_CTRL});
            if (rstx.push_block(ib)) rs_drain();
          end
        end
        else if (cfg.num_lanes > 1) begin
          // FEC 叠加时每 lane 预灌 2 个整码字（码字整体突发入队，垫须按
          // 码字粒度，同单 lane FEC 的删除阈值取法）
          repeat ((cfg.fec_enable ? 2 * FEC_BLOCKS : PRIME_BLOCKS) * cfg.num_lanes) begin
            block66_t ib;
            int lane;
            bit amv;
            block66_t amb;
            ib.sync    = SYNC_CTRL;
            ib.payload = scr.scramble({56'h0, BT_CTRL});
            mtx.push_block(ib, lane, amv, amb);
            if (amv) lane_push(lane, amb);
            lane_push(lane, ib);
          end
        end
        else if (cfg.fec_enable) begin
          // 单 lane cl74：经编码器预灌 2 个整码字。此前直灌原始 66b 块，
          // 首码字（需集满 32 块）产出前线路断流 ~1500bit，stress 的
          // tx_underrun==0 检查因此一直报错（回归判据未查 UVM_ERROR 而漏过）
          repeat (2 * FEC_BLOCKS) begin
            block66_t ib;
            logic     cw[FEC_N];
            ib.sync    = SYNC_CTRL;
            ib.payload = scr.scramble({56'h0, BT_CTRL});
            if (fenc.push_block(ib, cw))
              for (int i = 0; i < FEC_N; i++) txbit_q.push_back(cw[i]);
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

        blk = pcs_codec::encode(w, cl82());

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

        // 66b 级加扰：200G 除外（Clause 119 在 257b 层加扰）。RS-FEC 直接
        // 转码加扰后的块，只保留首个控制块加扰后的类型低 4 位（VIP 实测）
        if (!no66scr()) blk.payload = scr.scramble(blk.payload);

        if (cfg.cl400) begin
          if (c400tx.push_block(blk)) c400_drain();
        end
        else if (cfg.cl119) begin
          if (c119tx.push_block(blk)) c119_drain();
        end
        else if (cfg.rs_fec_enable) begin
          if (rstx.push_block(blk)) rs_drain();
        end
        else if (cfg.num_lanes > 1) begin
          // MLD 分发：AM 先行入该 lane 队列，数据块随后
          int lane;
          bit amv;
          block66_t amb;
          mtx.push_block(blk, lane, amv, amb);
          if (amv) lane_push(lane, amb);
          lane_push(lane, blk);
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
        rxpin_burst++;
        void'(rx_gmii.try_put(out));
      end
    end
  endtask

  // 每 GMII 字节时钟驱动一拍 RX 引脚；无数据时 rx_dv=0
  // 弹性约定同 XGMII（见 rxpin_low 处注释）：帧 = rx_dv 连续为 1 的区间
  protected task basex_rxpin_loop();
    gmii_byte_t o;
    forever begin
      @(cfg.vif_gmii.phy_cb);
      rxpin_note_burst();
      o = '{en:0, er:0, d:8'h00};
      if (rxgmii_q.size() == 0) begin
        if (rxpin_in_frame) begin
          rxpin_midframe_underrun++;
          rxpin_in_frame = 0;
        end
      end
      else if (!rxpin_in_frame && rxgmii_q.size() < rxpin_low()) begin
        rxpin_ins_count++;
      end
      else begin
        if (!rxpin_in_frame && rxgmii_q.size() > rxpin_high() &&
            !rxgmii_q[0].en && !rxgmii_q[0].er) begin
          void'(rxgmii_q.pop_front());
          rxpin_del_count++;
        end
        o = rxgmii_q.pop_front();
        rxpin_in_frame = o.en;
      end
      cfg.vif_gmii.phy_cb.rxd   <= o.d;
      cfg.vif_gmii.phy_cb.rx_dv <= o.en;
      cfg.vif_gmii.phy_cb.rx_er <= o.er;
    end
  endtask

  // RS-FEC：把本次产出的 FEC lane 比特搬入串行队列（单 lane 走 txbit_q）
  protected function void rs_drain();
    if (!rs4()) begin
      while (rstx.out_bits[0].size() > 0) txbit_q.push_back(rstx.out_bits[0].pop_front());
      return;
    end
    for (int l = 0; l < 4; l++)
      while (rstx.out_bits[l].size() > 0)
        txbit_lq[l].push_back(rstx.out_bits[l].pop_front());
  endfunction

  // 200G：把 c119 TX 本次产出的各逻辑 lane 比特搬入串行队列
  protected function void c119_drain();
    for (int l = 0; l < C119_LANES; l++)
      while (c119tx.out_bits[l].size() > 0)
        txbit_lq[l].push_back(c119tx.out_bits[l].pop_front());
  endfunction

  // 400G: move each CDBI logical lane's newly encoded bits into its PMA
  // queue.  For ETH_400G_SERIAL there is a one-to-one 16-lane mapping.
  protected function void c400_drain();
    for (int l = 0; l < C400_LANES; l++)
      while (c400tx.out_bits[l].size() > 0)
        txbit_lq[l].push_back(c400tx.out_bits[l].pop_front());
  endfunction

  // 66b 块按线路发送序压入指定 bit 队列。
  // 同步头发送顺序（802.3 惯例，与 svt VIP 实测一致）：数据块 "01"
  // 先发 0、控制块 "10" 先发 1，即先发 sync[1] 再 sync[0]
  protected function void push66(ref logic q[$], input block66_t b);
    q.push_back(b.sync[1]);
    q.push_back(b.sync[0]);
    for (int i = 0; i < 64; i++) q.push_back(b.payload[i]);
  endfunction

  // MLD 分发出的块（含 AM）入指定 PCS lane：FEC 叠加时先进本 lane 的
  // cl74 编码器，集满 32 块整码字入队；否则 66b 直接入队
  protected function void lane_push(int lane, block66_t b);
    logic cw[FEC_N];
    if (!cfg.fec_enable) begin
      push66(txbit_lq[lane], b);
      return;
    end
    if (fenc_l[lane].push_block(b, cw))
      for (int i = 0; i < FEC_N; i++) txbit_lq[lane].push_back(cw[i]);
  endfunction

  // 多 lane 串行发送线程：每 bit 时钟从本 lane 队列出 1 bit。
  // 多 lane 域约定生产恒盈余（字钟 +100ppm），队列空仅发生在启动
  // 瞬态（发 0，对端搜索期无害）；稳态断流计 underrun 暴露
  // li 为物理 lane；PMA 复用时逐 bit 轮转取下属 PCS lane p*m+k 的队列
  protected task tx_serial_lane_loop(int li);
    int m, pcs;
    forever begin
      @(cfg.vif_serial_lanes[li].tx_cb);
      m   = mux_ratio();
      pcs = li * m + tx_rot[li];
      tx_rot[li] = (tx_rot[li] + 1) % m;
      if (txbit_lq[pcs].size() > 0) begin
        cfg.vif_serial_lanes[li].tx_cb.tx_bit <= txbit_lq[pcs].pop_front();
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
  // li 为物理 lane；PMA 解复用逐 bit 轮转分发到下属 PCS 流 p*m+k。
  // 解复用相位任意：各流独立块同步，哪条流是哪条 PCS lane 由 MLD 按
  // AM 自识别（与 TX 映射无关，对端复用映射不同也能收）
  protected task rx_serial_lane_loop(int li);
    int m, pcs;
    bit pma_skip;
    logic b;
    block66_t blk, ob;
    if ($test$plusargs("PMA_RX_FIRST")) pma_skip = 1'b1;
    forever begin
      @(cfg.vif_serial_lanes[li].rx_cb);
      // ETH_50G_SERIAL drives the 4-to-2 gearbox at the 53.125 GHz
      // reference, while each physical data bit is presented on alternate
      // reference edges.  Keep the normal bit-per-edge path as the default;
      // +PMA_RX_DIV2 enables the diagnostic sampling mode for the external
      // SVT source without changing loopback mappings.
      if ($test$plusargs("PMA_RX_DIV2") && cfg.num_lanes == 4 &&
          nphys() == 2) begin
        // ETH_50G_SERIAL drives each PMA data bit at half the 53.125GHz
        // reference (25.78125G in the SVT model).  Select every other edge.
        // The first selected edge is phase-sensitive after reset; +PMA_RX_FIRST
        // starts with the first edge instead of the default second edge.
        pma_skip = ~pma_skip;
        if (pma_skip) continue;
      end
      m   = mux_ratio();
      pcs = li * m + rx_rot[li];
      rx_rot[li] = (rx_rot[li] + 1) % m;
      b = $isunknown(cfg.vif_serial_lanes[li].rx_cb.rx_bit)
          ? 1'b0 : cfg.vif_serial_lanes[li].rx_cb.rx_bit;
      if (cfg.cl400) begin
        c400rx.push_bit(li, b);
        while (c400rx.pop_block(ob)) deliver_block(ob);
        continue;
      end
      if (cfg.cl119) begin
        c119rx.push_bit(li, b);
        while (c119rx.pop_block(ob)) deliver_block(ob);
        continue;
      end
      // 100G RS-FEC：物理 lane 即 FEC lane，AM 锁定/识别/去偏斜在 rsrx 内
      if (rs4()) begin
        rsrx.push_bit(li, b);
        if (!rsrx.is_aligned()) rx_warm = 1;
        while (rsrx.pop_block(ob)) deliver_block(ob);
        continue;
      end
      // cl74 叠加：本 PCS 流的 FEC 码字对齐取代块同步，译出的 32 块交 MLD
      if (cfg.fec_enable) begin
        block66_t fb[FEC_BLOCKS];
        if (fdec_l[pcs].push_bit(b, fb)) begin
          foreach (fb[k]) mrx.push_block(pcs, fb[k]);
          if (!mrx.is_aligned()) rx_warm = 1;
          while (mrx.pop_block(ob)) deliver_block(ob);
        end
        lane_lock_edge(pcs, fdec_l[pcs].is_locked());
        continue;
      end
      if (bsync_l[pcs].push_bit(b, blk) && bsync_l[pcs].is_locked()) begin
        mrx.push_block(pcs, blk);
        if (!mrx.is_aligned()) rx_warm = 1;
        while (mrx.pop_block(ob)) deliver_block(ob);
      end
      lane_lock_edge(pcs, bsync_l[pcs].is_locked());
    end
  endtask

  // 某 PCS lane 由锁定转失锁：IEEE align_status 要求全部 lane 块锁定，
  // 故 MLD 立即整体重对齐。否则 mrx 仍报已对齐、在失锁 lane 上空等，
  // MAC 侧见不到 Local Fault（该 lane 重锁后才靠 AM 间隔自检发现错位）
  protected function void lane_lock_edge(int pcs, bit locked);
    if (lane_was_locked[pcs] && !locked) begin
      mrx.reset();
      rx_warm = 1;
    end
    lane_was_locked[pcs] = locked;
  endfunction

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
          block66_t rb;
          rsrx.push_bit(0, b);
          if (!rsrx.is_aligned()) rx_warm = 1;
          while (rsrx.pop_block(rb)) deliver_block(rb);
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
          else if (!bsync.is_locked())
            rx_warm = 1;
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
  // 解扰器热身：锁定/对齐后交付的第一个块由陈旧解扰状态解出（自同步
  // 解扰须先吃进 58bit 新输入），净荷必为乱码 —— 多数解成非法块（启动
  // 期常见的 invalid=1），但可能恰好解成合法帧起始块、后接 idle 而被
  // 报成 len=0 损伤帧（100G 对齐时两个方向各出现一次，已实测）。故该块
  // 只喂解扰器更新状态，向上以 idle 代替。
  protected bit rx_warm = 1;

  protected function void deliver_block(block66_t blk);
    xgmii64_t w;
    // 与 TX 对称：仅 200G 不做 66b 级解扰（见 tx_sample_loop 注释）
    if (!no66scr()) blk.payload = descr.descramble(blk.payload);
    // BER 监视；链路未起（hi_ber、cl74 锁定判据期间的干净码字）不向上
    // 交付 —— IEEE 此时向 MAC 输出 Local Fault（引脚由 rx_pin_drive_loop
    // 驱出）。解扰照常推进，链路起来后首块即可正确解出
    bermon.push_sh(blk.sync == SYNC_DATA || blk.sync == SYNC_CTRL);
    if (!rx_link_up()) return;
    if (rx_warm && !no66scr()) begin
      rx_warm = 0;
      w = xgmii_all_idle();
      void'(rx_words.try_put(w));
      rxpin_q.push_back(w);
      rxpin_burst++;
      return;
    end
    if (!pcs_codec::decode(blk, w, cl82())) begin
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
    rxpin_burst++;
  endfunction

  // 每字时钟从驱动队列取一拍驱动 XGMII RX 引脚；无数据时驱动 IDLE，
  // 链路未起时驱动 Local Fault（对接真实 MAC 时它只见连续合法码流）。
  // 插/删与帧内见底的约定见 rxpin_low 处注释
  protected task rx_pin_drive_loop();
    xgmii64_t w;
    forever begin
      @(cfg.vif_xgmii.phy_cb);
      rxpin_note_burst();
      an_link_supervise();
      w = xgmii_all_idle();
      // 链路未起（未锁定/未对齐、hi_ber、AN/LT 阶段）：IEEE RX 状态机输出
      // LBLOCK_R，MAC 侧见连续 Local Fault，残留拍作废。BER 监视随失锁
      // 复位（BER_MON_INIT）。直驱模式恒视为已起
      if (!rx_link_up()) begin
        if (!rx_locked()) bermon.reset();
        rxpin_q.delete();
        rxpin_in_frame = 0;
        w = xgmii_local_fault(cl82());
      end
      else if (rxpin_q.size() == 0) begin
        if (rxpin_in_frame) begin
          rxpin_midframe_underrun++;
          rxpin_in_frame = 0;
        end
      end
      // 帧间补 idle 攒回低水位。直驱模式不补也不删：那时队列是 driver
      // 整批压入的发送队列（含刻意留的 IPG），不是弹性缓冲 —— 补会把
      // 尾部不足水位的帧永久扣住，删会压缩 IPG
      else if (!cfg.xgmii_direct && !rxpin_in_frame &&
               rxpin_q.size() < rxpin_low()) begin
        rxpin_ins_count++;
      end
      else begin
        if (!cfg.xgmii_direct && !rxpin_in_frame &&
            rxpin_q.size() > rxpin_high() && rxpin_q[0] == xgmii_all_idle()) begin
          void'(rxpin_q.pop_front());
          rxpin_del_count++;
        end
        w = rxpin_q.pop_front();
        rxpin_track(w);
      end
      cfg.vif_xgmii.phy_cb.rxd <= w.data;
      cfg.vif_xgmii.phy_cb.rxc <= w.ctl;
    end
  endtask

  // 每个驱动周期结算一次：上个周期内新压入的拍数即一次突发，取最大值
  protected function void rxpin_note_burst();
    if (rxpin_burst > rxpin_max_burst) rxpin_max_burst = rxpin_burst;
    rxpin_burst = 0;
  endfunction

  // 按驱出的拍跟踪是否处于帧内（逐 lane 顺序扫描）：S 置位；其余任何控制
  // 字符清零 —— /T/ 正常结束，/E/ 等说明帧已损（与帧装配器一致），否则
  // 丢了 /T/ 的坏帧会让帧间弹性一直冻结
  protected function void rxpin_track(xgmii64_t w);
    for (int i = 0; i < 8; i++)
      if (w.ctl[i]) rxpin_in_frame = (w.data[8*i +: 8] == XGMII_START);
  endfunction

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
    rstx.reset();
    rsrx.reset();
    txbit_q.delete();
    rxpin_q.delete();
    rxpin_in_frame = 0;
    tx_started = 0;
    tx_primed  = 0;
    if (cfg.an_enable) an_eng.reset();
    if (cfg.lt_enable) lt_eng.reset();
    btx.reset();
    brx.reset();
    rxgmii_q.delete();
    bx_primed = 0;
    rx_warm   = 1;
    bermon.reset();
    foreach (lane_was_locked[i]) lane_was_locked[i] = 0;
    an_fail_since = -1;

    c119tx.reset();
    c119rx.reset();
    c400tx.reset();
    c400rx.reset();
    if (cfg.num_lanes > 1) begin
      mtx.reset();
      mrx.reset();
      foreach (bsync_l[i]) bsync_l[i].reset();
      foreach (fenc_l[i]) fenc_l[i].reset();
      foreach (fdec_l[i]) fdec_l[i].reset();
      foreach (txbit_lq[i]) txbit_lq[i].delete();
      foreach (tx_rot[i]) tx_rot[i] = 0;
      foreach (rx_rot[i]) rx_rot[i] = 0;
      // Optional PMA phase override for external multi-lane sources.  A
      // gearbox can begin with either member of a 2:1 interleave after the
      // far-end reset; the normal loopback path remains phase 0.  This is
      // deliberately a run-time diagnostic knob, not a protocol default.
      begin
        int pma_phase;
        if ($value$plusargs("PMA_RX_PHASE=%d", pma_phase) && mux_ratio() > 1)
          foreach (rx_rot[i]) rx_rot[i] = pma_phase % mux_ratio();
      end
    end
  endfunction

endclass

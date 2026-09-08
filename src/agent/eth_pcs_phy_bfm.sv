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

  // 协议完整性统计（记分板/测试 check_phase 汇总）
  int invalid_block_count;   // 解码非法块（坏同步头/未知块型）
  int tx_underrun_count;     // 串行发送队列空（仅在数据已开始后计数）

  // ---------------- 流水线子对象 ----------------

  protected scrambler_c        scr;
  protected descrambler_c      descr;
  protected block_sync_c       bsync;
  protected fec_cl74_encoder_c fenc;
  protected fec_cl74_decoder_c fdec;

  // TX 串行 bit 队列（编码侧生产、串行侧消费）与 RX XGMII 引脚驱动队列
  protected logic     txbit_q[$];
  protected xgmii64_t rxpin_q[$];
  protected bit       tx_started;

  // RX 链路是否已完成块/码字对齐（test 在发流前等待，模拟 link-up）
  function bit rx_locked();
    return cfg.fec_enable ? fdec.is_locked() : bsync.is_locked();
  endfunction

  // 对外暴露 RX 侧对齐器统计的只读视图
  function int get_slip_count();
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
    scr       = new();
    descr     = new();
    bsync     = new();
    fenc      = new();
    fdec      = new();
    tx_started = 0;
  endfunction

  // 启动全部通路线程；由 agent 的 run_phase fork 调用，永不返回
  task run();
    fork
      tx_sample_loop();
      tx_serial_loop();
      rx_serial_loop();
      rx_pin_drive_loop();
    join
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
        blk.payload = scr.scramble(blk.payload);

        if (cfg.fec_enable) begin
          logic cw[FEC_N];
          if (fenc.push_block(blk, cw))
            for (int i = 0; i < FEC_N; i++) txbit_q.push_back(cw[i]);
        end
        else begin
          txbit_q.push_back(blk.sync[0]);
          txbit_q.push_back(blk.sync[1]);
          for (int i = 0; i < 64; i++) txbit_q.push_back(blk.payload[i]);
        end
      end
    end
  endtask

  // 每 bit 时钟送出一个线路 bit。队列尚未产出首 bit 前发 0（对端处于
  // 搜索态，无害）；数据开始后再空即为真实 underrun，计数暴露。
  protected task tx_serial_loop();
    forever begin
      @(cfg.vif_serial.tx_cb);
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

        if (cfg.fec_enable) begin
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

  // 单块后处理：解扰 -> 解码 -> 双路递交
  protected function void deliver_block(block66_t blk);
    xgmii64_t w;
    blk.payload = descr.descramble(blk.payload);
    if (!pcs_codec::decode(blk, w)) invalid_block_count++;
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
  protected function void pipeline_reset();
    scr.reset();
    descr.reset();
    bsync.reset();
    fenc.reset();
    fdec.reset();
    txbit_q.delete();
    rxpin_q.delete();
    tx_started = 0;
  endfunction

endclass

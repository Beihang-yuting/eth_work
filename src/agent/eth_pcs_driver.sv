// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— MAC 替身驱动器（阶段 1 环回用）
// 职责：从 sequencer 取 eth_frame_txn，转换为 XGMII 拍序列（含 preamble/
//       FCS/IPG）驱动 xgmii_if 的 MAC 侧，同时把已发送帧经 tx_ap 递交
//       记分板作为期望流。对接真实 MAC（阶段 3）时本组件不例化，XGMII
//       由 MAC RTL 驱动。
// 依赖：eth_pcs_cfg / eth_frame_txn / eth_frame_utils。
// 所有权：agent 在主动模式下创建；随 UVM 组件树存续。
// -----------------------------------------------------------------------------

// 为什么拆成取帧线程 + 驱动线程：XGMII 无握手，引脚必须每拍有合法值
// （帧间为 IDLE)；单线程 get_next_item 阻塞期间引脚会悬空。驱动线程
// 恒定节拍消费字队列、空则补 IDLE，取帧线程只负责灌队列。
class eth_pcs_driver extends uvm_driver #(eth_frame_txn);

  `uvm_component_utils(eth_pcs_driver)

  eth_pcs_cfg cfg;

  // 直驱模式下的发包通道（agent 注入；普通模式不用）
  eth_pcs_phy_bfm bfm;

  // 已发送帧（期望流）
  uvm_analysis_port #(eth_frame_txn) tx_ap;

  // 待驱动 XGMII 拍队列：fetch 线程生产，drive 线程消费
  protected xgmii64_t word_q[$];

  // BASE-X：待驱动 GMII 字节队列（帧字节 tx_en=1 + IPG 字节 tx_en=0）
  protected gmii_byte_t gbyte_q[$];

  // BASE-X 帧间 IPG 字节数（最小 IPG 12 字节）
  localparam int GMII_IPG = 12;

  // 发送队列是否已排空（sequencer 供帧不耗时，帧会先整批入队；测试
  // 判"在途帧已全部发出"须看队列而非固定延时 —— 线速越低排空越久）
  function bit is_idle();
    return cfg.basex ? (gbyte_q.size() == 0) : (word_q.size() == 0);
  endfunction

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tx_ap = new("tx_ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(eth_pcs_cfg)::get(this, "", "cfg", cfg) || cfg == null)
      `uvm_fatal("CFG", "eth_pcs_driver 未取得 eth_pcs_cfg")
  endfunction

  virtual task run_phase(uvm_phase phase);
    if (cfg.xgmii_direct && bfm == null)
      `uvm_fatal("BFM", "直驱模式需要 agent 注入 phy_bfm 句柄")
    fork
      fetch_loop();
      // 直驱模式不驱 XGMII 引脚（引脚属于对端 MAC 方向，由 BFM 驱动）
      if (cfg.basex)              gmii_drive_loop();
      else if (!cfg.xgmii_direct) drive_loop();
    join
  endtask

  // 取帧线程：帧 -> 拍序列 + 帧间 IDLE，入队后立即 item_done
  //（XGMII 无反压，队列即已"接受"该帧）。
  // 必须先等复位释放：sequencer 供帧不耗仿真时间，若在复位期取帧，
  // drive_loop 的复位清队会把整批帧静默丢光。
  protected task fetch_loop();
    if (cfg.basex) begin
      gmii_fetch_loop();
      return;
    end

    wait (cfg.vif_xgmii.rst_n === 1'b1);
    @(cfg.vif_xgmii.mac_cb);

    for (int n = 0; ; n++) begin
      eth_frame_txn t;
      xgmii64_t words[$];

      seq_item_port.get_next_item(t);

      // lane4_start：奇数帧从 lane4 起（交替覆盖两个起点）
      eth_frame_to_words(t.data, words, cfg.lane4_start && n[0]);
      if (cfg.xgmii_direct) begin
        // 直驱：拍序列绕过引脚，直接进 BFM 的对端驱动队列
        foreach (words[i]) bfm.direct_tx_word(words[i]);
        repeat (cfg.idle_words_per_gap) bfm.direct_tx_word(xgmii_all_idle());
      end
      else begin
        foreach (words[i]) word_q.push_back(words[i]);
        repeat (cfg.idle_words_per_gap) word_q.push_back(xgmii_all_idle());
      end

      tx_ap.write(t);
      seq_item_port.item_done();
    end
  endtask

  // 驱动线程：复位驱动 IDLE 并清队列；正常时每拍出队或补 IDLE
  protected task drive_loop();
    forever begin
      @(cfg.vif_xgmii.mac_cb);

      if (!cfg.vif_xgmii.rst_n) begin
        xgmii64_t w = xgmii_all_idle();
        word_q.delete();
        cfg.vif_xgmii.mac_cb.txd <= w.data;
        cfg.vif_xgmii.mac_cb.txc <= w.ctl;
        continue;
      end

      begin
        xgmii64_t w = (word_q.size() > 0) ? word_q.pop_front()
                                          : xgmii_all_idle();
        cfg.vif_xgmii.mac_cb.txd <= w.data;
        cfg.vif_xgmii.mac_cb.txc <= w.ctl;
      end
    end
  endtask

  // ---------------- BASE-X（GMII）----------------

  // 取帧 -> GMII 字节（前导/SFD/帧/FCS，tx_en=1）+ IPG（tx_en=0）
  protected task gmii_fetch_loop();
    wait (cfg.vif_gmii.rst_n === 1'b1);
    @(cfg.vif_gmii.mac_cb);
    forever begin
      eth_frame_txn t;
      byte unsigned b[$];
      seq_item_port.get_next_item(t);
      eth_frame_to_gmii(t.data, b);
      foreach (b[i]) gbyte_q.push_back('{en:1, er:0, d:b[i]});
      repeat (GMII_IPG) gbyte_q.push_back('{en:0, er:0, d:8'h07});
      tx_ap.write(t);
      seq_item_port.item_done();
    end
  endtask

  // 每 GMII 字节时钟出一拍；复位期间清队并驱 idle
  protected task gmii_drive_loop();
    gmii_byte_t o;
    forever begin
      @(cfg.vif_gmii.mac_cb);
      if (!cfg.vif_gmii.rst_n) begin
        gbyte_q.delete();
        o = '{en:0, er:0, d:8'h07};
      end
      else
        o = (gbyte_q.size() > 0) ? gbyte_q.pop_front()
                                 : '{en:0, er:0, d:8'h07};
      cfg.vif_gmii.mac_cb.txd   <= o.d;
      cfg.vif_gmii.mac_cb.tx_en <= o.en;
      cfg.vif_gmii.mac_cb.tx_er <= o.er;
    end
  endtask

endclass

// sequencer 无定制需求，直接用参数化基类的别名保持命名一致
typedef uvm_sequencer #(eth_frame_txn) eth_pcs_sequencer;

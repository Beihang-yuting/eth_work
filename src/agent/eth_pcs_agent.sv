// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— PCS/SerDes agent 顶层组件
// 职责：按 cfg 装配 BFM、monitor 以及（主动模式）sequencer+driver；
//       run_phase 启动 BFM 数据通路线程。对外只暴露 driver.tx_ap 与
//       monitor.rx_ap 两个分析口和 cfg 句柄。
// 依赖：本目录全部组件类。
// 所有权：env/test 创建；BFM 纯类对象由 agent 构造并注入 monitor。
// -----------------------------------------------------------------------------

// 为什么 BFM 不做成 uvm_component：数据通路是纯行为线程集合，无 phase
// 语义需求；类对象便于在单元测试中脱离 UVM 树独立实例化复用。
class eth_pcs_agent extends uvm_agent;

  `uvm_component_utils(eth_pcs_agent)

  eth_pcs_cfg       cfg;
  eth_pcs_phy_bfm   bfm;
  eth_pcs_monitor   mon;
  eth_pcs_driver    drv;
  eth_pcs_sequencer sqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // 装配：cfg 必须已由 test 放入本层级 config_db；接口句柄缺失即致命
  //（后续所有线程都依赖，缺了只会以更难懂的方式挂死）。
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(eth_pcs_cfg)::get(this, "", "cfg", cfg) || cfg == null)
      `uvm_fatal("CFG", "eth_pcs_agent 未取得 eth_pcs_cfg")
    if (cfg.vif_xgmii == null)
      `uvm_fatal("CFG", "eth_pcs_cfg.vif_xgmii 为空")
    if (cfg.num_lanes <= 1 && cfg.vif_serial == null)
      `uvm_fatal("CFG", "单 lane 模式 vif_serial 为空")
    if (cfg.num_lanes > 1) begin
      if (cfg.fec_enable)
        `uvm_fatal("CFG", "MLD 多 lane 模式暂不支持叠加 FEC")
      for (int i = 0; i < cfg.num_lanes; i++)
        if (cfg.vif_serial_lanes[i] == null)
          `uvm_fatal("CFG", $sformatf("vif_serial_lanes[%0d] 为空", i))
    end

    // 向子组件透传同一 cfg
    uvm_config_db#(eth_pcs_cfg)::set(this, "*", "cfg", cfg);

    if (cfg.basex && (cfg.fec_enable || cfg.rs_fec_enable || cfg.num_lanes > 1 ||
                      cfg.an_enable || cfg.lt_enable || cfg.xgmii_direct))
      `uvm_fatal("CFG", "BASE-X 模式不与 FEC/MLD/AN/LT/直驱叠加")
    if (cfg.basex && cfg.vif_gmii == null)
      `uvm_fatal("CFG", "BASE-X 模式需要 vif_gmii")
    if (cfg.fec_enable && cfg.rs_fec_enable)
      `uvm_fatal("CFG", "fec_enable 与 rs_fec_enable 互斥（不同的码，不叠加）")
    if (cfg.rs_fec_enable && cfg.num_lanes > 1)
      `uvm_fatal("CFG", "RS-FEC 与 MLD 叠加未实现（随 100G 多 lane 一并做）")

    bfm = new(cfg);
    bfm.arm_rx_dump();
    mon = eth_pcs_monitor::type_id::create("mon", this);

    if (cfg.is_active) begin
      drv = eth_pcs_driver::type_id::create("drv", this);
      sqr = eth_pcs_sequencer::type_id::create("sqr", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.bfm = bfm;
    if (drv != null) drv.bfm = bfm;
    if (cfg.is_active)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bfm.run();
  endtask

endclass

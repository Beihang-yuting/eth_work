// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— RX 侧帧监视器
// 职责：消费 BFM 还原的 XGMII 拍流（rx_words mailbox），用帧装配器检出
//       帧并校验 preamble/FCS，经 rx_ap 递交记分板；report_phase 汇总
//       块级/帧级协议完整性统计（非法块、slip、FEC 纠错、CRC 错）。
// 依赖：eth_pcs_cfg / eth_frame_txn / frame_assembler_c / eth_pcs_phy_bfm。
// 所有权：agent 创建；bfm 句柄由 agent 在 connect 前注入（非 config_db，
//         因 BFM 是纯类对象、与 monitor 同属一个 agent 内部装配）。
// -----------------------------------------------------------------------------

// 为什么从 mailbox 而非 XGMII RX 引脚采样：mailbox 与引脚承载同一拍流，
// 但 mailbox 无时序竞争、且在对接真实 MAC 时（RX 引脚被 MAC 消费）监视
// 路径保持不变；引脚版监视器留待接 RTL 时按需增加。
class eth_pcs_monitor extends uvm_monitor;

  `uvm_component_utils(eth_pcs_monitor)

  eth_pcs_cfg     cfg;
  eth_pcs_phy_bfm bfm;

  // 观测到的接收帧
  uvm_analysis_port #(eth_frame_txn) rx_ap;

  protected frame_assembler_c asm;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_ap = new("rx_ap", this);
    asm   = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(eth_pcs_cfg)::get(this, "", "cfg", cfg) || cfg == null)
      `uvm_fatal("CFG", "eth_pcs_monitor 未取得 eth_pcs_cfg")
  endfunction

  // 逐拍装配；检出帧即发布。bfm 句柄必须已由 agent 注入。
  virtual task run_phase(uvm_phase phase);
    if (bfm == null)
      `uvm_fatal("BFM", "eth_pcs_monitor 未注入 phy_bfm 句柄")

    forever begin
      xgmii64_t w;
      frame_assembler_c::frame_result_t res;

      bfm.rx_words.get(w);
      if (asm.push_word(w, res)) begin
        eth_frame_txn t = eth_frame_txn::type_id::create("rx_frame");
        t.data        = res.data;
        t.crc_ok      = res.crc_ok;
        t.preamble_ok = res.preamble_ok;
        rx_ap.write(t);
      end
    end
  endtask

  // 协议完整性汇总。错误计数不在此判失败 —— 是否可接受由测试场景决定
  //（如注错测试预期非零），monitor 只负责如实曝光。
  virtual function void report_phase(uvm_phase phase);
    `uvm_info("PCS_STATS", $sformatf(
      "frames=%0d crc_err=%0d preamble_err=%0d invalid_block=%0d slip=%0d fec_corr=%0d fec_uncorr=%0d tx_underrun=%0d idle_ins=%0d idle_del=%0d",
      asm.frames_seen, asm.crc_err_count, asm.preamble_err_count,
      bfm.invalid_block_count, bfm.get_slip_count(),
      bfm.get_fec_corrected(), bfm.get_fec_uncorrectable(),
      bfm.tx_underrun_count, bfm.idle_ins_count, bfm.idle_del_count), UVM_LOW)
  endfunction

  // 记分板/测试用查询接口
  function int crc_err_count();
    return asm.crc_err_count;
  endfunction

  function int frames_seen();
    return asm.frames_seen;
  endfunction

endclass

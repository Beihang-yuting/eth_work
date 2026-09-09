// -----------------------------------------------------------------------------
// 所属：eth_work/test/svt —— 阶段 2 交叉验证仿真顶层
// 职责：实例化 VIP 侧（svt_ethernet_txrx_if + xxm bfm/monitor 模型）与
//       自研侧（xgmii_if + serial_if），把 VIP 的 XSBI serial 线
//       （tx_lane[0]/rx_lane[0]，10.3125GHz）与自研 serial_if 交叉连接；
//       产生 VIP 所需的全套时钟（沿用 VIP 示例数值）与复位脉冲。
// 依赖：svt_ethernet.uvm.pkg、svt_ethernet_txrx_if.svi（VIP 安装树）、
//       eth_pcs_if.sv、eth_svt_cross_pkg。
// 所有权：仿真进程顶层，持有全部接口与模型实例。
// -----------------------------------------------------------------------------

// 高精度时钟生成复用 aip_core（third_party/aip_core，vendored 1fs 精度版）。
// include 须在本文件 timescale 之前。
`include "aip_log.sv"
`include "aip_time.sv"
`include "aip_clk.sv"

`timescale 1ps/1fs

// VIP 示例的时钟半周期定义（只保留本 TB 会转动的；其余接口时钟保持 0，
// 对应模式未启用即可）
`define SVT_ETHERNET_SERIAL_BASER_CLOCK  (96.97/2.0)
`define SVT_ETHERNET_XSBI_CLOCK          (1551.52/2.0)
`define SVT_ETHERNET_XGMII_CLOCK         3200
`define SVT_ETHERNET_GMII_CLOCK          4000
`define SVT_ETHERNET_REFERENCE_CLOCK     50

// VIP 包与接口由 svt_pkg_bootstrap.sv 先行编译（见 filelist_svt.f 顺序）

module top_svt;

  import uvm_pkg::*;
  import svt_ethernet_uvm_pkg::*;
  import eth_svt_cross_pkg::*;

  // ---------------- 时钟与复位 ----------------

  bit reference_clk;
  bit gmii_clk;
  bit xgmii_clk;
  bit xsbi_clk;
  bit serial_baser_clk;

  // 自研侧字时钟：aip_clk 独立产生 156.25MHz；与 VIP 串行位时钟的微小
  // 速率差（非严格 66:1）由 BFM 弹性 idle 插入/删除吸收
  aip_clk_if our_word_clk_if ();
  aip_clk our_word_clk_gen;
  wire our_word_clk = our_word_clk_if.clk;

  logic tb_reset = 0;
  logic our_rst_n = 0;

  always #`SVT_ETHERNET_REFERENCE_CLOCK    reference_clk    = ~reference_clk;
  always #`SVT_ETHERNET_GMII_CLOCK         gmii_clk         = ~gmii_clk;
  always #`SVT_ETHERNET_XGMII_CLOCK        xgmii_clk        = ~xgmii_clk;
  always #`SVT_ETHERNET_XSBI_CLOCK         xsbi_clk         = ~xsbi_clk;
  always #`SVT_ETHERNET_SERIAL_BASER_CLOCK serial_baser_clk = ~serial_baser_clk;

  initial begin
    our_word_clk_gen = new("our_word_clk", our_word_clk_if);
    our_word_clk_gen.set_freq(156.25e6);
    // +100ppm：删除主导域（生产恒盈余，弹性删除只删帧间 idle），
    // 覆盖 fs 舍入与 VIP 位钟的微小速率差
    our_word_clk_gen.set_ppm(100);
    our_word_clk_gen.start();
  end

  // 复位：VIP 侧一个 gmii 时钟宽度的高脉冲（同示例 reset 序列时序）；
  // 自研侧低有效复位同窗释放
  initial begin
    repeat (4) @(posedge gmii_clk);
    tb_reset = 1;
    @(posedge gmii_clk);
    tb_reset = 0;
    repeat (2) @(posedge gmii_clk);
    our_rst_n = 1;
  end

  // ---------------- VIP 侧 ----------------

  svt_ethernet_txrx_if mac_ethernet_if (reference_clk);

  // xxm 模型：BFM 驱动器 + 监视/检查器（VIP 的实际引擎，必须实例化）
  svt_ethernet_xxm_bfm_driver     ethernet_mac_txrx (mac_ethernet_if);
  svt_ethernet_xxm_mon_chk_driver ethernet_mac_mon  (mac_ethernet_if);

  // 本 TB 用到的接口时钟；未启用模式的时钟信号保持 0
  assign mac_ethernet_if.reference_clk       = reference_clk;
  assign mac_ethernet_if.gmii_tx_clk         = gmii_clk;
  assign mac_ethernet_if.gmii_rx_clk         = gmii_clk;
  assign mac_ethernet_if.xgmii_tx_clk        = xgmii_clk;
  assign mac_ethernet_if.xgmii_rx_clk        = xgmii_clk;
  assign mac_ethernet_if.xsbi_tx_clk         = xsbi_clk;
  assign mac_ethernet_if.xsbi_rx_clk         = xsbi_clk;
  assign mac_ethernet_if.serial_tx_baser_clk = serial_baser_clk;
  assign mac_ethernet_if.serial_rx_baser_clk = serial_baser_clk;

  assign mac_ethernet_if.reset     = tb_reset;
  assign mac_ethernet_if.stream_id = 0;

  // ---------------- 自研侧 ----------------

  xgmii_if  xgmii_p  (our_word_clk, our_rst_n);
  serial_if serial_p (serial_baser_clk, our_rst_n);

  // ---------------- 串行链路交叉连接 ----------------

  // VIP MAC 的接收线 = 我方发送；我方接收 = VIP MAC 的发送。
  // XSBI_SERIAL 模式只用 lane bit0，其余位清零。
  assign mac_ethernet_if.rx_lane = {'0, serial_p.tx_bit};
  assign serial_p.rx_bit         = mac_ethernet_if.tx_lane[0];

  // ---------------- UVM 启动 ----------------

  initial begin
    uvm_config_db#(virtual svt_ethernet_txrx_if)::set(
      uvm_root::get(), "uvm_test_top.env.vip_mac*", "if_port", mac_ethernet_if);

    uvm_config_db#(virtual xgmii_if)::set(
      null, "uvm_test_top", "vif_xgmii_p", xgmii_p);
    uvm_config_db#(virtual serial_if)::set(
      null, "uvm_test_top", "vif_serial_p", serial_p);

    run_test();
  end

endmodule

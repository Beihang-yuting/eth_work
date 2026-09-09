// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— TB 集成便捷宏（一个宏完成一类接线/配置）
// 职责：封装 top 层集成的样板代码：时钟对生成（含 +SPEED 模式选择）、
//       接口对实例化、双 agent 串行交叉连线、与 svt VIP 串行对接、
//       virtual interface 下发。使用者按序放置数个宏即可完成集成，
//       无需了解时钟比/弹性域/lane 位置等内部约定。
// 依赖：aip_clk 三件套（须先 include）、eth_pcs_if.sv。
// 用法示例见 docs/integration_10g_basekr.md 与 test/uvm/top.sv。
// -----------------------------------------------------------------------------

`ifndef ETH_PCS_MACROS_SVH
`define ETH_PCS_MACROS_SVH

// 时钟对：<name>_word_clk / <name>_bit_clk 两根 wire。
// +SPEED=10g|25g|5g 选线速率（默认 10g）；字时钟恒为位钟/66 并加
// +100ppm（删除主导域约定，见 phy_bfm 头注），使用者无需关心。
`define eth_pcs_clk_gen(name) \
  aip_clk_if name``_word_clk_if (); \
  aip_clk_if name``_bit_clk_if (); \
  aip_clk name``_word_clk_gen; \
  aip_clk name``_bit_clk_gen; \
  wire name``_word_clk = name``_word_clk_if.clk; \
  wire name``_bit_clk  = name``_bit_clk_if.clk; \
  initial begin \
    string speed_s = "10g"; \
    real   bit_hz; \
    void'($value$plusargs("SPEED=%s", speed_s)); \
    case (speed_s) \
      "25g":   bit_hz = 25.78125e9; \
      "5g":    bit_hz = 5.15625e9; \
      default: bit_hz = 10.3125e9; \
    endcase \
    name``_word_clk_gen = new(`"name``_word_clk`", name``_word_clk_if); \
    name``_word_clk_gen.set_freq(bit_hz / 66.0); \
    name``_word_clk_gen.set_ppm(100); \
    name``_bit_clk_gen = new(`"name``_bit_clk`", name``_bit_clk_if); \
    name``_bit_clk_gen.set_freq(bit_hz); \
    name``_word_clk_gen.start(); \
    name``_bit_clk_gen.start(); \
  end

// 复位：低有效 rst_n，上电 10 个字时钟后释放
`define eth_pcs_reset_gen(rst, word_clk) \
  logic rst = 0; \
  initial begin \
    repeat (10) @(posedge word_clk); \
    rst = 1; \
  end

// 一个 agent 端口的接口对：<name>_xgmii（接 MAC）+ <name>_serial（接对端）
`define eth_pcs_port(name, word_clk, bit_clk, rst_n) \
  xgmii_if  name``_xgmii (word_clk, rst_n); \
  serial_if name``_serial (bit_clk, rst_n);

// 双 agent 串行交叉连线（环回/背靠背拓扑）
`define eth_pcs_connect(a, b) \
  assign b``_serial.rx_bit = a``_serial.tx_bit; \
  assign a``_serial.rx_bit = b``_serial.tx_bit;

// 与 svt ethernet VIP 串行对接（VIP serial 系模式：数据在 lane bit0）
`define eth_pcs_connect_svt(port, vip_if) \
  assign vip_if.rx_lane = {'0, port``_serial.tx_bit}; \
  assign port``_serial.rx_bit = vip_if.tx_lane[0];

// 下发一个端口的 virtual interface 到 uvm_test_top，config_db 键名
// "vif_xgmii_<name>" / "vif_serial_<name>"（与各 test 的取用约定一致）
`define eth_pcs_vifs(name) \
  initial begin \
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top", \
      {"vif_xgmii_", `"name`"}, name``_xgmii); \
    uvm_config_db#(virtual serial_if)::set(null, "uvm_test_top", \
      {"vif_serial_", `"name`"}, name``_serial); \
  end

// svt ethernet VIP 全套接口时钟：一键生成全部时钟信号 + 翻转 + 接线。
// 周期值取自 VIP 25G 示例 top；必须全接 —— 只接子集会导致某些
// interface_select 模式内部时钟不转、TX 恒值（25G 曾因此假死）。
// 须放在 vip_if 实例之后。暴露常用时钟：pfx_serial_baser_clk（10G 位钟）、
// pfx_serial_25g_clk（25G 位钟）、pfx_gmii_clk（复位节拍）、
// pfx_reference_clk（接口构造参数）。
`define eth_pcs_svt_clock_gen(pfx) \
  bit pfx``_reference_clk, pfx``_gmii_clk, pfx``_xgmii_clk, pfx``_xsbi_clk; \
  bit pfx``_serial_baser_clk, pfx``_serial_25g_clk; \
  bit pfx``_xxgmii_clk, pfx``_xxvgmii_clk, pfx``_xxvsbi_clk; \
  bit pfx``_lgmii_clk, pfx``_lsbi_clk, pfx``_s12p5g_clk, pfx``_scd_clk; \
  bit pfx``_vsbi_clk, pfx``_xfbi_clk, pfx``_xlgmii_clk, pfx``_cgmii_clk; \
  bit pfx``_66t_clk, pfx``_40t_clk, pfx``_s4x_clk, pfx``_sx_clk; \
  bit pfx``_grmii_clk, pfx``_rmii_clk, pfx``_m100_clk, pfx``_m10_clk; \
  bit pfx``_tbi_clk, pfx``_mdio_clk; \
  always #50         pfx``_reference_clk = ~pfx``_reference_clk; \
  always #4000       pfx``_gmii_clk      = ~pfx``_gmii_clk; \
  always #3200       pfx``_xgmii_clk     = ~pfx``_xgmii_clk; \
  always #(1551.52/2.0) pfx``_xsbi_clk   = ~pfx``_xsbi_clk; \
  always #(96.97/2.0)   pfx``_serial_baser_clk = ~pfx``_serial_baser_clk; \
  always #(38.788/2.0)  pfx``_serial_25g_clk   = ~pfx``_serial_25g_clk; \
  always #1600       pfx``_xxgmii_clk    = ~pfx``_xxgmii_clk; \
  always #1280       pfx``_xxvgmii_clk   = ~pfx``_xxvgmii_clk; \
  always #(620.608/2.0) pfx``_xxvsbi_clk = ~pfx``_xxvsbi_clk; \
  always #640        pfx``_lgmii_clk     = ~pfx``_lgmii_clk; \
  always #620.608    pfx``_lsbi_clk      = ~pfx``_lsbi_clk; \
  always #38.788     pfx``_s12p5g_clk    = ~pfx``_s12p5g_clk; \
  always #18.824     pfx``_scd_clk       = ~pfx``_scd_clk; \
  always #1551.52    pfx``_vsbi_clk      = ~pfx``_vsbi_clk; \
  always #1600       pfx``_xfbi_clk      = ~pfx``_xfbi_clk; \
  always #800        pfx``_xlgmii_clk    = ~pfx``_xlgmii_clk; \
  always #320        pfx``_cgmii_clk     = ~pfx``_cgmii_clk; \
  always #1280       pfx``_66t_clk       = ~pfx``_66t_clk; \
  always #775.757576 pfx``_40t_clk       = ~pfx``_40t_clk; \
  always #160        pfx``_s4x_clk       = ~pfx``_s4x_clk; \
  always #400        pfx``_sx_clk        = ~pfx``_sx_clk; \
  always #40000      pfx``_grmii_clk     = ~pfx``_grmii_clk; \
  always #10000      pfx``_rmii_clk      = ~pfx``_rmii_clk; \
  always #20000      pfx``_m100_clk      = ~pfx``_m100_clk; \
  always #200000     pfx``_m10_clk       = ~pfx``_m10_clk; \
  always #4000       pfx``_tbi_clk       = ~pfx``_tbi_clk; \
  always #200        pfx``_mdio_clk      = ~pfx``_mdio_clk;

// 接线半部：放在 vip_if 实例之后
`define eth_pcs_svt_clock_wire(pfx, vip_if) \
  assign vip_if.reference_clk          = pfx``_reference_clk; \
  assign vip_if.gmii_tx_clk            = pfx``_gmii_clk; \
  assign vip_if.gmii_rx_clk            = pfx``_gmii_clk; \
  assign vip_if.xgmii_tx_clk           = pfx``_xgmii_clk; \
  assign vip_if.xgmii_rx_clk           = pfx``_xgmii_clk; \
  assign vip_if.xsbi_tx_clk            = pfx``_xsbi_clk; \
  assign vip_if.xsbi_rx_clk            = pfx``_xsbi_clk; \
  assign vip_if.serial_tx_baser_clk    = pfx``_serial_baser_clk; \
  assign vip_if.serial_rx_baser_clk    = pfx``_serial_baser_clk; \
  assign vip_if.serial_caui_25g_clk_tx = pfx``_serial_25g_clk; \
  assign vip_if.serial_caui_25g_clk_rx = pfx``_serial_25g_clk; \
  assign vip_if.xxgmii_tx_clk          = pfx``_xxgmii_clk; \
  assign vip_if.xxgmii_rx_clk          = pfx``_xxgmii_clk; \
  assign vip_if.xxvgmii_tx_clk         = pfx``_xxvgmii_clk; \
  assign vip_if.xxvgmii_rx_clk         = pfx``_xxvgmii_clk; \
  assign vip_if.xxvsbi_tx_clk          = pfx``_xxvsbi_clk; \
  assign vip_if.xxvsbi_rx_clk          = pfx``_xxvsbi_clk; \
  assign vip_if.lgmii_tx_clk           = pfx``_lgmii_clk; \
  assign vip_if.lgmii_rx_clk           = pfx``_lgmii_clk; \
  assign vip_if.lsbi_tx_clk            = pfx``_lsbi_clk; \
  assign vip_if.lsbi_rx_clk            = pfx``_lsbi_clk; \
  assign vip_if.serial_12pt5g_clk_tx   = pfx``_s12p5g_clk; \
  assign vip_if.serial_12pt5g_clk_rx   = pfx``_s12p5g_clk; \
  assign vip_if.serial_cd_tx_clk       = pfx``_scd_clk; \
  assign vip_if.serial_cd_rx_clk       = pfx``_scd_clk; \
  assign vip_if.vsbi_tx_clk            = pfx``_vsbi_clk; \
  assign vip_if.vsbi_rx_clk            = pfx``_vsbi_clk; \
  assign vip_if.xfbi_tx_clk            = pfx``_xfbi_clk; \
  assign vip_if.xfbi_rx_clk            = pfx``_xfbi_clk; \
  assign vip_if.xlgmii_tx_clk          = pfx``_xlgmii_clk; \
  assign vip_if.xlgmii_rx_clk          = pfx``_xlgmii_clk; \
  assign vip_if.cgmii_tx_clk           = pfx``_cgmii_clk; \
  assign vip_if.cgmii_rx_clk           = pfx``_cgmii_clk; \
  assign vip_if.clk_66t_tx             = pfx``_66t_clk; \
  assign vip_if.clk_66t_rx             = pfx``_66t_clk; \
  assign vip_if.clk_40t_tx             = pfx``_40t_clk; \
  assign vip_if.clk_40t_rx             = pfx``_40t_clk; \
  assign vip_if.serial_tx_base4x_clk   = pfx``_s4x_clk; \
  assign vip_if.serial_rx_base4x_clk   = pfx``_s4x_clk; \
  assign vip_if.serial_tx_basex_clk    = pfx``_sx_clk; \
  assign vip_if.serial_rx_basex_clk    = pfx``_sx_clk; \
  assign vip_if.gmii_rmii_tx_clk       = pfx``_grmii_clk; \
  assign vip_if.gmii_rmii_rx_clk       = pfx``_grmii_clk; \
  assign vip_if.rmii_tx_clk            = pfx``_rmii_clk; \
  assign vip_if.rmii_rx_clk            = pfx``_rmii_clk; \
  assign vip_if.mii_100M_tx_clk        = pfx``_m100_clk; \
  assign vip_if.mii_100M_rx_clk        = pfx``_m100_clk; \
  assign vip_if.mii_10M_tx_clk         = pfx``_m10_clk; \
  assign vip_if.mii_10M_rx_clk         = pfx``_m10_clk; \
  assign vip_if.mdio_clk               = pfx``_mdio_clk;

`endif // ETH_PCS_MACROS_SVH

// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— TB 集成便捷宏（一个宏完成一类接线/配置）
// 职责：封装 top 层集成的样板代码：时钟对生成（含 +SPEED 模式选择）、
//       接口对实例化、双 agent 串行交叉连线、与 svt VIP 串行对接、
//       virtual interface 下发。使用者按序放置数个宏即可完成集成，
//       无需了解时钟比/弹性域/lane 位置等内部约定。
// 依赖：aip_clk 三件套（须先 include）、eth_pcs_if.sv。
// 用法示例见 docs/integration_10g_basekr.md 与 test/uvm/top.sv。
//
// 宏 <-> 速率对照（速率由 +SPEED 运行时选择，无需换宏/换 top）：
//   eth_pcs_lb_env        全速率一键环回环境（10g/25g/5g 单 lane +
//                         40g 4 lane 超集，推荐入口，见 test/uvm/top.sv）
//   eth_pcs_clk_gen       全速率（内含 +SPEED 频率表：10g/25g/5g/40g；
//                         40g 另读 +AM_SPACING，默认 512）
//   eth_pcs_ctrl_reset    全速率（复位 + 中途复位/扰动钩子）
//   eth_pcs_port/vifs/connect        10g/25g/5g 单 lane
//   （1g/2.5g BASE-X：lb_env 另建 <a>_gmii/<b>_gmii，vif 键 vif_gmii_<x>）
//   eth_pcs_mld_lanes/connect/vifs   40g（100G 后续同族）
//   eth_pcs_mld_rx_wire   40g 接 svt VIP 专用
//   eth_pcs_connect_svt   10g/25g/5g 接 svt VIP 专用
//   eth_pcs_svt_clock_gen/wire       svt VIP 全模式（27 域时钟全套）
// -----------------------------------------------------------------------------

`ifndef ETH_PCS_MACROS_SVH
`define ETH_PCS_MACROS_SVH

// 时钟对：<name>_word_clk / <name>_bit_clk 两根 wire。
// +SPEED=10g|25g|5g|40g|1g|2.5g 选线速率（默认 10g）；字时钟 = 位钟/66
// （1g/2.5g 为 8b/10b：字节时钟 = 位钟/10，即 GMII 125/312.5MHz；40g
// 为 4 lane 合流：4×位钟/66 再扣 AM 带宽开销 (sp-1)/sp，sp 由
// +AM_SPACING 给出，默认 512，须与 test 侧 cfg.am_spacing 一致）并加
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
    int    am_sp; \
    real   bit_hz, word_hz; \
    void'($value$plusargs("SPEED=%s", speed_s)); \
    am_sp = (speed_s == "100g" || speed_s == "100g4") ? 64 : 512; \
    void'($value$plusargs("AM_SPACING=%d", am_sp)); \
    case (speed_s) \
      "25g":   bit_hz = 25.78125e9; \
      "5g":    bit_hz = 5.15625e9; \
      "1g":    bit_hz = 1.25e9; \
      "2.5g":  bit_hz = 3.125e9; \
      "100g4": bit_hz = 25.78125e9; \
      "200g":  bit_hz = 26.5625e9; \
      default: bit_hz = 10.3125e9; \
    endcase \
    if (speed_s == "40g") \
      word_hz = bit_hz * 4.0 / 66.0 * (am_sp - 1.0) / am_sp; \
    else if (speed_s == "100g") \
      word_hz = bit_hz * 10.0 / 66.0 * (am_sp - 1.0) / am_sp; \
    else if (speed_s == "100g4") \
      word_hz = bit_hz * 4.0 / 66.0 * (am_sp - 1.0) / am_sp; \
    else if (speed_s == "200g") \
      /* 8 lane × 26.5625G，RS(544,514)+257b 后净 200G = 3.125G 块/s；AM */ \
      /* 周期 16 码字中 4/320 块位让给 AM+填充 -> ×316/320 */ \
      word_hz = 3.125e9 * 316.0 / 320.0; \
    else if (speed_s == "1g" || speed_s == "2.5g") \
      word_hz = bit_hz / 10.0; \
    else \
      word_hz = bit_hz / 66.0; \
    name``_word_clk_gen = new(`"name``_word_clk`", name``_word_clk_if); \
    name``_word_clk_gen.set_freq(word_hz); \
    name``_word_clk_gen.set_ppm(100); \
    name``_bit_clk_gen = new(`"name``_bit_clk`", name``_bit_clk_if); \
    name``_bit_clk_gen.set_freq(bit_hz); \
    name``_word_clk_gen.start(); \
    if (!$test$plusargs("XGMII_DIRECT")) name``_bit_clk_gen.start(); \
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
// 覆盖 VIP svt_ethernet_txrx_if 的全部时钟端口（2026-09-15 逐一对照补齐
// 33 路，此前漏接的 ccmii 等恰为 200G 所需）。
// 周期值取自 VIP 25G 示例 top；+SPEED=2.5g 时 GMII/XGMII/basex 串行三路
// 改为 2.5GBASE-X 频率（VIP 在该模式直接以 serial_basex_clk 为位钟，
// 已用波形探针实测确认）。必须全接 —— 只接子集会导致某些
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
  /* 以下为补齐的 33 路（VIP txrx_if 全部时钟端口逐一对照）*/ \
  bit pfx``_caui64b_clk, pfx``_ccmii_clk, pfx``_cdmii_clk, pfx``_cdxbi_clk; \
  bit pfx``_dcccmii_clk, pfx``_lsbi1_clk, pfx``_ptp_clk, pfx``_rgmii_clk; \
  bit pfx``_rxaui_clk, pfx``_srxaui_clk, pfx``_s100bt1_clk, pfx``_sbt1_clk; \
  bit pfx``_smii_clk, pfx``_s100g_clk, pfx``_s50g_clk, pfx``_s100g1_clk; \
  bit pfx``_s50g1_clk; \
  realtime pfx``_gmii_half = 4000, pfx``_xgmii_half = 3200, pfx``_sx_half = 400; \
  /* 超高速串行钟（半周期 4.7~9.7ps）默认慢速翻转：只保证"在转"防 VIP */ \
  /* 假死，避免拖慢所有 svt 仿真；接对应模式时由 +SPEED 切真实频率 */ \
  realtime pfx``_s100g_half = 4000, pfx``_s50g_half = 4000; \
  realtime pfx``_s100g1_half = 4000, pfx``_s50g1_half = 4000; \
  initial begin \
    string sp_s; \
    if ($value$plusargs("SPEED=%s", sp_s) && sp_s == "2.5g") begin \
      pfx``_gmii_half  = 1600;   /* GMII 312.5MHz */ \
      pfx``_xgmii_half = 12800;  /* XGMII 39.0625MHz（VIP 2.5G 文档值）*/ \
      pfx``_sx_half    = 160;    /* basex 串行 3.125Gbaud */ \
    end \
  end \
  always #50         pfx``_reference_clk = ~pfx``_reference_clk; \
  always #(pfx``_gmii_half)  pfx``_gmii_clk  = ~pfx``_gmii_clk; \
  always #(pfx``_xgmii_half) pfx``_xgmii_clk = ~pfx``_xgmii_clk; \
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
  always #(pfx``_sx_half) pfx``_sx_clk   = ~pfx``_sx_clk; \
  always #40000      pfx``_grmii_clk     = ~pfx``_grmii_clk; \
  always #10000      pfx``_rmii_clk      = ~pfx``_rmii_clk; \
  always #20000      pfx``_m100_clk      = ~pfx``_m100_clk; \
  always #200000     pfx``_m10_clk       = ~pfx``_m10_clk; \
  always #4000       pfx``_tbi_clk       = ~pfx``_tbi_clk; \
  always #200        pfx``_mdio_clk      = ~pfx``_mdio_clk; \
  always #(2482.424/2.0) pfx``_caui64b_clk = ~pfx``_caui64b_clk; /* 示例值 */ \
  always #160        pfx``_ccmii_clk     = ~pfx``_ccmii_clk;   /* 200G 3.125GHz */ \
  always #80         pfx``_cdmii_clk     = ~pfx``_cdmii_clk;   /* 400G 6.25GHz */ \
  always #(376.48/2.0) pfx``_cdxbi_clk   = ~pfx``_cdxbi_clk;   /* 示例值 */ \
  always #40         pfx``_dcccmii_clk   = ~pfx``_dcccmii_clk; /* 800G 推导 */ \
  always #620.608    pfx``_lsbi1_clk     = ~pfx``_lsbi1_clk;   /* 同 lsbi */ \
  always #500000     pfx``_ptp_clk       = ~pfx``_ptp_clk;     /* 示例值 */ \
  always #4000       pfx``_rgmii_clk     = ~pfx``_rgmii_clk;   /* 125MHz */ \
  always #3200       pfx``_rxaui_clk     = ~pfx``_rxaui_clk;   /* 推导 */ \
  always #80         pfx``_srxaui_clk    = ~pfx``_srxaui_clk;  /* 6.25G 推导 */ \
  always #7500       pfx``_s100bt1_clk   = ~pfx``_s100bt1_clk; /* 推导 */ \
  always #666.667    pfx``_sbt1_clk      = ~pfx``_sbt1_clk;    /* 推导 */ \
  always #4000       pfx``_smii_clk      = ~pfx``_smii_clk;    /* 125MHz */ \
  always #(pfx``_s100g_half)  pfx``_s100g_clk  = ~pfx``_s100g_clk; \
  always #(pfx``_s50g_half)   pfx``_s50g_clk   = ~pfx``_s50g_clk; \
  always #(pfx``_s100g1_half) pfx``_s100g1_clk = ~pfx``_s100g1_clk; \
  always #(pfx``_s50g1_half)  pfx``_s50g1_clk  = ~pfx``_s50g1_clk;

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
  assign vip_if.mdio_clk               = pfx``_mdio_clk; \
  assign vip_if.caui_64b_clk_tx        = pfx``_caui64b_clk; \
  assign vip_if.caui_64b_clk_rx        = pfx``_caui64b_clk; \
  assign vip_if.ccmii_tx_clk           = pfx``_ccmii_clk; \
  assign vip_if.ccmii_rx_clk           = pfx``_ccmii_clk; \
  assign vip_if.cdmii_tx_clk           = pfx``_cdmii_clk; \
  assign vip_if.cdmii_rx_clk           = pfx``_cdmii_clk; \
  assign vip_if.cdxbi_tx_clk           = pfx``_cdxbi_clk; \
  assign vip_if.cdxbi_rx_clk           = pfx``_cdxbi_clk; \
  assign vip_if.dcccmii_tx_clk         = pfx``_dcccmii_clk; \
  assign vip_if.dcccmii_rx_clk         = pfx``_dcccmii_clk; \
  assign vip_if.lsbi_single_lane_tx_clk = pfx``_lsbi1_clk; \
  assign vip_if.lsbi_single_lane_rx_clk = pfx``_lsbi1_clk; \
  assign vip_if.ptp_system_clk         = pfx``_ptp_clk; \
  assign vip_if.rgmii_tx_clk           = pfx``_rgmii_clk; \
  assign vip_if.rgmii_rx_clk           = pfx``_rgmii_clk; \
  assign vip_if.rxaui_tx_clk           = pfx``_rxaui_clk; \
  assign vip_if.rxaui_rx_clk           = pfx``_rxaui_clk; \
  assign vip_if.serial_rxaui_tx_clk    = pfx``_srxaui_clk; \
  assign vip_if.serial_rxaui_rx_clk    = pfx``_srxaui_clk; \
  assign vip_if.serial_100baset1_tx_clk = pfx``_s100bt1_clk; \
  assign vip_if.serial_100baset1_rx_clk = pfx``_s100bt1_clk; \
  assign vip_if.serial_baset1_tx_clk   = pfx``_sbt1_clk; \
  assign vip_if.serial_baset1_rx_clk   = pfx``_sbt1_clk; \
  assign vip_if.smii_tx_clk            = pfx``_smii_clk; \
  assign vip_if.smii_rx_clk            = pfx``_smii_clk; \
  assign vip_if.serial_100g_tx_clk     = pfx``_s100g_clk; \
  assign vip_if.serial_100g_rx_clk     = pfx``_s100g_clk; \
  assign vip_if.serial_50g_tx_clk      = pfx``_s50g_clk; \
  assign vip_if.serial_50g_rx_clk      = pfx``_s50g_clk; \
  assign vip_if.serial_100g_single_lane_tx_clk = pfx``_s100g1_clk; \
  assign vip_if.serial_100g_single_lane_rx_clk = pfx``_s100g1_clk; \
  assign vip_if.serial_50g_single_lane_tx_clk  = pfx``_s50g1_clk; \
  assign vip_if.serial_50g_single_lane_rx_clk  = pfx``_s50g1_clk;

// ---------------- 多 lane（MLD，40G/100G）一键宏 ----------------

// 多 lane 串行接口组：声明 <name>_l[n]（40G n=4；100G 后续 20）
`define eth_pcs_mld_lanes(name, n, bit_clk, rst_n) \
  serial_if name``_l [n] (bit_clk, rst_n);

// 双端多 lane 交叉环回（背靠背拓扑）；err 注到 a->b 的 lane0 ——
// 多 lane 下单 lane 受扰即破坏重组，足以覆盖扰动恢复场景。
// 不需要扰动时传 1'b0。
`define eth_pcs_mld_connect(a, b, n, err) \
  for (genvar gi = 0; gi < n; gi++) begin : g_mldconn_``a``_``b \
    assign b``_l[gi].rx_bit = a``_l[gi].tx_bit ^ ((gi == 0) ? (err) : 1'b0); \
    assign a``_l[gi].rx_bit = b``_l[gi].tx_bit; \
  end

// 多 lane 接 svt VIP 的接收方向：<port>_l[i].rx <= vip.tx_lane[i]。
// 发送方向 vip.rx_lane 因需按运行时模式 mux（单/多 lane 不能双驱动），
// 留在 top 手写。
`define eth_pcs_mld_rx_wire(port, vip_if, n) \
  for (genvar gi = 0; gi < n; gi++) begin : g_mldsvt_``port \
    assign port``_l[gi].rx_bit = vip_if.tx_lane[gi]; \
  end

// 下发多 lane virtual interface，键名 "vif_serial_<name>_l<i>"
// （与 eth_loopback_test 40G 装配、svt 40g 测试的取用约定一致）
`define eth_pcs_mld_vifs(name, n) \
  for (genvar gi = 0; gi < n; gi++) begin : g_mldvif_``name \
    initial uvm_config_db#(virtual serial_if)::set(null, "uvm_test_top", \
      $sformatf({"vif_serial_", `"name`", "_l%0d"}, gi), name``_l[gi]); \
  end

// 复位 + TB 控制钩子：上电 10 字拍释放 rst；此后响应 ctrl.reset_req
// 产生复位脉冲并清零作完成握手（中途复位测试协议，见 tb_ctrl_if 头注）。
// vif 键 "vif_ctrl"。
`define eth_pcs_ctrl_reset(ctrl, rst, word_clk) \
  tb_ctrl_if ctrl (); \
  logic rst = 0; \
  initial begin \
    repeat (10) @(posedge word_clk); \
    rst = 1; \
    forever begin \
      @(posedge word_clk); \
      if (ctrl.reset_req) begin \
        rst = 0; \
        repeat (10) @(posedge word_clk); \
        rst = 1; \
        ctrl.reset_req = 0; \
      end \
    end \
  end \
  initial uvm_config_db#(virtual tb_ctrl_if)::set(null, "uvm_test_top", \
                                                  "vif_ctrl", ctrl);

// ---------------- 一键环回环境（速率 +SPEED 运行时选择） ----------------

// 展开 = 时钟（+SPEED 频率表）+ 复位/控制 + A/B 两端单 lane 接口对与
// 4 lane 接口组 + 全部交叉接线（扰动注 A->B：单 lane 线及 lane0）+
// 全部 vif 下发。top 仅需本宏与 run_test（见 test/uvm/top.sv）。
// 各速率取用：10g/25g/5g 走 <a>_serial 单 lane；40g 走 <a>_l[0..3]；
// 100g（CAUI-10）走 <a>_l[0..9]（20 条 PCS lane 2:1 复用）；
// 100g4（CAUI-4）走 <a>_l[0..3]（25.78G，5:1 复用）；
// 200g（Clause 119）走 <a>_l[0..7]（26.5625G，8 条 PCS lane 1:1）。
// 单/多 lane 接口恒实例化（elaboration 静态），闲置侧无害。
// +XGMII_DIRECT：直驱模式环回 —— 双向 XGMII 交叉 force（a 的 PHY 驱动
// rxd 直接成为 b 的 MAC 输入 txd，反之亦然），位钟关闭省事件（提速
// 主要来源），串行线闲置。cfg.xgmii_direct 由 test 按同名插件参数置位。
`define eth_pcs_lb_env(a, b) \
  `eth_pcs_clk_gen(sys) \
  `eth_pcs_ctrl_reset(ctrl, rst_n, sys_word_clk) \
  `eth_pcs_port(a, sys_word_clk, sys_bit_clk, rst_n) \
  `eth_pcs_port(b, sys_word_clk, sys_bit_clk, rst_n) \
  `eth_pcs_mld_lanes(a, 10, sys_bit_clk, rst_n) \
  `eth_pcs_mld_lanes(b, 10, sys_bit_clk, rst_n) \
  gmii_if a``_gmii (sys_word_clk, rst_n); \
  gmii_if b``_gmii (sys_word_clk, rst_n); \
  assign b``_serial.rx_bit = a``_serial.tx_bit ^ ctrl.err_inject; \
  assign a``_serial.rx_bit = b``_serial.tx_bit; \
  `eth_pcs_mld_connect(a, b, 10, ctrl.err_inject) \
  `eth_pcs_vifs(a) \
  `eth_pcs_vifs(b) \
  `eth_pcs_mld_vifs(a, 10) \
  `eth_pcs_mld_vifs(b, 10) \
  initial begin \
    uvm_config_db#(virtual gmii_if)::set(null, "uvm_test_top", \
      {"vif_gmii_", `"a`"}, a``_gmii); \
    uvm_config_db#(virtual gmii_if)::set(null, "uvm_test_top", \
      {"vif_gmii_", `"b`"}, b``_gmii); \
  end \
  initial if ($test$plusargs("XGMII_DIRECT")) begin \
    force b``_xgmii.txd = a``_xgmii.rxd; \
    force b``_xgmii.txc = a``_xgmii.rxc; \
    force a``_xgmii.txd = b``_xgmii.rxd; \
    force a``_xgmii.txc = b``_xgmii.rxc; \
  end

`endif // ETH_PCS_MACROS_SVH

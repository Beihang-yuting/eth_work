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

`include "agent/eth_pcs_macros.svh"

// VIP 包与接口由 svt_pkg_bootstrap.sv 先行编译（见 filelist_svt.f 顺序）

module top_svt;

  import uvm_pkg::*;
  import svt_ethernet_uvm_pkg::*;
  import eth_svt_cross_pkg::*;

  // ---------------- 时钟与复位 ----------------

  // VIP 全套接口时钟：集成宏一键生成（v_ 前缀）。声明/翻转半部在此，
  // 接线半部在接口实例之后；此前只接子集导致 25G 模式 TX 恒值假死
  `eth_pcs_svt_clock_gen(v)

  // +SPEED=25g/40g 切模式（默认 10g/BASE-KR）。时钟起振前由 initial
  // 设定；test 侧读同一 plusarg 选 VIP cfg
  bit use_25g = 0;
  bit use_40g = 0;

  initial begin
    string speed = "10g";
    void'($value$plusargs("SPEED=%s", speed));
    use_25g = (speed == "25g");
    use_40g = (speed == "40g");
  end

  // 自研侧字时钟：aip_clk 独立产生 156.25MHz；与 VIP 串行位时钟的微小
  // 速率差（非严格 66:1）由 BFM 弹性 idle 插入/删除吸收
  aip_clk_if our_word_clk_if ();
  aip_clk our_word_clk_gen;
  wire our_word_clk = our_word_clk_if.clk;

  logic tb_reset = 0;
  logic our_rst_n = 0;


  initial begin
    our_word_clk_gen = new("our_word_clk", our_word_clk_if);
    #1;   // 等 use_25g 决议
    if (use_40g)
      // 40G：4 lane 合流字率，扣 AM 间隔 64（与 VIP align_timer 一致）
      // 的带宽开销
      our_word_clk_gen.set_freq(4.0 * 10.3125e9 / 66.0 * 63.0 / 64.0);
    else
      our_word_clk_gen.set_freq((use_25g ? 25.78125e9 : 10.3125e9) / 66.0);
    // +100ppm：删除主导域（生产恒盈余，弹性删除只删帧间 idle），
    // 覆盖 fs 舍入与 VIP 位钟的微小速率差
    our_word_clk_gen.set_ppm(100);
    our_word_clk_gen.start();
  end

  // 我方串行位时钟随速率选择（与 VIP 同源信号）
  wire our_serial_clk = use_25g ? v_serial_25g_clk : v_serial_baser_clk;

  // 复位：VIP 侧一个 gmii 时钟宽度的高脉冲（同示例 reset 序列时序）；
  // 自研侧低有效复位同窗释放
  initial begin
    repeat (4) @(posedge v_gmii_clk);
    tb_reset = 1;
    @(posedge v_gmii_clk);
    tb_reset = 0;
    repeat (2) @(posedge v_gmii_clk);
    our_rst_n = 1;
  end

  // ---------------- VIP 侧 ----------------

  svt_ethernet_txrx_if mac_ethernet_if (v_reference_clk);

  // xxm 模型：BFM 驱动器 + 监视/检查器（VIP 的实际引擎，必须实例化）
  svt_ethernet_xxm_bfm_driver     ethernet_mac_txrx (mac_ethernet_if);
  svt_ethernet_xxm_mon_chk_driver ethernet_mac_mon  (mac_ethernet_if);

  // 全套接口时钟接线（宏另一半）
  `eth_pcs_svt_clock_wire(v, mac_ethernet_if)

  assign mac_ethernet_if.reset     = tb_reset;
  assign mac_ethernet_if.stream_id = 0;

  // ---------------- 自研侧 ----------------

  // 集成宏：一行实例化 agent 接口对（p_xgmii / p_serial）
  `eth_pcs_port(p, our_word_clk, our_serial_clk, our_rst_n)

  // 40G 模式的 4 条串行 lane（位钟同 BASE-R 10.3125G；其余模式闲置）
  // 集成宏：lane 组声明（实例 p_l[i]，vif 键 vif_serial_p_l<i>）
  `eth_pcs_mld_lanes(p, 4, v_serial_baser_clk, our_rst_n)

  // ---------------- 串行链路交叉连接 ----------------

  // VIP MAC 的接收线 = 我方发送；我方接收 = VIP MAC 的发送。
  // 单 lane（10G/25G）走 lane bit0；40G 走 tx_lane[3:0]/rx_lane[3:0]。
  // rx_lane 按模式 mux（不能双驱动，故不复用 connect_svt 宏）
  assign mac_ethernet_if.rx_lane =
    use_40g ? {'0, p_l[3].tx_bit, p_l[2].tx_bit,
                    p_l[1].tx_bit, p_l[0].tx_bit}
            : {'0, p_serial.tx_bit};
  assign p_serial.rx_bit = mac_ethernet_if.tx_lane[0];

  // 集成宏：多 lane 接收方向接线 + vif 下发
  `eth_pcs_mld_rx_wire(p, mac_ethernet_if, 4)
  `eth_pcs_mld_vifs(p, 4)

  // ---------------- TB 控制（中途复位钩子） ----------------

  // 复位仅作用我方 PHY 域（our_rst_n）；VIP 持续运行，覆盖"对端在线、
  // 我方复位重连"的恢复场景（键名 tb_ctrl，测试握手协议见 tb_ctrl_if）
  tb_ctrl_if ctrl ();

  always @(posedge our_word_clk) begin
    if (ctrl.reset_req) begin
      our_rst_n = 0;
      repeat (20) @(posedge our_word_clk);
      our_rst_n = 1;
      ctrl.reset_req = 0;
    end
  end

  initial uvm_config_db#(virtual tb_ctrl_if)::set(null, "uvm_test_top",
                                                  "tb_ctrl", ctrl);

  // ---------------- UVM 启动 ----------------

  // 集成宏：下发 p 端口的 virtual interface（键名 vif_xgmii_p / vif_serial_p）
  `eth_pcs_vifs(p)

  initial begin
    uvm_config_db#(virtual svt_ethernet_txrx_if)::set(
      uvm_root::get(), "uvm_test_top.env.vip_mac*", "if_port", mac_ethernet_if);
    run_test();
  end

endmodule

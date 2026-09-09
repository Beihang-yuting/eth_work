// -----------------------------------------------------------------------------
// 所属：eth_work/test/uvm —— 40G（4 lane MLD）环回仿真顶层
// 职责：双 agent 各 4 条串行 lane 交叉连接的环回拓扑。字时钟按 40G
//       XGMII 语义 = 4×10.3125G/66 再扣除 AM 开销（spacing=512 时
//       511/512）后加 +100ppm 盈余 —— 保证删除主导域在 AM 插入后仍
//       成立（AM 占用线上带宽，字侧生产必须留出该开销）。
// 依赖：eth_pcs_if.sv、tb_ctrl_if.sv、eth_tb_pkg（+SPEED=40g 装配）、
//       aip 时钟三件套、集成宏。
// 所有权：仿真进程顶层。
// -----------------------------------------------------------------------------

`include "aip_log.sv"
`include "aip_time.sv"
`include "aip_clk.sv"

`timescale 1ps/1ps

`include "agent/eth_pcs_macros.svh"

module top_40g;

  import uvm_pkg::*;
  import eth_tb_pkg::*;

  localparam int LANES      = 4;
  localparam int AM_SPACING = 512;    // 与 test 侧 cfg.am_spacing 一致

  // 位时钟：每 lane 10.3125G；字时钟见文件头公式
  aip_clk_if word_clk_if ();
  aip_clk_if bit_clk_if ();
  aip_clk word_clk_gen;
  aip_clk bit_clk_gen;
  wire word_clk = word_clk_if.clk;
  wire bit_clk  = bit_clk_if.clk;

  logic rst_n = 0;

  initial begin
    real lane_hz = 10.3125e9;
    real word_hz = lane_hz * LANES / 66.0
                   * (AM_SPACING - 1.0) / AM_SPACING;

    word_clk_gen = new("word_clk", word_clk_if);
    word_clk_gen.set_freq(word_hz);
    word_clk_gen.set_ppm(100);
    bit_clk_gen = new("bit_clk", bit_clk_if);
    bit_clk_gen.set_freq(lane_hz);
    word_clk_gen.start();
    bit_clk_gen.start();
  end

  // TB 控制接口（复位/扰动钩子，语义同单 lane top）
  tb_ctrl_if ctrl ();

  initial begin
    repeat (10) @(posedge word_clk);
    rst_n = 1;
    forever begin
      @(posedge word_clk);
      if (ctrl.reset_req) begin
        rst_n = 0;
        repeat (10) @(posedge word_clk);
        rst_n = 1;
        ctrl.reset_req = 0;
      end
    end
  end

  // 两端接口：XGMII + 每端 4 条串行 lane
  xgmii_if xgmii_a (word_clk, rst_n);
  xgmii_if xgmii_b (word_clk, rst_n);

  serial_if serial_a_l [LANES] (bit_clk, rst_n);
  serial_if serial_b_l [LANES] (bit_clk, rst_n);

  // 每 lane 交叉连线与 vif 下发（generate 内索引为常量）。
  // err_inject 扰动注到 A->B 的 lane0：多 lane 下单 lane 受扰即破坏
  // 重组，足以覆盖扰动恢复场景
  for (genvar gi = 0; gi < LANES; gi++) begin : g_lane
    assign serial_b_l[gi].rx_bit = serial_a_l[gi].tx_bit ^
                                   ((gi == 0) ? ctrl.err_inject : 1'b0);
    assign serial_a_l[gi].rx_bit = serial_b_l[gi].tx_bit;

    initial begin
      uvm_config_db#(virtual serial_if)::set(null, "uvm_test_top",
        $sformatf("vif_serial_a_l%0d", gi), serial_a_l[gi]);
      uvm_config_db#(virtual serial_if)::set(null, "uvm_test_top",
        $sformatf("vif_serial_b_l%0d", gi), serial_b_l[gi]);
    end
  end

  initial begin
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top",
                                          "vif_xgmii_a", xgmii_a);
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top",
                                          "vif_xgmii_b", xgmii_b);
    uvm_config_db#(virtual tb_ctrl_if)::set(null, "uvm_test_top",
                                            "vif_ctrl", ctrl);
    run_test();
  end

endmodule

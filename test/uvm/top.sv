// -----------------------------------------------------------------------------
// 所属：eth_work/test/uvm —— 环回 TB 仿真顶层
// 职责：产生字时钟（6600ps）与 66 倍频 bit 时钟（100ps）及复位；实例化
//       两端 XGMII/串行接口并交叉连接串行线（A.tx -> B.rx，B.tx -> A.rx）；
//       把接口句柄放入 config_db 后启动 UVM。
// 依赖：eth_pcs_if.sv（接口）、eth_tb_pkg（测试）。
// 所有权：仿真进程顶层，持有全部接口实例。
// -----------------------------------------------------------------------------

`timescale 1ps/1ps

module top;

  import uvm_pkg::*;
  import eth_tb_pkg::*;

  // 时钟比严格 66:1（见 phy_bfm 头注：FEC 开关不改变线速率）
  localparam time BIT_CLK_PERIOD  = 100;
  localparam time WORD_CLK_PERIOD = BIT_CLK_PERIOD * 66;

  logic word_clk = 0;
  logic bit_clk  = 0;
  logic rst_n    = 0;

  always #(WORD_CLK_PERIOD / 2) word_clk = ~word_clk;
  always #(BIT_CLK_PERIOD / 2)  bit_clk  = ~bit_clk;

  // 复位释放对齐字时钟沿，避免两端流水线半拍错位
  initial begin
    repeat (10) @(posedge word_clk);
    rst_n = 1;
  end

  // 两端接口
  xgmii_if  xgmii_a (word_clk, rst_n);
  xgmii_if  xgmii_b (word_clk, rst_n);
  serial_if serial_a (bit_clk, rst_n);
  serial_if serial_b (bit_clk, rst_n);

  // 串行链路交叉连接（双工；阶段 1 仅 A->B 承载流量，反向为 idle 码流）
  assign serial_b.rx_bit = serial_a.tx_bit;
  assign serial_a.rx_bit = serial_b.tx_bit;

  initial begin
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top",
                                          "vif_xgmii_a", xgmii_a);
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top",
                                          "vif_xgmii_b", xgmii_b);
    uvm_config_db#(virtual serial_if)::set(null, "uvm_test_top",
                                           "vif_serial_a", serial_a);
    uvm_config_db#(virtual serial_if)::set(null, "uvm_test_top",
                                           "vif_serial_b", serial_b);
    run_test();
  end

endmodule

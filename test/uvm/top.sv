// -----------------------------------------------------------------------------
// 所属：eth_work/test/uvm —— 环回 TB 仿真顶层
// 职责：产生字时钟（6600ps）与 66 倍频 bit 时钟（100ps）及复位；实例化
//       两端 XGMII/串行接口并交叉连接串行线（A.tx -> B.rx，B.tx -> A.rx）；
//       把接口句柄放入 config_db 后启动 UVM。
// 依赖：eth_pcs_if.sv（接口）、eth_tb_pkg（测试）。
// 所有权：仿真进程顶层，持有全部接口实例。
// -----------------------------------------------------------------------------

// 高精度时钟生成复用 aip_core（third_party/aip_core，vendored 1fs 精度版）。
// 注意 include 须在本文件 timescale 之前，且其后重新声明本文件 timescale。
`include "aip_log.sv"
`include "aip_time.sv"
`include "aip_clk.sv"

`timescale 1ps/1ps

module top;

  import uvm_pkg::*;
  import eth_tb_pkg::*;

  // 时钟：aip_clk 独立产生字时钟 156.25MHz 与位时钟 10.3125GHz。
  // 不再要求严格 66:1 —— 字时钟故意加 +50ppm，速率差由 BFM 弹性
  // idle 插入/删除吸收（真实 PHY 行为），顺带常态化验证弹性路径。
  aip_clk_if word_clk_if ();
  aip_clk_if bit_clk_if ();

  aip_clk word_clk_gen;
  aip_clk bit_clk_gen;

  wire word_clk = word_clk_if.clk;
  wire bit_clk  = bit_clk_if.clk;

  logic rst_n = 0;

  initial begin
    word_clk_gen = new("word_clk", word_clk_if);
    // +100ppm：确保字时钟生产速率严格大于位时钟消耗（含 fs 舍入误差），
    // BFM 工作在"删除主导域"—— 删除只发生在帧间 idle，永不伤帧；
    // 插入路径仅作启动瞬态兜底
    word_clk_gen.set_freq(156.25e6);
    word_clk_gen.set_ppm(100);

    bit_clk_gen = new("bit_clk", bit_clk_if);
    bit_clk_gen.set_freq(10.3125e9);

    word_clk_gen.start();
    bit_clk_gen.start();
  end

  // TB 控制接口：test 经此请求中途复位 / 注入链路误码
  tb_ctrl_if ctrl ();

  // 复位释放对齐字时钟沿，避免两端流水线半拍错位；
  // 上电复位之后，响应 test 的 reset_req 再次产生复位脉冲，
  // 清零 reset_req 作为完成握手
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

  // 两端接口
  xgmii_if  xgmii_a (word_clk, rst_n);
  xgmii_if  xgmii_b (word_clk, rst_n);
  serial_if serial_a (bit_clk, rst_n);
  serial_if serial_b (bit_clk, rst_n);

  // 串行链路交叉连接（双工；阶段 1 仅 A->B 承载流量，反向为 idle 码流）。
  // err_inject 置 1 期间翻转 A->B 方向线路 bit —— 模拟链路误码/瞬断
  assign serial_b.rx_bit = serial_a.tx_bit ^ ctrl.err_inject;
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
    uvm_config_db#(virtual tb_ctrl_if)::set(null, "uvm_test_top",
                                            "vif_ctrl", ctrl);
    run_test();
  end

endmodule

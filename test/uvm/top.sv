// -----------------------------------------------------------------------------
// 所属：eth_work/test/uvm —— 环回 TB 仿真顶层（全速率，+SPEED 运行时选择）
// 职责：`eth_pcs_lb_env 一键展开完整双 agent 环回环境：时钟（+SPEED
//       频率表：10g/25g/5g/40g，40g 另读 +AM_SPACING）、复位/TB 控制
//       钩子、单 lane 接口对与 4 lane 接口组、交叉接线（含扰动注入）、
//       全部 vif 下发。速率切换只换 +SPEED 插件参数，无需换 top。
// 依赖：eth_pcs_if.sv、tb_ctrl_if.sv、eth_tb_pkg、aip 时钟三件套、集成宏。
// 所有权：仿真进程顶层，持有全部接口实例。
// -----------------------------------------------------------------------------

// 高精度时钟生成复用 aip_core（third_party/aip_core，vendored 1fs 精度版）。
// 注意 include 须在本文件 timescale 之前，且其后重新声明本文件 timescale。
`include "aip_log.sv"
`include "aip_time.sv"
`include "aip_clk.sv"

`timescale 1ps/1ps

`include "agent/eth_pcs_macros.svh"

module top;

  import uvm_pkg::*;
  import eth_tb_pkg::*;

  // 一键环回环境：a/b 两端（vif 键 vif_xgmii_a、vif_serial_a、
  // vif_serial_a_l<i>、vif_ctrl 等，与 eth_tb_pkg 各测试取用约定一致）
  `eth_pcs_lb_env(a, b)

  initial run_test();

endmodule

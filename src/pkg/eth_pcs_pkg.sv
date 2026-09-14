// -----------------------------------------------------------------------------
// 所属：eth_work/src/pkg —— 编译单元入口 package
// 职责：按依赖顺序聚合 PCS/FEC/agent 全部类型与类；测试端只需
//       `import eth_pcs_pkg::*`。接口（eth_pcs_if.sv）不能入 package，
//       由 filelist 单独编译。
// 依赖：src 下全部实现文件；UVM 1.2。
// 所有权：无状态容器，无生命周期问题。
// -----------------------------------------------------------------------------

// include 顺序即依赖顺序：类型 -> 无状态编解码 -> 有状态流水线 -> FEC ->
// cfg/txn -> BFM -> driver/monitor -> agent。新增文件时必须维持该拓扑。
package eth_pcs_pkg;

  `include "uvm_macros.svh"
  import uvm_pkg::*;

  `include "pcs/pcs_types.sv"
  `include "pcs/pcs_codec.sv"
  `include "pcs/scrambler.sv"
  `include "pcs/block_sync.sv"
  `include "pcs/mld.sv"
  `include "pcs/an_cl73.sv"
  `include "pcs/lt_cl72.sv"
  `include "pcs/pcs_8b10b.sv"
  `include "pcs/basex_pcs.sv"
  `include "fec/fec_cl74.sv"
  `include "fec/rs_fec_cl91.sv"
  `include "agent/eth_frame_utils.sv"
  `include "agent/eth_pcs_cfg.sv"
  `include "agent/eth_pcs_phy_bfm.sv"
  `include "agent/eth_pcs_driver.sv"
  `include "agent/eth_pcs_monitor.sv"
  `include "agent/eth_pcs_agent.sv"

endpackage

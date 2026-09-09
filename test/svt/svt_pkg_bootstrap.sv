// -----------------------------------------------------------------------------
// 所属：eth_work/test/svt —— VIP 包引导文件
// 职责：在任何使用方之前把 svt ethernet UVM 包与接口定义拉进编译单元
//       （filelist_svt.f 第一个源文件）。VIP 的 .pkg 文件自带 include
//       guard，top 不再重复 include。
// 依赖：design_dir 的 include/sverilog 路径（filelist 提供 +incdir）。
// -----------------------------------------------------------------------------

`include "svt_ethernet.uvm.pkg"
`include "svt_ethernet_txrx_if.svi"

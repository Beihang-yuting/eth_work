// eth_work 阶段 2（svt VIP 交叉验证）编译清单。
// 前提：53 上已用 dw_vip_setup 生成 design_dir（环境变量 ETH_SVT_DESIGN
// 指向，默认 /home/ubuntu/ryan/eth_svt_design），内含 VIP 模型源码拷贝。
// 选项与 define 取自 VIP 示例生成的 vcs 命令行。
+lint=none
+define+SVT_ETHERNET
+define+UVM_PACKER_MAX_BYTES=16384
+define+UVM_NO_DEPRECATED
+define+SVT_ETHERNET_DEBUG_BUS_ENABLE
+define+SVT_UVM_TECHNOLOGY
+define+SYNOPSYS_SV

+incdir+$ETH_SVT_DESIGN/src/sverilog/vcs
+incdir+$ETH_SVT_DESIGN/include/sverilog
+incdir+$ETH_SVT_DESIGN/src/verilog/vcs
+incdir+$ETH_SVT_DESIGN/include/verilog

+incdir+../src
+incdir+../third_party/aip_core
+incdir+../third_party/net_packet/src
+incdir+../third_party/net_packet/src/common
+incdir+../third_party/net_packet/src/protocols
+incdir+../third_party/net_packet/src/protocols/l2
+incdir+../third_party/net_packet/src/protocols/l3
+incdir+../third_party/net_packet/src/protocols/l4
+incdir+../third_party/net_packet/src/protocols/tunnel
+incdir+../third_party/net_packet/src/protocols/rdma
+incdir+../third_party/net_packet/src/protocols/storage
+incdir+../third_party/net_packet/src/protocols/app
+incdir+../third_party/net_packet/src/core

../test/svt/svt_pkg_bootstrap.sv
../src/agent/eth_pcs_if.sv
../test/uvm/tb_ctrl_if.sv
../src/pkg/eth_pcs_pkg.sv
../test/uvm/eth_tb_pkg.sv
../test/svt/eth_svt_cross_pkg.sv
../test/svt/top_svt.sv

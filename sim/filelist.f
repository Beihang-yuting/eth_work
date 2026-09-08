// eth_work UVM 环回 TB 编译清单（相对 sim/ 目录；vcs 在 sim/ 下执行）
// 顺序：接口 -> agent package -> TB package -> top
+incdir+../src
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

../src/agent/eth_pcs_if.sv
../src/pkg/eth_pcs_pkg.sv
../test/uvm/eth_tb_pkg.sv
../test/uvm/top.sv

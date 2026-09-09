// eth_work 40G（4 lane MLD）环回 TB 编译清单：与 filelist.f 同源，
// 仅顶层换 top_40g
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

../src/agent/eth_pcs_if.sv
../test/uvm/tb_ctrl_if.sv
../src/pkg/eth_pcs_pkg.sv
../test/uvm/eth_tb_pkg.sv
../test/uvm/top_40g.sv

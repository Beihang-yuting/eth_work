// test_proto_complete.sv — 验证新实现的 9 个协议模板可建/可打包 + 默认随机 0 warning
`include "packet.sv"

module test_proto_complete;
    int pass_cnt = 0, fail_cnt = 0;

    task build_check(packet_template_e tmpl, string name);
        packet pkt = new();
        pkt.build_from_template(tmpl);
        pkt.do_pack();
        if (pkt.layer_stack.size() > 0 && pkt.raw_data.size() > 0) begin
            $display("[PASS] %s built: %0d layers, %0d bytes", name, pkt.layer_stack.size(), pkt.raw_data.size());
            pass_cnt++;
        end else begin
            $display("[FAIL] %s build empty", name);
            fail_cnt++;
        end
    endtask

    initial begin
        $display("\n=== 新协议模板 build + pack ===");
        build_check(ETH_LLDP,                      "ETH_LLDP");
        build_check(ETH_LACP,                      "ETH_LACP");
        build_check(ETH_STP,                       "ETH_STP");
        build_check(ETH_MAC_CONTROL,               "ETH_MAC_CONTROL");
        build_check(ETH_IPV4_UDP_DHCP,             "ETH_IPV4_UDP_DHCP");
        build_check(ETH_IPV6_UDP_DHCPV6,           "ETH_IPV6_UDP_DHCPV6");
        build_check(ETH_IPV4_UDP_DNS,              "ETH_IPV4_UDP_DNS");
        build_check(ETH_IPV4_UDP_BFD,              "ETH_IPV4_UDP_BFD");
        build_check(ETH_IPV4_UDP_ROCEV2_NVME_RDMA, "ETH_IPV4_UDP_ROCEV2_NVME_RDMA");
        build_check(ETH_IPV6_UDP_ROCEV2_NVME_RDMA, "ETH_IPV6_UDP_ROCEV2_NVME_RDMA");
        build_check(ETH_PTP_L2,                    "ETH_PTP_L2");

        $display("\n=== 800x 默认 randomize (全模板可建, 应 0 warning) ===");
        begin
            int n_ok = 0;
            for (int i = 0; i < 800; i++) begin
                automatic packet rp = new();
                if (rp.randomize()) n_ok++;
            end
            if (n_ok == 800) begin $display("[PASS] randomize 800/800"); pass_cnt++; end
            else begin $display("[FAIL] randomize %0d/800", n_ok); fail_cnt++; end
        end

        $display("\n===== PROTO_COMPLETE: %0d passed, %0d failed =====", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL PROTO_COMPLETE TESTS PASSED");
        else               $display("SOME TESTS FAILED");
        $finish;
    end
endmodule

// test_load_params.sv — 验证 load_params 通过 aip_cmdline_override 设值后报文字段正确
`include "aip_core_pkg.sv"
`include "packet.sv"

module test_load_params;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task check(string name, longint unsigned actual, longint unsigned expected);
        if (actual == expected) begin
            $display("[PASS] %s = 0x%0h", name, actual);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s = 0x%0h (expected 0x%0h)", name, actual, expected);
            fail_cnt++;
        end
    endtask

    initial begin
        packet pkt;
        eth_header  eth_h;
        ipv4_header ipv4_h;
        tcp_header  tcp_h;
        udp_header  udp_h;
        vxlan_header vxlan_h;

        // ============================================================
        // Test 1: ETH_IPV4_TCP — 基本字段覆盖
        // ============================================================
        $display("\n=== Test 1: ETH_IPV4_TCP load_params ===");

        aip_cmdline_override::set_val("t1.outer_eth.dst_mac", "0xAABBCCDDEEFF");
        aip_cmdline_override::set_val("t1.outer_eth.src_mac", "0x112233445566");
        aip_cmdline_override::set_val("t1.ipv4.src_addr", "0xC0A80001");
        aip_cmdline_override::set_val("t1.ipv4.dst_addr", "0xC0A80002");
        aip_cmdline_override::set_val("t1.ipv4.ttl", "128");
        aip_cmdline_override::set_val("t1.tcp.src_port", "12345");
        aip_cmdline_override::set_val("t1.tcp.dst_port", "80");
        aip_cmdline_override::set_val("t1.pkt_len", "100");

        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        pkt.load_params("t1");
        pkt.do_pack();

        $cast(eth_h, pkt.layer_stack[0]);
        check("eth.dst_mac", eth_h.dst_mac, 48'hAABBCCDDEEFF);
        check("eth.src_mac", eth_h.src_mac, 48'h112233445566);
        check("eth.ethertype", eth_h.ethertype, 16'h0800);

        $cast(ipv4_h, pkt.layer_stack[1]);
        check("ipv4.src_addr", ipv4_h.src_addr, 32'hC0A80001);
        check("ipv4.dst_addr", ipv4_h.dst_addr, 32'hC0A80002);
        check("ipv4.ttl", ipv4_h.ttl, 128);
        check("ipv4.protocol", ipv4_h.protocol, 6);

        $cast(tcp_h, pkt.layer_stack[2]);
        check("tcp.src_port", tcp_h.src_port, 12345);
        check("tcp.dst_port", tcp_h.dst_port, 80);

        check("pkt_len", pkt.pkt_len, 100);
        check("raw_data.size", pkt.raw_data.size(), 100);

        check("raw[0]", pkt.raw_data[0], 8'hAA);
        check("raw[1]", pkt.raw_data[1], 8'hBB);
        check("raw[5]", pkt.raw_data[5], 8'hFF);

        aip_cmdline_override::clear_all();

        // ============================================================
        // Test 2: VXLAN 隧道 — outer/inner 区分
        // ============================================================
        $display("\n=== Test 2: VXLAN tunnel outer/inner ===");

        aip_cmdline_override::set_val("t2.outer_eth.dst_mac", "0xAAAAAAAAAAAA");
        aip_cmdline_override::set_val("t2.outer_ipv4.src_addr", "0x0A000001");
        aip_cmdline_override::set_val("t2.outer_udp.dst_port", "4789");
        aip_cmdline_override::set_val("t2.vxlan.vni", "0x123456");
        aip_cmdline_override::set_val("t2.inner_eth.dst_mac", "0xBBBBBBBBBBBB");
        aip_cmdline_override::set_val("t2.inner_ipv4.dst_addr", "0xC0A80064");
        aip_cmdline_override::set_val("t2.tcp.dst_port", "443");

        pkt = new();
        pkt.build_from_template(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
        pkt.load_params("t2");
        pkt.do_pack();

        $cast(eth_h, pkt.layer_stack[0]);
        check("outer_eth.dst_mac", eth_h.dst_mac, 48'hAAAAAAAAAAAA);

        $cast(ipv4_h, pkt.layer_stack[1]);
        check("outer_ipv4.src_addr", ipv4_h.src_addr, 32'h0A000001);

        $cast(udp_h, pkt.layer_stack[2]);
        check("outer_udp.dst_port", udp_h.dst_port, 4789);

        $cast(vxlan_h, pkt.layer_stack[3]);
        check("vxlan.vni", vxlan_h.vni, 24'h123456);

        $cast(eth_h, pkt.layer_stack[4]);
        check("inner_eth.dst_mac", eth_h.dst_mac, 48'hBBBBBBBBBBBB);

        $cast(ipv4_h, pkt.layer_stack[5]);
        check("inner_ipv4.dst_addr", ipv4_h.dst_addr, 32'hC0A80064);

        $cast(tcp_h, pkt.layer_stack[6]);
        check("tcp.dst_port", tcp_h.dst_port, 443);

        aip_cmdline_override::clear_all();

        // ============================================================
        // Test 3: 无 override — 默认值不被破坏
        // ============================================================
        $display("\n=== Test 3: No override — defaults preserved ===");

        pkt = new();
        pkt.build_from_template(ETH_IPV4_UDP);
        pkt.load_params("t3_empty");
        pkt.do_pack();

        $cast(udp_h, pkt.layer_stack[2]);
        check("udp.src_port_default", udp_h.src_port, 0);
        check("udp.dst_port_default", udp_h.dst_port, 0);
        check("raw_data_not_empty", (pkt.raw_data.size() > 0) ? 1 : 0, 1);

        // ============================================================
        // Summary
        // ============================================================
        $display("\n==========================================");
        $display("  PASS: %0d", pass_cnt);
        $display("  FAIL: %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("==========================================");
        $finish;
    end

endmodule

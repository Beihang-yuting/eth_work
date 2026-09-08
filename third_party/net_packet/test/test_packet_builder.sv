`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "l2/eth_header.sv"
`include "l2/vlan_header.sv"
`include "l3/ipv4_header.sv"
`include "l3/ipv6_header.sv"
`include "l3/arp_header.sv"
`include "l4/tcp_header.sv"
`include "l4/udp_header.sv"
`include "l4/icmp_header.sv"
`include "l4/icmpv6_header.sv"
`include "core/protocol_graph.sv"
`include "core/template_registry.sv"
`include "core/packet.sv"

program test_packet_builder;
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string name, bit condition);
        if (condition) begin $display("[PASS] %s", name); pass_count++; end
        else begin $display("[FAIL] %s", name); fail_count++; end
    endtask

    initial begin
        packet pkt;
        protocol_base layers[$];
        protocol_base found;
        string s;

        $display("=== test_packet_builder ===");

        // -----------------------------------------------------------------
        // 1. Build from template ETH_IPV4_TCP — 3 layers, headers_length=54
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        check("tmpl_eth_ipv4_tcp: 3 layers", pkt.layer_stack.size() == 3);
        check("tmpl_eth_ipv4_tcp: layer[0] is ETHERNET",
              pkt.layer_stack[0].proto_type == PROTO_ETHERNET);
        check("tmpl_eth_ipv4_tcp: layer[1] is IPV4",
              pkt.layer_stack[1].proto_type == PROTO_IPV4);
        check("tmpl_eth_ipv4_tcp: layer[2] is TCP",
              pkt.layer_stack[2].proto_type == PROTO_TCP);
        check("tmpl_eth_ipv4_tcp: headers_length == 54",
              pkt.get_all_headers_length() == 54);

        // -----------------------------------------------------------------
        // 2. Build from template ETH_ARP — 2 layers
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_ARP);
        check("tmpl_eth_arp: 2 layers", pkt.layer_stack.size() == 2);
        check("tmpl_eth_arp: layer[0] is ETHERNET",
              pkt.layer_stack[0].proto_type == PROTO_ETHERNET);
        check("tmpl_eth_arp: layer[1] is ARP",
              pkt.layer_stack[1].proto_type == PROTO_ARP);

        // -----------------------------------------------------------------
        // 3. Free-form: add eth+vlan+ipv4+tcp — 4 layers
        // -----------------------------------------------------------------
        pkt = new();
        begin
            eth_header  eh  = new();
            vlan_header vh  = new();
            ipv4_header iph = new();
            tcp_header  th  = new();
            bit ok;

            ok = pkt.add_layer(eh);
            check("freeform: add eth", ok == 1);
            ok = pkt.add_layer(vh);
            check("freeform: add vlan", ok == 1);
            ok = pkt.add_layer(iph);
            check("freeform: add ipv4", ok == 1);
            ok = pkt.add_layer(th);
            check("freeform: add tcp", ok == 1);
            check("freeform: 4 layers", pkt.layer_stack.size() == 4);
        end

        // -----------------------------------------------------------------
        // 4. Invalid chain rejected (eth->tcp without force_mode)
        // -----------------------------------------------------------------
        pkt = new();
        begin
            eth_header eh2 = new();
            tcp_header th2 = new();
            bit ok;

            ok = pkt.add_layer(eh2);
            check("invalid_chain: add eth", ok == 1);
            ok = pkt.add_layer(th2);
            check("invalid_chain: eth->tcp rejected", ok == 0);
            check("invalid_chain: only 1 layer", pkt.layer_stack.size() == 1);
        end

        // -----------------------------------------------------------------
        // 5. Force mode allows invalid chain
        // -----------------------------------------------------------------
        pkt = new();
        pkt.force_mode = 1;
        begin
            eth_header eh3 = new();
            tcp_header th3 = new();
            bit ok;

            ok = pkt.add_layer(eh3);
            check("force_mode: add eth", ok == 1);
            ok = pkt.add_layer(th3);
            check("force_mode: eth->tcp allowed", ok == 1);
            check("force_mode: 2 layers", pkt.layer_stack.size() == 2);
        end

        // -----------------------------------------------------------------
        // 6. get_layer finds IPv4, returns null for missing VXLAN
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        found = pkt.get_layer(PROTO_IPV4);
        check("get_layer: found IPV4", found != null);
        check("get_layer: IPV4 proto_type", found.proto_type == PROTO_IPV4);
        found = pkt.get_layer(PROTO_VXLAN);
        check("get_layer: VXLAN is null", found == null);

        // -----------------------------------------------------------------
        // 7. Length control: pkt_length=100 -> raw_data.size()==100
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        pkt.pkt_len = 100;
        pkt.payload_mode = PAYLOAD_FIXED;
        pkt.payload_fixed_val = 8'hAA;
        pkt.do_pack();
        check("length_control_100: raw_data.size() == 100",
              pkt.raw_data.size() == 100);

        // -----------------------------------------------------------------
        // 8. Length control: pkt_length < headers triggers warning,
        //    raw_data.size()==headers_length
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        pkt.pkt_len = 10;  // less than 54
        pkt.do_pack();
        check("length_control_short: raw_data.size() == headers_length",
              pkt.raw_data.size() == pkt.get_all_headers_length());

        // -----------------------------------------------------------------
        // 9. Payload modes: PAYLOAD_INCREMENT, verify bytes after headers
        //    are 0x00, 0x01, 0x02 ...
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        pkt.pkt_len = 64;
        pkt.payload_mode = PAYLOAD_INCREMENT;
        pkt.do_pack();
        begin
            int hdr_len;
            int payload_len;
            bit incr_ok = 1;
            hdr_len = pkt.get_all_headers_length();
            payload_len = 64 - hdr_len;
            check("payload_incr: raw_data.size() == 64", pkt.raw_data.size() == 64);
            for (int i = 0; i < payload_len; i++) begin
                if (pkt.raw_data[hdr_len + i] != (i % 256)) begin
                    incr_ok = 0;
                    $display("  payload byte[%0d] = 0x%02x, expected 0x%02x",
                             i, pkt.raw_data[hdr_len + i], i % 256);
                    break;
                end
            end
            check("payload_incr: bytes are 0x00,0x01,0x02...", incr_ok);
        end

        // -----------------------------------------------------------------
        // 10. Pack/unpack roundtrip: build ETH_IPV4_TCP, pack, unpack,
        //     verify 3 layers recovered
        // -----------------------------------------------------------------
        begin
            packet pkt_tx = new();
            packet pkt_rx = new();
            pkt_tx.build_from_template(ETH_IPV4_TCP);
            pkt_tx.pkt_len = 100;
            pkt_tx.payload_mode = PAYLOAD_FIXED;
            pkt_tx.payload_fixed_val = 8'h55;
            pkt_tx.do_pack();

            pkt_rx.unpack(pkt_tx.raw_data);
            check("roundtrip: 3 layers recovered", pkt_rx.layer_stack.size() == 3);
            if (pkt_rx.layer_stack.size() >= 3) begin
                check("roundtrip: layer[0] is ETHERNET",
                      pkt_rx.layer_stack[0].proto_type == PROTO_ETHERNET);
                check("roundtrip: layer[1] is IPV4",
                      pkt_rx.layer_stack[1].proto_type == PROTO_IPV4);
                check("roundtrip: layer[2] is TCP",
                      pkt_rx.layer_stack[2].proto_type == PROTO_TCP);
            end
        end

        // -----------------------------------------------------------------
        // 11. to_proto_chain() returns expected string
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        s = pkt.to_proto_chain();
        check("to_proto_chain: correct string",
              s == "PROTO_ETHERNET -> PROTO_IPV4 -> PROTO_TCP");

        // -----------------------------------------------------------------
        // 12. to_brief() returns non-empty string
        // -----------------------------------------------------------------
        pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        pkt.pkt_len = 64;
        pkt.do_pack();
        s = pkt.to_brief();
        check("to_brief: non-empty", s.len() > 0);
        $display("  to_brief = %s", s);

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end
endprogram

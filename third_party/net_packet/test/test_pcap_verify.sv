// test/test_pcap_verify.sv
// Comprehensive protocol verification via PCAP round-trip:
//   build packet -> set fields -> do_pack -> write PCAP -> read PCAP -> unpack -> validate -> compare
`include "pcap/pcap_writer.sv"
`include "pcap/pcap_reader.sv"
`include "parser/protocol_parser.sv"
`include "parser/packet_comparator.sv"

program test_pcap_verify;
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string name, bit condition);
        if (condition) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask

    // Helper: write packet list to pcap, read back, return parsed packets
    task automatic pcap_roundtrip(
        string filename,
        ref packet pkts_in[$],
        ref packet pkts_out[$]
    );
        pcap_writer pw;
        pcap_reader pr;
        pw = new();
        pr = new();

        pw.open(filename);
        pw.write_packets(pkts_in);
        pw.close();

        pr.open(filename);
        pr.read_all(pkts_out);
        pr.close();
    endtask

    initial begin
        protocol_parser parser;
        packet_comparator comparator;
        parser = new();
        comparator = new();
        parser.verify_en = 1;

        $display("================================================================");
        $display("  Comprehensive Protocol PCAP Round-Trip Verification");
        $display("================================================================");

        // =================================================================
        // 1. ETH + IPv4 + TCP
        // =================================================================
        $display("\n--- 1. ETH/IPv4/TCP ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_IPV4_TCP);
            begin
                eth_header eth;
                $cast(eth, pkt_tx.get_layer(PROTO_ETHERNET));
                eth.dst_mac = 48'h001122334455;
                eth.src_mac = 48'h665544332211;
            end
            begin
                ipv4_header ip;
                $cast(ip, pkt_tx.get_layer(PROTO_IPV4));
                ip.src_addr = 32'hC0A80101;  // 192.168.1.1
                ip.dst_addr = 32'hC0A80102;  // 192.168.1.2
                ip.ttl = 64;
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkt_tx.get_layer(PROTO_TCP));
                tcp.src_port = 16'd45678;
                tcp.dst_port = 16'd443;
                tcp.flags = 9'b0_0000_0010;  // SYN
                tcp.window_size = 16'd65535;
            end
            pkt_tx.pkt_len = 74;
            pkt_tx.payload_mode = PAYLOAD_INCREMENT;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_ipv4_tcp.pcap", pkts_in, pkts_out);

            check("ipv4_tcp: pcap roundtrip count", pkts_out.size() == 1);
            check("ipv4_tcp: raw_data size", pkts_out[0].raw_data.size() == 74);
            check("ipv4_tcp: layer count", pkts_out[0].layer_stack.size() == 3);

            begin
                ipv4_header ip_rx;
                $cast(ip_rx, pkts_out[0].get_layer(PROTO_IPV4));
                check("ipv4_tcp: src_addr", ip_rx.src_addr == 32'hC0A80101);
                check("ipv4_tcp: dst_addr", ip_rx.dst_addr == 32'hC0A80102);
                check("ipv4_tcp: ttl", ip_rx.ttl == 64);
            end
            begin
                tcp_header tcp_rx;
                $cast(tcp_rx, pkts_out[0].get_layer(PROTO_TCP));
                check("ipv4_tcp: src_port", tcp_rx.src_port == 16'd45678);
                check("ipv4_tcp: dst_port", tcp_rx.dst_port == 16'd443);
                check("ipv4_tcp: syn flag", tcp_rx.flags[1] == 1);
            end

            result = parser.validate(pkts_out[0]);
            check("ipv4_tcp: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 2. ETH + IPv4 + UDP
        // =================================================================
        $display("\n--- 2. ETH/IPv4/UDP ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_IPV4_UDP);
            begin
                ipv4_header ip;
                $cast(ip, pkt_tx.get_layer(PROTO_IPV4));
                ip.src_addr = 32'h0A000001;  // 10.0.0.1
                ip.dst_addr = 32'h0A000002;  // 10.0.0.2
            end
            begin
                udp_header udp;
                $cast(udp, pkt_tx.get_layer(PROTO_UDP));
                udp.src_port = 16'd53;
                udp.dst_port = 16'd1024;
            end
            pkt_tx.pkt_len = 100;
            pkt_tx.payload_mode = PAYLOAD_FIXED;
            pkt_tx.payload_fixed_val = 8'hBB;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_ipv4_udp.pcap", pkts_in, pkts_out);

            check("ipv4_udp: layer count", pkts_out[0].layer_stack.size() == 3);
            begin
                udp_header udp_rx;
                $cast(udp_rx, pkts_out[0].get_layer(PROTO_UDP));
                check("ipv4_udp: src_port", udp_rx.src_port == 16'd53);
                check("ipv4_udp: dst_port", udp_rx.dst_port == 16'd1024);
            end

            result = parser.validate(pkts_out[0]);
            check("ipv4_udp: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 3. ETH + IPv6 + TCP
        // =================================================================
        $display("\n--- 3. ETH/IPv6/TCP ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_IPV6_TCP);
            begin
                ipv6_header ip6;
                $cast(ip6, pkt_tx.get_layer(PROTO_IPV6));
                ip6.src_addr = 128'hFD000000_00000000_00000000_00000001;
                ip6.dst_addr = 128'hFD000000_00000000_00000000_00000002;
                ip6.hop_limit = 128;
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkt_tx.get_layer(PROTO_TCP));
                tcp.src_port = 16'd8080;
                tcp.dst_port = 16'd22;
                tcp.flags = 9'b0_0001_0000;  // ACK
                tcp.seq_num = 32'hAABBCCDD;
            end
            pkt_tx.pkt_len = 120;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_ipv6_tcp.pcap", pkts_in, pkts_out);

            check("ipv6_tcp: layer count", pkts_out[0].layer_stack.size() == 3);
            begin
                ipv6_header ip6_rx;
                $cast(ip6_rx, pkts_out[0].get_layer(PROTO_IPV6));
                check("ipv6_tcp: src_addr", ip6_rx.src_addr == 128'hFD000000_00000000_00000000_00000001);
                check("ipv6_tcp: hop_limit", ip6_rx.hop_limit == 128);
            end
            begin
                tcp_header tcp_rx;
                $cast(tcp_rx, pkts_out[0].get_layer(PROTO_TCP));
                check("ipv6_tcp: src_port", tcp_rx.src_port == 16'd8080);
                check("ipv6_tcp: dst_port", tcp_rx.dst_port == 16'd22);
                check("ipv6_tcp: seq_num", tcp_rx.seq_num == 32'hAABBCCDD);
            end

            result = parser.validate(pkts_out[0]);
            check("ipv6_tcp: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 4. ETH + VLAN + IPv4 + TCP
        // =================================================================
        $display("\n--- 4. ETH/VLAN/IPv4/TCP ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_VLAN_IPV4_TCP);
            begin
                vlan_header vl;
                $cast(vl, pkt_tx.get_layer(PROTO_VLAN));
                vl.vlan_id = 12'd100;
                vl.pcp = 3'd5;
            end
            begin
                ipv4_header ip;
                $cast(ip, pkt_tx.get_layer(PROTO_IPV4));
                ip.src_addr = 32'hAC100164;  // 172.16.1.100
                ip.dst_addr = 32'hAC1001C8;  // 172.16.1.200
            end
            pkt_tx.pkt_len = 100;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_vlan_tcp.pcap", pkts_in, pkts_out);

            check("vlan_tcp: layer count", pkts_out[0].layer_stack.size() == 4);
            begin
                vlan_header vl_rx;
                $cast(vl_rx, pkts_out[0].get_layer(PROTO_VLAN));
                check("vlan_tcp: vlan_id", vl_rx.vlan_id == 12'd100);
                check("vlan_tcp: pcp", vl_rx.pcp == 3'd5);
            end

            result = parser.validate(pkts_out[0]);
            check("vlan_tcp: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 5. ETH + IPv4 + UDP + VXLAN + ETH + IPv4 + TCP — VXLAN tunnel
        // =================================================================
        $display("\n--- 5. VXLAN Tunnel ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;
            diff_entry_t diffs[$];

            pkt_tx.build_from_template(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
            begin
                ipv4_header ip_outer;
                ip_outer = pkt_tx.get_ipv4(0);
                ip_outer.src_addr = 32'hC0A80A01;  // 192.168.10.1
                ip_outer.dst_addr = 32'hC0A80A02;  // 192.168.10.2
            end
            begin
                vxlan_header vx;
                $cast(vx, pkt_tx.get_layer(PROTO_VXLAN));
                vx.vni = 24'd5000;
            end
            begin
                ipv4_header ip_inner;
                ip_inner = pkt_tx.get_ipv4(1);
                ip_inner.src_addr = 32'h0A0A0A01;  // 10.10.10.1
                ip_inner.dst_addr = 32'h0A0A0A02;  // 10.10.10.2
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkt_tx.get_layer(PROTO_TCP));
                tcp.src_port = 16'd11111;
                tcp.dst_port = 16'd22222;
            end
            pkt_tx.pkt_len = 150;
            pkt_tx.payload_mode = PAYLOAD_INCREMENT;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_vxlan.pcap", pkts_in, pkts_out);

            check("vxlan: layer count", pkts_out[0].layer_stack.size() == 7);
            check("vxlan: raw_data size", pkts_out[0].raw_data.size() == 150);

            if (pkts_out[0].layer_stack.size() == 7) begin
                check("vxlan: layer[0] ETH",  pkts_out[0].layer_stack[0].proto_type == PROTO_ETHERNET);
                check("vxlan: layer[1] IPv4", pkts_out[0].layer_stack[1].proto_type == PROTO_IPV4);
                check("vxlan: layer[2] UDP",  pkts_out[0].layer_stack[2].proto_type == PROTO_UDP);
                check("vxlan: layer[3] VXLAN",pkts_out[0].layer_stack[3].proto_type == PROTO_VXLAN);
                check("vxlan: layer[4] ETH",  pkts_out[0].layer_stack[4].proto_type == PROTO_ETHERNET);
                check("vxlan: layer[5] IPv4", pkts_out[0].layer_stack[5].proto_type == PROTO_IPV4);
                check("vxlan: layer[6] TCP",  pkts_out[0].layer_stack[6].proto_type == PROTO_TCP);
            end

            begin
                ipv4_header ip_rx;
                ip_rx = pkts_out[0].get_ipv4(0);
                check("vxlan: outer src_addr", ip_rx.src_addr == 32'hC0A80A01);
                check("vxlan: outer dst_addr", ip_rx.dst_addr == 32'hC0A80A02);
            end
            begin
                vxlan_header vx_rx;
                $cast(vx_rx, pkts_out[0].get_layer(PROTO_VXLAN));
                check("vxlan: vni", vx_rx.vni == 24'd5000);
            end
            begin
                ipv4_header ip_inner_rx;
                ip_inner_rx = pkts_out[0].get_ipv4(1);
                check("vxlan: inner src_addr", ip_inner_rx.src_addr == 32'h0A0A0A01);
                check("vxlan: inner dst_addr", ip_inner_rx.dst_addr == 32'h0A0A0A02);
            end
            begin
                tcp_header tcp_rx;
                $cast(tcp_rx, pkts_out[0].get_layer(PROTO_TCP));
                check("vxlan: inner src_port", tcp_rx.src_port == 16'd11111);
                check("vxlan: inner dst_port", tcp_rx.dst_port == 16'd22222);
            end

            result = parser.validate(pkts_out[0]);
            check("vxlan: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));

            comparator.compare(pkt_tx, pkts_out[0], diffs);
            check("vxlan: comparator no diffs", diffs.size() == 0);
            if (diffs.size() > 0) begin
                foreach (diffs[d])
                    $display("  DIFF: %s.%s: %s vs %s",
                        diffs[d].layer.name(), diffs[d].field_name,
                        diffs[d].val_a, diffs[d].val_b);
            end
        end

        // =================================================================
        // 6. ETH + IPv4 + GRE + IPv4 + TCP — GRE tunnel
        // =================================================================
        $display("\n--- 6. GRE Tunnel ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_IPV4_GRE_IPV4_TCP);
            begin
                ipv4_header ip_outer;
                ip_outer = pkt_tx.get_ipv4(0);
                ip_outer.src_addr = 32'hC0A81401;  // 192.168.20.1
                ip_outer.dst_addr = 32'hC0A81402;  // 192.168.20.2
            end
            begin
                gre_header gre;
                $cast(gre, pkt_tx.get_layer(PROTO_GRE));
                gre.k_flag = 1;
                gre.key = 32'hDEAD_BEEF;
            end
            begin
                ipv4_header ip_inner;
                ip_inner = pkt_tx.get_ipv4(1);
                ip_inner.src_addr = 32'h0A141401;  // 10.20.20.1
                ip_inner.dst_addr = 32'h0A141402;  // 10.20.20.2
            end
            pkt_tx.pkt_len = 130;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_gre.pcap", pkts_in, pkts_out);

            check("gre: layer count >= 5", pkts_out[0].layer_stack.size() >= 5);
            begin
                gre_header gre_rx;
                $cast(gre_rx, pkts_out[0].get_layer(PROTO_GRE));
                check("gre: k_flag", gre_rx.k_flag == 1);
                check("gre: key", gre_rx.key == 32'hDEAD_BEEF);
            end
            begin
                ipv4_header ip_inner_rx;
                ip_inner_rx = pkts_out[0].get_ipv4(1);
                check("gre: inner src_addr", ip_inner_rx.src_addr == 32'h0A141401);
            end

            result = parser.validate(pkts_out[0]);
            check("gre: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 7. ETH + IPv4 + UDP + Geneve + ETH + IPv4 + UDP — Geneve tunnel
        // =================================================================
        $display("\n--- 7. Geneve Tunnel ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP);
            begin
                geneve_header gn;
                $cast(gn, pkt_tx.get_layer(PROTO_GENEVE));
                gn.vni = 24'hABCDEF;
            end
            pkt_tx.pkt_len = 150;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_geneve.pcap", pkts_in, pkts_out);

            check("geneve: layer count", pkts_out[0].layer_stack.size() == 7);
            begin
                geneve_header gn_rx;
                $cast(gn_rx, pkts_out[0].get_layer(PROTO_GENEVE));
                check("geneve: vni", gn_rx.vni == 24'hABCDEF);
            end

            result = parser.validate(pkts_out[0]);
            check("geneve: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 8. ETH + IPv4 + UDP + RoCEv2 — RDMA
        // =================================================================
        $display("\n--- 8. RoCEv2 ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_IPV4_UDP_ROCEV2);
            begin
                ipv4_header ip;
                $cast(ip, pkt_tx.get_layer(PROTO_IPV4));
                ip.src_addr = 32'hC0A83201;  // 192.168.50.1
                ip.dst_addr = 32'hC0A83202;  // 192.168.50.2
            end
            begin
                rocev2_bth bth;
                $cast(bth, pkt_tx.get_layer(PROTO_ROCEV2));
                bth.opcode = 8'h04;   // SEND Only
                bth.dest_qp = 24'h000100;
                bth.psn = 24'h000001;
            end
            pkt_tx.pkt_len = 100;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_rocev2.pcap", pkts_in, pkts_out);

            check("rocev2: layer count", pkts_out[0].layer_stack.size() == 4);
            begin
                rocev2_bth bth_rx;
                $cast(bth_rx, pkts_out[0].get_layer(PROTO_ROCEV2));
                check("rocev2: opcode", bth_rx.opcode == 8'h04);
                check("rocev2: dest_qp", bth_rx.dest_qp == 24'h000100);
                check("rocev2: psn", bth_rx.psn == 24'h000001);
            end

            result = parser.validate(pkts_out[0]);
            check("rocev2: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 9. ETH + ARP
        // =================================================================
        $display("\n--- 9. ARP ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            parse_result_t result;

            pkt_tx.build_from_template(ETH_ARP);
            begin
                arp_header arp;
                $cast(arp, pkt_tx.get_layer(PROTO_ARP));
                arp.opcode     = 16'd1;   // ARP Request
                arp.sender_mac  = 48'h001122334455;
                arp.sender_ip  = 32'hC0A80101;
                arp.target_mac  = 48'h000000000000;
                arp.target_ip  = 32'hC0A80102;
            end
            pkt_tx.pkt_len = 60;
            pkt_tx.do_pack();

            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_arp.pcap", pkts_in, pkts_out);

            check("arp: layer count", pkts_out[0].layer_stack.size() == 2);
            begin
                arp_header arp_rx;
                $cast(arp_rx, pkts_out[0].get_layer(PROTO_ARP));
                check("arp: opcode", arp_rx.opcode == 16'd1);
                check("arp: sender_mac", arp_rx.sender_mac == 48'h001122334455);
                check("arp: sender_ip", arp_rx.sender_ip == 32'hC0A80101);
                check("arp: target_ip", arp_rx.target_ip == 32'hC0A80102);
            end

            result = parser.validate(pkts_out[0]);
            check("arp: parser valid", result.valid == 1);
            if (!result.valid)
                $display("  %s", parser.result_to_string(result));
        end

        // =================================================================
        // 10. Mixed Traffic PCAP (6 packets)
        // =================================================================
        $display("\n--- 10. Mixed Traffic PCAP (6 packets) ---");
        begin
            packet pkts_in[$];
            packet pkts_out[$];
            packet p;
            parse_result_t result;
            int all_valid;

            // Packet 0: IPv4 TCP SYN
            p = new();
            p.build_from_template(ETH_IPV4_TCP);
            begin
                tcp_header tcp;
                $cast(tcp, p.get_layer(PROTO_TCP));
                tcp.flags = 9'b0_0000_0010; tcp.src_port = 16'd50000; tcp.dst_port = 16'd80;
            end
            p.pkt_len = 64;
            p.do_pack();
            pkts_in.push_back(p);

            // Packet 1: IPv6 UDP
            p = new();
            p.build_from_template(ETH_IPV6_UDP);
            begin
                udp_header udp;
                $cast(udp, p.get_layer(PROTO_UDP));
                udp.src_port = 16'd12345; udp.dst_port = 16'd53;
            end
            p.pkt_len = 100;
            p.do_pack();
            pkts_in.push_back(p);

            // Packet 2: ARP
            p = new();
            p.build_from_template(ETH_ARP);
            p.pkt_len = 60;
            p.do_pack();
            pkts_in.push_back(p);

            // Packet 3: VLAN IPv4 UDP
            p = new();
            p.build_from_template(ETH_VLAN_IPV4_UDP);
            begin
                vlan_header vl;
                $cast(vl, p.get_layer(PROTO_VLAN));
                vl.vlan_id = 12'd200;
            end
            p.pkt_len = 80;
            p.do_pack();
            pkts_in.push_back(p);

            // Packet 4: VXLAN tunnel
            p = new();
            p.build_from_template(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
            p.pkt_len = 200;
            p.do_pack();
            pkts_in.push_back(p);

            // Packet 5: GRE tunnel
            p = new();
            p.build_from_template(ETH_IPV4_GRE_IPV4_TCP);
            p.pkt_len = 120;
            p.do_pack();
            pkts_in.push_back(p);

            pcap_roundtrip("verify_mixed.pcap", pkts_in, pkts_out);

            check("mixed: packet count", pkts_out.size() == 6);

            if (pkts_out.size() == 6) begin
                check("mixed: pkt[0] size=64",  pkts_out[0].raw_data.size() == 64);
                check("mixed: pkt[1] size=100", pkts_out[1].raw_data.size() == 100);
                check("mixed: pkt[2] size=60",  pkts_out[2].raw_data.size() == 60);
                check("mixed: pkt[3] size=80",  pkts_out[3].raw_data.size() == 80);
                check("mixed: pkt[4] size=200", pkts_out[4].raw_data.size() == 200);
                check("mixed: pkt[5] size=120", pkts_out[5].raw_data.size() == 120);

                // Parser validation for each packet
                all_valid = 1;
                for (int i = 0; i < 6; i++) begin
                    result = parser.validate(pkts_out[i]);
                    if (!result.valid) begin
                        all_valid = 0;
                        $display("  mixed pkt[%0d] FAIL: %s", i, parser.result_to_string(result));
                    end
                end
                check("mixed: all 6 packets parser valid", all_valid == 1);
            end

            // Byte-level comparison: TX raw_data == RX raw_data
            begin
                int byte_match;
                byte_match = 1;
                for (int i = 0; i < 6; i++) begin
                    if (pkts_in[i].raw_data.size() != pkts_out[i].raw_data.size()) begin
                        byte_match = 0;
                        break;
                    end
                    for (int b = 0; b < pkts_in[i].raw_data.size(); b++) begin
                        if (pkts_in[i].raw_data[b] != pkts_out[i].raw_data[b]) begin
                            byte_match = 0;
                            $display("  mixed pkt[%0d] byte[%0d]: TX=0x%02x RX=0x%02x",
                                i, b, pkts_in[i].raw_data[b], pkts_out[i].raw_data[b]);
                            break;
                        end
                    end
                    if (!byte_match) break;
                end
                check("mixed: all bytes match (TX == RX)", byte_match == 1);
            end
        end

        // =================================================================
        // 11. Payload Integrity — increment pattern survives PCAP roundtrip
        // =================================================================
        $display("\n--- 11. Payload Integrity ---");
        begin
            packet pkt_tx = new();
            packet pkts_in[$];
            packet pkts_out[$];
            int hdr_len;
            int payload_ok;

            pkt_tx.build_from_template(ETH_IPV4_UDP);
            pkt_tx.pkt_len = 256;
            pkt_tx.payload_mode = PAYLOAD_INCREMENT;
            pkt_tx.do_pack();

            hdr_len = pkt_tx.get_all_headers_length();
            pkts_in.push_back(pkt_tx);
            pcap_roundtrip("verify_payload.pcap", pkts_in, pkts_out);

            payload_ok = 1;
            for (int i = 0; i < (256 - hdr_len); i++) begin
                if (pkts_out[0].raw_data[hdr_len + i] != (i % 256)) begin
                    payload_ok = 0;
                    $display("  payload byte[%0d]: expected 0x%02x, got 0x%02x",
                        i, i % 256, pkts_out[0].raw_data[hdr_len + i]);
                    break;
                end
            end
            check("payload: increment pattern intact after PCAP roundtrip", payload_ok == 1);
        end

        // =================================================================
        // Summary
        // =================================================================
        $display("\n================================================================");
        $display("  PCAP Round-Trip Verification Summary");
        $display("================================================================");
        $display("  Protocols tested:");
        $display("    - ETH/IPv4/TCP      (basic L2-L4)");
        $display("    - ETH/IPv4/UDP      (basic L2-L4)");
        $display("    - ETH/IPv6/TCP      (IPv6)");
        $display("    - ETH/VLAN/IPv4/TCP (802.1Q)");
        $display("    - VXLAN tunnel      (7-layer encapsulation)");
        $display("    - GRE tunnel        (with key)");
        $display("    - Geneve tunnel     (with VNI)");
        $display("    - RoCEv2            (RDMA over Ethernet)");
        $display("    - ARP               (L2 control plane)");
        $display("    - Mixed 6-pkt PCAP  (multi-protocol stream)");
        $display("    - Payload integrity (256-byte increment)");
        $display("================================================================");
        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
        $finish;
    end
endprogram

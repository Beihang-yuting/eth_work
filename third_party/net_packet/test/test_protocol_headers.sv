// test/test_protocol_headers.sv
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

program test_protocol_headers;

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

    initial begin
        $display("=== test_protocol_headers ===");

        // ---- Ethernet ----
        begin
            eth_header eth = new();
            byte unsigned pkd[$];
            byte unsigned raw[$];
            int offset;

            check("eth: proto_type", eth.proto_type == PROTO_ETHERNET);
            check("eth: header_length", eth.get_header_length() == 14);

            eth.dst_mac = 48'h001122334455;
            eth.src_mac = 48'h665544332211;
            eth.ethertype = ETHERTYPE_IPV4;
            eth.calc_fields('{}, PROTO_IPV4);
            eth.pack_header(pkd);

            check("eth: pack size", pkd.size() == 14);
            check("eth: pack dst_mac[0]", pkd[0] == 8'h00);
            check("eth: pack dst_mac[5]", pkd[5] == 8'h55);
            check("eth: pack src_mac[0]", pkd[6] == 8'h66);
            check("eth: pack ethertype", {pkd[12], pkd[13]} == 16'h0800);

            begin
                eth_header eth2 = new();
                offset = 0;
                eth2.unpack_header(pkd, offset);
                check("eth: unpack dst_mac", eth2.dst_mac == 48'h001122334455);
                check("eth: unpack src_mac", eth2.src_mac == 48'h665544332211);
                check("eth: unpack ethertype", eth2.ethertype == ETHERTYPE_IPV4);
                check("eth: unpack offset", offset == 14);
            end

            begin
                protocol_base eth3;
                eth3 = eth.clone();
                check("eth: clone compare", eth.compare(eth3));
            end

            eth.auto_calc = 1;
            eth.calc_fields('{}, PROTO_IPV6);
            check("eth: calc_fields ethertype IPv6", eth.ethertype == ETHERTYPE_IPV6);

            eth.calc_fields('{}, PROTO_ARP);
            check("eth: calc_fields ethertype ARP", eth.ethertype == ETHERTYPE_ARP);

            eth.auto_calc = 0;
            eth.ethertype = 16'hDEAD;
            eth.calc_fields('{}, PROTO_IPV4);
            check("eth: auto_calc=0 preserves ethertype", eth.ethertype == 16'hDEAD);
        end

        // ---- VLAN ----
        begin
            vlan_header vlan = new();
            byte unsigned pkd[$];
            int offset;

            check("vlan: proto_type", vlan.proto_type == PROTO_VLAN);
            check("vlan: header_length", vlan.get_header_length() == 4);

            vlan.pcp     = 3'b101;
            vlan.dei     = 1;
            vlan.vlan_id = 12'h123;
            vlan.ethertype = ETHERTYPE_IPV4;
            vlan.pack_header(pkd);

            check("vlan: pack size", pkd.size() == 4);
            // TCI = {pcp=101, dei=1, vlan_id=0x123} = 0xB123
            check("vlan: pack TCI", {pkd[0], pkd[1]} == 16'hB123);
            check("vlan: pack ethertype", {pkd[2], pkd[3]} == 16'h0800);

            begin
                vlan_header vlan2 = new();
                offset = 0;
                vlan2.unpack_header(pkd, offset);
                check("vlan: unpack pcp", vlan2.pcp == 3'b101);
                check("vlan: unpack dei", vlan2.dei == 1);
                check("vlan: unpack vlan_id", vlan2.vlan_id == 12'h123);
                check("vlan: unpack ethertype", vlan2.ethertype == ETHERTYPE_IPV4);
                check("vlan: unpack offset", offset == 4);
            end

            begin
                protocol_base vlan3;
                vlan3 = vlan.clone();
                check("vlan: clone compare", vlan.compare(vlan3));
            end

            vlan.auto_calc = 1;
            vlan.calc_fields('{}, PROTO_IPV6);
            check("vlan: calc_fields ethertype IPv6", vlan.ethertype == ETHERTYPE_IPV6);
        end

        // ---- IPv4 ----
        begin
            ipv4_header ip = new();
            byte unsigned pkd[$];
            int offset;

            check("ipv4: proto_type", ip.proto_type == PROTO_IPV4);
            check("ipv4: header_length", ip.get_header_length() == 20);

            ip.src_addr = 32'hC0A80001;  // 192.168.0.1
            ip.dst_addr = 32'hC0A80002;  // 192.168.0.2
            ip.ttl      = 64;
            ip.identification = 16'h1234;

            // calc_fields with 10 bytes of payload
            begin
                byte unsigned payload[10];
                byte unsigned pay_q[$];
                foreach (payload[i]) payload[i] = i;
                foreach (payload[i]) pay_q.push_back(payload[i]);
                ip.calc_fields(pay_q, PROTO_TCP);
            end

            check("ipv4: calc protocol", ip.protocol == IP_PROTO_TCP);
            check("ipv4: calc total_length", ip.total_length == 30);

            ip.pack_header(pkd);
            check("ipv4: pack size", pkd.size() == 20);
            check("ipv4: pack version_ihl", pkd[0] == 8'h45);

            // Verify checksum: ones_complement_checksum of pkd header should be 0
            begin
                bit [15:0] verify_cksum;
                verify_cksum = packet_utils::ones_complement_checksum(pkd);
                check("ipv4: checksum verification", verify_cksum == 0);
            end

            begin
                ipv4_header ip2 = new();
                offset = 0;
                ip2.unpack_header(pkd, offset);
                check("ipv4: unpack version", ip2.version == 4);
                check("ipv4: unpack ihl", ip2.ihl == 5);
                check("ipv4: unpack src_addr", ip2.src_addr == 32'hC0A80001);
                check("ipv4: unpack dst_addr", ip2.dst_addr == 32'hC0A80002);
                check("ipv4: unpack ttl", ip2.ttl == 64);
                check("ipv4: unpack offset", offset == 20);
            end

            begin
                protocol_base ip3;
                ip3 = ip.clone();
                check("ipv4: clone compare", ip.compare(ip3));
            end
        end

        // ---- IPv6 ----
        begin
            ipv6_header ip6 = new();
            byte unsigned pkd[$];
            int offset;

            check("ipv6: proto_type", ip6.proto_type == PROTO_IPV6);
            check("ipv6: header_length", ip6.get_header_length() == 40);

            ip6.src_addr = 128'h20010db8000000000000000000000001;
            ip6.dst_addr = 128'h20010db8000000000000000000000002;
            ip6.hop_limit = 64;
            ip6.traffic_class = 8'hAB;
            ip6.flow_label = 20'h12345;

            begin
                byte unsigned pay_q[$];
                for (int i = 0; i < 20; i++) pay_q.push_back(i);
                ip6.calc_fields(pay_q, PROTO_TCP);
            end

            check("ipv6: calc next_header", ip6.next_header == IPV6_NH_TCP);
            check("ipv6: calc payload_length", ip6.payload_length == 20);

            ip6.pack_header(pkd);
            check("ipv6: pack size", pkd.size() == 40);
            // First nibble should be 6 (version)
            check("ipv6: pack version", pkd[0][7:4] == 4'h6);

            begin
                ipv6_header ip6b = new();
                offset = 0;
                ip6b.unpack_header(pkd, offset);
                check("ipv6: unpack version", ip6b.version == 6);
                check("ipv6: unpack tc", ip6b.traffic_class == 8'hAB);
                check("ipv6: unpack flow_label", ip6b.flow_label == 20'h12345);
                check("ipv6: unpack src_addr", ip6b.src_addr == 128'h20010db8000000000000000000000001);
                check("ipv6: unpack dst_addr", ip6b.dst_addr == 128'h20010db8000000000000000000000002);
                check("ipv6: unpack hop_limit", ip6b.hop_limit == 64);
                check("ipv6: unpack offset", offset == 40);
            end

            begin
                protocol_base ip6c;
                ip6c = ip6.clone();
                check("ipv6: clone compare", ip6.compare(ip6c));
            end
        end

        // ---- ARP ----
        begin
            arp_header arp = new();
            byte unsigned pkd[$];
            int offset;

            check("arp: proto_type", arp.proto_type == PROTO_ARP);
            check("arp: header_length", arp.get_header_length() == 28);

            arp.opcode     = 1;
            arp.sender_mac = 48'hAABBCCDDEEFF;
            arp.sender_ip  = 32'hC0A80001;
            arp.target_mac = 48'h000000000000;
            arp.target_ip  = 32'hC0A80002;
            arp.pack_header(pkd);

            check("arp: pack size", pkd.size() == 28);
            check("arp: pack hw_type", {pkd[0], pkd[1]} == 16'h0001);
            check("arp: pack proto_type", {pkd[2], pkd[3]} == 16'h0800);
            check("arp: pack opcode", {pkd[6], pkd[7]} == 16'h0001);

            begin
                arp_header arp2 = new();
                offset = 0;
                arp2.unpack_header(pkd, offset);
                check("arp: unpack hw_type", arp2.hw_type == 1);
                check("arp: unpack opcode", arp2.opcode == 1);
                check("arp: unpack sender_mac", arp2.sender_mac == 48'hAABBCCDDEEFF);
                check("arp: unpack sender_ip", arp2.sender_ip == 32'hC0A80001);
                check("arp: unpack target_ip", arp2.target_ip == 32'hC0A80002);
                check("arp: unpack offset", offset == 28);
            end

            begin
                protocol_base arp3;
                arp3 = arp.clone();
                check("arp: clone compare", arp.compare(arp3));
            end
        end

        // ---- TCP ----
        begin
            tcp_header tcp = new();
            byte unsigned pkd[$];
            int offset;

            check("tcp: proto_type", tcp.proto_type == PROTO_TCP);
            check("tcp: header_length", tcp.get_header_length() == 20);

            tcp.src_port    = 16'h1234;
            tcp.dst_port    = 16'h0050;  // port 80
            tcp.seq_num     = 32'hDEADBEEF;
            tcp.ack_num     = 32'h12345678;
            tcp.window_size = 16'h7FFF;
            tcp.set_syn(1);
            tcp.set_ack(1);

            check("tcp: get_syn", tcp.get_syn() == 1);
            check("tcp: get_ack", tcp.get_ack() == 1);
            check("tcp: get_fin", tcp.get_fin() == 0);

            tcp.calc_fields('{}, PROTO_RAW_PAYLOAD);

            check("tcp: calc data_offset", tcp.data_offset == 5);
            check("tcp: calc checksum", tcp.checksum == 0);

            tcp.pack_header(pkd);
            check("tcp: pack size", pkd.size() == 20);
            check("tcp: pack src_port", {pkd[0], pkd[1]} == 16'h1234);
            check("tcp: pack dst_port", {pkd[2], pkd[3]} == 16'h0050);

            begin
                tcp_header tcp2 = new();
                offset = 0;
                tcp2.unpack_header(pkd, offset);
                check("tcp: unpack src_port", tcp2.src_port == 16'h1234);
                check("tcp: unpack dst_port", tcp2.dst_port == 16'h0050);
                check("tcp: unpack seq_num", tcp2.seq_num == 32'hDEADBEEF);
                check("tcp: unpack ack_num", tcp2.ack_num == 32'h12345678);
                check("tcp: unpack data_offset", tcp2.data_offset == 5);
                check("tcp: unpack syn", tcp2.get_syn() == 1);
                check("tcp: unpack ack", tcp2.get_ack() == 1);
                check("tcp: unpack offset", offset == 20);
            end

            begin
                protocol_base tcp3;
                tcp3 = tcp.clone();
                check("tcp: clone compare", tcp.compare(tcp3));
            end
        end

        // ---- UDP ----
        begin
            udp_header udp = new();
            byte unsigned pkd[$];
            int offset;

            check("udp: proto_type", udp.proto_type == PROTO_UDP);
            check("udp: header_length", udp.get_header_length() == 8);

            udp.src_port = 16'h1234;
            udp.dst_port = 16'h0035;  // port 53 (DNS)

            begin
                byte unsigned pay_q[$];
                for (int i = 0; i < 20; i++) pay_q.push_back(i);
                udp.calc_fields(pay_q, PROTO_RAW_PAYLOAD);
            end

            check("udp: calc length", udp.length == 28);
            check("udp: calc checksum", udp.checksum == 0);

            udp.pack_header(pkd);
            check("udp: pack size", pkd.size() == 8);
            check("udp: pack src_port", {pkd[0], pkd[1]} == 16'h1234);
            check("udp: pack dst_port", {pkd[2], pkd[3]} == 16'h0035);
            check("udp: pack length", {pkd[4], pkd[5]} == 16'h001C);

            begin
                udp_header udp2 = new();
                offset = 0;
                udp2.unpack_header(pkd, offset);
                check("udp: unpack src_port", udp2.src_port == 16'h1234);
                check("udp: unpack dst_port", udp2.dst_port == 16'h0035);
                check("udp: unpack length", udp2.length == 28);
                check("udp: unpack offset", offset == 8);
            end

            begin
                protocol_base udp3;
                udp3 = udp.clone();
                check("udp: clone compare", udp.compare(udp3));
            end
        end

        // ---- ICMP ----
        begin
            icmp_header icmp = new();
            byte unsigned pkd[$];
            int offset;

            check("icmp: proto_type", icmp.proto_type == PROTO_ICMP);
            check("icmp: header_length", icmp.get_header_length() == 8);

            icmp.icmp_type    = 8;  // Echo Request
            icmp.icmp_code    = 0;
            icmp.identifier   = 16'h0001;
            icmp.sequence_num = 16'h0001;

            // calc_fields computes checksum over header + payload
            begin
                byte unsigned pay_q[$];
                for (int i = 0; i < 4; i++) pay_q.push_back(i);
                icmp.calc_fields(pay_q, PROTO_RAW_PAYLOAD);
            end

            check("icmp: checksum nonzero", icmp.checksum != 0);

            // Verify checksum: pack header + payload, checksum should be 0
            begin
                byte unsigned all_data[$];
                bit [15:0] verify_cksum;
                icmp.pack_header(all_data);
                for (int i = 0; i < 4; i++) all_data.push_back(i);
                verify_cksum = packet_utils::ones_complement_checksum(all_data);
                check("icmp: checksum verification", verify_cksum == 0);
            end

            icmp.pack_header(pkd);
            check("icmp: pack size", pkd.size() == 8);
            check("icmp: pack type", pkd[0] == 8);
            check("icmp: pack code", pkd[1] == 0);

            begin
                icmp_header icmp2 = new();
                offset = 0;
                icmp2.unpack_header(pkd, offset);
                check("icmp: unpack type", icmp2.icmp_type == 8);
                check("icmp: unpack code", icmp2.icmp_code == 0);
                check("icmp: unpack identifier", icmp2.identifier == 16'h0001);
                check("icmp: unpack sequence_num", icmp2.sequence_num == 16'h0001);
                check("icmp: unpack offset", offset == 8);
            end

            begin
                protocol_base icmp3;
                icmp3 = icmp.clone();
                check("icmp: clone compare", icmp.compare(icmp3));
            end
        end

        // ---- ICMPv6 ----
        begin
            icmpv6_header icmp6 = new();
            byte unsigned pkd[$];
            int offset;

            check("icmpv6: proto_type", icmp6.proto_type == PROTO_ICMPV6);
            check("icmpv6: header_length", icmp6.get_header_length() == 8);
            check("icmpv6: default type", icmp6.icmp_type == 128);

            icmp6.icmp_code    = 0;
            icmp6.identifier   = 16'h0042;
            icmp6.sequence_num = 16'h0007;

            // calc_fields zeros checksum (needs pseudo-header for real computation)
            icmp6.checksum = 16'hFFFF;
            icmp6.calc_fields('{}, PROTO_RAW_PAYLOAD);
            check("icmpv6: calc zeros checksum", icmp6.checksum == 0);

            icmp6.pack_header(pkd);
            check("icmpv6: pack size", pkd.size() == 8);
            check("icmpv6: pack type", pkd[0] == 128);
            check("icmpv6: pack code", pkd[1] == 0);

            begin
                icmpv6_header icmp6b = new();
                offset = 0;
                icmp6b.unpack_header(pkd, offset);
                check("icmpv6: unpack type", icmp6b.icmp_type == 128);
                check("icmpv6: unpack identifier", icmp6b.identifier == 16'h0042);
                check("icmpv6: unpack sequence_num", icmp6b.sequence_num == 16'h0007);
                check("icmpv6: unpack offset", offset == 8);
            end

            begin
                protocol_base icmp6c;
                icmp6c = icmp6.clone();
                check("icmpv6: clone compare", icmp6.compare(icmp6c));
            end
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end
endprogram

// test/test_protocol_sequences.sv
`include "sequence/tcp_sequences.sv"
`include "sequence/arp_sequence.sv"
`include "sequence/icmp_sequence.sv"
`include "sequence/ptp_sequence.sv"

program test_protocol_sequences;

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
        $display("=== test_protocol_sequences ===");

        // ---- TCP Handshake ----
        begin
            tcp_handshake_seq hs = new();
            packet pkts[$];

            hs.src_ip   = 32'hC0A80001;
            hs.dst_ip   = 32'hC0A80002;
            hs.src_port = 16'd10000;
            hs.dst_port = 16'd443;
            hs.isn_client = 32'd100;
            hs.isn_server = 32'd200;
            hs.gen_packets();
            hs.get_packets(pkts);

            check("hs: 3 packets", pkts.size() == 3);

            // SYN
            begin
                tcp_header tcp;
                $cast(tcp, pkts[0].get_layer(PROTO_TCP));
                check("hs: pkt[0] SYN flag", tcp.flags == 9'h002);
                check("hs: pkt[0] seq", tcp.seq_num == 32'd100);
                check("hs: pkt[0] src_port", tcp.src_port == 16'd10000);
                check("hs: pkt[0] dst_port", tcp.dst_port == 16'd443);
            end

            // SYN-ACK
            begin
                tcp_header tcp;
                $cast(tcp, pkts[1].get_layer(PROTO_TCP));
                check("hs: pkt[1] SYN+ACK flag", tcp.flags == 9'h012);
                check("hs: pkt[1] seq", tcp.seq_num == 32'd200);
                check("hs: pkt[1] ack", tcp.ack_num == 32'd101);
                // Reversed ports
                check("hs: pkt[1] src_port", tcp.src_port == 16'd443);
                check("hs: pkt[1] dst_port", tcp.dst_port == 16'd10000);
            end

            // ACK
            begin
                tcp_header tcp;
                $cast(tcp, pkts[2].get_layer(PROTO_TCP));
                check("hs: pkt[2] ACK flag", tcp.flags == 9'h010);
                check("hs: pkt[2] seq", tcp.seq_num == 32'd101);
                check("hs: pkt[2] ack", tcp.ack_num == 32'd201);
            end

            // Verify IP addresses
            begin
                ipv4_header ip0, ip1;
                $cast(ip0, pkts[0].get_layer(PROTO_IPV4));
                $cast(ip1, pkts[1].get_layer(PROTO_IPV4));
                check("hs: pkt[0] src_ip", ip0.src_addr == 32'hC0A80001);
                check("hs: pkt[1] src_ip reversed", ip1.src_addr == 32'hC0A80002);
            end
        end

        // ---- TCP Full Session ----
        begin
            tcp_full_session_seq sess = new();
            packet pkts[$];

            sess.src_ip          = 32'hAC100001;
            sess.dst_ip          = 32'hAC100002;
            sess.src_port        = 16'd55555;
            sess.dst_port        = 16'd80;
            sess.data_pkt_count  = 3;
            sess.data_pkt_len = 100;
            sess.gen_packets();
            sess.get_packets(pkts);

            // 3 handshake + 3 data + 4 teardown = 10
            check("sess: 10 packets", pkts.size() == 10);

            // First 3: handshake
            begin
                tcp_header tcp;
                $cast(tcp, pkts[0].get_layer(PROTO_TCP));
                check("sess: pkt[0] SYN", tcp.flags == 9'h002);
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkts[1].get_layer(PROTO_TCP));
                check("sess: pkt[1] SYN-ACK", tcp.flags == 9'h012);
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkts[2].get_layer(PROTO_TCP));
                check("sess: pkt[2] ACK", tcp.flags == 9'h010);
            end

            // Data packets (3-5): PSH+ACK
            begin
                tcp_header tcp;
                $cast(tcp, pkts[3].get_layer(PROTO_TCP));
                check("sess: pkt[3] PSH+ACK", tcp.flags == 9'h018);
            end

            // Check data packet size
            check("sess: pkt[3] size", pkts[3].raw_data.size() == 100);

            // Last 4: teardown
            begin
                tcp_header tcp;
                $cast(tcp, pkts[6].get_layer(PROTO_TCP));
                check("sess: pkt[6] FIN+ACK", tcp.flags == 9'h011);
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkts[9].get_layer(PROTO_TCP));
                check("sess: pkt[9] final ACK", tcp.flags == 9'h010);
            end
        end

        // ---- ARP Sequence ----
        begin
            arp_seq arp = new();
            packet pkts[$];

            arp.src_mac = 48'h001122334455;
            arp.dst_mac = 48'hAABBCCDDEEFF;
            arp.src_ip  = 32'hC0A80001;
            arp.dst_ip  = 32'hC0A80002;
            arp.gen_packets();
            arp.get_packets(pkts);

            check("arp: 2 packets", pkts.size() == 2);

            // ARP Request
            begin
                eth_header eth;
                arp_header arph;
                $cast(eth,  pkts[0].get_layer(PROTO_ETHERNET));
                $cast(arph, pkts[0].get_layer(PROTO_ARP));
                check("arp: pkt[0] opcode==1 (Request)",  arph.opcode == 16'd1);
                check("arp: pkt[0] dst_mac broadcast",    eth.dst_mac == 48'hFFFFFFFFFFFF);
                check("arp: pkt[0] sender_ip",            arph.sender_ip == 32'hC0A80001);
                check("arp: pkt[0] target_ip",            arph.target_ip == 32'hC0A80002);
                check("arp: pkt[0] target_mac zeroed",    arph.target_mac == 48'h000000000000);
            end

            // ARP Reply
            begin
                eth_header eth;
                arp_header arph;
                $cast(eth,  pkts[1].get_layer(PROTO_ETHERNET));
                $cast(arph, pkts[1].get_layer(PROTO_ARP));
                check("arp: pkt[1] opcode==2 (Reply)",    arph.opcode == 16'd2);
                check("arp: pkt[1] sender_mac reversed",  arph.sender_mac == 48'hAABBCCDDEEFF);
                check("arp: pkt[1] target_mac reversed",  arph.target_mac == 48'h001122334455);
                check("arp: pkt[1] sender_ip reversed",   arph.sender_ip == 32'hC0A80002);
                check("arp: pkt[1] target_ip reversed",   arph.target_ip == 32'hC0A80001);
            end
        end

        // ---- ICMP Ping Sequence ----
        begin
            icmp_ping_seq ping = new();
            packet pkts[$];

            ping.src_mac         = 48'h001122334455;
            ping.dst_mac         = 48'hAABBCCDDEEFF;
            ping.src_ip          = 32'hC0A80001;
            ping.dst_ip          = 32'hC0A80002;
            ping.identifier      = 16'h1234;
            ping.sequence_number = 16'h0001;
            ping.ping_length     = 64;
            ping.gen_packets();
            ping.get_packets(pkts);

            check("icmp: 2 packets", pkts.size() == 2);

            // Echo Request
            begin
                ipv4_header ip;
                icmp_header icmph;
                $cast(ip,    pkts[0].get_layer(PROTO_IPV4));
                $cast(icmph, pkts[0].get_layer(PROTO_ICMP));
                check("icmp: pkt[0] type==8 (Echo Request)", icmph.icmp_type == 8'd8);
                check("icmp: pkt[0] code==0",                icmph.icmp_code == 8'd0);
                check("icmp: pkt[0] identifier",             icmph.identifier == 16'h1234);
                check("icmp: pkt[0] sequence_num",           icmph.sequence_num == 16'h0001);
                check("icmp: pkt[0] src_ip",                 ip.src_addr == 32'hC0A80001);
                check("icmp: pkt[0] dst_ip",                 ip.dst_addr == 32'hC0A80002);
            end

            // Echo Reply
            begin
                ipv4_header ip;
                icmp_header icmph;
                $cast(ip,    pkts[1].get_layer(PROTO_IPV4));
                $cast(icmph, pkts[1].get_layer(PROTO_ICMP));
                check("icmp: pkt[1] type==0 (Echo Reply)",   icmph.icmp_type == 8'd0);
                check("icmp: pkt[1] code==0",                icmph.icmp_code == 8'd0);
                check("icmp: pkt[1] src_ip reversed",        ip.src_addr == 32'hC0A80002);
                check("icmp: pkt[1] dst_ip reversed",        ip.dst_addr == 32'hC0A80001);
            end
        end

        // ---- PTP Sync Sequence ----
        begin
            ptp_sync_seq ptp = new();
            packet pkts[$];

            ptp.master_mac     = 48'h001122334455;
            ptp.slave_mac      = 48'hAABBCCDDEEFF;
            ptp.clock_identity = 64'h0011223344556677;
            ptp.port_number    = 16'd1;
            ptp.sequence_id    = 16'd0;
            ptp.domain         = 8'd0;
            ptp.gen_packets();
            ptp.get_packets(pkts);

            check("ptp: 4 packets", pkts.size() == 4);

            // Sync
            begin
                eth_header eth;
                ptp_header ptph;
                $cast(eth,  pkts[0].get_layer(PROTO_ETHERNET));
                $cast(ptph, pkts[0].get_layer(PROTO_PTP));
                check("ptp: pkt[0] message_type==0 (Sync)",   ptph.message_type == 4'd0);
                check("ptp: pkt[0] src_mac master",           eth.src_mac == 48'h001122334455);
                check("ptp: pkt[0] clock_identity",           ptph.clock_identity == 64'h0011223344556677);
            end

            // Follow_Up
            begin
                ptp_header ptph;
                $cast(ptph, pkts[1].get_layer(PROTO_PTP));
                check("ptp: pkt[1] message_type==8 (Follow_Up)", ptph.message_type == 4'd8);
            end

            // Delay_Req (slave -> master)
            begin
                eth_header eth;
                ptp_header ptph;
                $cast(eth,  pkts[2].get_layer(PROTO_ETHERNET));
                $cast(ptph, pkts[2].get_layer(PROTO_PTP));
                check("ptp: pkt[2] message_type==1 (Delay_Req)", ptph.message_type == 4'd1);
                check("ptp: pkt[2] src_mac slave",               eth.src_mac == 48'hAABBCCDDEEFF);
                check("ptp: pkt[2] dst_mac master",              eth.dst_mac == 48'h001122334455);
            end

            // Delay_Resp
            begin
                eth_header eth;
                ptp_header ptph;
                $cast(eth,  pkts[3].get_layer(PROTO_ETHERNET));
                $cast(ptph, pkts[3].get_layer(PROTO_PTP));
                check("ptp: pkt[3] message_type==9 (Delay_Resp)", ptph.message_type == 4'd9);
                check("ptp: pkt[3] src_mac master",               eth.src_mac == 48'h001122334455);
            end
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

// test/test_pcap.sv
`include "pcap/pcap_writer.sv"
`include "pcap/pcap_reader.sv"

program test_pcap;

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
        $display("=== test_pcap ===");

        // ---- Write and read back single packet ----
        begin
            pcap_writer pw = new();
            pcap_reader pr = new();
            packet pkt_orig = new();
            packet pkts_read[$];

            // Build a packet
            pkt_orig.build_from_template(ETH_IPV4_TCP);
            begin
                ipv4_header ip;
                $cast(ip, pkt_orig.get_layer(PROTO_IPV4));
                ip.src_addr = 32'hC0A80001;
                ip.dst_addr = 32'hC0A80002;
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkt_orig.get_layer(PROTO_TCP));
                tcp.src_port = 16'd12345;
                tcp.dst_port = 16'd80;
            end
            pkt_orig.pkt_len = 100;
            pkt_orig.payload_mode = PAYLOAD_INCREMENT;
            pkt_orig.do_pack();

            // Write to pcap
            pw.open("test_single.pcap");
            pw.write_packet(pkt_orig, 1000, 500);
            pw.close();

            // Read back
            pr.open("test_single.pcap");
            pr.read_all(pkts_read);
            pr.close();

            check("pcap_single: read 1 packet", pkts_read.size() == 1);
            check("pcap_single: layer count", pkts_read[0].layer_stack.size() == 3);
            check("pcap_single: raw_data size", pkts_read[0].raw_data.size() == 100);

            // Verify parsed fields
            begin
                ipv4_header ip;
                $cast(ip, pkts_read[0].get_layer(PROTO_IPV4));
                check("pcap_single: src_addr", ip.src_addr == 32'hC0A80001);
                check("pcap_single: dst_addr", ip.dst_addr == 32'hC0A80002);
            end
            begin
                tcp_header tcp;
                $cast(tcp, pkts_read[0].get_layer(PROTO_TCP));
                check("pcap_single: src_port", tcp.src_port == 16'd12345);
                check("pcap_single: dst_port", tcp.dst_port == 16'd80);
            end
        end

        // ---- Write and read back multiple packets ----
        begin
            pcap_writer pw = new();
            pcap_reader pr = new();
            packet pkts[$];
            packet pkts_read[$];

            for (int i = 0; i < 3; i++) begin
                packet p = new();
                p.build_from_template(ETH_IPV4_UDP);
                begin
                    udp_header u;
                    $cast(u, p.get_layer(PROTO_UDP));
                    u.dst_port = 5000 + i;
                end
                p.pkt_len = 64 + i * 10;
                p.do_pack();
                pkts.push_back(p);
            end

            pw.open("test_multi.pcap");
            pw.write_packets(pkts);
            pw.close();

            pr.open("test_multi.pcap");
            pr.read_all(pkts_read);
            pr.close();

            check("pcap_multi: read 3 packets", pkts_read.size() == 3);
            check("pcap_multi: pkt[0] size", pkts_read[0].raw_data.size() == 64);
            check("pcap_multi: pkt[1] size", pkts_read[1].raw_data.size() == 74);
            check("pcap_multi: pkt[2] size", pkts_read[2].raw_data.size() == 84);

            begin
                udp_header u;
                $cast(u, pkts_read[1].get_layer(PROTO_UDP));
                check("pcap_multi: pkt[1] dst_port", u.dst_port == 16'd5001);
            end
        end

        // ---- Reader: open nonexistent file ----
        begin
            pcap_reader pr = new();
            pr.open("nonexistent.pcap");
            check("pcap_nofile: eof", pr.eof() == 1);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

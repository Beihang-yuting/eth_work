// test/test_ip_fragment.sv
`include "core/ip_fragment.sv"

program test_ip_fragment;

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
        $display("=== test_ip_fragment ===");

        // ---- Fragment a large packet ----
        begin
            packet pkt = new();
            packet fragments[$];

            pkt.build_from_template(ETH_IPV4_TCP);
            pkt.pkt_len = 300;   // 14 ETH + 20 IPv4 + 20 TCP + 246 payload = 300
            pkt.payload_mode = PAYLOAD_INCREMENT;
            pkt.do_pack();

            // Fragment with MTU=100 (IP level: 100 bytes = 20 hdr + 80 payload)
            // IP payload = 20 TCP + 246 data = 266 bytes
            // max_frag_payload = (100-20)/8 * 8 = 80 bytes (must be multiple of 8)
            // Fragments: 80 + 80 + 80 + 26 = 266 bytes, 4 fragments
            ip_fragment::fragment(pkt, 100, fragments);

            check("frag: fragment count", fragments.size() == 4);

            // Check first fragment: MF=1, offset=0
            begin
                ipv4_header ip;
                $cast(ip, fragments[0].get_layer(PROTO_IPV4));
                check("frag: frag[0] MF=1", ip.flags[0] == 1);
                check("frag: frag[0] offset=0", ip.fragment_offset == 0);
                check("frag: frag[0] total_length", ip.total_length == 100);
            end

            // Check middle fragment: MF=1, offset=10 (80/8)
            begin
                ipv4_header ip;
                $cast(ip, fragments[1].get_layer(PROTO_IPV4));
                check("frag: frag[1] MF=1", ip.flags[0] == 1);
                check("frag: frag[1] offset=10", ip.fragment_offset == 10);
            end

            // Check last fragment: MF=0
            begin
                ipv4_header ip;
                int last;
                last = fragments.size() - 1;
                $cast(ip, fragments[last].get_layer(PROTO_IPV4));
                check("frag: frag[last] MF=0", ip.flags[0] == 0);
            end
        end

        // ---- No fragmentation needed ----
        begin
            packet pkt = new();
            packet fragments[$];

            pkt.build_from_template(ETH_IPV4_TCP);
            pkt.pkt_len = 80;
            pkt.do_pack();

            ip_fragment::fragment(pkt, 1500, fragments);
            check("nofrag: 1 fragment", fragments.size() == 1);
        end

        // ---- Reassemble fragments ----
        begin
            packet pkt_orig = new();
            packet fragments[$];
            packet reassembled;

            pkt_orig.build_from_template(ETH_IPV4_TCP);
            pkt_orig.pkt_len = 300;
            pkt_orig.payload_mode = PAYLOAD_INCREMENT;
            pkt_orig.do_pack();

            ip_fragment::fragment(pkt_orig, 100, fragments);

            reassembled = ip_fragment::reassemble(fragments);
            check("reassemble: not null", reassembled != null);

            // Check reassembled IP header
            begin
                ipv4_header ip;
                $cast(ip, reassembled.get_layer(PROTO_IPV4));
                check("reassemble: MF=0", ip.flags[0] == 0);
                check("reassemble: offset=0", ip.fragment_offset == 0);
            end

            // Check total reassembled data size
            // Original: 14 ETH + 20 IPv4 + (20 TCP + 246 payload) = 300
            // Reassembled: 14 ETH + 20 IPv4 + 266 payload (TCP header included as payload) = 300
            check("reassemble: raw_data size", reassembled.raw_data.size() == 300);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

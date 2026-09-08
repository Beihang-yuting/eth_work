// test/test_parser.sv
`include "parser/protocol_parser.sv"
`include "parser/packet_comparator.sv"

program test_parser;

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
        $display("=== test_parser ===");

        // ---- Parser: parse raw bytes ----
        begin
            protocol_parser parser = new();
            packet pkt_orig = new();
            packet pkt_parsed;

            // Build and pack a known packet
            pkt_orig.build_from_template(ETH_IPV4_TCP);
            pkt_orig.pkt_len = 100;
            pkt_orig.do_pack();

            // Parse the raw bytes
            pkt_parsed = parser.parse(pkt_orig.raw_data);
            check("parser: parsed layer count", pkt_parsed.layer_stack.size() == 3);
            check("parser: parsed ETH", pkt_parsed.layer_stack[0].proto_type == PROTO_ETHERNET);
            check("parser: parsed IPv4", pkt_parsed.layer_stack[1].proto_type == PROTO_IPV4);
            check("parser: parsed TCP", pkt_parsed.layer_stack[2].proto_type == PROTO_TCP);
        end

        // ---- Parser: validate valid packet ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            pkt.build_from_template(ETH_IPV4_UDP);
            result = parser.validate(pkt);
            check("validate: valid packet", result.valid == 1);
            check("validate: no errors", result.errors.size() == 0);
            check("validate: chain size", result.proto_chain.size() == 3);
        end

        // ---- Parser: validate invalid packet ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            // Force invalid chain
            pkt.force_mode = 1;
            pkt.add_layer(eth_header::create());
            pkt.add_layer(tcp_header::create());  // Invalid: ETH->TCP not allowed
            result = parser.validate(pkt);
            check("validate: invalid transition detected", result.valid == 0);
            check("validate: has error", result.errors.size() > 0);
        end

        // ---- Parser: validate empty packet ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            result = parser.validate(pkt);
            check("validate: empty invalid", result.valid == 0);
        end

        // ---- Comparator: identical packets ----
        begin
            packet_comparator comp = new();
            packet pkt_a = new();
            packet pkt_b = new();
            diff_entry_t diffs[$];

            pkt_a.build_from_template(ETH_IPV4_TCP);
            pkt_a.pkt_len = 100;
            pkt_a.do_pack();

            pkt_b.build_from_template(ETH_IPV4_TCP);
            pkt_b.pkt_len = 100;
            pkt_b.do_pack();

            // Since both use same template with same defaults, layers should match
            // But raw_data may differ (random payload). Compare layers only.
            // Actually, let's unpack pkt_a's data into pkt_b for exact match
            pkt_b.unpack(pkt_a.raw_data);

            comp.compare(pkt_a, pkt_b, diffs);
            check("comparator: identical no diffs", diffs.size() == 0);
        end

        // ---- Comparator: different packets ----
        begin
            packet_comparator comp = new();
            packet pkt_a = new();
            packet pkt_b = new();
            diff_entry_t diffs[$];

            pkt_a.build_from_template(ETH_IPV4_TCP);
            pkt_b.build_from_template(ETH_IPV4_TCP);

            // Modify one field
            begin
                ipv4_header ip;
                $cast(ip, pkt_b.get_layer(PROTO_IPV4));
                ip.ttl = 8'd1;  // Different TTL
            end

            comp.compare(pkt_a, pkt_b, diffs);
            check("comparator: has diffs", diffs.size() > 0);

            // Print diffs
            $display("%s", comp.diff_to_string(diffs));
        end

        // ---- Comparator: different layer count ----
        begin
            packet_comparator comp = new();
            packet pkt_a = new();
            packet pkt_b = new();
            diff_entry_t diffs[$];

            pkt_a.build_from_template(ETH_IPV4_TCP);
            pkt_b.build_from_template(ETH_IPV4_UDP);

            comp.compare(pkt_a, pkt_b, diffs);
            check("comparator: layer diff detected", diffs.size() > 0);
        end

        // ---- Verify: valid packet with verify_en ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            parser.verify_en = 1;  // Enable field verification

            pkt.randomize() with {
                pkt_kind == ETH_IPV4_TCP;
                pkt_len == 100;
            };

            result = parser.validate(pkt);
            check("verify_en: valid packet passes", result.valid == 1);
            $display("  verify result: %s", parser.result_to_string(result));
        end

        // ---- Verify: detect bad IPv4 version ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            parser.verify_en = 1;

            pkt.randomize() with {
                pkt_kind == ETH_IPV4_TCP;
                pkt_len == 100;
            };

            // Corrupt IPv4 version
            begin
                ipv4_header ip4;
                ip4 = pkt.get_ipv4(0);
                ip4.version = 5;  // Wrong version
            end

            result = parser.validate(pkt);
            check("verify_en: bad IPv4 version detected", result.valid == 0);
            $display("  verify result: %s", parser.result_to_string(result));
        end

        // ---- Verify: detect bad TCP flags ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            parser.verify_en = 1;

            pkt.randomize() with {
                pkt_kind == ETH_IPV4_TCP;
                pkt_len == 100;
            };

            // Set SYN+FIN (unusual)
            begin
                tcp_header tcp;
                tcp = pkt.get_tcp(0);
                tcp.flags = 9'b000000011;  // SYN+FIN
            end

            result = parser.validate(pkt);
            check("verify_en: SYN+FIN warning", result.warnings.size() > 0);
            $display("  verify result: %s", parser.result_to_string(result));
        end

        // ---- Verify: detect bad IPv4 checksum ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            parser.verify_en = 1;

            pkt.randomize() with {
                pkt_kind == ETH_IPV4_UDP;
                pkt_len == 80;
            };

            // Corrupt IPv4 checksum
            begin
                ipv4_header ip4;
                ip4 = pkt.get_ipv4(0);
                ip4.header_checksum = 16'hDEAD;
            end

            result = parser.validate(pkt);
            check("verify_en: bad IPv4 checksum detected", result.valid == 0);
            $display("  verify result: %s", parser.result_to_string(result));
        end

        // ---- Verify: tunnel packet full verification ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            parser.verify_en = 1;

            pkt.randomize() with {
                pkt_kind == ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP;
                pkt_len == 200;
            };

            result = parser.validate(pkt);
            check("verify_en: tunnel packet valid", result.valid == 1);
            $display("  verify result: %s", parser.result_to_string(result));
        end

        // ---- Verify: parse and verify round-trip ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            packet parsed;
            parse_result_t result;

            parser.verify_en = 1;

            pkt.randomize() with {
                pkt_kind == ETH_IPV4_TCP;
                pkt_len == 120;
            };

            // Parse from raw bytes and verify
            parsed = parser.parse(pkt.raw_data);
            result = parser.validate(parsed);
            check("verify_en: parse+verify round-trip", result.valid == 1);

            // Compare original and parsed
            begin
                packet_comparator comp = new();
                bit pass;
                pass = comp.compare_and_print(pkt, parsed);
                check("verify_en: round-trip compare", pass == 1);
            end
        end

        // ---- Verify: result_to_string output ----
        begin
            protocol_parser parser = new();
            packet pkt = new();
            parse_result_t result;

            parser.verify_en = 1;

            pkt.randomize() with {
                pkt_kind == ETH_IPV6_UDP;
                pkt_len == 100;
            };

            result = parser.validate(pkt);
            check("verify_en: IPv6 packet valid", result.valid == 1);
            $display("%s", parser.result_to_string(result));
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

// test/test_mass_verify.sv
// Mass packet generation test: generates packets for ALL templates,
// writes to PCAP for external tool (tshark/scapy) verification.
// Each template is randomized multiple times for coverage.

`include "pcap/pcap_writer.sv"
`include "pcap/pcap_reader.sv"
`include "parser/protocol_parser.sv"

program test_mass_verify;

    int pass_count = 0;
    int fail_count = 0;
    int total_pkts = 0;

    task automatic check(string name, bit condition);
        if (condition) begin
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask

    initial begin
        pcap_writer pw;
        protocol_parser parser;
        packet pkt;
        int pkt_id;

        // Number of random iterations per template
        int REPEAT = 5;

        parser = new();
        parser.verify_en = 1;

        $display("=== test_mass_verify: generating packets for ALL templates ===");

        // =====================================================================
        // Phase 1: Write all packets to PCAP
        // =====================================================================
        pw = new();
        pw.open("mass_verify.pcap");
        pkt_id = 0;

        begin
            packet_template_e tmpl;
            tmpl = tmpl.first();
            forever begin
                for (int r = 0; r < REPEAT; r++) begin
                    pkt = new();
                    if (!pkt.randomize() with {
                        pkt_kind == tmpl;
                        pkt_len inside {[64:512]};
                    }) begin
                        $display("[WARN] randomize failed for %s iter %0d", tmpl.name(), r);
                        continue;
                    end

                    // Verify with our own parser first
                    begin
                        parse_result_t result;
                        result = parser.validate(pkt);

                        // Check our parser says valid (no hard errors)
                        // Some warnings are expected (e.g., UDP checksum=0)
                        check($sformatf("self_verify[%0d] %s #%0d", pkt_id, tmpl.name(), r),
                              result.valid);

                        if (!result.valid) begin
                            $display("  Template: %s  iter: %0d", tmpl.name(), r);
                            foreach (result.errors[e])
                                $display("    ERROR: %s", result.errors[e]);
                        end
                    end

                    // Write to PCAP for external verification
                    pw.write_packet(pkt, pkt_id, 0);
                    pkt_id++;
                    total_pkts++;
                end

                if (tmpl == tmpl.last()) break;
                tmpl = tmpl.next();
            end
        end

        pw.close();
        $display("");
        $display("=== Phase 1 complete: %0d packets written to mass_verify.pcap ===", total_pkts);

        // =====================================================================
        // Phase 2: Read back from PCAP + roundtrip verify
        // =====================================================================
        begin
            pcap_reader pr = new();
            packet pkts_read[$];
            int roundtrip_pass = 0;
            int roundtrip_fail = 0;

            pr.open("mass_verify.pcap");
            pr.read_all(pkts_read);
            pr.close();

            check("pcap_readback: count matches", pkts_read.size() == total_pkts);
            $display("  Read back %0d / %0d packets from PCAP", pkts_read.size(), total_pkts);

            // Validate each read-back packet
            foreach (pkts_read[i]) begin
                parse_result_t result;
                result = parser.validate(pkts_read[i]);

                if (result.valid) begin
                    roundtrip_pass++;
                end else begin
                    roundtrip_fail++;
                    if (roundtrip_fail <= 20) begin // limit output
                        $display("  [FAIL] roundtrip pkt[%0d]:", i);
                        foreach (result.errors[e])
                            $display("    ERROR: %s", result.errors[e]);
                    end
                end
            end

            $display("  Roundtrip verify: %0d pass, %0d fail (of %0d)",
                     roundtrip_pass, roundtrip_fail, pkts_read.size());

            // Count roundtrip results
            pass_count += roundtrip_pass;
            fail_count += roundtrip_fail;
        end

        // =====================================================================
        // Phase 3: Category-based random (extra coverage)
        // =====================================================================
        begin
            pcap_writer pw2 = new();
            int cat_pkt_count = 0;
            int CAT_REPEAT = 10;

            pw2.open("mass_verify_cat.pcap");

            begin
                pkt_category_e cat;
                cat = cat.first();
                forever begin
                    for (int r = 0; r < CAT_REPEAT; r++) begin
                        pkt = new();
                        if (!pkt.randomize() with {
                            pkt_rand_kind == cat;
                            pkt_len inside {[64:1518]};
                        }) begin
                            continue;
                        end

                        begin
                            parse_result_t result;
                            result = parser.validate(pkt);
                            check($sformatf("cat_verify %s #%0d", cat.name(), r), result.valid);
                            if (!result.valid) begin
                                $display("  Cat: %s  iter: %0d  tmpl: %s", cat.name(), r, pkt.pkt_kind.name());
                                foreach (result.errors[e])
                                    $display("    ERROR: %s", result.errors[e]);
                            end
                        end

                        pw2.write_packet(pkt, cat_pkt_count, 0);
                        cat_pkt_count++;
                    end

                    if (cat == cat.last()) break;
                    cat = cat.next();
                end
            end

            pw2.close();
            $display("");
            $display("=== Phase 3 complete: %0d category-random packets written to mass_verify_cat.pcap ===",
                     cat_pkt_count);
            total_pkts += cat_pkt_count;
        end

        // =====================================================================
        // Phase 4: VLAN stacking tests (1-4 VLANs)
        // =====================================================================
        begin
            int vlan_pkt_count = 0;
            for (int v = 1; v <= 4; v++) begin
                for (int r = 0; r < 3; r++) begin
                    pkt = new();
                    if (!pkt.randomize() with {
                        pkt_kind == ETH_IPV4_TCP;
                        outer_vlan_num == v;
                        pkt_len inside {[100:256]};
                    }) begin
                        continue;
                    end

                    begin
                        parse_result_t result;
                        result = parser.validate(pkt);
                        check($sformatf("vlan_%0d_stack #%0d", v, r), result.valid);
                        if (!result.valid) begin
                            foreach (result.errors[e])
                                $display("    ERROR: %s", result.errors[e]);
                        end
                    end
                    vlan_pkt_count++;
                end
            end
            $display("");
            $display("=== Phase 4 complete: %0d VLAN stacking packets verified ===", vlan_pkt_count);
        end

        // =====================================================================
        // Phase 5: Error/abnormal packets via set_chain (should NOT pass verify)
        // =====================================================================
        begin
            string error_chains[] = '{
                "ETH_TCP",                    // skip IP layer
                "ETH_ETH_IPV4_TCP",           // double Ethernet
                "ETH_IPV4_IPV4_TCP",          // double IPv4
                "ETH_GRE_IPV4_TCP",           // GRE without outer IP
                "ETH_IPV4_VXLAN_TCP"          // VXLAN without UDP
            };
            int error_pass = 0;

            foreach (error_chains[i]) begin
                pkt = new();
                pkt.set_chain(error_chains[i]);
                if (!pkt.randomize() with { pkt_len inside {[80:200]}; }) continue;

                begin
                    parse_result_t result;
                    result = parser.validate(pkt);
                    // These SHOULD fail validation (invalid transitions)
                    if (!result.valid) begin
                        error_pass++;
                        pass_count++;
                    end else begin
                        $display("[FAIL] error_pkt '%s' should have failed validation", error_chains[i]);
                        fail_count++;
                    end
                end
                pkt.clear_chain();
            end
            $display("");
            $display("=== Phase 5 complete: %0d/%0d error packets correctly rejected ===",
                     error_pass, error_chains.size());
        end

        $display("");
        $display("=== Total packets generated: %0d ===", total_pkts);
        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

// test/test_phase2c_packet.sv
`include "core/packet.sv"

program test_phase2c_packet;

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
        $display("=== test_phase2c_packet ===");

        // ---- MPLS template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_MPLS_IPV4_TCP);
            check("mpls_tmpl: layer count", pkt.layer_stack.size() == 4);
            check("mpls_tmpl: layer[1] MPLS", pkt.layer_stack[1].proto_type == PROTO_MPLS);

            begin
                mpls_header m;
                $cast(m, pkt.get_layer(PROTO_MPLS));
                m.label = 20'd1000;
                m.ttl   = 8'd128;
            end

            pkt.pkt_len = 100;
            pkt.do_pack();
            check("mpls_tmpl: raw_data size", pkt.raw_data.size() == 100);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("mpls_tmpl: unpack layer count", pkt2.layer_stack.size() == 4);
                check("mpls_tmpl: unpack MPLS", pkt2.layer_stack[1].proto_type == PROTO_MPLS);
                begin
                    mpls_header m2;
                    $cast(m2, pkt2.get_layer(PROTO_MPLS));
                    check("mpls_tmpl: unpack label", m2.label == 20'd1000);
                end
            end
        end

        // ---- L2 PTP template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_PTP_L2);
            check("ptp_l2: layer count", pkt.layer_stack.size() == 2);
            check("ptp_l2: layer[0] ETH", pkt.layer_stack[0].proto_type == PROTO_ETHERNET);
            check("ptp_l2: layer[1] PTP", pkt.layer_stack[1].proto_type == PROTO_PTP);

            begin
                ptp_header p;
                $cast(p, pkt.get_layer(PROTO_PTP));
                p.message_type = 4'd0;  // Sync
                p.sequence_id  = 16'd42;
            end

            pkt.pkt_len = 80;
            pkt.do_pack();
            check("ptp_l2: raw_data size", pkt.raw_data.size() == 80);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("ptp_l2: unpack layer count", pkt2.layer_stack.size() == 2);
                begin
                    ptp_header p2;
                    $cast(p2, pkt2.get_layer(PROTO_PTP));
                    check("ptp_l2: unpack sequence_id", p2.sequence_id == 16'd42);
                end
            end
        end

        // ---- Free-form: IPv6 with extension headers ----
        begin
            packet pkt = new();
            pkt.add_layer(eth_header::create());
            pkt.add_layer(ipv6_header::create());

            begin
                ipv6_hbh_header hbh = new();
                pkt.add_layer(hbh);
            end

            pkt.add_layer(tcp_header::create());
            check("ipv6_ext: layer count", pkt.layer_stack.size() == 4);
            check("ipv6_ext: layer[2] HBH", pkt.layer_stack[2].proto_type == PROTO_IPV6_HBH);

            pkt.pkt_len = 120;
            pkt.do_pack();
            check("ipv6_ext: raw_data size", pkt.raw_data.size() == 120);
        end

        // ---- Free-form: ESP ----
        begin
            packet pkt = new();
            pkt.add_layer(eth_header::create());
            pkt.add_layer(ipv4_header::create());

            begin
                esp_header esp = new();
                esp.spi = 32'h00001234;
                esp.sequence_number = 32'd1;
                pkt.add_layer(esp);
            end

            check("esp: layer count", pkt.layer_stack.size() == 3);
            check("esp: layer[2] ESP", pkt.layer_stack[2].proto_type == PROTO_ESP);

            pkt.pkt_len = 100;
            pkt.do_pack();
            check("esp: raw_data size", pkt.raw_data.size() == 100);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

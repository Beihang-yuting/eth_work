// test/test_tunnel_packet.sv
`include "core/packet.sv"

program test_tunnel_packet;

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
        $display("=== test_tunnel_packet ===");

        // ---- VXLAN template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
            check("vxlan_tmpl: layer count", pkt.layer_stack.size() == 7);
            check("vxlan_tmpl: layer[0] ETH", pkt.layer_stack[0].proto_type == PROTO_ETHERNET);
            check("vxlan_tmpl: layer[1] IPv4", pkt.layer_stack[1].proto_type == PROTO_IPV4);
            check("vxlan_tmpl: layer[2] UDP", pkt.layer_stack[2].proto_type == PROTO_UDP);
            check("vxlan_tmpl: layer[3] VXLAN", pkt.layer_stack[3].proto_type == PROTO_VXLAN);
            check("vxlan_tmpl: layer[4] ETH", pkt.layer_stack[4].proto_type == PROTO_ETHERNET);
            check("vxlan_tmpl: layer[5] IPv4", pkt.layer_stack[5].proto_type == PROTO_IPV4);
            check("vxlan_tmpl: layer[6] TCP", pkt.layer_stack[6].proto_type == PROTO_TCP);

            // Set VNI
            begin
                vxlan_header vx;
                $cast(vx, pkt.get_layer(PROTO_VXLAN));
                vx.vni = 24'd1000;
            end

            // Pack
            pkt.pkt_len = 128;
            pkt.do_pack();
            check("vxlan_tmpl: raw_data not empty", pkt.raw_data.size() > 0);
            check("vxlan_tmpl: raw_data size", pkt.raw_data.size() == 128);

            // Unpack
            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("vxlan_tmpl: unpack layer count", pkt2.layer_stack.size() == 7);
                check("vxlan_tmpl: unpack layer[3] VXLAN", pkt2.layer_stack[3].proto_type == PROTO_VXLAN);
                begin
                    vxlan_header vx2;
                    $cast(vx2, pkt2.get_layer(PROTO_VXLAN));
                    check("vxlan_tmpl: unpack VNI", vx2.vni == 24'd1000);
                end
            end
        end

        // ---- GRE template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_GRE_IPV4_TCP);
            check("gre_tmpl: layer count", pkt.layer_stack.size() == 5);
            check("gre_tmpl: layer[2] GRE", pkt.layer_stack[2].proto_type == PROTO_GRE);

            pkt.pkt_len = 100;
            pkt.do_pack();
            check("gre_tmpl: raw_data size", pkt.raw_data.size() == 100);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("gre_tmpl: unpack layer count", pkt2.layer_stack.size() == 5);
                check("gre_tmpl: unpack layer[2] GRE", pkt2.layer_stack[2].proto_type == PROTO_GRE);
            end
        end

        // ---- Geneve template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP);
            check("geneve_tmpl: layer count", pkt.layer_stack.size() == 7);
            check("geneve_tmpl: layer[3] Geneve", pkt.layer_stack[3].proto_type == PROTO_GENEVE);

            pkt.pkt_len = 128;
            pkt.do_pack();
            check("geneve_tmpl: raw_data size", pkt.raw_data.size() == 128);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("geneve_tmpl: unpack layer count", pkt2.layer_stack.size() == 7);
                check("geneve_tmpl: unpack layer[3] Geneve", pkt2.layer_stack[3].proto_type == PROTO_GENEVE);
            end
        end

        // ---- ERSPAN template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP);
            check("erspan_tmpl: layer count", pkt.layer_stack.size() == 7);
            check("erspan_tmpl: layer[2] GRE", pkt.layer_stack[2].proto_type == PROTO_GRE);
            check("erspan_tmpl: layer[3] ERSPAN_II", pkt.layer_stack[3].proto_type == PROTO_ERSPAN_II);

            begin
                erspan_ii_header es;
                $cast(es, pkt.get_layer(PROTO_ERSPAN_II));
                es.session_id = 10'd42;
            end

            pkt.pkt_len = 128;
            pkt.do_pack();
            check("erspan_tmpl: raw_data size", pkt.raw_data.size() == 128);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("erspan_tmpl: unpack layer count", pkt2.layer_stack.size() == 7);
                begin
                    erspan_ii_header es2;
                    $cast(es2, pkt2.get_layer(PROTO_ERSPAN_II));
                    check("erspan_tmpl: unpack session_id", es2.session_id == 10'd42);
                end
            end
        end

        // ---- GTP-U template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_GTP_U_IPV4_TCP);
            check("gtp_tmpl: layer count", pkt.layer_stack.size() == 6);
            check("gtp_tmpl: layer[3] GTP_U", pkt.layer_stack[3].proto_type == PROTO_GTP_U);

            begin
                gtp_u_header gtp;
                $cast(gtp, pkt.get_layer(PROTO_GTP_U));
                gtp.teid = 32'h0000ABCD;
            end

            pkt.pkt_len = 120;
            pkt.do_pack();
            check("gtp_tmpl: raw_data size", pkt.raw_data.size() == 120);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("gtp_tmpl: unpack layer count", pkt2.layer_stack.size() == 6);
                begin
                    gtp_u_header gtp2;
                    $cast(gtp2, pkt2.get_layer(PROTO_GTP_U));
                    check("gtp_tmpl: unpack teid", gtp2.teid == 32'h0000ABCD);
                end
            end
        end

        // ---- NVGRE (GRE+Ethernet) template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_GRE_ETH_IPV4_TCP);
            check("nvgre_tmpl: layer count", pkt.layer_stack.size() == 6);
            check("nvgre_tmpl: layer[2] GRE", pkt.layer_stack[2].proto_type == PROTO_GRE);
            check("nvgre_tmpl: layer[3] ETH", pkt.layer_stack[3].proto_type == PROTO_ETHERNET);

            pkt.pkt_len = 128;
            pkt.do_pack();
            check("nvgre_tmpl: raw_data not empty", pkt.raw_data.size() > 0);
        end

        // ---- Free-form: VXLAN with custom fields ----
        begin
            packet pkt = new();
            pkt.add_layer(eth_header::create());
            pkt.add_layer(ipv4_header::create());
            pkt.add_layer(udp_header::create());
            pkt.add_layer(vxlan_header::create(24'd999));
            pkt.add_layer(eth_header::create());
            pkt.add_layer(ipv4_header::create());
            pkt.add_layer(tcp_header::create());
            check("freeform_vxlan: layer count", pkt.layer_stack.size() == 7);

            begin
                vxlan_header vx;
                $cast(vx, pkt.get_layer(PROTO_VXLAN));
                check("freeform_vxlan: vni", vx.vni == 24'd999);
            end
        end

        // ---- VLAN + VXLAN template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_VLAN_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
            check("vlan_vxlan_tmpl: layer count", pkt.layer_stack.size() == 8);
            check("vlan_vxlan_tmpl: layer[1] VLAN", pkt.layer_stack[1].proto_type == PROTO_VLAN);
            check("vlan_vxlan_tmpl: layer[4] VXLAN", pkt.layer_stack[4].proto_type == PROTO_VXLAN);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

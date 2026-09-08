// test/test_traffic_stream.sv
`include "stream/traffic_stream.sv"

program test_traffic_stream;

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
        $display("=== test_traffic_stream ===");

        // ---- Increment src_addr ----
        begin
            traffic_stream stream = new();
            field_modifier mod = new("ipv4.src_addr", MOD_INCREMENT);
            packet base = new();
            packet pkts[$];

            base.build_from_template(ETH_IPV4_TCP);
            base.pkt_len = 64;

            mod.min_val = 32'hC0A80001;
            mod.max_val = 32'hC0A800FF;
            mod.step    = 1;

            stream.base_pkt  = base;
            stream.pkt_count = 5;
            stream.modifiers.push_back(mod);
            stream.gen_packets(pkts);

            check("stream_inc: pkt count", pkts.size() == 5);

            begin
                ipv4_header ip0, ip1, ip4;
                $cast(ip0, pkts[0].get_layer(PROTO_IPV4));
                $cast(ip1, pkts[1].get_layer(PROTO_IPV4));
                $cast(ip4, pkts[4].get_layer(PROTO_IPV4));
                check("stream_inc: pkt[0] src", ip0.src_addr == 32'hC0A80001);
                check("stream_inc: pkt[1] src", ip1.src_addr == 32'hC0A80002);
                check("stream_inc: pkt[4] src", ip4.src_addr == 32'hC0A80005);
            end

            // Verify all packets are packed_data
            check("stream_inc: pkt[0] has raw_data", pkts[0].raw_data.size() == 64);
        end

        // ---- Multiple modifiers ----
        begin
            traffic_stream stream = new();
            field_modifier mod_ip = new("ipv4.src_addr", MOD_INCREMENT);
            field_modifier mod_port = new("tcp.dst_port", MOD_INCREMENT);
            packet base = new();
            packet pkts[$];

            base.build_from_template(ETH_IPV4_TCP);
            base.pkt_len = 64;

            mod_ip.min_val = 32'h0A000001;
            mod_ip.max_val = 32'h0A0000FF;
            mod_ip.step = 1;

            mod_port.min_val = 16'd8000;
            mod_port.max_val = 16'd9000;
            mod_port.step = 1;

            stream.base_pkt  = base;
            stream.pkt_count = 3;
            stream.modifiers.push_back(mod_ip);
            stream.modifiers.push_back(mod_port);
            stream.gen_packets(pkts);

            check("stream_multi: pkt count", pkts.size() == 3);

            begin
                ipv4_header ip;
                tcp_header tcp;
                $cast(ip, pkts[2].get_layer(PROTO_IPV4));
                $cast(tcp, pkts[2].get_layer(PROTO_TCP));
                check("stream_multi: pkt[2] src", ip.src_addr == 32'h0A000003);
                check("stream_multi: pkt[2] port", tcp.dst_port == 16'd8002);
            end
        end

        // ---- List mode ----
        begin
            traffic_stream stream = new();
            field_modifier mod = new("udp.dst_port", MOD_LIST);
            packet base = new();
            packet pkts[$];

            base.build_from_template(ETH_IPV4_UDP);
            base.pkt_len = 64;

            mod.value_list = '{16'd53, 16'd80, 16'd443};

            stream.base_pkt  = base;
            stream.pkt_count = 5;
            stream.modifiers.push_back(mod);
            stream.gen_packets(pkts);

            check("stream_list: pkt count", pkts.size() == 5);

            begin
                udp_header u0, u1, u3;
                $cast(u0, pkts[0].get_layer(PROTO_UDP));
                $cast(u1, pkts[1].get_layer(PROTO_UDP));
                $cast(u3, pkts[3].get_layer(PROTO_UDP));
                check("stream_list: pkt[0] port", u0.dst_port == 16'd53);
                check("stream_list: pkt[1] port", u1.dst_port == 16'd80);
                check("stream_list: pkt[3] port wrap", u3.dst_port == 16'd53);
            end
        end

        // ---- Decrement mode ----
        begin
            traffic_stream stream = new();
            field_modifier mod = new("ipv4.ttl", MOD_DECREMENT);
            packet base = new();
            packet pkts[$];

            base.build_from_template(ETH_IPV4_TCP);
            base.pkt_len = 64;

            mod.min_val = 8'd1;
            mod.max_val = 8'd255;
            mod.step    = 1;

            stream.base_pkt  = base;
            stream.pkt_count = 3;
            stream.modifiers.push_back(mod);
            stream.gen_packets(pkts);

            begin
                ipv4_header ip0, ip1, ip2;
                $cast(ip0, pkts[0].get_layer(PROTO_IPV4));
                $cast(ip1, pkts[1].get_layer(PROTO_IPV4));
                $cast(ip2, pkts[2].get_layer(PROTO_IPV4));
                check("stream_dec: pkt[0] ttl", ip0.ttl == 8'd255);
                check("stream_dec: pkt[1] ttl", ip1.ttl == 8'd254);
                check("stream_dec: pkt[2] ttl", ip2.ttl == 8'd253);
            end
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

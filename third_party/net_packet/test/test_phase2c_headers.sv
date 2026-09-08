// test/test_phase2c_headers.sv
`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "l2/mpls_header.sv"
`include "l3/ipv6_ext_header.sv"
`include "l4/sctp_header.sv"
`include "app/ptp_header.sv"
`include "tunnel/vxlan_gpe_header.sv"
`include "tunnel/esp_header.sv"

program test_phase2c_headers;

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
        $display("=== test_phase2c_headers ===");

        // ---- MPLS: basic construction ----
        begin
            mpls_header m = new();

            check("mpls_basic: proto_type",    m.proto_type == PROTO_MPLS);
            check("mpls_basic: header_length", m.get_header_length() == 4);
            check("mpls_basic: default s_bit", m.s_bit == 1'b1);
            check("mpls_basic: default ttl",   m.ttl == 8'd64);
        end

        // ---- MPLS: pack ----
        begin
            mpls_header m = new();
            byte unsigned pkd[$];

            m.label = 20'd1000;
            m.tc    = 3'd5;
            m.s_bit = 1'b1;
            m.ttl   = 8'd128;
            m.pack_header(pkd);
            check("mpls_pack: size", pkd.size() == 4);
        end

        // ---- MPLS: unpack round-trip ----
        begin
            mpls_header m = new();
            byte unsigned pkd[$];
            int offset;

            m.label = 20'd1000;
            m.tc    = 3'd5;
            m.s_bit = 1'b1;
            m.ttl   = 8'd128;
            m.pack_header(pkd);

            begin
                mpls_header m2 = new();
                offset = 0;
                m2.unpack_header(pkd, offset);
                check("mpls_unpack: label",  m2.label == 20'd1000);
                check("mpls_unpack: tc",     m2.tc    == 3'd5);
                check("mpls_unpack: s_bit",  m2.s_bit == 1'b1);
                check("mpls_unpack: ttl",    m2.ttl   == 8'd128);
                check("mpls_unpack: offset", offset   == 4);
            end
        end

        // ---- MPLS: clone+compare ----
        begin
            mpls_header m = new();
            m.label = 20'd1000;
            m.tc    = 3'd5;
            m.s_bit = 1'b1;
            m.ttl   = 8'd128;

            begin
                protocol_base m2;
                m2 = m.clone();
                check("mpls_clone: compare", m.compare(m2));
            end
        end

        // ---- MPLS: calc_fields with next_proto=PROTO_MPLS -> s_bit==0 ----
        begin
            mpls_header m = new();
            byte unsigned empty[$];

            m.s_bit = 1'b1;
            m.calc_fields(empty, PROTO_MPLS);
            check("mpls_calc: s_bit=0 when next is MPLS", m.s_bit == 1'b0);
        end

        // ---- MPLS: calc_fields with next_proto=PROTO_IPV4 -> s_bit==1 ----
        begin
            mpls_header m = new();
            byte unsigned empty[$];

            m.s_bit = 1'b0;
            m.calc_fields(empty, PROTO_IPV4);
            check("mpls_calc: s_bit=1 when next is IPV4", m.s_bit == 1'b1);
        end

        // ---- MPLS: static create ----
        begin
            mpls_header m;
            m = mpls_header::create(20'd500, 8'd32);
            check("mpls_create: label", m.label == 20'd500);
            check("mpls_create: ttl",   m.ttl   == 8'd32);
        end

        // ---- ipv6_hbh_header: basic construction ----
        begin
            ipv6_hbh_header h = new();

            check("hbh_basic: proto_type",     h.proto_type == PROTO_IPV6_HBH);
            check("hbh_basic: header_length",  h.get_header_length() == 8);
            check("hbh_basic: default nh",     h.next_header == 8'd59);
            check("hbh_basic: default ext_len",h.hdr_ext_len == 8'd0);
        end

        // ---- ipv6_hbh_header: pack ----
        begin
            ipv6_hbh_header h = new();
            byte unsigned pkd[$];

            h.pack_header(pkd);
            check("hbh_pack: size", pkd.size() == 8);
        end

        // ---- ipv6_hbh_header: unpack round-trip ----
        begin
            ipv6_hbh_header h = new();
            byte unsigned pkd[$];
            int offset;

            h.next_header = 8'd6; // TCP
            h.hdr_ext_len = 8'd0;
            h.pack_header(pkd);

            begin
                ipv6_hbh_header h2 = new();
                offset = 0;
                h2.unpack_header(pkd, offset);
                check("hbh_unpack: next_header", h2.next_header == 8'd6);
                check("hbh_unpack: hdr_ext_len", h2.hdr_ext_len == 8'd0);
                check("hbh_unpack: offset",      offset == 8);
            end
        end

        // ---- ipv6_hbh_header: calc_fields sets next_header ----
        begin
            ipv6_hbh_header h = new();
            byte unsigned empty[$];

            h.calc_fields(empty, PROTO_TCP);
            check("hbh_calc: next_header TCP",    h.next_header == 8'd6);
            h.calc_fields(empty, PROTO_UDP);
            check("hbh_calc: next_header UDP",    h.next_header == 8'd17);
            h.calc_fields(empty, PROTO_ICMPV6);
            check("hbh_calc: next_header ICMPv6", h.next_header == 8'd58);
        end

        // ---- ipv6_routing_header: basic construction ----
        begin
            ipv6_routing_header h = new();

            check("routing_basic: proto_type",     h.proto_type == PROTO_IPV6_ROUTING);
            check("routing_basic: header_length",  h.get_header_length() == 8);
            check("routing_basic: routing_type",   h.routing_type == 8'd0);
            check("routing_basic: segments_left",  h.segments_left == 8'd0);
        end

        // ---- ipv6_routing_header: pack/unpack round-trip ----
        begin
            ipv6_routing_header h = new();
            byte unsigned pkd[$];
            int offset;

            h.next_header   = 8'd6;
            h.hdr_ext_len   = 8'd0;
            h.routing_type  = 8'd2;
            h.segments_left = 8'd3;
            h.pack_header(pkd);
            check("routing_pack: size", pkd.size() == 8);

            begin
                ipv6_routing_header h2 = new();
                offset = 0;
                h2.unpack_header(pkd, offset);
                check("routing_unpack: next_header",   h2.next_header   == 8'd6);
                check("routing_unpack: routing_type",  h2.routing_type  == 8'd2);
                check("routing_unpack: segments_left", h2.segments_left == 8'd3);
                check("routing_unpack: offset",        offset == 8);
            end
        end

        // ---- ipv6_routing_header: calc_fields ----
        begin
            ipv6_routing_header h = new();
            byte unsigned empty[$];

            h.calc_fields(empty, PROTO_UDP);
            check("routing_calc: next_header UDP", h.next_header == 8'd17);
        end

        // ---- ipv6_fragment_header: basic construction ----
        begin
            ipv6_fragment_header h = new();

            check("fragment_basic: proto_type",    h.proto_type == PROTO_IPV6_FRAGMENT);
            check("fragment_basic: header_length", h.get_header_length() == 8);
            check("fragment_basic: default nh",    h.next_header == 8'd59);
        end

        // ---- ipv6_fragment_header: pack/unpack round-trip with fields ----
        begin
            ipv6_fragment_header h = new();
            byte unsigned pkd[$];
            int offset;

            h.next_header     = 8'd6;
            h.fragment_offset = 13'd100;
            h.m_flag          = 1'b1;
            h.identification  = 32'h12345678;
            h.pack_header(pkd);
            check("fragment_pack: size", pkd.size() == 8);

            begin
                ipv6_fragment_header h2 = new();
                offset = 0;
                h2.unpack_header(pkd, offset);
                check("fragment_unpack: next_header",     h2.next_header     == 8'd6);
                check("fragment_unpack: fragment_offset", h2.fragment_offset == 13'd100);
                check("fragment_unpack: m_flag",          h2.m_flag          == 1'b1);
                check("fragment_unpack: identification",  h2.identification  == 32'h12345678);
                check("fragment_unpack: offset",          offset == 8);
            end
        end

        // ---- ipv6_fragment_header: calc_fields ----
        begin
            ipv6_fragment_header h = new();
            byte unsigned empty[$];

            h.calc_fields(empty, PROTO_TCP);
            check("fragment_calc: next_header TCP", h.next_header == 8'd6);
        end

        // ---- ipv6_dest_header: basic construction ----
        begin
            ipv6_dest_header h = new();

            check("dest_basic: proto_type",    h.proto_type == PROTO_IPV6_DEST);
            check("dest_basic: header_length", h.get_header_length() == 8);
            check("dest_basic: default nh",    h.next_header == 8'd59);
        end

        // ---- ipv6_dest_header: pack/unpack round-trip ----
        begin
            ipv6_dest_header h = new();
            byte unsigned pkd[$];
            int offset;

            h.next_header = 8'd17; // UDP
            h.hdr_ext_len = 8'd0;
            h.pack_header(pkd);
            check("dest_pack: size", pkd.size() == 8);

            begin
                ipv6_dest_header h2 = new();
                offset = 0;
                h2.unpack_header(pkd, offset);
                check("dest_unpack: next_header", h2.next_header == 8'd17);
                check("dest_unpack: hdr_ext_len", h2.hdr_ext_len == 8'd0);
                check("dest_unpack: offset",      offset == 8);
            end
        end

        // ---- ipv6_dest_header: calc_fields ----
        begin
            ipv6_dest_header h = new();
            byte unsigned empty[$];

            h.calc_fields(empty, PROTO_ICMPV6);
            check("dest_calc: next_header ICMPv6", h.next_header == 8'd58);
        end

        // ---- ipv6_hbh_header: clone+compare ----
        begin
            ipv6_hbh_header h = new();
            h.next_header = 8'd6;

            begin
                protocol_base h2;
                h2 = h.clone();
                check("hbh_clone: compare", h.compare(h2));
            end
        end

        // ---- ipv6_routing_header: clone+compare ----
        begin
            ipv6_routing_header h = new();
            h.next_header   = 8'd17;
            h.routing_type  = 8'd2;
            h.segments_left = 8'd1;

            begin
                protocol_base h2;
                h2 = h.clone();
                check("routing_clone: compare", h.compare(h2));
            end
        end

        // ---- ipv6_fragment_header: clone+compare ----
        begin
            ipv6_fragment_header h = new();
            h.fragment_offset = 13'd50;
            h.m_flag          = 1'b1;
            h.identification  = 32'hDEADBEEF;

            begin
                protocol_base h2;
                h2 = h.clone();
                check("fragment_clone: compare", h.compare(h2));
            end
        end

        // ---- ipv6_dest_header: clone+compare ----
        begin
            ipv6_dest_header h = new();
            h.next_header = 8'd58;

            begin
                protocol_base h2;
                h2 = h.clone();
                check("dest_clone: compare", h.compare(h2));
            end
        end

        // ---- SCTP: basic construction ----
        begin
            sctp_header s = new();

            check("sctp_basic: proto_type",    s.proto_type == PROTO_SCTP);
            check("sctp_basic: header_length", s.get_header_length() == 12);
        end

        // ---- SCTP: pack ----
        begin
            sctp_header s = new();
            byte unsigned pkd[$];

            s.src_port         = 16'd1234;
            s.dst_port         = 16'd5678;
            s.verification_tag = 32'hAABBCCDD;
            s.pack_header(pkd);
            check("sctp_pack: size", pkd.size() == 12);
        end

        // ---- SCTP: unpack round-trip ----
        begin
            sctp_header s = new();
            byte unsigned pkd[$];
            int offset;

            s.src_port         = 16'd1234;
            s.dst_port         = 16'd5678;
            s.verification_tag = 32'hAABBCCDD;
            s.checksum         = 32'h11223344;
            s.pack_header(pkd);

            begin
                sctp_header s2 = new();
                offset = 0;
                s2.unpack_header(pkd, offset);
                check("sctp_unpack: src_port",         s2.src_port         == 16'd1234);
                check("sctp_unpack: dst_port",         s2.dst_port         == 16'd5678);
                check("sctp_unpack: verification_tag", s2.verification_tag == 32'hAABBCCDD);
                check("sctp_unpack: checksum",         s2.checksum         == 32'h11223344);
                check("sctp_unpack: offset",           offset              == 12);
            end
        end

        // ---- SCTP: clone+compare ----
        begin
            sctp_header s = new();
            s.src_port         = 16'd1234;
            s.dst_port         = 16'd5678;
            s.verification_tag = 32'hAABBCCDD;

            begin
                protocol_base s2;
                s2 = s.clone();
                check("sctp_clone: compare", s.compare(s2));
            end
        end

        // ---- PTP: basic construction ----
        begin
            ptp_header p = new();

            check("ptp_basic: proto_type",    p.proto_type == PROTO_PTP);
            check("ptp_basic: header_length", p.get_header_length() == 34);
            check("ptp_basic: default version", p.version_ptp == 4'd2);
            check("ptp_basic: default message_type", p.message_type == 4'd0);
        end

        // ---- PTP: pack ----
        begin
            ptp_header p = new();
            byte unsigned pkd[$];

            p.message_type   = 4'd0;
            p.domain_number  = 8'd0;
            p.sequence_id    = 16'd100;
            p.clock_identity = 64'h0011223344556677;
            p.port_number    = 16'd1;
            p.pack_header(pkd);
            check("ptp_pack: size", pkd.size() == 34);
        end

        // ---- PTP: unpack round-trip ----
        begin
            ptp_header p = new();
            byte unsigned pkd[$];
            int offset;

            p.message_type   = 4'd0;
            p.domain_number  = 8'd0;
            p.sequence_id    = 16'd100;
            p.clock_identity = 64'h0011223344556677;
            p.port_number    = 16'd1;
            p.pack_header(pkd);

            begin
                ptp_header p2 = new();
                offset = 0;
                p2.unpack_header(pkd, offset);
                check("ptp_unpack: message_type",   p2.message_type   == 4'd0);
                check("ptp_unpack: sequence_id",    p2.sequence_id    == 16'd100);
                check("ptp_unpack: clock_identity", p2.clock_identity == 64'h0011223344556677);
                check("ptp_unpack: port_number",    p2.port_number    == 16'd1);
                check("ptp_unpack: offset",         offset            == 34);
            end
        end

        // ---- PTP: clone+compare ----
        begin
            ptp_header p = new();
            p.message_type   = 4'd2;
            p.domain_number  = 8'd5;
            p.sequence_id    = 16'd42;
            p.clock_identity = 64'hDEADBEEFCAFEBABE;
            p.port_number    = 16'd3;

            begin
                protocol_base p2;
                p2 = p.clone();
                check("ptp_clone: compare", p.compare(p2));
            end
        end

        // ---- PTP: static create ----
        begin
            ptp_header p;
            p = ptp_header::create(.msg_type(4'd1));
            check("ptp_create: message_type", p.message_type == 4'd1);
        end

        // ---- VXLAN-GPE: basic construction ----
        begin
            vxlan_gpe_header v = new();

            check("vxlan_gpe_basic: proto_type",    v.proto_type == PROTO_VXLAN_GPE);
            check("vxlan_gpe_basic: header_length", v.get_header_length() == 8);
            check("vxlan_gpe_basic: default vni",   v.vni == 24'd100);
            check("vxlan_gpe_basic: default flags",          v.flags == 8'h0C);
            check("vxlan_gpe_basic: default next_protocol",  v.next_protocol == 8'd3);
        end

        // ---- VXLAN-GPE: pack ----
        begin
            vxlan_gpe_header v = new();
            byte unsigned pkd[$];

            v.vni           = 24'hABCDEF;
            v.next_protocol = 8'd3;
            v.pack_header(pkd);
            check("vxlan_gpe_pack: size", pkd.size() == 8);
        end

        // ---- VXLAN-GPE: unpack round-trip ----
        begin
            vxlan_gpe_header v = new();
            byte unsigned pkd[$];
            int offset;

            v.flags         = 8'h0C;
            v.next_protocol = 8'd1;   // IPv4
            v.vni           = 24'hABCDEF;
            v.pack_header(pkd);

            begin
                vxlan_gpe_header v2 = new();
                offset = 0;
                v2.unpack_header(pkd, offset);
                check("vxlan_gpe_unpack: flags",         v2.flags         == 8'h0C);
                check("vxlan_gpe_unpack: next_protocol", v2.next_protocol == 8'd1);
                check("vxlan_gpe_unpack: vni",           v2.vni           == 24'hABCDEF);
                check("vxlan_gpe_unpack: offset",        offset           == 8);
            end
        end

        // ---- VXLAN-GPE: calc_fields ----
        begin
            vxlan_gpe_header v = new();
            byte unsigned empty[$];

            v.calc_fields(empty, PROTO_IPV4);
            check("vxlan_gpe_calc: PROTO_IPV4 -> next_protocol==1", v.next_protocol == 8'd1);

            v.calc_fields(empty, PROTO_ETHERNET);
            check("vxlan_gpe_calc: PROTO_ETHERNET -> next_protocol==3", v.next_protocol == 8'd3);
        end

        // ---- VXLAN-GPE: clone+compare ----
        begin
            vxlan_gpe_header v = new();
            v.flags         = 8'h0C;
            v.next_protocol = 8'd2;
            v.vni           = 24'd999;

            begin
                protocol_base v2;
                v2 = v.clone();
                check("vxlan_gpe_clone: compare", v.compare(v2));
            end
        end

        // ---- ESP: basic construction ----
        begin
            esp_header e = new();

            check("esp_basic: proto_type",    e.proto_type == PROTO_ESP);
            check("esp_basic: header_length", e.get_header_length() == 8);
        end

        // ---- ESP: pack ----
        begin
            esp_header e = new();
            byte unsigned pkd[$];

            e.spi             = 32'h12345678;
            e.sequence_number = 32'd1;
            e.pack_header(pkd);
            check("esp_pack: size", pkd.size() == 8);
        end

        // ---- ESP: unpack round-trip ----
        begin
            esp_header e = new();
            byte unsigned pkd[$];
            int offset;

            e.spi             = 32'h12345678;
            e.sequence_number = 32'd1;
            e.pack_header(pkd);

            begin
                esp_header e2 = new();
                offset = 0;
                e2.unpack_header(pkd, offset);
                check("esp_unpack: spi",             e2.spi             == 32'h12345678);
                check("esp_unpack: sequence_number", e2.sequence_number == 32'd1);
                check("esp_unpack: offset",          offset             == 8);
            end
        end

        // ---- ESP: clone+compare ----
        begin
            esp_header e = new();
            e.spi             = 32'hDEADBEEF;
            e.sequence_number = 32'd42;

            begin
                protocol_base e2;
                e2 = e.clone();
                check("esp_clone: compare", e.compare(e2));
            end
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

// src/protocols/l3/ipv6_header.sv
`ifndef IPV6_HEADER_SV
`define IPV6_HEADER_SV

`include "protocol_base.sv"

class ipv6_header extends protocol_base;

    rand bit [3:0]   version;
    rand bit [7:0]   traffic_class;
    rand bit [19:0]  flow_label;
    rand bit [15:0]  payload_length;
    rand bit [7:0]   next_header;
    rand bit [7:0]   hop_limit;
    rand bit [127:0] src_addr;
    rand bit [127:0] dst_addr;

    constraint c_default {
        soft version == 6;
        soft hop_limit inside {[1:255]};
        soft traffic_class == 0;
        soft flow_label == 0;
        // next_header: exclude values that the parser maps to a known next-layer protocol.
        // calc_fields() will override with the correct value when a next layer exists.
        // When IPv6 is the last layer, the random value must not match a known
        // next-header number that would cause the parser to expect another header.
        // Note: 59 = No Next Header is safe and allowed.
        soft !(next_header inside {8'd0, 8'd6, 8'd17, 8'd41,      // HBH, TCP, UDP, IPv6
                                    8'd43, 8'd44, 8'd47, 8'd50,    // Routing, Fragment, GRE, ESP
                                    8'd58, 8'd60, 8'd89, 8'd132}); // ICMPv6, Dest, OSPF, SCTP
    }

    function new();
        proto_type      = PROTO_IPV6;
        version         = 6;
        traffic_class   = 0;
        flow_label      = 0;
        payload_length  = 0;
        next_header     = IPV6_NH_TCP;
        hop_limit       = 64;
        src_addr        = 0;
        dst_addr        = 0;
    endfunction

    static function ipv6_header create(bit [127:0] src = 0, bit [127:0] dst = 0,
                                        bit [7:0] nh = IPV6_NH_TCP, bit [7:0] hl = 64);
        ipv6_header h = new();
        h.src_addr    = src;
        h.dst_addr    = dst;
        h.next_header = nh;
        h.hop_limit   = hl;
        return h;
    endfunction

    // Pack 128-bit address as 16 bytes (big-endian)
    static function void pack_bytes_128(ref byte unsigned data[$], bit [127:0] val);
        for (int i = 15; i >= 0; i--) begin
            data.push_back(val[i*8 +: 8]);
        end
    endfunction

    static function bit [127:0] unpack_bytes_128(byte unsigned data[$], ref int offset);
        bit [127:0] val = 0;
        for (int i = 15; i >= 0; i--) begin
            val[i*8 +: 8] = data[offset];
            offset++;
        end
        return val;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [31:0] ver_tc_fl = {version, traffic_class, flow_label};
        packet_utils::pack_bytes_32(data, ver_tc_fl);
        packet_utils::pack_bytes_16(data, payload_length);
        data.push_back(next_header);
        data.push_back(hop_limit);
        pack_bytes_128(data, src_addr);
        pack_bytes_128(data, dst_addr);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] ver_tc_fl = packet_utils::unpack_bytes_32(data, offset);
        version       = ver_tc_fl[31:28];
        traffic_class = ver_tc_fl[27:20];
        flow_label    = ver_tc_fl[19:0];
        payload_length = packet_utils::unpack_bytes_16(data, offset);
        next_header    = data[offset]; offset++;
        hop_limit      = data[offset]; offset++;
        src_addr       = unpack_bytes_128(data, offset);
        dst_addr       = unpack_bytes_128(data, offset);
    endfunction

    virtual function int get_header_length();
        return 40;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;

        // Set next_header from next_proto
        case (next_proto)
            PROTO_TCP:           next_header = IPV6_NH_TCP;
            PROTO_UDP:           next_header = IPV6_NH_UDP;
            PROTO_ICMPV6:        next_header = IPV6_NH_ICMPV6;
            PROTO_IPV6:          next_header = IPV6_NH_IPV6;
            PROTO_GRE:           next_header = IPV6_NH_GRE;
            PROTO_SCTP:          next_header = IPV6_NH_SCTP;
            PROTO_OSPF:          next_header = IPV6_NH_OSPF;
            PROTO_IPV6_HBH:      next_header = IPV6_NH_HBH;
            PROTO_IPV6_ROUTING:  next_header = IPV6_NH_ROUTING;
            PROTO_IPV6_FRAGMENT: next_header = IPV6_NH_FRAGMENT;
            PROTO_IPV6_DEST:     next_header = IPV6_NH_DEST;
            PROTO_ESP:           next_header = IPV6_NH_ESP;
            PROTO_RAW_PAYLOAD:   next_header = 8'd59;  // No Next Header (RFC 8200 Sec 4.7)
            default: ;
        endcase

        // payload_length = size of everything after the IPv6 header
        payload_length = payload_data.size();
    endfunction

    virtual function protocol_base clone();
        ipv6_header h = new();
        h.version        = version;
        h.traffic_class  = traffic_class;
        h.flow_label     = flow_label;
        h.payload_length = payload_length;
        h.next_header    = next_header;
        h.hop_limit      = hop_limit;
        h.src_addr       = src_addr;
        h.dst_addr       = dst_addr;
        h.auto_calc      = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv6_header o;
        if (!$cast(o, other)) return 0;
        return (version == o.version) && (traffic_class == o.traffic_class) &&
               (flow_label == o.flow_label) && (payload_length == o.payload_length) &&
               (next_header == o.next_header) && (hop_limit == o.hop_limit) &&
               (src_addr == o.src_addr) && (dst_addr == o.dst_addr);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version  : %0d\n", version)};
        s = {s, $sformatf("  tc       : 0x%02x\n", traffic_class)};
        s = {s, $sformatf("  flow_lbl : 0x%05x\n", flow_label)};
        s = {s, $sformatf("  pay_len  : %0d\n", payload_length)};
        s = {s, $sformatf("  next_hdr : %0d\n", next_header)};
        s = {s, $sformatf("  hop_limit: %0d\n", hop_limit)};
        s = {s, $sformatf("  src_addr : %s\n", packet_utils::format_ipv6(src_addr))};
        s = {s, $sformatf("  dst_addr : %s\n", packet_utils::format_ipv6(dst_addr))};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%s -> %s nh:%0d hl:%0d len:%0d",
                         packet_utils::format_ipv6(src_addr),
                         packet_utils::format_ipv6(dst_addr),
                         next_header, hop_limit, payload_length);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        // src_addr/dst_addr 128-bit: str_to_num 仅 64bit, 用 packet_utils::parse_ipv6
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("src_addr", path);
            if (__v != "") begin
                bit __ok; bit [127:0] __a = packet_utils::parse_ipv6(__v, __ok);
                if (__ok) src_addr = __a;
            end
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("dst_addr", path);
            if (__v != "") begin
                bit __ok; bit [127:0] __a = packet_utils::parse_ipv6(__v, __ok);
                if (__ok) dst_addr = __a;
            end
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hop_limit", path);
            if (__v != "") hop_limit = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("traffic_class", path);
            if (__v != "") traffic_class = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("flow_label", path);
            if (__v != "") flow_label = 20'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    // RFC 8200 (IPv6)
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (version != 6)
            errors.push_back($sformatf("IPv6: version=%0d, expected 6", version));
        if (hop_limit == 0)
            warnings.push_back("IPv6: hop_limit=0 (packet will be dropped by routers)");
        if (payload_length == 0 && next_header != IPV6_NH_HBH)
            warnings.push_back($sformatf("IPv6: payload_length=0 with next_header=%0d (jumbogram?)", next_header));
        // Validate next_header is a known IANA value
        if (!(next_header inside {8'd0, 8'd6, 8'd17, 8'd41, 8'd43, 8'd44, 8'd47,
                                   8'd50, 8'd58, 8'd59, 8'd60, 8'd89, 8'd132}))
            warnings.push_back($sformatf("IPv6: next_header=%0d not a common IANA protocol number", next_header));
    endfunction

endclass

`endif // IPV6_HEADER_SV

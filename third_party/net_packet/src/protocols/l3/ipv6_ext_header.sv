// src/protocols/l3/ipv6_ext_header.sv
`ifndef IPV6_EXT_HEADER_SV
`define IPV6_EXT_HEADER_SV

`include "protocol_base.sv"

// Helper function to map protocol_type_e to IPv6 next_header byte value
function automatic bit [7:0] proto_to_ipv6_nh(protocol_type_e proto);
    case (proto)
        PROTO_TCP:           return 8'd6;
        PROTO_UDP:           return 8'd17;
        PROTO_ICMPV6:        return 8'd58;
        PROTO_IPV6_HBH:      return 8'd0;
        PROTO_IPV6_ROUTING:  return 8'd43;
        PROTO_IPV6_FRAGMENT: return 8'd44;
        PROTO_IPV6_DEST:     return 8'd60;
        PROTO_GRE:           return 8'd47;
        PROTO_SCTP:          return 8'd132;
        PROTO_ESP:           return 8'd50;
        PROTO_RAW_PAYLOAD:   return 8'd59; // No Next Header
        default:             return 8'd59; // No Next Header
    endcase
endfunction

// =============================================================================
// ipv6_hbh_header — Hop-by-Hop Options (PROTO_IPV6_HBH = 14)
// Wire: next_header (1B), hdr_ext_len (1B), options (variable, padded to 8B)
// =============================================================================
class ipv6_hbh_header extends protocol_base;

    rand bit [7:0]        next_header;
    rand bit [7:0]        hdr_ext_len;
    byte unsigned         options[$];   // type-specific data (default: 6 padding bytes)

    // ----- HBH Option rand controls -----
    rand bit        opt_router_alert_en;
    rand bit [15:0] opt_router_alert_val;  // 0=MLD, 1=RSVP, 2=Active Networks
    rand bit        opt_jumbo_en;
    rand bit [31:0] opt_jumbo_len;         // Jumbo payload length

    constraint c_opt_ctrl {
        soft opt_router_alert_en  == 0;
        soft opt_router_alert_val == 0;  // MLD
        soft opt_jumbo_en         == 0;
        soft opt_jumbo_len inside {[65536:32'hFFFFFFFF]};
    }

    function new();
        proto_type  = PROTO_IPV6_HBH;
        next_header = 8'd59; // No Next Header
        hdr_ext_len = 8'd0;
        options = '{0,0,0,0,0,0};
        foreach (options[i]) options[i] = 8'h00;
        opt_router_alert_en  = 0;
        opt_router_alert_val = 0;
        opt_jumbo_en         = 0;
        opt_jumbo_len        = 32'd65536;
    endfunction

    static function ipv6_hbh_header create(bit [7:0] nh = 8'd59, bit [7:0] ext_len = 8'd0);
        ipv6_hbh_header h = new();
        h.next_header = nh;
        h.hdr_ext_len = ext_len;
        return h;
    endfunction

    virtual function int get_header_length();
        return (hdr_ext_len + 1) * 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        int total_len   = get_header_length();
        int options_len = total_len - 2; // 2 fixed bytes (next_header + hdr_ext_len)
        int pad_needed;

        data.push_back(next_header);
        data.push_back(hdr_ext_len);

        // Pack options, padded/truncated to fill the remaining space
        if (options.size() >= options_len) begin
            for (int i = 0; i < options_len; i++)
                data.push_back(options[i]);
        end else begin
            foreach (options[i]) data.push_back(options[i]);
            pad_needed = options_len - options.size();
            for (int i = 0; i < pad_needed; i++) data.push_back(8'h00);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        int total_len;
        int options_len;

        next_header = data[offset]; offset++;
        hdr_ext_len = data[offset]; offset++;

        total_len   = get_header_length();
        options_len = total_len - 2;
        options.delete();
        for (int i = 0; i < options_len; i++) begin
            options.push_back(data[offset]);
            offset++;
        end
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Auto-build options from rand fields
        if (opt_router_alert_en || opt_jumbo_en) begin
            options.delete();
            if (opt_router_alert_en) begin
                // Router Alert: type=5, len=2, value(16-bit)
                options.push_back(8'd5);
                options.push_back(8'd2);
                options.push_back(opt_router_alert_val[15:8]);
                options.push_back(opt_router_alert_val[7:0]);
            end
            if (opt_jumbo_en) begin
                // Jumbo Payload: type=0xC2, len=4, value(32-bit)
                options.push_back(8'hC2);
                options.push_back(8'd4);
                options.push_back(opt_jumbo_len[31:24]);
                options.push_back(opt_jumbo_len[23:16]);
                options.push_back(opt_jumbo_len[15:8]);
                options.push_back(opt_jumbo_len[7:0]);
            end
            // Pad to make total (2 + options.size()) multiple of 8
            begin
                int total = 2 + options.size();
                while (total % 8 != 0) begin
                    options.push_back(8'd0);
                    total++;
                end
            end
        end
        // Auto-compute hdr_ext_len: total = (hdr_ext_len+1)*8, minus 2 bytes for next_header+hdr_ext_len = options
        // So hdr_ext_len = (2 + options.size() + padding) / 8 - 1
        begin
            int total_opt_len = options.size();
            int padded_len = ((2 + total_opt_len + 7) / 8) * 8;  // round up to 8-byte boundary
            hdr_ext_len = (padded_len / 8) - 1;
        end
        next_header = proto_to_ipv6_nh(next_proto);
    endfunction

    virtual function protocol_base clone();
        ipv6_hbh_header h = new();
        h.next_header            = next_header;
        h.hdr_ext_len            = hdr_ext_len;
        h.options = options;
        h.opt_router_alert_en    = opt_router_alert_en;
        h.opt_router_alert_val   = opt_router_alert_val;
        h.opt_jumbo_en           = opt_jumbo_en;
        h.opt_jumbo_len          = opt_jumbo_len;
        h.auto_calc              = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv6_hbh_header o;
        if (!$cast(o, other)) return 0;
        if (next_header != o.next_header) return 0;
        if (hdr_ext_len != o.hdr_ext_len) return 0;
        if (options.size() != o.options.size()) return 0;
        foreach (options[i]) if (options[i] != o.options[i]) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  next_header : %0d\n", next_header)};
        s = {s, $sformatf("  hdr_ext_len : %0d (%0d bytes total)\n", hdr_ext_len, get_header_length())};
        s = {s, $sformatf("  options_len : %0d bytes\n", options.size())};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("HBH nh:%0d ext_len:%0d total:%0dB",
                         next_header, hdr_ext_len, get_header_length());
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("next_header", path);
            if (__v != "") next_header = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hdr_ext_len", path);
            if (__v != "") hdr_ext_len = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opt_router_alert_en", path);
            if (__v != "") opt_router_alert_en = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opt_router_alert_val", path);
            if (__v != "") opt_router_alert_val = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opt_jumbo_en", path);
            if (__v != "") opt_jumbo_en = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opt_jumbo_len", path);
            if (__v != "") opt_jumbo_len = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

// =============================================================================
// ipv6_routing_header — Routing Extension Header (PROTO_IPV6_ROUTING = 15)
// Wire: next_header(1), hdr_ext_len(1), routing_type(1), segments_left(1), data(variable)
// =============================================================================
class ipv6_routing_header extends protocol_base;

    rand bit [7:0]        next_header;
    rand bit [7:0]        hdr_ext_len;
    rand bit [7:0]        routing_type;
    rand bit [7:0]        segments_left;
    byte unsigned         data[];       // type-specific data (default: 4 zero bytes)

    function new();
        proto_type    = PROTO_IPV6_ROUTING;
        next_header   = 8'd59;
        hdr_ext_len   = 8'd0;
        routing_type  = 8'd0;
        segments_left = 8'd0;
        data          = new[4];
        foreach (data[i]) data[i] = 8'h00;
    endfunction

    static function ipv6_routing_header create(bit [7:0] nh = 8'd59,
                                                bit [7:0] ext_len = 8'd0,
                                                bit [7:0] rtype = 8'd0,
                                                bit [7:0] segs = 8'd0);
        ipv6_routing_header h = new();
        h.next_header   = nh;
        h.hdr_ext_len   = ext_len;
        h.routing_type  = rtype;
        h.segments_left = segs;
        return h;
    endfunction

    virtual function int get_header_length();
        return (hdr_ext_len + 1) * 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data_out[$]);
        int total_len  = get_header_length();
        int data_len   = total_len - 4; // 4 fixed bytes
        int pad_needed;

        data_out.push_back(next_header);
        data_out.push_back(hdr_ext_len);
        data_out.push_back(routing_type);
        data_out.push_back(segments_left);

        if (data.size() >= data_len) begin
            for (int i = 0; i < data_len; i++) data_out.push_back(data[i]);
        end else begin
            foreach (data[i]) data_out.push_back(data[i]);
            pad_needed = data_len - data.size();
            for (int i = 0; i < pad_needed; i++) data_out.push_back(8'h00);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data_in[$], ref int offset);
        int total_len;
        int data_len;

        next_header   = data_in[offset]; offset++;
        hdr_ext_len   = data_in[offset]; offset++;
        routing_type  = data_in[offset]; offset++;
        segments_left = data_in[offset]; offset++;

        total_len = get_header_length();
        data_len  = total_len - 4;
        data      = new[data_len];
        for (int i = 0; i < data_len; i++) begin
            data[i] = data_in[offset];
            offset++;
        end
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Auto-compute hdr_ext_len from data size
        // header = next_header(1) + hdr_ext_len(1) + routing_type(1) + segments_left(1) + data
        begin
            int total_len = 4 + data.size();
            int padded_len = ((total_len + 7) / 8) * 8;
            hdr_ext_len = (padded_len / 8) - 1;
        end
        next_header = proto_to_ipv6_nh(next_proto);
    endfunction

    virtual function protocol_base clone();
        ipv6_routing_header h = new();
        h.next_header   = next_header;
        h.hdr_ext_len   = hdr_ext_len;
        h.routing_type  = routing_type;
        h.segments_left = segments_left;
        h.data          = new[data.size()];
        foreach (data[i]) h.data[i] = data[i];
        h.auto_calc     = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv6_routing_header o;
        if (!$cast(o, other)) return 0;
        if (next_header   != o.next_header)   return 0;
        if (hdr_ext_len   != o.hdr_ext_len)   return 0;
        if (routing_type  != o.routing_type)  return 0;
        if (segments_left != o.segments_left) return 0;
        if (data.size()   != o.data.size())   return 0;
        foreach (data[i]) if (data[i] != o.data[i]) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  next_header   : %0d\n", next_header)};
        s = {s, $sformatf("  hdr_ext_len   : %0d (%0d bytes total)\n", hdr_ext_len, get_header_length())};
        s = {s, $sformatf("  routing_type  : %0d\n", routing_type)};
        s = {s, $sformatf("  segments_left : %0d\n", segments_left)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("Routing nh:%0d type:%0d segs:%0d total:%0dB",
                         next_header, routing_type, segments_left, get_header_length());
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("next_header", path);
            if (__v != "") next_header = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hdr_ext_len", path);
            if (__v != "") hdr_ext_len = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("routing_type", path);
            if (__v != "") routing_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("segments_left", path);
            if (__v != "") segments_left = 8'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

// =============================================================================
// ipv6_fragment_header — Fragment Extension Header (PROTO_IPV6_FRAGMENT = 16)
// FIXED 8 bytes. Wire format:
//   Byte 0:   next_header
//   Byte 1:   reserved1
//   Bytes 2-3:{fragment_offset[12:0], reserved2[1:0], m_flag}
//   Bytes 4-7: identification (32-bit big-endian)
// =============================================================================
class ipv6_fragment_header extends protocol_base;

    rand bit [7:0]  next_header;
    rand bit [7:0]  reserved1;
    rand bit [12:0] fragment_offset;
    rand bit [1:0]  reserved2;
    rand bit        m_flag;
    rand bit [31:0] identification;

    // RFC 8200 Section 4.5: reserved fields MUST be zero
    constraint c_default {
        soft reserved1 == 8'd0;
        soft reserved2 == 2'd0;
    }

    function new();
        proto_type      = PROTO_IPV6_FRAGMENT;
        next_header     = 8'd59;
        reserved1       = 8'd0;
        fragment_offset = 13'd0;
        reserved2       = 2'd0;
        m_flag          = 1'b0;
        identification  = 32'd0;
    endfunction

    static function ipv6_fragment_header create(bit [7:0] nh = 8'd59,
                                                 bit [12:0] frag_off = 13'd0,
                                                 bit m = 1'b0,
                                                 bit [31:0] id = 32'd0);
        ipv6_fragment_header h = new();
        h.next_header    = nh;
        h.fragment_offset = frag_off;
        h.m_flag          = m;
        h.identification  = id;
        return h;
    endfunction

    virtual function int get_header_length();
        return 8; // always fixed
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [15:0] frag_word;

        data.push_back(next_header);
        data.push_back(reserved1);
        // Bytes 2-3: {fragment_offset[12:0], reserved2[1:0], m_flag}
        frag_word = {fragment_offset, reserved2, m_flag};
        packet_utils::pack_bytes_16(data, frag_word);
        packet_utils::pack_bytes_32(data, identification);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [15:0] frag_word;

        next_header = data[offset]; offset++;
        reserved1   = data[offset]; offset++;
        frag_word   = packet_utils::unpack_bytes_16(data, offset);
        fragment_offset = frag_word[15:3];
        reserved2       = frag_word[2:1];
        m_flag          = frag_word[0];
        identification  = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        next_header = proto_to_ipv6_nh(next_proto);
    endfunction

    virtual function protocol_base clone();
        ipv6_fragment_header h = new();
        h.next_header     = next_header;
        h.reserved1       = reserved1;
        h.fragment_offset = fragment_offset;
        h.reserved2       = reserved2;
        h.m_flag          = m_flag;
        h.identification  = identification;
        h.auto_calc       = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv6_fragment_header o;
        if (!$cast(o, other)) return 0;
        return (next_header     == o.next_header)     &&
               (reserved1       == o.reserved1)       &&
               (fragment_offset == o.fragment_offset) &&
               (reserved2       == o.reserved2)       &&
               (m_flag          == o.m_flag)           &&
               (identification  == o.identification);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  next_header     : %0d\n", next_header)};
        s = {s, $sformatf("  fragment_offset : %0d\n", fragment_offset)};
        s = {s, $sformatf("  m_flag          : %0b\n", m_flag)};
        s = {s, $sformatf("  identification  : 0x%08x\n", identification)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("Fragment nh:%0d off:%0d M:%0b id:0x%08x",
                         next_header, fragment_offset, m_flag, identification);
    endfunction

    // RFC 8200 Section 4.5
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (reserved1 != 0)
            warnings.push_back($sformatf("IPv6 Fragment: reserved1=0x%02x, MUST be 0 (RFC 8200)", reserved1));
        if (reserved2 != 0)
            warnings.push_back($sformatf("IPv6 Fragment: reserved2=%0d, MUST be 0 (RFC 8200)", reserved2));
        if (fragment_offset == 0 && m_flag == 0)
            warnings.push_back("IPv6 Fragment: offset=0 and M=0 (unfragmented, fragment header unnecessary)");
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("next_header", path);
            if (__v != "") next_header = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("fragment_offset", path);
            if (__v != "") fragment_offset = 13'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("m_flag", path);
            if (__v != "") m_flag = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("identification", path);
            if (__v != "") identification = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

// =============================================================================
// ipv6_dest_header — Destination Options (PROTO_IPV6_DEST = 17)
// Same wire format as HBH, different proto_type.
// =============================================================================
class ipv6_dest_header extends protocol_base;

    rand bit [7:0]        next_header;
    rand bit [7:0]        hdr_ext_len;
    byte unsigned         options[$];   // type-specific data (default: 6 padding bytes)

    // ----- Dest Option rand controls -----
    rand bit        opt_custom_en;
    rand bit [7:0]  opt_custom_type;
    rand bit [31:0] opt_custom_data;

    constraint c_opt_ctrl {
        soft opt_custom_en   == 0;
        soft opt_custom_type == 8'h1E;  // RFC 6553 RPL Option (common dest option)
        soft opt_custom_data == 32'h0;
    }

    function new();
        proto_type  = PROTO_IPV6_DEST;
        next_header      = 8'd59;
        hdr_ext_len      = 8'd0;
        options = '{0,0,0,0,0,0};
        opt_custom_en    = 0;
        opt_custom_type  = 8'h1E;
        opt_custom_data  = 32'h0;
    endfunction

    static function ipv6_dest_header create(bit [7:0] nh = 8'd59, bit [7:0] ext_len = 8'd0);
        ipv6_dest_header h = new();
        h.next_header = nh;
        h.hdr_ext_len = ext_len;
        return h;
    endfunction

    virtual function int get_header_length();
        return (hdr_ext_len + 1) * 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        int total_len   = get_header_length();
        int options_len = total_len - 2;
        int pad_needed;

        data.push_back(next_header);
        data.push_back(hdr_ext_len);

        if (options.size() >= options_len) begin
            for (int i = 0; i < options_len; i++) data.push_back(options[i]);
        end else begin
            foreach (options[i]) data.push_back(options[i]);
            pad_needed = options_len - options.size();
            for (int i = 0; i < pad_needed; i++) data.push_back(8'h00);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        int total_len;
        int options_len;

        next_header = data[offset]; offset++;
        hdr_ext_len = data[offset]; offset++;

        total_len   = get_header_length();
        options_len = total_len - 2;
        options.delete();
        for (int i = 0; i < options_len; i++) begin
            options.push_back(data[offset]);
            offset++;
        end
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Auto-build options from rand fields
        if (opt_custom_en) begin
            options.delete();
            // Custom option: type(1) + len(1) + data(4) = 6 bytes
            options.push_back(opt_custom_type);
            options.push_back(8'd4);  // 4 bytes of data
            options.push_back(opt_custom_data[31:24]);
            options.push_back(opt_custom_data[23:16]);
            options.push_back(opt_custom_data[15:8]);
            options.push_back(opt_custom_data[7:0]);
            // Pad to make total (2 + options.size()) multiple of 8
            begin
                int total = 2 + options.size();
                while (total % 8 != 0) begin
                    options.push_back(8'd0);
                    total++;
                end
            end
        end
        // Auto-compute hdr_ext_len: same as HBH
        begin
            int total_opt_len = options.size();
            int padded_len = ((2 + total_opt_len + 7) / 8) * 8;  // round up to 8-byte boundary
            hdr_ext_len = (padded_len / 8) - 1;
        end
        next_header = proto_to_ipv6_nh(next_proto);
    endfunction

    virtual function protocol_base clone();
        ipv6_dest_header h = new();
        h.next_header     = next_header;
        h.hdr_ext_len     = hdr_ext_len;
        h.options = options;
        h.opt_custom_en   = opt_custom_en;
        h.opt_custom_type = opt_custom_type;
        h.opt_custom_data = opt_custom_data;
        h.auto_calc       = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv6_dest_header o;
        if (!$cast(o, other)) return 0;
        if (next_header != o.next_header) return 0;
        if (hdr_ext_len != o.hdr_ext_len) return 0;
        if (options.size() != o.options.size()) return 0;
        foreach (options[i]) if (options[i] != o.options[i]) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  next_header : %0d\n", next_header)};
        s = {s, $sformatf("  hdr_ext_len : %0d (%0d bytes total)\n", hdr_ext_len, get_header_length())};
        s = {s, $sformatf("  options_len : %0d bytes\n", options.size())};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("Dest nh:%0d ext_len:%0d total:%0dB",
                         next_header, hdr_ext_len, get_header_length());
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("next_header", path);
            if (__v != "") next_header = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hdr_ext_len", path);
            if (__v != "") hdr_ext_len = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opt_custom_en", path);
            if (__v != "") opt_custom_en = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opt_custom_type", path);
            if (__v != "") opt_custom_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opt_custom_data", path);
            if (__v != "") opt_custom_data = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // IPV6_EXT_HEADER_SV

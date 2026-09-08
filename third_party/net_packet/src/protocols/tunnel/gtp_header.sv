// src/protocols/tunnel/gtp_header.sv
`ifndef GTP_HEADER_SV
`define GTP_HEADER_SV

`include "protocol_base.sv"

// ============================================================
// GTP-U header (3GPP TS 29.281): 8 or 12 bytes
// Wire format:
//   Byte 0: {version[2:0], pt, reserved, e_flag, s_flag, pn_flag}
//   Byte 1: message_type
//   Bytes 2-3: length (16-bit big-endian)
//   Bytes 4-7: teid (32-bit big-endian)
//   Optional (when e_flag|s_flag|pn_flag):
//     Bytes 8-9: sequence_number (16-bit)
//     Byte 10:   n_pdu_number
//     Byte 11:   next_ext_hdr_type
// ============================================================
class gtp_u_header extends protocol_base;

    rand bit [2:0]  version;
    rand bit        pt;
    rand bit        reserved;
    rand bit        e_flag;
    rand bit        s_flag;
    rand bit        pn_flag;
    rand bit [7:0]  message_type;
    rand bit [15:0] length;
    rand bit [31:0] teid;
    rand bit [15:0] sequence_number;
    rand bit [7:0]  n_pdu_number;
    rand bit [7:0]  next_ext_hdr_type;

    // ----- GTP-U Extension Header rand control -----
    rand bit [7:0]  ext_hdr_type;     // Extension header type (e.g. 0x85=PDU Session Container)
    rand byte unsigned ext_hdr_data[4]; // Extension header content (4 bytes)

    constraint c_default {
        soft version      == 3'b001;
        soft pt           == 1'b1;
        soft reserved     == 1'b0;
        soft e_flag       == 1'b0;
        soft s_flag       == 1'b0;
        soft pn_flag      == 1'b0;
        soft message_type == 8'hFF;
    }

    constraint c_ext_hdr {
        soft ext_hdr_type == 8'h85;   // PDU Session Container (most common in 5G)
    }

    function new();
        proto_type       = PROTO_GTP_U;
        version          = 3'b001;
        pt               = 1'b1;
        reserved         = 1'b0;
        e_flag           = 1'b0;
        s_flag           = 1'b0;
        pn_flag          = 1'b0;
        message_type     = 8'hFF;
        length           = 16'd0;
        teid             = 32'd0;
        sequence_number  = 16'd0;
        n_pdu_number     = 8'd0;
        next_ext_hdr_type = 8'd0;
        ext_hdr_type = 8'h85;
        foreach (ext_hdr_data[i]) ext_hdr_data[i] = 0;
    endfunction

    static function gtp_u_header create(bit [31:0] t = 32'd0);
        gtp_u_header h = new();
        h.teid = t;
        return h;
    endfunction

    function bit has_optional_fields();
        return (e_flag || s_flag || pn_flag);
    endfunction

    virtual function int get_header_length();
        int len = has_optional_fields() ? 12 : 8;
        if (e_flag && next_ext_hdr_type != 0) len += 8;  // extension header
        return len;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        byte unsigned b0;
        b0 = {version, pt, reserved, e_flag, s_flag, pn_flag};
        data.push_back(b0);
        data.push_back(message_type);
        packet_utils::pack_bytes_16(data, length);
        packet_utils::pack_bytes_32(data, teid);
        if (has_optional_fields()) begin
            packet_utils::pack_bytes_16(data, sequence_number);
            data.push_back(n_pdu_number);
            data.push_back(next_ext_hdr_type);
        end
        // Extension header (when e_flag set and next_ext_hdr_type != 0)
        if (e_flag && next_ext_hdr_type != 0) begin
            // Length in 4-byte units: 1(len) + 4(data) + padding + 1(next_type) = 8 bytes = 2 units
            data.push_back(8'd2);  // length = 2 (in 4-byte units)
            foreach (ext_hdr_data[i]) data.push_back(ext_hdr_data[i]);
            data.push_back(8'd0);  // padding
            data.push_back(8'd0);  // padding
            data.push_back(8'd0);  // next extension header type = 0 (no more)
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        byte unsigned b0;
        int ext_len;
        int ext_bytes;
        b0             = data[offset]; offset++;
        version        = b0[7:5];
        pt             = b0[4];
        reserved       = b0[3];
        e_flag         = b0[2];
        s_flag         = b0[1];
        pn_flag        = b0[0];
        message_type   = data[offset]; offset++;
        length         = packet_utils::unpack_bytes_16(data, offset);
        teid           = packet_utils::unpack_bytes_32(data, offset);
        if (has_optional_fields()) begin
            sequence_number   = packet_utils::unpack_bytes_16(data, offset);
            n_pdu_number      = data[offset]; offset++;
            next_ext_hdr_type = data[offset]; offset++;
        end
        if (e_flag && next_ext_hdr_type != 0 && offset < data.size()) begin
            ext_len = data[offset]; offset++;  // length in 4-byte units
            ext_bytes = ext_len * 4 - 2;  // minus length byte and next_type byte
            for (int i = 0; i < 4 && i < ext_bytes; i++) begin
                ext_hdr_data[i] = data[offset]; offset++;
            end
            // Skip remaining bytes
            for (int i = 4; i < ext_bytes; i++) offset++;
            // Read next extension header type
            if (offset < data.size()) offset++;  // next_ext_hdr_type (already have it)
        end
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        length = payload_data.size();
        if (has_optional_fields()) length += 4;
        if (e_flag && next_ext_hdr_type != 0) length += 8;  // extension header
    endfunction

    virtual function protocol_base clone();
        gtp_u_header h = new();
        h.version           = version;
        h.pt                = pt;
        h.reserved          = reserved;
        h.e_flag            = e_flag;
        h.s_flag            = s_flag;
        h.pn_flag           = pn_flag;
        h.message_type      = message_type;
        h.length            = length;
        h.teid              = teid;
        h.sequence_number   = sequence_number;
        h.n_pdu_number      = n_pdu_number;
        h.next_ext_hdr_type = next_ext_hdr_type;
        h.ext_hdr_type      = ext_hdr_type;
        foreach (ext_hdr_data[i]) h.ext_hdr_data[i] = ext_hdr_data[i];
        h.auto_calc         = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        gtp_u_header o;
        if (!$cast(o, other)) return 0;
        if (version      != o.version)      return 0;
        if (pt           != o.pt)           return 0;
        if (message_type != o.message_type) return 0;
        if (teid         != o.teid)         return 0;
        if (has_optional_fields()) begin
            if (sequence_number != o.sequence_number) return 0;
            if (n_pdu_number    != o.n_pdu_number)    return 0;
        end
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version          : %0d\n",    version)};
        s = {s, $sformatf("  pt               : %0d\n",    pt)};
        s = {s, $sformatf("  e_flag           : %0d\n",    e_flag)};
        s = {s, $sformatf("  s_flag           : %0d\n",    s_flag)};
        s = {s, $sformatf("  pn_flag          : %0d\n",    pn_flag)};
        s = {s, $sformatf("  message_type     : 0x%02x\n", message_type)};
        s = {s, $sformatf("  length           : %0d\n",    length)};
        s = {s, $sformatf("  teid             : 0x%08x\n", teid)};
        if (has_optional_fields()) begin
            s = {s, $sformatf("  sequence_number  : 0x%04x\n", sequence_number)};
            s = {s, $sformatf("  n_pdu_number     : 0x%02x\n", n_pdu_number)};
            s = {s, $sformatf("  next_ext_hdr_type: 0x%02x\n", next_ext_hdr_type)};
        end
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("GTP-U teid:0x%08x msg_type:0x%02x len:%0d", teid, message_type, length);
    endfunction

    // =========================================================================
    // GTP-U Extension Header Helpers
    // =========================================================================

    // Build a single GTP-U extension header
    // ext_type: extension header type (put in previous header's next_ext_hdr_type)
    // ext_data: content bytes (will be padded to make total multiple of 4)
    // next_type: next extension header type (0=no more)
    // Returns: {length, content_bytes..., next_type} with proper padding
    static function byte_queue build_ext_header(
        byte unsigned ext_data[$],
        bit [7:0] next_type = 0
    );
        byte unsigned ext[$];
        int content_len = ext_data.size();
        // Total = 1 (length) + content + padding + 1 (next_type)
        // Must be multiple of 4 bytes
        int total_len = 2 + content_len;  // length byte + content + next_type byte
        int padded_total = ((total_len + 3) / 4) * 4;
        int pad_bytes = padded_total - total_len;
        // Length in 4-byte units
        ext.push_back(padded_total / 4);
        // Content
        foreach (ext_data[i]) ext.push_back(ext_data[i]);
        // Padding
        for (int i = 0; i < pad_bytes; i++) ext.push_back(8'h00);
        // Next extension header type
        ext.push_back(next_type);
        return ext;
    endfunction

    // help — print GTP-U usage guide
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (version != 1)
            errors.push_back($sformatf("GTP-U: version=%0d, expected 1 (GTPv1)", version));
        if (pt != 1)
            warnings.push_back($sformatf("GTP-U: pt=%0d, expected 1 (GTP)", pt));
        if (message_type != 8'hFF)
            warnings.push_back($sformatf("GTP-U: message_type=0x%02x, T-PDU is 0xFF", message_type));
        if (teid == 0)
            warnings.push_back("GTP-U: TEID=0");
    endfunction

    static function void help();
        $display("============================================================================");
        $display(" GTP-U Header Guide (3GPP TS 29.281)");
        $display("============================================================================");
        $display("");
        $display(" Basic fields:");
        $display("   version(3b)=1, pt(1b)=1, message_type(8b)=0xFF(G-PDU)");
        $display("   teid(32b): Tunnel Endpoint Identifier");
        $display("   length(16b): auto-computed by calc_fields");
        $display("");
        $display(" Optional fields (when e_flag|s_flag|pn_flag set):");
        $display("   sequence_number(16b), n_pdu_number(8b), next_ext_hdr_type(8b)");
        $display("   Header grows from 8B to 12B");
        $display("");
        $display(" Usage:");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_UDP_GTP_U_IPV4_TCP;");
        $display("       gtp_u.teid == 32'h0000_ABCD;");
        $display("   };");
        $display("");
        $display("   // With sequence number:");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_UDP_GTP_U_IPV4_TCP;");
        $display("       gtp_u.teid   == 32'h0000_1234;");
        $display("       gtp_u.s_flag == 1;");
        $display("       gtp_u.sequence_number == 16'h0001;");
        $display("   };");
        $display("");
        $display(" Common next_ext_hdr_type values:");
        $display("   0x00 = No more extension headers");
        $display("   0x03 = Long PDCP PDU Number");
        $display("   0x20 = Service Class Indicator");
        $display("   0x40 = UDP Port (for NR user plane)");
        $display("   0x81 = RAN Container");
        $display("   0x82 = Long PDCP PDU Number (old)");
        $display("   0x83 = Xw RAN Container");
        $display("   0x84 = NR RAN Container");
        $display("   0x85 = PDU Session Container");
        $display("   0xC0 = PDCP PDU Number");
        $display("============================================================================");
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("version", path);
            if (__v != "") version = 3'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("message_type", path);
            if (__v != "") message_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("teid", path);
            if (__v != "") teid = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("sequence_number", path);
            if (__v != "") sequence_number = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("n_pdu_number", path);
            if (__v != "") n_pdu_number = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("next_ext_hdr_type", path);
            if (__v != "") next_ext_hdr_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ext_hdr_type", path);
            if (__v != "") ext_hdr_type = 8'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // GTP_HEADER_SV

// src/protocols/l4/sctp_header.sv
`ifndef SCTP_HEADER_SV
`define SCTP_HEADER_SV

`include "protocol_base.sv"

// SCTP Common Header (12 bytes)
// RFC 4960
// Wire format:
//   Bytes 0-1 : src_port (16-bit)
//   Bytes 2-3 : dst_port (16-bit)
//   Bytes 4-7 : verification_tag (32-bit)
//   Bytes 8-11: checksum (32-bit, CRC-32c — placeholder)

class sctp_header extends protocol_base;

    rand bit [15:0] src_port;
    rand bit [15:0] dst_port;
    rand bit [31:0] verification_tag;
    rand bit [31:0] checksum;

    function new();
        proto_type       = PROTO_SCTP;
        src_port         = 16'd0;
        dst_port         = 16'd0;
        verification_tag = 32'd0;
        checksum         = 32'd0;
    endfunction

    static function sctp_header create(bit [15:0] sp = 0, bit [15:0] dp = 0);
        sctp_header h = new();
        h.src_port = sp;
        h.dst_port = dp;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, src_port);
        packet_utils::pack_bytes_16(data, dst_port);
        packet_utils::pack_bytes_32(data, verification_tag);
        packet_utils::pack_bytes_32(data, checksum);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        src_port         = packet_utils::unpack_bytes_16(data, offset);
        dst_port         = packet_utils::unpack_bytes_16(data, offset);
        verification_tag = packet_utils::unpack_bytes_32(data, offset);
        checksum         = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 12;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // CRC-32c checksum requires full chunk data — leave as placeholder
    endfunction

    virtual function protocol_base clone();
        sctp_header h = new();
        h.src_port         = src_port;
        h.dst_port         = dst_port;
        h.verification_tag = verification_tag;
        h.checksum         = checksum;
        h.auto_calc        = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        sctp_header o;
        if (!$cast(o, other)) return 0;
        return (src_port         == o.src_port)         &&
               (dst_port         == o.dst_port)         &&
               (verification_tag == o.verification_tag);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  src_port        : %0d\n",   src_port)};
        s = {s, $sformatf("  dst_port        : %0d\n",   dst_port)};
        s = {s, $sformatf("  verification_tag: 0x%08x\n", verification_tag)};
        s = {s, $sformatf("  checksum        : 0x%08x\n", checksum)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("SCTP sport:%0d dport:%0d vtag:0x%08x",
                         src_port, dst_port, verification_tag);
    endfunction

    // RFC 9260 (SCTP)
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (src_port == 0)
            warnings.push_back("SCTP: src_port=0");
        if (dst_port == 0)
            warnings.push_back("SCTP: dst_port=0");
        // INIT chunk must have verification_tag==0 (RFC 9260 Section 8.1)
        // For general check: tag==0 on non-INIT is suspicious
        if (verification_tag == 0)
            warnings.push_back("SCTP: verification_tag=0 (only valid in INIT chunk)");
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("src_port", path);
            if (__v != "") src_port = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("dst_port", path);
            if (__v != "") dst_port = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("verification_tag", path);
            if (__v != "") verification_tag = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // SCTP_HEADER_SV

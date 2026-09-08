// src/protocols/l2/mpls_header.sv
`ifndef MPLS_HEADER_SV
`define MPLS_HEADER_SV

`include "protocol_base.sv"

class mpls_header extends protocol_base;

    rand bit [19:0] label;
    rand bit [2:0]  tc;
    rand bit        s_bit;
    rand bit [7:0]  ttl;

    constraint c_default {
        soft ttl inside {[1:255]};
        soft s_bit == 1;
    }

    function new();
        proto_type = PROTO_MPLS;
        label      = 0;
        tc         = 0;
        s_bit      = 1;
        ttl        = 64;
    endfunction

    static function mpls_header create(bit [19:0] l = 0, bit [7:0] t = 64);
        mpls_header h = new();
        h.label = l;
        h.ttl   = t;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [31:0] word = {label, tc, s_bit, ttl};
        packet_utils::pack_bytes_32(data, word);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] word = packet_utils::unpack_bytes_32(data, offset);
        label = word[31:12];
        tc    = word[11:9];
        s_bit = word[8];
        ttl   = word[7:0];
    endfunction

    virtual function int get_header_length();
        return 4;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        if (next_proto == PROTO_MPLS)
            s_bit = 0;
        else
            s_bit = 1;
    endfunction

    virtual function protocol_base clone();
        mpls_header h = new();
        h.label     = label;
        h.tc        = tc;
        h.s_bit     = s_bit;
        h.ttl       = ttl;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        mpls_header o;
        if (!$cast(o, other)) return 0;
        return (label == o.label) && (tc == o.tc) && (s_bit == o.s_bit) && (ttl == o.ttl);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  label : %0d\n", label)};
        s = {s, $sformatf("  tc    : %0d\n", tc)};
        s = {s, $sformatf("  s_bit : %0d\n", s_bit)};
        s = {s, $sformatf("  ttl   : %0d\n", ttl)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("MPLS label:%0d tc:%0d s:%0d ttl:%0d", label, tc, s_bit, ttl);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("label", path);
            if (__v != "") label = 20'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("tc", path);
            if (__v != "") tc = 3'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ttl", path);
            if (__v != "") ttl = 8'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (ttl == 0)
            warnings.push_back("MPLS: TTL=0 (packet will be dropped)");
        // Reserved label range 0-15
        if (label <= 15 && label != 0 && label != 3)
            warnings.push_back($sformatf("MPLS: label=%0d is in reserved range (0-15)", label));
    endfunction

endclass

`endif // MPLS_HEADER_SV

// src/protocols/tunnel/ip_in_ip_header.sv
`ifndef IP_IN_IP_HEADER_SV
`define IP_IN_IP_HEADER_SV

`include "protocol_base.sv"

// ============================================================
// IP-in-IP header (RFC 2003): zero-length marker header.
// The outer IPv4 protocol=4 indicates the next layer is another
// IPv4 header.  This class exists so that protocol_graph
// transitions work (IPv4 -> IP_IN_IP -> IPv4).
// ============================================================
class ip_in_ip_header extends protocol_base;

    function new();
        proto_type = PROTO_IP_IN_IP;
    endfunction

    static function ip_in_ip_header create();
        ip_in_ip_header h = new();
        return h;
    endfunction

    virtual function int get_header_length();
        return 0;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // zero-length: nothing to pack
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        // zero-length: nothing to unpack
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        // zero-length: nothing to calculate
    endfunction

    virtual function protocol_base clone();
        ip_in_ip_header h = new();
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ip_in_ip_header o;
        if (!$cast(o, other)) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        return "=== PROTO_IP_IN_IP ===\n  (marker — zero length)\n";
    endfunction

    virtual function string to_brief();
        return "IP-in-IP (marker)";
    endfunction

endclass

`endif // IP_IN_IP_HEADER_SV

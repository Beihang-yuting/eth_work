// src/protocols/tunnel/vxlan_gpe_header.sv
`ifndef VXLAN_GPE_HEADER_SV
`define VXLAN_GPE_HEADER_SV

`include "protocol_base.sv"

// ============================================================
// VXLAN-GPE header (Generic Protocol Extension, RFC 8926): 8 bytes.
// UDP port 4790.  Unlike standard VXLAN, the next_protocol field
// identifies the inner payload type explicitly.
//
// Wire format:
//   Byte 0: flags        [7:0]  — bit3=I, bit2=P, bit1=B, bit0=O
//   Byte 1: reserved1   [7:0]
//   Byte 2: next_protocol[7:0]  — 1=IPv4, 2=IPv6, 3=Eth, 4=NSH, 5=MPLS
//   Byte 3: reserved2   [7:0]
//   Bytes 4-6: vni      [23:0]
//   Byte 7: reserved3   [7:0]
// ============================================================
class vxlan_gpe_header extends protocol_base;

    rand bit [7:0]  flags;
    rand bit [7:0]  reserved1;
    rand bit [7:0]  next_protocol;
    rand bit [7:0]  reserved2;
    rand bit [23:0] vni;
    rand bit [7:0]  reserved3;

    constraint c_default {
        soft flags     == 8'h0C;   // I flag (bit3) + P flag (bit2)
        soft reserved1 == 8'h0;
        soft reserved2 == 8'h0;
        soft reserved3 == 8'h0;
        // next_protocol: exclude values that the parser maps to a known next-layer.
        // calc_fields() overrides with the correct value when a next layer exists.
        soft !(next_protocol inside {8'd1, 8'd2, 8'd3, 8'd5}); // IPv4, IPv6, Ethernet, MPLS
    }

    function new();
        proto_type    = PROTO_VXLAN_GPE;
        flags         = 8'h0C;
        reserved1     = 8'h0;
        next_protocol = 8'd3;   // Ethernet
        reserved2     = 8'h0;
        vni           = 24'd100;
        reserved3     = 8'h0;
    endfunction

    static function vxlan_gpe_header create(bit [23:0] v = 24'd100);
        vxlan_gpe_header h = new();
        h.vni = v;
        return h;
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(flags);
        data.push_back(reserved1);
        data.push_back(next_protocol);
        data.push_back(reserved2);
        data.push_back(vni[23:16]);
        data.push_back(vni[15:8]);
        data.push_back(vni[7:0]);
        data.push_back(reserved3);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        flags         = data[offset]; offset++;
        reserved1     = data[offset]; offset++;
        next_protocol = data[offset]; offset++;
        reserved2     = data[offset]; offset++;
        vni[23:16]    = data[offset]; offset++;
        vni[15:8]     = data[offset]; offset++;
        vni[7:0]      = data[offset]; offset++;
        reserved3     = data[offset]; offset++;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        case (next_proto)
            PROTO_IPV4:     next_protocol = 8'd1;
            PROTO_IPV6:     next_protocol = 8'd2;
            PROTO_ETHERNET: next_protocol = 8'd3;
            PROTO_MPLS:     next_protocol = 8'd5;
            default:        next_protocol = next_protocol;
        endcase
    endfunction

    virtual function protocol_base clone();
        vxlan_gpe_header h = new();
        h.flags         = flags;
        h.reserved1     = reserved1;
        h.next_protocol = next_protocol;
        h.reserved2     = reserved2;
        h.vni           = vni;
        h.reserved3     = reserved3;
        h.auto_calc     = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        vxlan_gpe_header o;
        if (!$cast(o, other)) return 0;
        return (flags == o.flags) && (next_protocol == o.next_protocol) && (vni == o.vni);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  flags        : 0x%02x\n", flags)};
        s = {s, $sformatf("  next_protocol: %0d\n", next_protocol)};
        s = {s, $sformatf("  vni          : %0d\n", vni)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("VXLAN-GPE vni:%0d np:%0d flags:0x%02x", vni, next_protocol, flags);
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // I and P flags should be set
        if (flags[3] != 1)
            errors.push_back($sformatf("VXLAN-GPE: I-bit not set (flags=0x%02x)", flags));
        if (next_protocol == 0 || next_protocol > 5)
            warnings.push_back($sformatf("VXLAN-GPE: next_protocol=%0d out of known range (1-5)", next_protocol));
        if (vni == 0)
            warnings.push_back("VXLAN-GPE: VNI=0");
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("flags", path);
            if (__v != "") flags = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("next_protocol", path);
            if (__v != "") next_protocol = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("vni", path);
            if (__v != "") vni = 24'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // VXLAN_GPE_HEADER_SV

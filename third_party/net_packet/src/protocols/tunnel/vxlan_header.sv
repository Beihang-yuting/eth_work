// src/protocols/tunnel/vxlan_header.sv
`ifndef VXLAN_HEADER_SV
`define VXLAN_HEADER_SV

`include "protocol_base.sv"

class vxlan_header extends protocol_base;

    rand bit [7:0]  flags;
    rand bit [23:0] reserved1;
    rand bit [23:0] vni;
    rand bit [7:0]  reserved2;

    constraint c_default {
        soft flags     == 8'h08;
        soft reserved1 == 24'h0;
        soft reserved2 == 8'h0;
    }

    function new();
        proto_type = PROTO_VXLAN;
        flags      = 8'h08;
        reserved1  = 24'h0;
        vni        = 24'd100;
        reserved2  = 8'h0;
    endfunction

    static function vxlan_header create(bit [23:0] v = 24'd100);
        vxlan_header h = new();
        h.vni = v;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(flags);
        data.push_back(reserved1[23:16]);
        data.push_back(reserved1[15:8]);
        data.push_back(reserved1[7:0]);
        data.push_back(vni[23:16]);
        data.push_back(vni[15:8]);
        data.push_back(vni[7:0]);
        data.push_back(reserved2);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        flags         = data[offset];     offset++;
        reserved1[23:16] = data[offset]; offset++;
        reserved1[15:8]  = data[offset]; offset++;
        reserved1[7:0]   = data[offset]; offset++;
        vni[23:16]    = data[offset];    offset++;
        vni[15:8]     = data[offset];    offset++;
        vni[7:0]      = data[offset];    offset++;
        reserved2     = data[offset];    offset++;
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        flags = 8'h08;
    endfunction

    virtual function protocol_base clone();
        vxlan_header h = new();
        h.flags     = flags;
        h.reserved1 = reserved1;
        h.vni       = vni;
        h.reserved2 = reserved2;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        vxlan_header o;
        if (!$cast(o, other)) return 0;
        return (flags == o.flags) && (vni == o.vni);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  flags    : 0x%02x\n", flags)};
        s = {s, $sformatf("  reserved1: 0x%06x\n", reserved1)};
        s = {s, $sformatf("  vni      : %0d\n", vni)};
        s = {s, $sformatf("  reserved2: 0x%02x\n", reserved2)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("VXLAN vni:%0d flags:0x%02x", vni, flags);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("vni", path);
            if (__v != "") vni = 24'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // I flag (bit 3) must be set per RFC 7348
        if (flags[3] != 1)
            errors.push_back($sformatf("VXLAN: flags=0x%02x, I-bit (bit3) not set (required by RFC 7348)", flags));
        // Reserved fields
        if (reserved1 != 0)
            warnings.push_back($sformatf("VXLAN: reserved1=0x%06x, should be 0", reserved1));
        if (reserved2 != 0)
            warnings.push_back($sformatf("VXLAN: reserved2=0x%02x, should be 0", reserved2));
        // VNI range
        if (vni == 0)
            warnings.push_back("VXLAN: VNI=0");
    endfunction

    static function void help();
        $display("============================================================================");
        $display(" VXLAN Header Guide (RFC 7348)");
        $display("============================================================================");
        $display("");
        $display(" Fields:");
        $display("   flags(8b)    = 0x08 (I-flag set, auto-computed)");
        $display("   vni(24b)     = VXLAN Network Identifier");
        $display("   reserved(32b)= 0 (auto)");
        $display("   UDP dst_port = 4789 (auto-set by calc_fields)");
        $display("");
        $display(" Usage:");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP;");
        $display("       vxlan.vni == 24'd1000;");
        $display("       outer_vlan_num == 1;");
        $display("       outer_vlan[0].vlan_id == 100;");
        $display("   };");
        $display("============================================================================");
    endfunction

endclass

`endif // VXLAN_HEADER_SV

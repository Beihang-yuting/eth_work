// src/protocols/l2/vlan_header.sv
`ifndef VLAN_HEADER_SV
`define VLAN_HEADER_SV

`include "protocol_base.sv"

class vlan_header extends protocol_base;

    rand bit [2:0]  pcp;
    rand bit        dei;
    rand bit [11:0] vlan_id;
    rand bit [15:0] ethertype;

    constraint c_default {
        soft pcp inside {[0:7]};
        soft vlan_id inside {[1:4094]};
        // Ethertype: exclude values that the parser maps to a known next-layer protocol.
        // calc_fields() will override with the correct value when a next layer exists.
        soft !(ethertype inside {16'h0800, 16'h86DD, 16'h0806,   // IPv4, IPv6, ARP
                                  16'h8100, 16'h88A8,              // VLAN, QinQ
                                  16'h8847, 16'h8848,              // MPLS
                                  16'h88F7, 16'h88CC, 16'h88E5});  // PTP, LLDP, MACsec
    }

    function new();
        proto_type = PROTO_VLAN;
        pcp        = 0;
        dei        = 0;
        vlan_id    = 1;
        ethertype  = ETHERTYPE_IPV4;
    endfunction

    static function vlan_header create(bit [11:0] vid = 1, bit [2:0] p = 0,
                                        bit d = 0, bit [15:0] etype = ETHERTYPE_IPV4);
        vlan_header h = new();
        h.vlan_id   = vid;
        h.pcp       = p;
        h.dei       = d;
        h.ethertype = etype;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [15:0] tci = {pcp, dei, vlan_id};
        packet_utils::pack_bytes_16(data, tci);
        packet_utils::pack_bytes_16(data, ethertype);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [15:0] tci = packet_utils::unpack_bytes_16(data, offset);
        pcp     = tci[15:13];
        dei     = tci[12];
        vlan_id = tci[11:0];
        ethertype = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 4;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        case (next_proto)
            PROTO_IPV4:     ethertype = ETHERTYPE_IPV4;
            PROTO_IPV6:     ethertype = ETHERTYPE_IPV6;
            PROTO_ARP:      ethertype = ETHERTYPE_ARP;
            PROTO_VLAN:     ethertype = ETHERTYPE_VLAN;
            PROTO_QINQ:     ethertype = ETHERTYPE_QINQ;
            PROTO_MPLS:     ethertype = ETHERTYPE_MPLS_UNI;
            PROTO_LLDP:     ethertype = ETHERTYPE_LLDP;
            PROTO_PTP:      ethertype = ETHERTYPE_PTP;
            PROTO_MACSEC:   ethertype = ETHERTYPE_MACSEC;
            default: ;
        endcase
    endfunction

    virtual function protocol_base clone();
        vlan_header h = new();
        h.pcp       = pcp;
        h.dei       = dei;
        h.vlan_id   = vlan_id;
        h.ethertype = ethertype;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        vlan_header o;
        if (!$cast(o, other)) return 0;
        return (pcp == o.pcp) && (dei == o.dei) && (vlan_id == o.vlan_id) && (ethertype == o.ethertype);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  pcp      : %0d\n", pcp)};
        s = {s, $sformatf("  dei      : %0d\n", dei)};
        s = {s, $sformatf("  vlan_id  : %0d\n", vlan_id)};
        s = {s, $sformatf("  ethertype: 0x%04x\n", ethertype)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("VLAN %0d pcp:%0d dei:%0d type:0x%04x", vlan_id, pcp, dei, ethertype);
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (vlan_id == 0)
            warnings.push_back("VLAN: vlan_id=0 (reserved)");
        if (vlan_id > 4094)
            errors.push_back($sformatf("VLAN: vlan_id=%0d > 4094", vlan_id));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("vlan_id", path);
            if (__v != "") vlan_id = 12'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("pcp", path);
            if (__v != "") pcp = 3'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // VLAN_HEADER_SV

// src/protocols/l2/eth_header.sv
`ifndef ETH_HEADER_SV
`define ETH_HEADER_SV

`include "protocol_base.sv"

class eth_header extends protocol_base;

    rand bit [47:0] dst_mac;
    rand bit [47:0] src_mac;
    rand bit [15:0] ethertype;

    constraint c_default {
        soft dst_mac inside {[0:48'hFFFFFFFFFFFF]};
        soft src_mac inside {[0:48'hFFFFFFFFFFFF]};
        // Ethertype: exclude values that the parser maps to a known next-layer protocol.
        // calc_fields() will override with the correct value when a next layer exists,
        // but when Ethernet is the last layer the random value must not accidentally
        // match a known protocol ethertype — otherwise the parser will try to decode
        // payload bytes as a protocol header.
        soft !(ethertype inside {16'h0800, 16'h86DD, 16'h0806,   // IPv4, IPv6, ARP
                                  16'h8100, 16'h88A8,              // VLAN, QinQ
                                  16'h8847, 16'h8848,              // MPLS Uni/Multi
                                  16'h88F7, 16'h88CC, 16'h8809,   // PTP, LLDP, LACP/STP
                                  16'h88E5, 16'h888E, 16'h8808}); // MACsec, EAP, MAC_Control
    }

    function new();
        proto_type = PROTO_ETHERNET;
        dst_mac    = 48'h0;
        src_mac    = 48'h0;
        ethertype  = ETHERTYPE_IPV4;
    endfunction

    static function eth_header create(bit [47:0] dst = 0, bit [47:0] src = 0,
                                       bit [15:0] etype = ETHERTYPE_IPV4);
        eth_header h = new();
        h.dst_mac   = dst;
        h.src_mac   = src;
        h.ethertype = etype;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_48(data, dst_mac);
        packet_utils::pack_bytes_48(data, src_mac);
        packet_utils::pack_bytes_16(data, ethertype);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        dst_mac   = packet_utils::unpack_bytes_48(data, offset);
        src_mac   = packet_utils::unpack_bytes_48(data, offset);
        ethertype = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 14;
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
            PROTO_LACP:     ethertype = ETHERTYPE_SLOW;
            PROTO_PTP:      ethertype = ETHERTYPE_PTP;
            PROTO_MACSEC:   ethertype = ETHERTYPE_MACSEC;
            PROTO_EAP:      ethertype = ETHERTYPE_EAP;
            PROTO_STP:      ethertype = 16'h0000;
            PROTO_MAC_CONTROL: ethertype = 16'h8808;
            default: ;
        endcase
    endfunction

    virtual function protocol_base clone();
        eth_header h = new();
        h.dst_mac   = dst_mac;
        h.src_mac   = src_mac;
        h.ethertype = ethertype;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        eth_header o;
        if (!$cast(o, other)) return 0;
        return (dst_mac == o.dst_mac) && (src_mac == o.src_mac) && (ethertype == o.ethertype);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  dst_mac  : %s\n", packet_utils::format_mac(dst_mac))};
        s = {s, $sformatf("  src_mac  : %s\n", packet_utils::format_mac(src_mac))};
        s = {s, $sformatf("  ethertype: 0x%04x\n", ethertype)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%s -> %s type:0x%04x",
                         packet_utils::format_mac(src_mac),
                         packet_utils::format_mac(dst_mac),
                         ethertype);
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // Multicast source MAC
        if (src_mac[40])
            warnings.push_back($sformatf("Ethernet: src_mac %s is multicast (bit 40 set)",
                               packet_utils::format_mac(src_mac)));
        // Zero source MAC
        if (src_mac == 0)
            warnings.push_back("Ethernet: src_mac is all zeros");
        // Unknown ethertype
        if (ethertype < 16'h0600 && ethertype > 16'h05DC)
            warnings.push_back($sformatf("Ethernet: ethertype=0x%04x in undefined range", ethertype));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("dst_mac", path);
            if (__v != "") dst_mac = 48'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("src_mac", path);
            if (__v != "") src_mac = 48'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // ETH_HEADER_SV

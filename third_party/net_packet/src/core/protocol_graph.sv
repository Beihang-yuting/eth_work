// src/core/protocol_graph.sv
`ifndef PROTOCOL_GRAPH_SV
`define PROTOCOL_GRAPH_SV

`include "packet_defines.sv"

class protocol_graph;

    protected protocol_type_e legal_next[protocol_type_e][$];

    function new();
        init_default_transitions();
    endfunction

    function void register_transition(protocol_type_e from, protocol_type_e to);
        // Duplicate-safe: only add if not already present
        foreach (legal_next[from][i]) begin
            if (legal_next[from][i] == to) return;
        end
        legal_next[from].push_back(to);
    endfunction

    function bit is_valid_next(protocol_type_e from, protocol_type_e to);
        if (!legal_next.exists(from)) return 0;
        foreach (legal_next[from][i]) begin
            if (legal_next[from][i] == to) return 1;
        end
        return 0;
    endfunction

    function void get_valid_next(protocol_type_e from, ref protocol_type_e result[$]);
        result.delete();
        if (legal_next.exists(from)) begin
            result = legal_next[from];
        end
    endfunction

    function bit validate_chain(protocol_type_e chain[$]);
        if (chain.size() <= 1) return 1;
        for (int i = 0; i < int'(chain.size()) - 1; i++) begin
            if (!is_valid_next(chain[i], chain[i+1])) return 0;
        end
        return 1;
    endfunction

    protected function void init_default_transitions();
        // Ethernet -> {IPv4, IPv6, ARP, VLAN, QinQ, MPLS, LLDP, LACP, STP, MACsec, EAP, MAC_Control, PTP}
        register_transition(PROTO_ETHERNET, PROTO_IPV4);
        register_transition(PROTO_ETHERNET, PROTO_IPV6);
        register_transition(PROTO_ETHERNET, PROTO_ARP);
        register_transition(PROTO_ETHERNET, PROTO_VLAN);
        register_transition(PROTO_ETHERNET, PROTO_QINQ);
        register_transition(PROTO_ETHERNET, PROTO_MPLS);
        register_transition(PROTO_ETHERNET, PROTO_LLDP);
        register_transition(PROTO_ETHERNET, PROTO_LACP);
        register_transition(PROTO_ETHERNET, PROTO_STP);
        register_transition(PROTO_ETHERNET, PROTO_MACSEC);
        register_transition(PROTO_ETHERNET, PROTO_EAP);
        register_transition(PROTO_ETHERNET, PROTO_MAC_CONTROL);
        register_transition(PROTO_ETHERNET, PROTO_PTP);

        // VLAN -> {IPv4, IPv6, ARP, VLAN, MPLS}
        register_transition(PROTO_VLAN, PROTO_IPV4);
        register_transition(PROTO_VLAN, PROTO_IPV6);
        register_transition(PROTO_VLAN, PROTO_ARP);
        register_transition(PROTO_VLAN, PROTO_VLAN);
        register_transition(PROTO_VLAN, PROTO_MPLS);

        // QinQ -> {VLAN, QinQ, IPv4, IPv6}
        register_transition(PROTO_QINQ, PROTO_VLAN);
        register_transition(PROTO_QINQ, PROTO_QINQ);  // multi-layer S-VLAN stacking
        register_transition(PROTO_QINQ, PROTO_IPV4);
        register_transition(PROTO_QINQ, PROTO_IPV6);

        // IPv4 -> {TCP, UDP, ICMP, IGMP, GRE, IP_IN_IP, OSPF, SCTP}
        register_transition(PROTO_IPV4, PROTO_TCP);
        register_transition(PROTO_IPV4, PROTO_UDP);
        register_transition(PROTO_IPV4, PROTO_ICMP);
        register_transition(PROTO_IPV4, PROTO_IGMP);
        register_transition(PROTO_IPV4, PROTO_GRE);
        register_transition(PROTO_IPV4, PROTO_IP_IN_IP);
        register_transition(PROTO_IPV4, PROTO_OSPF);
        register_transition(PROTO_IPV4, PROTO_SCTP);

        // IPv6 -> {TCP, UDP, ICMPv6, HBH, Routing, Fragment, Dest, GRE, OSPF, SCTP}
        register_transition(PROTO_IPV6, PROTO_TCP);
        register_transition(PROTO_IPV6, PROTO_UDP);
        register_transition(PROTO_IPV6, PROTO_ICMPV6);
        register_transition(PROTO_IPV6, PROTO_IPV6_HBH);
        register_transition(PROTO_IPV6, PROTO_IPV6_ROUTING);
        register_transition(PROTO_IPV6, PROTO_IPV6_FRAGMENT);
        register_transition(PROTO_IPV6, PROTO_IPV6_DEST);
        register_transition(PROTO_IPV6, PROTO_GRE);
        register_transition(PROTO_IPV6, PROTO_OSPF);
        register_transition(PROTO_IPV6, PROTO_SCTP);

        // IPv6_HBH -> {Routing, Fragment, Dest, TCP, UDP, ICMPv6}
        register_transition(PROTO_IPV6_HBH, PROTO_IPV6_ROUTING);
        register_transition(PROTO_IPV6_HBH, PROTO_IPV6_FRAGMENT);
        register_transition(PROTO_IPV6_HBH, PROTO_IPV6_DEST);
        register_transition(PROTO_IPV6_HBH, PROTO_TCP);
        register_transition(PROTO_IPV6_HBH, PROTO_UDP);
        register_transition(PROTO_IPV6_HBH, PROTO_ICMPV6);

        // IPv6_Routing -> {Fragment, Dest, TCP, UDP, ICMPv6}
        register_transition(PROTO_IPV6_ROUTING, PROTO_IPV6_FRAGMENT);
        register_transition(PROTO_IPV6_ROUTING, PROTO_IPV6_DEST);
        register_transition(PROTO_IPV6_ROUTING, PROTO_TCP);
        register_transition(PROTO_IPV6_ROUTING, PROTO_UDP);
        register_transition(PROTO_IPV6_ROUTING, PROTO_ICMPV6);

        // IPv6_Fragment -> {TCP, UDP, ICMPv6, Dest}
        register_transition(PROTO_IPV6_FRAGMENT, PROTO_TCP);
        register_transition(PROTO_IPV6_FRAGMENT, PROTO_UDP);
        register_transition(PROTO_IPV6_FRAGMENT, PROTO_ICMPV6);
        register_transition(PROTO_IPV6_FRAGMENT, PROTO_IPV6_DEST);

        // IPv6_Dest -> {TCP, UDP, ICMPv6}
        register_transition(PROTO_IPV6_DEST, PROTO_TCP);
        register_transition(PROTO_IPV6_DEST, PROTO_UDP);
        register_transition(PROTO_IPV6_DEST, PROTO_ICMPV6);

        // UDP -> {VXLAN, Geneve, GTP_U, GTP_C, MPLS_UDP, DNS, DHCP, DHCPv6, BFD, RoCEv2, SNMP, PTP, RAW_PAYLOAD}
        register_transition(PROTO_UDP, PROTO_VXLAN);
        register_transition(PROTO_UDP, PROTO_GENEVE);
        register_transition(PROTO_UDP, PROTO_GTP_U);
        register_transition(PROTO_UDP, PROTO_GTP_C);
        register_transition(PROTO_UDP, PROTO_MPLS_UDP);
        register_transition(PROTO_UDP, PROTO_DNS);
        register_transition(PROTO_UDP, PROTO_DHCP);
        register_transition(PROTO_UDP, PROTO_DHCPV6);
        register_transition(PROTO_UDP, PROTO_BFD);
        register_transition(PROTO_UDP, PROTO_ROCEV2);
        register_transition(PROTO_UDP, PROTO_SNMP);
        register_transition(PROTO_UDP, PROTO_PTP);
        register_transition(PROTO_UDP, PROTO_RAW_PAYLOAD);

        // TCP -> {HTTP, iWARP, NVMe_TCP, iSCSI, BGP, DNS, RAW_PAYLOAD}
        register_transition(PROTO_TCP, PROTO_HTTP);
        register_transition(PROTO_TCP, PROTO_IWARP);
        register_transition(PROTO_TCP, PROTO_NVME_TCP);
        register_transition(PROTO_TCP, PROTO_ISCSI);
        register_transition(PROTO_TCP, PROTO_BGP);
        register_transition(PROTO_TCP, PROTO_DNS);
        register_transition(PROTO_TCP, PROTO_RAW_PAYLOAD);

        // VXLAN -> {Ethernet}
        register_transition(PROTO_VXLAN, PROTO_ETHERNET);

        // GRE -> {IPv4, IPv6, Ethernet, ERSPAN_I, ERSPAN_II, ERSPAN_III, MPLS_GRE}
        register_transition(PROTO_GRE, PROTO_IPV4);
        register_transition(PROTO_GRE, PROTO_IPV6);
        register_transition(PROTO_GRE, PROTO_ETHERNET);
        register_transition(PROTO_GRE, PROTO_ERSPAN_I);
        register_transition(PROTO_GRE, PROTO_ERSPAN_II);
        register_transition(PROTO_GRE, PROTO_ERSPAN_III);
        register_transition(PROTO_GRE, PROTO_MPLS_GRE);

        // Geneve -> {Ethernet}
        register_transition(PROTO_GENEVE, PROTO_ETHERNET);

        // NVGRE -> {Ethernet}
        register_transition(PROTO_NVGRE, PROTO_ETHERNET);

        // ERSPAN_II -> {Ethernet}
        register_transition(PROTO_ERSPAN_II, PROTO_ETHERNET);

        // ERSPAN_III -> {Ethernet}
        register_transition(PROTO_ERSPAN_III, PROTO_ETHERNET);

        // GTP_U -> {IPv4, IPv6}
        register_transition(PROTO_GTP_U, PROTO_IPV4);
        register_transition(PROTO_GTP_U, PROTO_IPV6);

        // L2TP -> {IPv4, IPv6}
        register_transition(PROTO_L2TP, PROTO_IPV4);
        register_transition(PROTO_L2TP, PROTO_IPV6);

        // RoCEv2 -> {NVMe_RDMA, RAW_PAYLOAD}
        register_transition(PROTO_ROCEV2, PROTO_NVME_RDMA);
        register_transition(PROTO_ROCEV2, PROTO_RAW_PAYLOAD);

        // MPLS -> {IPv4, IPv6, Ethernet, MPLS}
        register_transition(PROTO_MPLS, PROTO_IPV4);
        register_transition(PROTO_MPLS, PROTO_IPV6);
        register_transition(PROTO_MPLS, PROTO_ETHERNET);
        register_transition(PROTO_MPLS, PROTO_MPLS);

        // VXLAN-GPE -> {IPv4, IPv6, Ethernet, MPLS}
        register_transition(PROTO_VXLAN_GPE, PROTO_IPV4);
        register_transition(PROTO_VXLAN_GPE, PROTO_IPV6);
        register_transition(PROTO_VXLAN_GPE, PROTO_ETHERNET);
        register_transition(PROTO_VXLAN_GPE, PROTO_MPLS);

        // UDP -> VXLAN_GPE
        register_transition(PROTO_UDP, PROTO_VXLAN_GPE);

        // IPv4/IPv6 -> ESP
        register_transition(PROTO_IPV4, PROTO_ESP);
        register_transition(PROTO_IPV6, PROTO_ESP);
    endfunction

endclass

`endif // PROTOCOL_GRAPH_SV

// src/core/packet.sv
`ifndef PACKET_SV
`define PACKET_SV

`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "l2/eth_header.sv"
`include "l2/vlan_header.sv"
`include "l3/ipv4_header.sv"
`include "l3/ipv6_header.sv"
`include "l3/arp_header.sv"
`include "l4/tcp_header.sv"
`include "l4/udp_header.sv"
`include "l4/icmp_header.sv"
`include "l4/igmp_header.sv"
`include "l2/lldp_header.sv"
`include "l2/lacp_header.sv"
`include "l2/stp_header.sv"
`include "l2/mac_control_header.sv"
`include "l4/dhcp_header.sv"
`include "l4/dhcpv6_header.sv"
`include "l4/dns_header.sv"
`include "l4/bfd_header.sv"
`include "rdma/nvme_rdma_header.sv"
`include "l4/icmpv6_header.sv"
`include "tunnel/vxlan_header.sv"
`include "tunnel/gre_header.sv"
`include "tunnel/geneve_header.sv"
`include "tunnel/erspan_header.sv"
`include "tunnel/gtp_header.sv"
`include "tunnel/ip_in_ip_header.sv"
`include "rdma/rocev2_header.sv"
`include "rdma/iwarp_header.sv"
`include "storage/nvme_tcp_header.sv"
`include "storage/iscsi_header.sv"
`include "l2/mpls_header.sv"
`include "l3/ipv6_ext_header.sv"
`include "l4/sctp_header.sv"
`include "app/ptp_header.sv"
`include "tunnel/vxlan_gpe_header.sv"
`include "tunnel/esp_header.sv"
`include "core/protocol_graph.sv"
`include "core/template_registry.sv"

class packet;

    // ----- Layer stack -----
    protocol_base layer_stack[$];

    // ----- Raw data (result of do_pack) -----
    byte unsigned raw_data[$];

    // ----- Instance control -----
    bit              force_mode        = 0;
    payload_mode_e   payload_mode      = PAYLOAD_RANDOM;
    byte unsigned    payload_fixed_val = 8'h00;
    byte unsigned    payload_pattern[$];

    // ----- Custom chain for abnormal/error packets -----
    protected protocol_type_e custom_chain[$];
    protected bit              use_custom_chain = 0;

    // ----- Rand header pools (pre-allocated for single-call randomize) -----
    rand packet_template_e pkt_kind;
    rand pkt_category_e    pkt_rand_kind;
    rand int unsigned      pkt_len;

    // L2: outer/inner for tunnel scenarios; non-tunnel uses outer_xxx
    rand eth_header        outer_eth, inner_eth;
    rand vlan_header       outer_vlan[4];   // Up to 4 VLAN tags after outer Ethernet
    rand int unsigned      outer_vlan_num;  // Number of outer VLAN tags (0-4)
    rand vlan_header       inner_vlan[4];   // Up to 4 VLAN tags after inner Ethernet (tunnel)
    rand int unsigned      inner_vlan_num;  // Number of inner VLAN tags (0-4)
    rand mpls_header       outer_mpls, inner_mpls;
    // L3
    rand ipv4_header       outer_ipv4, inner_ipv4;
    rand ipv6_header       outer_ipv6, inner_ipv6;
    rand arp_header        arp;
    // L4
    rand tcp_header        tcp;
    rand udp_header        outer_udp, inner_udp;
    rand icmp_header       icmp;
    rand igmp_header       igmp;
    rand lldp_header       lldp;
    rand lacp_header       lacp;
    rand stp_header        stp;
    rand mac_control_header mac_control;
    rand dhcp_header       dhcp;
    rand dhcpv6_header     dhcpv6;
    rand dns_header        dns;
    rand bfd_header        bfd;
    rand nvme_rdma_header  nvme_rdma;
    rand icmpv6_header     icmpv6;
    rand sctp_header       sctp;
    // Tunnel
    rand vxlan_header      vxlan;
    rand gre_header        gre;
    rand geneve_header     geneve;
    rand gtp_u_header      gtp_u;
    rand erspan_ii_header  erspan_ii;
    rand erspan_iii_header erspan_iii;
    rand vxlan_gpe_header  vxlan_gpe;
    rand esp_header        esp;
    rand ip_in_ip_header   ip_in_ip;
    // RDMA
    rand rocev2_bth        rocev2;
    rand iwarp_header      iwarp;
    // Storage
    rand nvme_tcp_header   nvme_tcp;
    rand iscsi_header      iscsi;
    // App
    rand ptp_header        ptp;

    constraint c_pkt_len {
        soft pkt_len inside {[64:1518]};
    }

    constraint c_vlan_num {
        soft outer_vlan_num == 0;
        outer_vlan_num inside {[0:4]};
        soft inner_vlan_num == 0;
        inner_vlan_num inside {[0:4]};
    }

    constraint c_pkt_category {
        soft pkt_rand_kind == PKT_CAT_ALL;

        if (pkt_rand_kind == PKT_CAT_ALL) {
            // 所有模板的协议头均已实现, 无需排除 — 任意 pkt_kind 均可建
        }

        if (pkt_rand_kind == PKT_CAT_BASIC) {
            pkt_kind inside {ETH_IPV4_TCP, ETH_IPV4_UDP, ETH_IPV4_ICMP, ETH_IPV4_SCTP,
                             ETH_IPV6_TCP, ETH_IPV6_UDP, ETH_IPV6_ICMPV6, ETH_IPV6_SCTP,
                             ETH_ARP, ETH_IPV4_IGMP};
        }

        // --- L4 categories ---

        if (pkt_rand_kind == PKT_CAT_TCP) {
            pkt_kind inside {
                // Basic
                ETH_IPV4_TCP, ETH_IPV6_TCP,
                // MPLS
                ETH_MPLS_IPV4_TCP, ETH_MPLS_IPV6_TCP,
                // VXLAN
                ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV6_TCP,
                // Geneve
                ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV6_TCP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV6_TCP,
                // GRE L3
                ETH_IPV4_GRE_IPV4_TCP, ETH_IPV4_GRE_IPV6_TCP,
                ETH_IPV6_GRE_IPV4_TCP, ETH_IPV6_GRE_IPV6_TCP,
                // NVGRE
                ETH_IPV4_GRE_ETH_IPV4_TCP, ETH_IPV4_GRE_ETH_IPV6_TCP,
                ETH_IPV6_GRE_ETH_IPV4_TCP, ETH_IPV6_GRE_ETH_IPV6_TCP,
                // GTP-U
                ETH_IPV4_UDP_GTP_U_IPV4_TCP, ETH_IPV4_UDP_GTP_U_IPV6_TCP,
                ETH_IPV6_UDP_GTP_U_IPV4_TCP, ETH_IPV6_UDP_GTP_U_IPV6_TCP,
                // ERSPAN
                ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_TCP,
                ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_TCP,
                // VXLAN-GPE
                ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_TCP, ETH_IPV6_UDP_VXLAN_GPE_ETH_IPV4_TCP,
                ETH_IPV4_UDP_VXLAN_GPE_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_IPV6_TCP,
                // Storage over TCP
                ETH_IPV4_TCP_NVME_TCP, ETH_IPV6_TCP_NVME_TCP,
                ETH_IPV4_TCP_ISCSI, ETH_IPV6_TCP_ISCSI,
                ETH_IPV4_TCP_IWARP, ETH_IPV6_TCP_IWARP
            };
        }

        if (pkt_rand_kind == PKT_CAT_UDP) {
            pkt_kind inside {
                // Basic
                ETH_IPV4_UDP, ETH_IPV6_UDP,
                // MPLS
                ETH_MPLS_IPV4_UDP, ETH_MPLS_IPV6_UDP,
                // VXLAN (all have outer UDP)
                ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP,
                ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV6_UDP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV4_UDP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV6_UDP,
                // Geneve (all have outer UDP)
                ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP,
                ETH_IPV4_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV6_UDP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV4_UDP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV6_UDP,
                // GRE L3 (inner UDP)
                ETH_IPV4_GRE_IPV4_UDP, ETH_IPV4_GRE_IPV6_UDP,
                ETH_IPV6_GRE_IPV4_UDP, ETH_IPV6_GRE_IPV6_UDP,
                // NVGRE (inner UDP)
                ETH_IPV4_GRE_ETH_IPV4_UDP, ETH_IPV4_GRE_ETH_IPV6_UDP,
                ETH_IPV6_GRE_ETH_IPV4_UDP, ETH_IPV6_GRE_ETH_IPV6_UDP,
                // GTP-U (all have outer UDP)
                ETH_IPV4_UDP_GTP_U_IPV4_TCP, ETH_IPV4_UDP_GTP_U_IPV4_UDP,
                ETH_IPV4_UDP_GTP_U_IPV6_TCP, ETH_IPV4_UDP_GTP_U_IPV6_UDP,
                ETH_IPV6_UDP_GTP_U_IPV4_TCP, ETH_IPV6_UDP_GTP_U_IPV4_UDP,
                ETH_IPV6_UDP_GTP_U_IPV6_TCP, ETH_IPV6_UDP_GTP_U_IPV6_UDP,
                // ERSPAN (inner UDP)
                ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_UDP, ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_UDP,
                ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_UDP, ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_UDP,
                // VXLAN-GPE (all have outer UDP)
                ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_UDP,
                ETH_IPV6_UDP_VXLAN_GPE_ETH_IPV4_TCP,
                ETH_IPV4_UDP_VXLAN_GPE_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_IPV6_TCP,
                // RDMA
                ETH_IPV4_UDP_ROCEV2, ETH_IPV6_UDP_ROCEV2,
                ETH_IPV4_UDP_ROCEV2_NVME_RDMA, ETH_IPV6_UDP_ROCEV2_NVME_RDMA,
                // Mgmt
                ETH_IPV4_UDP_DHCP, ETH_IPV6_UDP_DHCPV6,
                ETH_IPV4_UDP_DNS, ETH_IPV4_UDP_BFD, ETH_IPV4_UDP_PTP
            };
        }

        if (pkt_rand_kind == PKT_CAT_ICMP) {
            pkt_kind inside {ETH_IPV4_ICMP, ETH_IPV6_ICMPV6,
                             ETH_MPLS_IPV4_ICMP, ETH_MPLS_IPV6_ICMPV6};
        }

        if (pkt_rand_kind == PKT_CAT_SCTP) {
            pkt_kind inside {ETH_IPV4_SCTP, ETH_IPV6_SCTP,
                             ETH_MPLS_IPV4_SCTP, ETH_MPLS_IPV6_SCTP};
        }

        // --- L3 categories (outer) ---

        if (pkt_rand_kind == PKT_CAT_OUTER_IPV4) {
            pkt_kind inside {
                // Basic
                ETH_IPV4_TCP, ETH_IPV4_UDP, ETH_IPV4_ICMP, ETH_IPV4_SCTP,
                ETH_IPV4_IGMP,
                // MPLS IPv4
                ETH_MPLS_IPV4_TCP, ETH_MPLS_IPV4_UDP, ETH_MPLS_IPV4_ICMP, ETH_MPLS_IPV4_SCTP,
                // ESP
                ETH_IPV4_ESP,
                // VXLAN outer IPv4
                ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP,
                ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV6_UDP,
                // Geneve outer IPv4
                ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP,
                ETH_IPV4_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV6_UDP,
                // GRE L3 outer IPv4
                ETH_IPV4_GRE_IPV4_TCP, ETH_IPV4_GRE_IPV4_UDP,
                ETH_IPV4_GRE_IPV6_TCP, ETH_IPV4_GRE_IPV6_UDP,
                // NVGRE outer IPv4
                ETH_IPV4_GRE_ETH_IPV4_TCP, ETH_IPV4_GRE_ETH_IPV4_UDP,
                ETH_IPV4_GRE_ETH_IPV6_TCP, ETH_IPV4_GRE_ETH_IPV6_UDP,
                // GTP-U outer IPv4
                ETH_IPV4_UDP_GTP_U_IPV4_TCP, ETH_IPV4_UDP_GTP_U_IPV4_UDP,
                ETH_IPV4_UDP_GTP_U_IPV6_TCP, ETH_IPV4_UDP_GTP_U_IPV6_UDP,
                // ERSPAN outer IPv4
                ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_UDP,
                ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_UDP,
                // VXLAN-GPE outer IPv4
                ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_UDP,
                ETH_IPV4_UDP_VXLAN_GPE_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_IPV6_TCP,
                // RDMA
                ETH_IPV4_UDP_ROCEV2, ETH_IPV4_UDP_ROCEV2_NVME_RDMA,
                // Storage
                ETH_IPV4_TCP_NVME_TCP, ETH_IPV4_TCP_ISCSI, ETH_IPV4_TCP_IWARP,
                // Mgmt
                ETH_IPV4_UDP_DHCP, ETH_IPV4_UDP_DNS, ETH_IPV4_UDP_BFD, ETH_IPV4_UDP_PTP
            };
        }

        if (pkt_rand_kind == PKT_CAT_OUTER_IPV6) {
            pkt_kind inside {
                // Basic
                ETH_IPV6_TCP, ETH_IPV6_UDP, ETH_IPV6_ICMPV6, ETH_IPV6_SCTP,
                // MPLS IPv6
                ETH_MPLS_IPV6_TCP, ETH_MPLS_IPV6_UDP, ETH_MPLS_IPV6_ICMPV6, ETH_MPLS_IPV6_SCTP,
                // ESP
                ETH_IPV6_ESP,
                // VXLAN outer IPv6
                ETH_IPV6_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV4_UDP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV6_UDP,
                // Geneve outer IPv6
                ETH_IPV6_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV4_UDP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV6_UDP,
                // GRE L3 outer IPv6
                ETH_IPV6_GRE_IPV4_TCP, ETH_IPV6_GRE_IPV4_UDP,
                ETH_IPV6_GRE_IPV6_TCP, ETH_IPV6_GRE_IPV6_UDP,
                // NVGRE outer IPv6
                ETH_IPV6_GRE_ETH_IPV4_TCP, ETH_IPV6_GRE_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ETH_IPV6_TCP, ETH_IPV6_GRE_ETH_IPV6_UDP,
                // GTP-U outer IPv6
                ETH_IPV6_UDP_GTP_U_IPV4_TCP, ETH_IPV6_UDP_GTP_U_IPV4_UDP,
                ETH_IPV6_UDP_GTP_U_IPV6_TCP, ETH_IPV6_UDP_GTP_U_IPV6_UDP,
                // ERSPAN outer IPv6
                ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_UDP,
                // VXLAN-GPE outer IPv6
                ETH_IPV6_UDP_VXLAN_GPE_ETH_IPV4_TCP,
                // RDMA
                ETH_IPV6_UDP_ROCEV2, ETH_IPV6_UDP_ROCEV2_NVME_RDMA,
                // Storage
                ETH_IPV6_TCP_NVME_TCP, ETH_IPV6_TCP_ISCSI, ETH_IPV6_TCP_IWARP,
                // Mgmt
                ETH_IPV6_UDP_DHCPV6
            };
        }

        // --- L3 categories (inner, tunnel only) ---

        if (pkt_rand_kind == PKT_CAT_INNER_IPV4) {
            pkt_kind inside {
                // VXLAN inner IPv4
                ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV4_UDP,
                // Geneve inner IPv4
                ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV4_UDP,
                // GRE L3 inner IPv4
                ETH_IPV4_GRE_IPV4_TCP, ETH_IPV4_GRE_IPV4_UDP,
                ETH_IPV6_GRE_IPV4_TCP, ETH_IPV6_GRE_IPV4_UDP,
                // NVGRE inner IPv4
                ETH_IPV4_GRE_ETH_IPV4_TCP, ETH_IPV4_GRE_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ETH_IPV4_TCP, ETH_IPV6_GRE_ETH_IPV4_UDP,
                // GTP-U inner IPv4
                ETH_IPV4_UDP_GTP_U_IPV4_TCP, ETH_IPV4_UDP_GTP_U_IPV4_UDP,
                ETH_IPV6_UDP_GTP_U_IPV4_TCP, ETH_IPV6_UDP_GTP_U_IPV4_UDP,
                // ERSPAN inner IPv4 (all ERSPAN have inner IPv4)
                ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_UDP,
                ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_UDP,
                // VXLAN-GPE inner IPv4
                ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_UDP,
                ETH_IPV6_UDP_VXLAN_GPE_ETH_IPV4_TCP,
                ETH_IPV4_UDP_VXLAN_GPE_IPV4_TCP
            };
        }

        if (pkt_rand_kind == PKT_CAT_INNER_IPV6) {
            pkt_kind inside {
                // VXLAN inner IPv6
                ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV6_UDP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV6_UDP,
                // Geneve inner IPv6
                ETH_IPV4_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV6_UDP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV6_UDP,
                // GRE L3 inner IPv6
                ETH_IPV4_GRE_IPV6_TCP, ETH_IPV4_GRE_IPV6_UDP,
                ETH_IPV6_GRE_IPV6_TCP, ETH_IPV6_GRE_IPV6_UDP,
                // NVGRE inner IPv6
                ETH_IPV4_GRE_ETH_IPV6_TCP, ETH_IPV4_GRE_ETH_IPV6_UDP,
                ETH_IPV6_GRE_ETH_IPV6_TCP, ETH_IPV6_GRE_ETH_IPV6_UDP,
                // GTP-U inner IPv6
                ETH_IPV4_UDP_GTP_U_IPV6_TCP, ETH_IPV4_UDP_GTP_U_IPV6_UDP,
                ETH_IPV6_UDP_GTP_U_IPV6_TCP, ETH_IPV6_UDP_GTP_U_IPV6_UDP,
                // VXLAN-GPE inner IPv6
                ETH_IPV4_UDP_VXLAN_GPE_IPV6_TCP
            };
        }

        // --- Tunnel categories ---

        if (pkt_rand_kind == PKT_CAT_TUNNEL) {
            pkt_kind inside {
                // VXLAN
                ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP,
                ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV6_UDP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV4_UDP,
                ETH_IPV6_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV6_UDP,
                // Geneve
                ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP,
                ETH_IPV4_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV6_UDP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV4_UDP,
                ETH_IPV6_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV6_UDP,
                // GRE L3
                ETH_IPV4_GRE_IPV4_TCP, ETH_IPV4_GRE_IPV4_UDP,
                ETH_IPV4_GRE_IPV6_TCP, ETH_IPV4_GRE_IPV6_UDP,
                ETH_IPV6_GRE_IPV4_TCP, ETH_IPV6_GRE_IPV4_UDP,
                ETH_IPV6_GRE_IPV6_TCP, ETH_IPV6_GRE_IPV6_UDP,
                // NVGRE
                ETH_IPV4_GRE_ETH_IPV4_TCP, ETH_IPV4_GRE_ETH_IPV4_UDP,
                ETH_IPV4_GRE_ETH_IPV6_TCP, ETH_IPV4_GRE_ETH_IPV6_UDP,
                ETH_IPV6_GRE_ETH_IPV4_TCP, ETH_IPV6_GRE_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ETH_IPV6_TCP, ETH_IPV6_GRE_ETH_IPV6_UDP,
                // GTP-U
                ETH_IPV4_UDP_GTP_U_IPV4_TCP, ETH_IPV4_UDP_GTP_U_IPV4_UDP,
                ETH_IPV4_UDP_GTP_U_IPV6_TCP, ETH_IPV4_UDP_GTP_U_IPV6_UDP,
                ETH_IPV6_UDP_GTP_U_IPV4_TCP, ETH_IPV6_UDP_GTP_U_IPV4_UDP,
                ETH_IPV6_UDP_GTP_U_IPV6_TCP, ETH_IPV6_UDP_GTP_U_IPV6_UDP,
                // ERSPAN
                ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_UDP,
                ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_UDP,
                ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_UDP,
                // VXLAN-GPE
                ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_UDP,
                ETH_IPV6_UDP_VXLAN_GPE_ETH_IPV4_TCP,
                ETH_IPV4_UDP_VXLAN_GPE_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_IPV6_TCP
            };
        }

        if (pkt_rand_kind == PKT_CAT_VXLAN) {
            pkt_kind inside {ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP,
                             ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV4_UDP_VXLAN_ETH_IPV6_UDP,
                             ETH_IPV6_UDP_VXLAN_ETH_IPV4_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV4_UDP,
                             ETH_IPV6_UDP_VXLAN_ETH_IPV6_TCP, ETH_IPV6_UDP_VXLAN_ETH_IPV6_UDP};
        }

        if (pkt_rand_kind == PKT_CAT_GRE) {
            pkt_kind inside {ETH_IPV4_GRE_IPV4_TCP, ETH_IPV4_GRE_IPV4_UDP,
                             ETH_IPV4_GRE_IPV6_TCP, ETH_IPV4_GRE_IPV6_UDP,
                             ETH_IPV6_GRE_IPV4_TCP, ETH_IPV6_GRE_IPV4_UDP,
                             ETH_IPV6_GRE_IPV6_TCP, ETH_IPV6_GRE_IPV6_UDP};
        }

        if (pkt_rand_kind == PKT_CAT_GENEVE) {
            pkt_kind inside {ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP,
                             ETH_IPV4_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV4_UDP_GENEVE_ETH_IPV6_UDP,
                             ETH_IPV6_UDP_GENEVE_ETH_IPV4_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV4_UDP,
                             ETH_IPV6_UDP_GENEVE_ETH_IPV6_TCP, ETH_IPV6_UDP_GENEVE_ETH_IPV6_UDP};
        }

        if (pkt_rand_kind == PKT_CAT_GTP) {
            pkt_kind inside {ETH_IPV4_UDP_GTP_U_IPV4_TCP, ETH_IPV4_UDP_GTP_U_IPV4_UDP,
                             ETH_IPV4_UDP_GTP_U_IPV6_TCP, ETH_IPV4_UDP_GTP_U_IPV6_UDP,
                             ETH_IPV6_UDP_GTP_U_IPV4_TCP, ETH_IPV6_UDP_GTP_U_IPV4_UDP,
                             ETH_IPV6_UDP_GTP_U_IPV6_TCP, ETH_IPV6_UDP_GTP_U_IPV6_UDP};
        }

        if (pkt_rand_kind == PKT_CAT_ERSPAN) {
            pkt_kind inside {ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_UDP,
                             ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_UDP,
                             ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_UDP,
                             ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_TCP, ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_UDP};
        }

        if (pkt_rand_kind == PKT_CAT_NVGRE) {
            pkt_kind inside {ETH_IPV4_GRE_ETH_IPV4_TCP, ETH_IPV4_GRE_ETH_IPV4_UDP,
                             ETH_IPV4_GRE_ETH_IPV6_TCP, ETH_IPV4_GRE_ETH_IPV6_UDP,
                             ETH_IPV6_GRE_ETH_IPV4_TCP, ETH_IPV6_GRE_ETH_IPV4_UDP,
                             ETH_IPV6_GRE_ETH_IPV6_TCP, ETH_IPV6_GRE_ETH_IPV6_UDP};
        }

        // --- Application categories ---

        if (pkt_rand_kind == PKT_CAT_ROCEV2) {
            pkt_kind inside {ETH_IPV4_UDP_ROCEV2, ETH_IPV6_UDP_ROCEV2,
                             ETH_IPV4_UDP_ROCEV2_NVME_RDMA, ETH_IPV6_UDP_ROCEV2_NVME_RDMA};
        }

        if (pkt_rand_kind == PKT_CAT_STORAGE) {
            pkt_kind inside {ETH_IPV4_TCP_NVME_TCP, ETH_IPV6_TCP_NVME_TCP,
                             ETH_IPV4_TCP_ISCSI, ETH_IPV6_TCP_ISCSI,
                             ETH_IPV4_TCP_IWARP, ETH_IPV6_TCP_IWARP,
                             ETH_IPV4_UDP_ROCEV2_NVME_RDMA, ETH_IPV6_UDP_ROCEV2_NVME_RDMA};
        }

        if (pkt_rand_kind == PKT_CAT_MPLS) {
            pkt_kind inside {ETH_MPLS_IPV4_TCP, ETH_MPLS_IPV4_UDP,
                             ETH_MPLS_IPV4_ICMP, ETH_MPLS_IPV4_SCTP,
                             ETH_MPLS_IPV6_TCP, ETH_MPLS_IPV6_UDP,
                             ETH_MPLS_IPV6_ICMPV6, ETH_MPLS_IPV6_SCTP};
        }

        if (pkt_rand_kind == PKT_CAT_MGMT) {
            pkt_kind inside {ETH_IPV4_UDP_DHCP, ETH_IPV6_UDP_DHCPV6,
                             ETH_IPV4_UDP_DNS, ETH_IPV4_UDP_BFD, ETH_IPV4_UDP_PTP,
                             ETH_PTP_L2, ETH_LLDP, ETH_LACP, ETH_STP, ETH_MAC_CONTROL};
        }

        if (pkt_rand_kind == PKT_CAT_ESP) {
            pkt_kind inside {ETH_IPV4_ESP, ETH_IPV6_ESP};
        }

        if (pkt_rand_kind == PKT_CAT_VXLAN_GPE) {
            pkt_kind inside {ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_UDP,
                             ETH_IPV6_UDP_VXLAN_GPE_ETH_IPV4_TCP,
                             ETH_IPV4_UDP_VXLAN_GPE_IPV4_TCP, ETH_IPV4_UDP_VXLAN_GPE_IPV6_TCP};
        }
    }

    // ----- Shared static instances -----
    static protocol_graph    s_graph    = new();
    static template_registry s_registry = new();

    // =========================================================================
    // Constructor — pre-allocate all rand header pools
    // =========================================================================
    function new();
        outer_eth    = new(); inner_eth    = new();
        foreach (outer_vlan[i]) outer_vlan[i] = new();
        foreach (inner_vlan[i]) inner_vlan[i] = new();
        outer_vlan_num = 0;
        inner_vlan_num = 0;
        outer_mpls   = new(); inner_mpls   = new();
        outer_ipv4   = new(); inner_ipv4   = new();
        outer_ipv6   = new(); inner_ipv6   = new();
        outer_udp    = new(); inner_udp    = new();
        arp          = new();
        tcp          = new();
        icmp         = new();
        igmp         = new();
        lldp         = new();
        lacp         = new();
        stp          = new();
        mac_control  = new();
        dhcp         = new();
        dhcpv6       = new();
        dns          = new();
        bfd          = new();
        nvme_rdma    = new();
        icmpv6       = new();
        sctp         = new();
        vxlan        = new();
        gre          = new();
        geneve       = new();
        gtp_u        = new();
        erspan_ii    = new();
        erspan_iii   = new();
        vxlan_gpe    = new();
        esp          = new();
        ip_in_ip     = new();
        rocev2       = new();
        iwarp        = new();
        nvme_tcp     = new();
        iscsi        = new();
        ptp          = new();
        pkt_kind     = ETH_IPV4_TCP;
    endfunction

    // =========================================================================
    // set_chain — specify custom protocol chain for abnormal/error packets
    // Accepts a string using the same naming as templates.
    // Overrides pkt_kind when set. Call before randomize().
    //
    // Usage:
    //   pkt.set_chain("ETH_ETH_IPV4");        // double Ethernet
    //   pkt.set_chain("ETH_TCP");              // skip IP layer
    //   pkt.set_chain("ETH_IPV4_IPV4_TCP");   // double IPv4
    //   pkt.set_chain("ETH_IPV4_UDP_VXLAN_ETH_IPV6_SCTP");  // custom tunnel
    // =========================================================================
    function void set_chain(string chain_str);
        custom_chain     = s_registry.parse_template_name(chain_str);
        use_custom_chain = 1;
        force_mode       = 1;
        if (custom_chain.size() == 0)
            $warning("packet::set_chain: failed to parse '%s'", chain_str);
    endfunction

    // clear_chain — revert to pkt_kind template mode
    function void clear_chain();
        custom_chain.delete();
        use_custom_chain = 0;
        force_mode       = 0;
    endfunction

    // =========================================================================
    // help — print usage guide for packet construction
    // Call: packet::help();
    // =========================================================================
    static function void help();
        $display("============================================================================");
        $display(" Net Packet Generator — Usage Guide");
        $display("============================================================================");
        $display("");
        $display(" 1. BASIC USAGE (single randomize call):");
        $display("    packet pkt = new();");
        $display("    pkt.randomize() with {");
        $display("        pkt_kind == ETH_IPV4_TCP;");
        $display("        outer_ipv4.src_addr == 32'hC0A80001;");
        $display("        tcp.dst_port == 16'd80;");
        $display("        pkt_len inside {[64:1518]};");
        $display("    };");
        $display("");
        $display(" 2. TUNNEL PACKET:");
        $display("    pkt.randomize() with {");
        $display("        pkt_kind == ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP;");
        $display("        outer_ipv4.src_addr == 32'hC0A80001;");
        $display("        vxlan.vni == 24'd1000;");
        $display("        inner_ipv4.src_addr == 32'h0A000001;");
        $display("        tcp.dst_port == 16'd80;");
        $display("    };");
        $display("");
        $display(" 3. VLAN CONTROL (no template needed):");
        $display("    pkt.randomize() with {");
        $display("        pkt_kind == ETH_IPV4_TCP;");
        $display("        outer_vlan_num == 2;              // QinQ");
        $display("        outer_vlan[0].vlan_id == 100;     // S-VLAN");
        $display("        outer_vlan[1].vlan_id == 200;     // C-VLAN");
        $display("    };");
        $display("");
        $display(" 4. CATEGORY RANDOM (test all TCP packets):");
        $display("    pkt.randomize() with {");
        $display("        pkt_rand_kind == PKT_CAT_TCP;     // random from all TCP templates");
        $display("    };");
        $display("");
        $display(" 5. RDMA (RoCEv2):");
        $display("    pkt.randomize() with {");
        $display("        pkt_kind == ETH_IPV4_UDP_ROCEV2;");
        $display("        rocev2.opcode       == RC_RDMA_WRITE_ONLY;");
        $display("        rocev2.dest_qp      == 24'h000100;");
        $display("        rocev2.reth_va      == 64'hDEAD_BEEF_0000_0000;");
        $display("        rocev2.reth_r_key   == 32'h1234;");
        $display("        rocev2.reth_dma_len == 32'd4096;");
        $display("    };");
        $display("    // Call rocev2_bth::help() for full opcode table");
        $display("");
        $display(" 6. ERROR/ABNORMAL PACKET:");
        $display("    Call packet::help_error_packet() for full error packet guide");
        $display("");
        $display("    Call packet::help_options() for full options control guide");
        $display("");
        $display(" 7. ACCESS FIELDS:");
        $display("    outer_eth / inner_eth         — Ethernet (outer/inner)");
        $display("    outer_ipv4 / inner_ipv4       — IPv4 (outer/inner)");
        $display("    outer_ipv6 / inner_ipv6       — IPv6 (outer/inner)");
        $display("    outer_udp / inner_udp         — UDP (outer/inner)");
        $display("    tcp, arp, icmp, sctp          — L4 (single instance)");
        $display("    vxlan, gre, geneve, gtp_u     — Tunnel headers");
        $display("    erspan_ii, erspan_iii, esp     — Tunnel/security");
        $display("    rocev2, iwarp                  — RDMA");
        $display("    nvme_tcp, iscsi                — Storage");
        $display("    outer_vlan[0..3]               — Outer VLAN tags");
        $display("    inner_vlan[0..3]               — Inner VLAN tags");
        $display("    outer_vlan_num / inner_vlan_num — VLAN tag count (0-4)");
        $display("    pkt_len                        — Total packet length");
        $display("");
        $display(" 8. CATEGORIES (pkt_rand_kind):");
        $display("    PKT_CAT_ALL         — all templates");
        $display("    PKT_CAT_BASIC       — non-tunnel basic");
        $display("    PKT_CAT_TCP/UDP/ICMP/SCTP  — by L4 type");
        $display("    PKT_CAT_OUTER_IPV4/IPV6    — by outer L3");
        $display("    PKT_CAT_INNER_IPV4/IPV6    — by inner L3 (tunnel)");
        $display("    PKT_CAT_TUNNEL      — all tunnels");
        $display("    PKT_CAT_VXLAN/GRE/GENEVE/GTP/ERSPAN/NVGRE/VXLAN_GPE");
        $display("    PKT_CAT_ROCEV2/STORAGE/MPLS/MGMT/ESP");
        $display("");
        $display(" 9. TEMPLATE LIST (pkt_kind):");
        begin
            packet_template_e t = t.first();
            forever begin
                $display("    %s = %0d", t.name(), t);
                if (t == t.last()) break;
                t = t.next();
            end
        end
        $display("============================================================================");
    endfunction

    // =========================================================================
    // help_error_packet — print guide for constructing abnormal/error packets
    // Call: packet::help_error_packet();
    // =========================================================================
    static function void help_error_packet();
        $display("============================================================================");
        $display(" Error/Abnormal Packet Construction Guide (set_chain)");
        $display("============================================================================");
        $display("");
        $display(" set_chain(string) lets you construct ANY protocol combination,");
        $display(" including invalid/abnormal ones not in the template library.");
        $display(" Protocol graph validation is automatically bypassed (force_mode=1).");
        $display(" All calc_fields still run — checksums, lengths, ethertypes auto-computed.");
        $display("");
        $display(" Syntax: pkt.set_chain(\"TOKEN1_TOKEN2_TOKEN3_...\");");
        $display("         pkt.randomize() with { ... };");
        $display("         pkt.clear_chain();  // revert to normal template mode");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Category 1: Missing Layer (skip required protocol layer)");
        $display(" -----------------------------------------------------------------------");
        $display("   pkt.set_chain(\"ETH_TCP\");              // skip IP → test L2 forwarding");
        $display("   pkt.randomize() with { tcp.dst_port == 80; pkt_len == 64; };");
        $display("");
        $display("   pkt.set_chain(\"ETH_UDP\");              // skip IP → malformed UDP");
        $display("   pkt.randomize() with { outer_udp.dst_port == 4789; pkt_len == 64; };");
        $display("");
        $display("   pkt.set_chain(\"ETH_VXLAN_ETH_IPV4_TCP\"); // skip outer IP+UDP");
        $display("   pkt.randomize() with { vxlan.vni == 100; pkt_len == 128; };");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Category 2: Duplicate Layer (same protocol appears multiple times)");
        $display(" -----------------------------------------------------------------------");
        $display("   pkt.set_chain(\"ETH_ETH_IPV4_TCP\");     // double Ethernet");
        $display("   pkt.randomize() with { outer_ipv4.ttl == 1; pkt_len == 80; };");
        $display("");
        $display("   pkt.set_chain(\"ETH_IPV4_IPV4_TCP\");    // double IPv4");
        $display("   pkt.randomize() with {");
        $display("       outer_ipv4.src_addr == 32'hC0A80001;");
        $display("       inner_ipv4.src_addr == 32'h0A000001;");
        $display("       pkt_len == 100;");
        $display("   };");
        $display("");
        $display("   pkt.set_chain(\"ETH_IPV4_TCP_TCP\");     // double TCP");
        $display("   pkt.randomize() with { pkt_len == 100; };");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Category 3: Wrong Layer Order (protocol at wrong position)");
        $display(" -----------------------------------------------------------------------");
        $display("   pkt.set_chain(\"TCP_ETH_IPV4\");         // TCP before Ethernet");
        $display("   pkt.randomize() with { pkt_len == 80; };");
        $display("");
        $display("   pkt.set_chain(\"ETH_GRE_IPV4_TCP\");     // GRE without outer IP");
        $display("   pkt.randomize() with { gre.k_flag == 1; pkt_len == 100; };");
        $display("");
        $display("   pkt.set_chain(\"ETH_IPV4_VXLAN_TCP\");   // VXLAN without UDP");
        $display("   pkt.randomize() with { vxlan.vni == 500; pkt_len == 100; };");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Category 4: Unsupported/Unusual Combinations");
        $display(" -----------------------------------------------------------------------");
        $display("   pkt.set_chain(\"ETH_IPV4_UDP_VXLAN_ETH_IPV6_SCTP\"); // non-standard inner");
        $display("   pkt.randomize() with { vxlan.vni == 2000; pkt_len == 256; };");
        $display("");
        $display("   pkt.set_chain(\"ETH_IPV6_GRE_IPV4_UDP_VXLAN_ETH_IPV4_TCP\"); // double tunnel");
        $display("   pkt.randomize() with { pkt_len == 300; };");
        $display("");
        $display("   pkt.set_chain(\"ETH_IPV4_ESP_IPV4_TCP\"); // ESP + inner packet");
        $display("   pkt.randomize() with { esp.spi == 32'h1234; pkt_len == 200; };");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Category 5: Abnormal Field Values (use soft constraint override)");
        $display(" -----------------------------------------------------------------------");
        $display("   // These work with both templates AND set_chain:");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_TCP;");
        $display("       outer_ipv4.version == 5;         // invalid IP version");
        $display("       outer_ipv4.ihl == 3;             // IHL too small");
        $display("       outer_ipv4.ttl == 0;             // zero TTL");
        $display("       tcp.data_offset == 2;            // data_offset too small");
        $display("       pkt_len == 20;                   // shorter than headers");
        $display("   };");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Category 6: VLAN Abnormal");
        $display(" -----------------------------------------------------------------------");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_TCP;");
        $display("       outer_vlan_num == 4;             // 4-layer VLAN stacking");
        $display("       outer_vlan[0].vlan_id == 0;      // reserved VLAN ID");
        $display("       outer_vlan[1].vlan_id == 4095;   // reserved VLAN ID");
        $display("       pkt_len == 100;");
        $display("   };");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Available Tokens for set_chain:");
        $display(" -----------------------------------------------------------------------");
        $display("   L2:     ETH, MPLS");
        $display("   L3:     IPV4, IPV6, ARP");
        $display("   L4:     TCP, UDP, ICMP, ICMPV6, SCTP, IGMP");
        $display("   Tunnel: VXLAN, GRE, GENEVE, GTP_U, ERSPAN_II, ERSPAN_III,");
        $display("           VXLAN_GPE, ESP, IP_IN_IP");
        $display("   RDMA:   ROCEV2, IWARP");
        $display("   Store:  NVME_TCP, NVME_RDMA, ISCSI");
        $display("   App:    PTP, DNS, DHCP, DHCPV6, BFD");
        $display("   L2 Ctl: LLDP, LACP, STP, MAC_CONTROL, MACSEC, EAP");
        $display("");
        $display(" Note: calc_fields still auto-computes all possible fields.");
        $display("       Fields without a valid parent (e.g. TCP checksum without IP)");
        $display("       will be set to 0 — which is itself a valid error condition.");
        $display("============================================================================");
    endfunction

    // =========================================================================
    // help_options — print guide for protocol options control
    // Call: packet::help_options();
    // =========================================================================
    static function void help_options();
        $display("============================================================================");
        $display(" Protocol Options Control Guide");
        $display("============================================================================");
        $display(" All options use rand enable/value fields with soft defaults.");
        $display(" Enable via randomize() with {}, no helper functions needed.");
        $display(" Soft constraints allow override for error/abnormal testing.");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" TCP Options (tcp.opt_xxx)");
        $display(" -----------------------------------------------------------------------");
        $display("   tcp.opt_mss_en       == 1;       // MSS (Kind=2, 4B)");
        $display("   tcp.opt_mss_val      == 16'd1460; // soft default: 1460");
        $display("");
        $display("   tcp.opt_wscale_en    == 1;       // Window Scale (Kind=3, 3B)");
        $display("   tcp.opt_wscale_val   == 8'd7;    // soft default: 0~14");
        $display("");
        $display("   tcp.opt_sack_perm_en == 1;       // SACK Permitted (Kind=4, 2B)");
        $display("");
        $display("   tcp.opt_ts_en        == 1;       // Timestamps (Kind=8, 10B)");
        $display("   tcp.opt_ts_val       == 32'h1234; // TSval");
        $display("   tcp.opt_ts_ecr       == 32'h0;    // TSecr");
        $display("");
        $display("   // SYN packet with full options:");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_TCP;");
        $display("       tcp.flags[1] == 1;  // SYN");
        $display("       tcp.opt_mss_en == 1; tcp.opt_wscale_en == 1;");
        $display("       tcp.opt_sack_perm_en == 1; tcp.opt_ts_en == 1;");
        $display("   };");
        $display("   // auto: options[] built, data_offset updated, padded to 4B");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" IPv4 Options (outer_ipv4.opt_xxx / inner_ipv4.opt_xxx)");
        $display(" -----------------------------------------------------------------------");
        $display("   outer_ipv4.opt_rr_en     == 1;    // Record Route (Type=7)");
        $display("   outer_ipv4.opt_rr_slots  == 9;    // soft default: 1~9 slots");
        $display("");
        $display("   outer_ipv4.opt_ts_en     == 1;    // Timestamp (Type=68)");
        $display("   outer_ipv4.opt_ts_slots  == 4;    // soft default: 1~4 slots");
        $display("");
        $display("   outer_ipv4.opt_lsr_en    == 1;    // Loose Source Route (Type=131)");
        $display("   outer_ipv4.opt_lsr_count == 3;    // 1~4 addresses");
        $display("   outer_ipv4.opt_lsr_addrs[0] == 32'hC0A80001;");
        $display("   outer_ipv4.opt_lsr_addrs[1] == 32'hC0A80002;");
        $display("   outer_ipv4.opt_lsr_addrs[2] == 32'hC0A80003;");
        $display("   // auto: ihl updated, checksum recalculated");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" GRE Options (gre.xxx_flag)");
        $display(" -----------------------------------------------------------------------");
        $display("   gre.c_flag == 1;                  // Checksum (auto-computed)");
        $display("   gre.k_flag == 1;                  // Key");
        $display("   gre.key    == 32'hDEAD_BEEF;");
        $display("   gre.s_flag == 1;                  // Sequence Number");
        $display("   gre.sequence_number == 32'd1;");
        $display("   // header: 4B(base) + 4B*flags = 4~16B");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Geneve TLV Options (geneve.opt_xxx)");
        $display(" -----------------------------------------------------------------------");
        $display("   geneve.opt_en     == 1;           // Enable TLV generation");
        $display("   geneve.opt_num    == 2;           // 1~3 TLV options");
        $display("   geneve.opt_class0 == 16'h0100;    // Option 0: class");
        $display("   geneve.opt_type0  == 7'd1;        // Option 0: type");
        $display("   geneve.opt_data0  == 32'hAABBCCDD; // Option 0: 4B data");
        $display("   geneve.opt_class1 == 16'h0100;    // Option 1: class");
        $display("   geneve.opt_type1  == 7'd2;        // Option 1: type");
        $display("   geneve.opt_data1  == 32'h11223344; // Option 1: data");
        $display("   // auto: opt_len computed, each TLV = 8 bytes");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" GTP-U Extension Header (gtp_u.xxx)");
        $display(" -----------------------------------------------------------------------");
        $display("   gtp_u.e_flag             == 1;    // Enable extension header");
        $display("   gtp_u.next_ext_hdr_type  == 8'h85; // PDU Session Container");
        $display("   gtp_u.ext_hdr_data[0]    == 8'h01; // Extension content");
        $display("   // Common next_ext_hdr_type: 0x85=PDU Session, 0x84=NR RAN,");
        $display("   //   0x81=RAN Container, 0xC0=PDCP PDU Number");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" IPv6 Hop-by-Hop Options (via set_chain)");
        $display(" -----------------------------------------------------------------------");
        $display("   // HBH requires set_chain or add_layer:");
        $display("   pkt.set_chain(\"ETH_IPV6_HBH_TCP\");");
        $display("   pkt.randomize() with { ... };");
        $display("   // Then access via layer_stack:");
        $display("   ipv6_hbh_header hbh;");
        $display("   $cast(hbh, pkt.layer_stack[2]);");
        $display("   hbh.opt_router_alert_en  = 1;     // Router Alert (Type=5)");
        $display("   hbh.opt_router_alert_val = 0;     // 0=MLD, 1=RSVP");
        $display("   hbh.opt_jumbo_en         = 1;     // Jumbo Payload (Type=0xC2)");
        $display("   hbh.opt_jumbo_len        = 32'd100000;");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" RoCEv2 Extended Headers (rocev2.opcode driven)");
        $display(" -----------------------------------------------------------------------");
        $display("   rocev2.opcode == RC_RDMA_WRITE_ONLY;  // auto: +RETH(16B)");
        $display("   rocev2.opcode == RC_RDMA_WRITE_ONLY_IMM; // auto: +RETH+ImmDt");
        $display("   rocev2.opcode == RC_CMP_SWAP;         // auto: +AtomicETH(28B)");
        $display("   rocev2.opcode == RC_ATOMIC_ACK;       // auto: +AETH+AtomicAckETH");
        $display("   rocev2.opcode == UD_SEND_ONLY;        // auto: +DETH(8B)");
        $display("   // Call rocev2_bth::help() for full opcode table");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" Error Testing (override soft defaults)");
        $display(" -----------------------------------------------------------------------");
        $display("   tcp.opt_mss_val     == 0;         // invalid MSS");
        $display("   tcp.opt_wscale_val  == 20;        // invalid scale > 14");
        $display("   outer_ipv4.opt_rr_slots == 0;     // invalid 0 slots");
        $display("   gtp_u.next_ext_hdr_type == 8'hFF; // unknown ext type");
        $display("   // All soft constraints — override freely, no conflict");
        $display("");
        $display(" -----------------------------------------------------------------------");
        $display(" All Help Functions");
        $display(" -----------------------------------------------------------------------");
        $display("   packet::help()              — General usage guide");
        $display("   packet::help_options()      — This guide (options control)");
        $display("   packet::help_error_packet() — Error packet construction");
        $display("   tcp_header::help()          — TCP options detail");
        $display("   ipv4_header::help()         — IPv4 options detail");
        $display("   geneve_header::help()       — Geneve TLV detail");
        $display("   gre_header::help()          — GRE optional fields");
        $display("   gtp_u_header::help()        — GTP-U extension headers");
        $display("   vxlan_header::help()        — VXLAN usage");
        $display("   rocev2_bth::help()          — RoCEv2 opcode table");
        $display("   ip_fragment::help()         — IP fragmentation");
        $display("   tcp_segment::help()         — TCP segmentation (TSO)");
        $display("============================================================================");
    endfunction

    // =========================================================================
    // post_randomize — auto-build layer_stack from pkt_kind/custom_chain,
    //                  then auto do_pack() so raw_data is ready immediately
    // =========================================================================
    function void post_randomize();
        protocol_type_e chain[$];
        int eth_idx = 0, mpls_idx = 0;
        int ipv4_idx = 0, ipv6_idx = 0, udp_idx = 0;
        bit first_eth_done = 0;

        // Custom chain (error packets) takes priority over pkt_kind (templates)
        if (use_custom_chain && custom_chain.size() > 0)
            chain = custom_chain;
        else
            s_registry.get_chain(pkt_kind, chain);
        layer_stack.delete();

        foreach (chain[i]) begin
            case (chain[i])
                PROTO_ETHERNET: begin
                    layer_stack.push_back(eth_idx == 0 ? outer_eth : inner_eth);
                    // Insert VLAN tags after this Ethernet layer
                    begin
                        int cur_vlan_num = (eth_idx == 0) ? outer_vlan_num : inner_vlan_num;
                        for (int v = 0; v < cur_vlan_num && v < 4; v++) begin
                            vlan_header vh = (eth_idx == 0) ? outer_vlan[v] : inner_vlan[v];
                            // Multi-VLAN: non-last VLANs are S-VLAN (QinQ ethertype)
                            if (cur_vlan_num > 1 && v < cur_vlan_num - 1) begin
                                vh.proto_type = PROTO_QINQ;
                                vh.ethertype  = ETHERTYPE_VLAN;
                            end else begin
                                vh.proto_type = PROTO_VLAN;
                            end
                            layer_stack.push_back(vh);
                        end
                    end
                    eth_idx++;
                end
                PROTO_VLAN, PROTO_QINQ: begin
                    // Skip — VLAN is now handled by vlan_num insertion above
                end
                PROTO_MPLS: begin
                    layer_stack.push_back(mpls_idx == 0 ? outer_mpls : inner_mpls);
                    mpls_idx++;
                end
                PROTO_IPV4: begin
                    layer_stack.push_back(ipv4_idx == 0 ? outer_ipv4 : inner_ipv4);
                    ipv4_idx++;
                end
                PROTO_IPV6: begin
                    layer_stack.push_back(ipv6_idx == 0 ? outer_ipv6 : inner_ipv6);
                    ipv6_idx++;
                end
                PROTO_UDP: begin
                    layer_stack.push_back(udp_idx == 0 ? outer_udp : inner_udp);
                    udp_idx++;
                end
                PROTO_ARP:         layer_stack.push_back(arp);
                PROTO_TCP:         layer_stack.push_back(tcp);
                PROTO_ICMP:        layer_stack.push_back(icmp);
                PROTO_IGMP:        layer_stack.push_back(igmp);
                PROTO_LLDP:        layer_stack.push_back(lldp);
                PROTO_LACP:        layer_stack.push_back(lacp);
                PROTO_STP:         layer_stack.push_back(stp);
                PROTO_MAC_CONTROL: layer_stack.push_back(mac_control);
                PROTO_DHCP:        layer_stack.push_back(dhcp);
                PROTO_DHCPV6:      layer_stack.push_back(dhcpv6);
                PROTO_DNS:         layer_stack.push_back(dns);
                PROTO_BFD:         layer_stack.push_back(bfd);
                PROTO_NVME_RDMA:   layer_stack.push_back(nvme_rdma);
                PROTO_ICMPV6:      layer_stack.push_back(icmpv6);
                PROTO_SCTP:        layer_stack.push_back(sctp);
                PROTO_VXLAN:       layer_stack.push_back(vxlan);
                PROTO_GRE:         layer_stack.push_back(gre);
                PROTO_GENEVE:      layer_stack.push_back(geneve);
                PROTO_GTP_U:       layer_stack.push_back(gtp_u);
                PROTO_ERSPAN_II:   layer_stack.push_back(erspan_ii);
                PROTO_ERSPAN_III:  layer_stack.push_back(erspan_iii);
                PROTO_VXLAN_GPE:   layer_stack.push_back(vxlan_gpe);
                PROTO_ESP:         layer_stack.push_back(esp);
                PROTO_IP_IN_IP:    layer_stack.push_back(ip_in_ip);
                PROTO_ROCEV2:      layer_stack.push_back(rocev2);
                PROTO_IWARP:       layer_stack.push_back(iwarp);
                PROTO_NVME_TCP:    layer_stack.push_back(nvme_tcp);
                PROTO_ISCSI:       layer_stack.push_back(iscsi);
                PROTO_PTP:         layer_stack.push_back(ptp);
                default: begin
                    $warning("packet::post_randomize: unsupported protocol %s in template %s",
                             chain[i].name(), pkt_kind.name());
                end
            endcase
        end

        // Auto-pack
        do_pack();
    endfunction

    // =========================================================================
    // Factory: create_header
    // =========================================================================
    static function protocol_base create_header(protocol_type_e proto);
        case (proto)
            PROTO_ETHERNET: begin
                eth_header h = new();
                return h;
            end
            PROTO_VLAN: begin
                vlan_header h = new();
                return h;
            end
            PROTO_QINQ: begin
                vlan_header h = new();
                h.proto_type = PROTO_QINQ;
                h.ethertype  = ETHERTYPE_VLAN;
                return h;
            end
            PROTO_IPV4: begin
                ipv4_header h = new();
                return h;
            end
            PROTO_IPV6: begin
                ipv6_header h = new();
                return h;
            end
            PROTO_ARP: begin
                arp_header h = new();
                return h;
            end
            PROTO_TCP: begin
                tcp_header h = new();
                return h;
            end
            PROTO_UDP: begin
                udp_header h = new();
                return h;
            end
            PROTO_ICMP: begin
                icmp_header h = new();
                return h;
            end
            PROTO_IGMP: begin
                igmp_header h = new();
                return h;
            end
            PROTO_LLDP: begin
                lldp_header h = new();
                return h;
            end
            PROTO_LACP: begin
                lacp_header h = new();
                return h;
            end
            PROTO_STP: begin
                stp_header h = new();
                return h;
            end
            PROTO_MAC_CONTROL: begin
                mac_control_header h = new();
                return h;
            end
            PROTO_DHCP: begin
                dhcp_header h = new();
                return h;
            end
            PROTO_DHCPV6: begin
                dhcpv6_header h = new();
                return h;
            end
            PROTO_DNS: begin
                dns_header h = new();
                return h;
            end
            PROTO_BFD: begin
                bfd_header h = new();
                return h;
            end
            PROTO_NVME_RDMA: begin
                nvme_rdma_header h = new();
                return h;
            end
            PROTO_ICMPV6: begin
                icmpv6_header h = new();
                return h;
            end
            PROTO_VXLAN: begin
                vxlan_header h = new();
                return h;
            end
            PROTO_GRE: begin
                gre_header h = new();
                return h;
            end
            PROTO_GENEVE: begin
                geneve_header h = new();
                return h;
            end
            PROTO_ERSPAN_II: begin
                erspan_ii_header h = new();
                return h;
            end
            PROTO_ERSPAN_III: begin
                erspan_iii_header h = new();
                return h;
            end
            PROTO_GTP_U: begin
                gtp_u_header h = new();
                return h;
            end
            PROTO_IP_IN_IP: begin
                ip_in_ip_header h = new();
                return h;
            end
            PROTO_ROCEV2: begin
                rocev2_bth h = new();
                return h;
            end
            PROTO_IWARP: begin
                iwarp_header h = new();
                return h;
            end
            PROTO_NVME_TCP: begin
                nvme_tcp_header h = new();
                return h;
            end
            PROTO_ISCSI: begin
                iscsi_header h = new();
                return h;
            end
            PROTO_MPLS: begin
                mpls_header h = new();
                return h;
            end
            PROTO_IPV6_HBH: begin
                ipv6_hbh_header h = new();
                return h;
            end
            PROTO_IPV6_ROUTING: begin
                ipv6_routing_header h = new();
                return h;
            end
            PROTO_IPV6_FRAGMENT: begin
                ipv6_fragment_header h = new();
                return h;
            end
            PROTO_IPV6_DEST: begin
                ipv6_dest_header h = new();
                return h;
            end
            PROTO_SCTP: begin
                sctp_header h = new();
                return h;
            end
            PROTO_PTP: begin
                ptp_header h = new();
                return h;
            end
            PROTO_VXLAN_GPE: begin
                vxlan_gpe_header h = new();
                return h;
            end
            PROTO_ESP: begin
                esp_header h = new();
                return h;
            end
            default: return null;
        endcase
    endfunction

    // =========================================================================
    // build_from_template
    // =========================================================================
    function void build_from_template(packet_template_e tmpl);
        protocol_type_e chain[$];
        s_registry.get_chain(tmpl, chain);
        layer_stack.delete();
        foreach (chain[i]) begin
            protocol_base hdr = create_header(chain[i]);
            if (hdr != null) begin
                layer_stack.push_back(hdr);
            end else begin
                $warning("packet::build_from_template: unsupported protocol %s in template %s",
                         chain[i].name(), tmpl.name());
            end
        end
    endfunction

    // =========================================================================
    // add_layer
    // =========================================================================
    function bit add_layer(protocol_base layer);
        if (layer == null) return 0;
        if (!force_mode && layer_stack.size() > 0) begin
            protocol_type_e prev = layer_stack[layer_stack.size()-1].proto_type;
            if (!s_graph.is_valid_next(prev, layer.proto_type)) begin
                $warning("packet::add_layer: invalid transition %s -> %s (use force_mode to override)",
                         prev.name(), layer.proto_type.name());
                return 0;
            end
        end
        layer_stack.push_back(layer);
        return 1;
    endfunction

    // =========================================================================
    // get_layer — returns first matching layer or null
    // =========================================================================
    function protocol_base get_layer(protocol_type_e proto);
        foreach (layer_stack[i]) begin
            if (layer_stack[i].proto_type == proto) return layer_stack[i];
        end
        return null;
    endfunction

    // =========================================================================
    // get_all_layers
    // =========================================================================
    function void get_all_layers(ref protocol_base layers[$]);
        layers = layer_stack;
    endfunction

    // =========================================================================
    // Typed layer accessors — no $cast needed
    // idx=0 returns first instance, idx=1 returns second, etc.
    // Returns null if not found.
    // =========================================================================

    protected function protocol_base get_layer_n(protocol_type_e proto, int idx = 0);
        int count = 0;
        foreach (layer_stack[i]) begin
            if (layer_stack[i].proto_type == proto) begin
                if (count == idx) return layer_stack[i];
                count++;
            end
        end
        return null;
    endfunction

    function eth_header get_eth(int idx = 0);
        eth_header h;
        protocol_base p = get_layer_n(PROTO_ETHERNET, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function vlan_header get_vlan(int idx = 0);
        vlan_header h;
        protocol_base p = get_layer_n(PROTO_VLAN, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function mpls_header get_mpls(int idx = 0);
        mpls_header h;
        protocol_base p = get_layer_n(PROTO_MPLS, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function ipv4_header get_ipv4(int idx = 0);
        ipv4_header h;
        protocol_base p = get_layer_n(PROTO_IPV4, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function ipv6_header get_ipv6(int idx = 0);
        ipv6_header h;
        protocol_base p = get_layer_n(PROTO_IPV6, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function arp_header get_arp(int idx = 0);
        arp_header h;
        protocol_base p = get_layer_n(PROTO_ARP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function tcp_header get_tcp(int idx = 0);
        tcp_header h;
        protocol_base p = get_layer_n(PROTO_TCP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function udp_header get_udp(int idx = 0);
        udp_header h;
        protocol_base p = get_layer_n(PROTO_UDP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function icmp_header get_icmp(int idx = 0);
        icmp_header h;
        protocol_base p = get_layer_n(PROTO_ICMP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function icmpv6_header get_icmpv6(int idx = 0);
        icmpv6_header h;
        protocol_base p = get_layer_n(PROTO_ICMPV6, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function sctp_header get_sctp(int idx = 0);
        sctp_header h;
        protocol_base p = get_layer_n(PROTO_SCTP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function vxlan_header get_vxlan(int idx = 0);
        vxlan_header h;
        protocol_base p = get_layer_n(PROTO_VXLAN, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function gre_header get_gre(int idx = 0);
        gre_header h;
        protocol_base p = get_layer_n(PROTO_GRE, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function geneve_header get_geneve(int idx = 0);
        geneve_header h;
        protocol_base p = get_layer_n(PROTO_GENEVE, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function gtp_u_header get_gtp_u(int idx = 0);
        gtp_u_header h;
        protocol_base p = get_layer_n(PROTO_GTP_U, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function erspan_ii_header get_erspan_ii(int idx = 0);
        erspan_ii_header h;
        protocol_base p = get_layer_n(PROTO_ERSPAN_II, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function erspan_iii_header get_erspan_iii(int idx = 0);
        erspan_iii_header h;
        protocol_base p = get_layer_n(PROTO_ERSPAN_III, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function vxlan_gpe_header get_vxlan_gpe(int idx = 0);
        vxlan_gpe_header h;
        protocol_base p = get_layer_n(PROTO_VXLAN_GPE, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function esp_header get_esp(int idx = 0);
        esp_header h;
        protocol_base p = get_layer_n(PROTO_ESP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function rocev2_bth get_rocev2(int idx = 0);
        rocev2_bth h;
        protocol_base p = get_layer_n(PROTO_ROCEV2, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function iwarp_header get_iwarp(int idx = 0);
        iwarp_header h;
        protocol_base p = get_layer_n(PROTO_IWARP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function nvme_tcp_header get_nvme_tcp(int idx = 0);
        nvme_tcp_header h;
        protocol_base p = get_layer_n(PROTO_NVME_TCP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function iscsi_header get_iscsi(int idx = 0);
        iscsi_header h;
        protocol_base p = get_layer_n(PROTO_ISCSI, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    function ptp_header get_ptp(int idx = 0);
        ptp_header h;
        protocol_base p = get_layer_n(PROTO_PTP, idx);
        if (p != null) $cast(h, p);
        return h;
    endfunction

    // =========================================================================
    // get_all_headers_length
    // =========================================================================
    function int get_all_headers_length();
        int total = 0;
        foreach (layer_stack[i]) begin
            total += layer_stack[i].get_header_length();
        end
        return total;
    endfunction

    // =========================================================================
    // randomize_all — randomize every layer with its built-in constraints
    // =========================================================================
    function void randomize_all();
        foreach (layer_stack[i]) begin
            if (!layer_stack[i].randomize())
                $warning("packet::randomize_all: randomize failed for layer %0d (%s)",
                         i, layer_stack[i].proto_type.name());
        end
    endfunction

    // =========================================================================
    // do_pack
    // =========================================================================
    function void do_pack();
        int headers_len;
        int payload_len;
        byte unsigned payload[$];

        headers_len = get_all_headers_length();

        // Determine payload length
        if (pkt_len == 0) begin
            payload_len = 0;
        end else if (pkt_len > headers_len) begin
            payload_len = pkt_len - headers_len;
        end else if (pkt_len == headers_len) begin
            payload_len = 0;
        end else begin
            $warning("packet::do_pack: pkt_len (%0d) < headers_length (%0d), no payload generated",
                     pkt_len, headers_len);
            payload_len = 0;
        end

        // Generate payload
        payload.delete();
        for (int i = 0; i < payload_len; i++) begin
            case (payload_mode)
                PAYLOAD_RANDOM:    payload.push_back($urandom_range(0, 255));
                PAYLOAD_FIXED:     payload.push_back(payload_fixed_val);
                PAYLOAD_INCREMENT: payload.push_back(i % 256);
                PAYLOAD_PATTERN: begin
                    if (payload_pattern.size() > 0)
                        payload.push_back(payload_pattern[i % payload_pattern.size()]);
                    else
                        payload.push_back(8'h00);
                end
            endcase
        end

        // calc_fields: innermost to outermost
        // For layer[i], remaining_data = packed(layer[i+1]..layer[N-1]) + payload
        // We build this from inside out.
        begin
            byte unsigned remaining_data[$];
            remaining_data = payload;

            for (int i = int'(layer_stack.size()) - 1; i >= 0; i--) begin
                protocol_type_e next_proto;

                if (i < int'(layer_stack.size()) - 1)
                    next_proto = layer_stack[i+1].proto_type;
                else
                    next_proto = PROTO_RAW_PAYLOAD;

                layer_stack[i].calc_fields(remaining_data, next_proto);

                // Prepend this header's packed bytes to remaining_data for the next outer layer
                if (i > 0) begin
                    byte unsigned hdr_bytes[$];
                    layer_stack[i].pack_header(hdr_bytes);
                    foreach (remaining_data[j])
                        hdr_bytes.push_back(remaining_data[j]);
                    remaining_data = hdr_bytes;
                end
            end
        end

        // Pack all headers + payload into raw_data
        raw_data.delete();
        foreach (layer_stack[i]) begin
            layer_stack[i].pack_header(raw_data);
        end
        foreach (payload[i]) begin
            raw_data.push_back(payload[i]);
        end

        // Compute TCP/UDP/ICMPv6 checksums (requires full raw_data + IP info)
        compute_transport_checksums();
    endfunction

    // =========================================================================
    // compute_transport_checksums — post-pack pseudo-header checksums
    // =========================================================================
    protected function void compute_transport_checksums();
        // Process innermost transport layers first (reverse order) so that
        // outer checksums include correct inner checksums in tunnel scenarios
        for (int i = int'(layer_stack.size()) - 1; i >= 0; i--) begin
            protocol_type_e ptype;
            int ip_idx;
            ptype = layer_stack[i].proto_type;
            if (ptype != PROTO_TCP && ptype != PROTO_UDP && ptype != PROTO_ICMPV6) continue;

            // Find parent IP layer (search backwards from current layer)
            ip_idx = -1;
            for (int j = i - 1; j >= 0; j--) begin
                if (layer_stack[j].proto_type == PROTO_IPV4 ||
                    layer_stack[j].proto_type == PROTO_IPV6) begin
                    ip_idx = j;
                    break;
                end
            end
            if (ip_idx < 0) continue;

            // Build pseudo-header + transport header + payload
            begin
                byte unsigned pseudo_hdr[$];
                byte unsigned transport_data[$];
                bit [31:0] src_v4, dst_v4;
                bit [127:0] src_v6, dst_v6;
                int transport_len;

                // Collect transport header (with checksum zeroed) + payload
                // Zero the checksum field before packing for computation
                if (ptype == PROTO_TCP) begin
                    tcp_header tcp;
                    if ($cast(tcp, layer_stack[i])) begin
                        bit [15:0] saved = tcp.checksum;
                        tcp.checksum = 0;
                        tcp.pack_header(transport_data);
                        tcp.checksum = saved;
                    end
                end else if (ptype == PROTO_UDP) begin
                    udp_header udp;
                    if ($cast(udp, layer_stack[i])) begin
                        bit [15:0] saved = udp.checksum;
                        udp.checksum = 0;
                        udp.pack_header(transport_data);
                        udp.checksum = saved;
                    end
                end else begin
                    icmpv6_header icmpv6;
                    if ($cast(icmpv6, layer_stack[i])) begin
                        bit [15:0] saved = icmpv6.checksum;
                        icmpv6.checksum = 0;
                        icmpv6.pack_header(transport_data);
                        icmpv6.checksum = saved;
                    end
                end

                // Calculate transport payload: bytes from raw_data after this layer's header
                begin
                    int hdr_offset;
                    int end_offset;
                    hdr_offset = 0;
                    for (int k = 0; k <= i; k++)
                        hdr_offset += layer_stack[k].get_header_length();

                    // Find end: either next Ethernet/IP layer or end of raw_data
                    end_offset = raw_data.size();
                    for (int k = i + 1; k < layer_stack.size(); k++) begin
                        // If we hit another IP layer that's not directly inside this transport
                        // (e.g., in tunnel scenario), stop
                        if (layer_stack[k].proto_type == PROTO_ETHERNET) begin
                            // This means there's a tunnel — the payload after transport
                            // is the tunnel content, include it
                            break;
                        end
                    end

                    for (int k = hdr_offset; k < end_offset; k++)
                        transport_data.push_back(raw_data[k]);
                end

                transport_len = transport_data.size();

                // Build pseudo-header based on IP version
                if (layer_stack[ip_idx].proto_type == PROTO_IPV4) begin
                    ipv4_header ip4;
                    if (!$cast(ip4, layer_stack[ip_idx])) continue;
                    // IPv4 pseudo-header: src(4) + dst(4) + zero(1) + protocol(1) + length(2)
                    packet_utils::pack_bytes_32(pseudo_hdr, ip4.src_addr);
                    packet_utils::pack_bytes_32(pseudo_hdr, ip4.dst_addr);
                    pseudo_hdr.push_back(8'h00);
                    pseudo_hdr.push_back(ip4.protocol);
                    begin
                        bit [15:0] _tl16 = transport_len[15:0];
                        packet_utils::pack_bytes_16(pseudo_hdr, _tl16);
                    end
                end else begin
                    ipv6_header ip6;
                    if (!$cast(ip6, layer_stack[ip_idx])) continue;
                    // IPv6 pseudo-header: src(16) + dst(16) + length(4) + zeros(3) + next_header(1)
                    for (int b = 15; b >= 0; b--)
                        pseudo_hdr.push_back(ip6.src_addr[b*8 +: 8]);
                    for (int b = 15; b >= 0; b--)
                        pseudo_hdr.push_back(ip6.dst_addr[b*8 +: 8]);
                    begin
                        bit [31:0] _tl32 = transport_len;
                        packet_utils::pack_bytes_32(pseudo_hdr, _tl32);
                    end
                    pseudo_hdr.push_back(8'h00);
                    pseudo_hdr.push_back(8'h00);
                    pseudo_hdr.push_back(8'h00);
                    pseudo_hdr.push_back(ip6.next_header);
                end

                // Combine pseudo-header + transport data
                foreach (transport_data[k])
                    pseudo_hdr.push_back(transport_data[k]);

                // Compute checksum
                begin
                    bit [15:0] cksum = packet_utils::ones_complement_checksum(pseudo_hdr);

                    // Write checksum back into the layer AND into raw_data
                    if (ptype == PROTO_TCP) begin
                        tcp_header tcp;
                        if ($cast(tcp, layer_stack[i])) begin
                            tcp.checksum = cksum;
                            // Update raw_data: TCP checksum is at offset +16 within TCP header
                            begin
                                int tcp_offset = 0;
                                for (int k = 0; k < i; k++)
                                    tcp_offset += layer_stack[k].get_header_length();
                                raw_data[tcp_offset + 16] = cksum[15:8];
                                raw_data[tcp_offset + 17] = cksum[7:0];
                            end
                        end
                    end else if (ptype == PROTO_UDP) begin
                        udp_header udp;
                        if ($cast(udp, layer_stack[i])) begin
                            udp.checksum = cksum;
                            begin
                                int udp_offset = 0;
                                for (int k = 0; k < i; k++)
                                    udp_offset += layer_stack[k].get_header_length();
                                raw_data[udp_offset + 6] = cksum[15:8];
                                raw_data[udp_offset + 7] = cksum[7:0];
                            end
                        end
                    end else if (ptype == PROTO_ICMPV6) begin
                        icmpv6_header icmpv6;
                        if ($cast(icmpv6, layer_stack[i])) begin
                            icmpv6.checksum = cksum;
                            begin
                                int icmpv6_offset = 0;
                                for (int k = 0; k < i; k++)
                                    icmpv6_offset += layer_stack[k].get_header_length();
                                raw_data[icmpv6_offset + 2] = cksum[15:8];
                                raw_data[icmpv6_offset + 3] = cksum[7:0];
                            end
                        end
                    end
                end
            end
        end
    endfunction

    // =========================================================================
    // identify_next_proto — used by unpack
    // =========================================================================
    static function protocol_type_e identify_next_proto(protocol_base hdr,
                                                         byte unsigned data[$],
                                                         int offset);
        case (hdr.proto_type)
            PROTO_ETHERNET: begin
                eth_header eth;
                if ($cast(eth, hdr)) begin
                    return ethertype_to_proto(eth.ethertype);
                end
            end
            PROTO_VLAN, PROTO_QINQ: begin
                vlan_header v;
                if ($cast(v, hdr)) begin
                    return ethertype_to_proto(v.ethertype);
                end
            end
            PROTO_IPV4: begin
                ipv4_header ip4;
                if ($cast(ip4, hdr)) begin
                    return ip_proto_to_proto(ip4.protocol);
                end
            end
            PROTO_IPV6: begin
                ipv6_header ip6;
                if ($cast(ip6, hdr)) begin
                    return ipv6_nh_to_proto(ip6.next_header);
                end
            end
            PROTO_UDP: begin
                udp_header u;
                if ($cast(u, hdr)) begin
                    return udp_dstport_to_proto(u.dst_port);
                end
            end
            PROTO_TCP: begin
                tcp_header t;
                if ($cast(t, hdr)) begin
                    return tcp_dstport_to_proto(t.dst_port);
                end
            end
            PROTO_GRE: begin
                gre_header g;
                if ($cast(g, hdr)) begin
                    return gre_proto_to_proto(g.protocol_type);
                end
            end
            PROTO_VXLAN: begin
                return PROTO_ETHERNET;
            end
            PROTO_GENEVE: begin
                geneve_header gn;
                if ($cast(gn, hdr)) begin
                    if (gn.protocol_type == 16'h6558) return PROTO_ETHERNET;
                    return ethertype_to_proto(gn.protocol_type);
                end
            end
            PROTO_ERSPAN_II, PROTO_ERSPAN_III: begin
                return PROTO_ETHERNET;
            end
            PROTO_GTP_U: begin
                if (offset < data.size()) begin
                    bit [3:0] ip_ver = data[offset][7:4];
                    if (ip_ver == 4) return PROTO_IPV4;
                    if (ip_ver == 6) return PROTO_IPV6;
                end
                return PROTO_RAW_PAYLOAD;
            end
            PROTO_ROCEV2: begin
                return PROTO_RAW_PAYLOAD;
            end
            PROTO_MPLS: begin
                mpls_header m;
                if ($cast(m, hdr)) begin
                    if (m.s_bit == 0) return PROTO_MPLS;  // More labels
                    // Bottom of stack: peek at next byte to determine IPv4/IPv6
                    if (offset < data.size()) begin
                        bit [3:0] ip_ver = data[offset][7:4];
                        if (ip_ver == 4) return PROTO_IPV4;
                        if (ip_ver == 6) return PROTO_IPV6;
                    end
                    return PROTO_ETHERNET;  // Default: assume Ethernet
                end
            end
            PROTO_IPV6_HBH, PROTO_IPV6_ROUTING, PROTO_IPV6_DEST: begin
                // These extension headers have next_header at byte[0]
                // But we've already unpacked past them, so use the stored field
                // The extension headers store next_header, we need to map it
                if (hdr.proto_type == PROTO_IPV6_HBH) begin
                    ipv6_hbh_header h;
                    if ($cast(h, hdr)) return ipv6_nh_to_proto(h.next_header);
                end
                if (hdr.proto_type == PROTO_IPV6_ROUTING) begin
                    ipv6_routing_header h;
                    if ($cast(h, hdr)) return ipv6_nh_to_proto(h.next_header);
                end
                if (hdr.proto_type == PROTO_IPV6_DEST) begin
                    ipv6_dest_header h;
                    if ($cast(h, hdr)) return ipv6_nh_to_proto(h.next_header);
                end
            end
            PROTO_IPV6_FRAGMENT: begin
                ipv6_fragment_header h;
                if ($cast(h, hdr)) return ipv6_nh_to_proto(h.next_header);
            end
            PROTO_VXLAN_GPE: begin
                vxlan_gpe_header vg;
                if ($cast(vg, hdr)) begin
                    case (vg.next_protocol)
                        8'd1: return PROTO_IPV4;
                        8'd2: return PROTO_IPV6;
                        8'd3: return PROTO_ETHERNET;
                        8'd5: return PROTO_MPLS;
                        default: return PROTO_RAW_PAYLOAD;
                    endcase
                end
            end
            PROTO_ESP: begin
                return PROTO_RAW_PAYLOAD;  // ESP payload is encrypted
            end
            PROTO_PTP: begin
                return PROTO_RAW_PAYLOAD;
            end
            default: return PROTO_RAW_PAYLOAD;
        endcase
        return PROTO_RAW_PAYLOAD;
    endfunction

    // =========================================================================
    // ethertype -> protocol mapping
    // =========================================================================
    static function protocol_type_e ethertype_to_proto(bit [15:0] etype);
        case (etype)
            ETHERTYPE_IPV4:   return PROTO_IPV4;
            ETHERTYPE_IPV6:   return PROTO_IPV6;
            ETHERTYPE_ARP:    return PROTO_ARP;
            ETHERTYPE_VLAN:   return PROTO_VLAN;
            ETHERTYPE_QINQ:      return PROTO_QINQ;
            ETHERTYPE_MPLS_UNI:  return PROTO_MPLS;
            ETHERTYPE_MPLS_MULTI: return PROTO_MPLS;
            ETHERTYPE_PTP:       return PROTO_PTP;
            default:             return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

    // =========================================================================
    // IP protocol -> protocol mapping
    // =========================================================================
    static function protocol_type_e ip_proto_to_proto(bit [7:0] proto);
        case (proto)
            IP_PROTO_TCP:      return PROTO_TCP;
            IP_PROTO_UDP:      return PROTO_UDP;
            IP_PROTO_ICMP:     return PROTO_ICMP;
            IP_PROTO_GRE:      return PROTO_GRE;
            IP_PROTO_ICMPV6:   return PROTO_ICMPV6;
            IP_PROTO_IGMP:     return PROTO_IGMP;
            IP_PROTO_SCTP:     return PROTO_SCTP;
            IP_PROTO_IP_IN_IP: return PROTO_IP_IN_IP;
            IP_PROTO_IPV6:     return PROTO_IPV6;
            IP_PROTO_OSPF:     return PROTO_OSPF;
            IP_PROTO_L2TP:     return PROTO_L2TP;
            IP_PROTO_ESP:      return PROTO_ESP;
            default:           return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

    // =========================================================================
    // IPv6 next_header -> protocol mapping
    // =========================================================================
    static function protocol_type_e ipv6_nh_to_proto(bit [7:0] nh);
        case (nh)
            IPV6_NH_TCP:      return PROTO_TCP;
            IPV6_NH_UDP:      return PROTO_UDP;
            IPV6_NH_ICMPV6:   return PROTO_ICMPV6;
            IPV6_NH_HBH:      return PROTO_IPV6_HBH;
            IPV6_NH_ROUTING:  return PROTO_IPV6_ROUTING;
            IPV6_NH_FRAGMENT: return PROTO_IPV6_FRAGMENT;
            IPV6_NH_DEST:     return PROTO_IPV6_DEST;
            IPV6_NH_GRE:      return PROTO_GRE;
            IPV6_NH_IPV6:     return PROTO_IPV6;
            IPV6_NH_OSPF:     return PROTO_OSPF;
            IPV6_NH_SCTP:     return PROTO_SCTP;
            IPV6_NH_ESP:      return PROTO_ESP;
            default:          return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

    // =========================================================================
    // UDP dst_port -> protocol mapping
    // =========================================================================
    static function protocol_type_e udp_dstport_to_proto(bit [15:0] port);
        case (port)
            16'd4789: return PROTO_VXLAN;
            16'd6081: return PROTO_GENEVE;
            16'd2152: return PROTO_GTP_U;
            16'd2123: return PROTO_GTP_C;
            16'd4791: return PROTO_ROCEV2;
            16'd4790: return PROTO_VXLAN_GPE;
            default:  return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

    // =========================================================================
    // GRE protocol_type -> protocol mapping
    // =========================================================================
    static function protocol_type_e gre_proto_to_proto(bit [15:0] proto);
        case (proto)
            ETHERTYPE_IPV4:  return PROTO_IPV4;
            ETHERTYPE_IPV6:  return PROTO_IPV6;
            16'h6558:        return PROTO_ETHERNET;
            16'h88BE:        return PROTO_ERSPAN_II;
            16'h22EB:        return PROTO_ERSPAN_III;
            default:         return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

    // =========================================================================
    // TCP dst_port -> protocol mapping
    // =========================================================================
    static function protocol_type_e tcp_dstport_to_proto(bit [15:0] port);
        case (port)
            16'd4420: return PROTO_NVME_TCP;
            16'd3260: return PROTO_ISCSI;
            16'd5044: return PROTO_IWARP;
            default:  return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

    // =========================================================================
    // unpack — parse byte stream into layer_stack
    // =========================================================================
    function void unpack(byte unsigned data[$]);
        int offset = 0;
        protocol_type_e cur_proto;
        protocol_base hdr;

        layer_stack.delete();
        raw_data = data;

        if (data.size() < 14) return;  // minimum Ethernet

        // Start with Ethernet
        cur_proto = PROTO_ETHERNET;

        while (offset < data.size() && cur_proto != PROTO_RAW_PAYLOAD) begin
            hdr = create_header(cur_proto);
            if (hdr == null) break;

            if (offset + hdr.get_header_length() > data.size()) break;

            hdr.unpack_header(data, offset);
            layer_stack.push_back(hdr);

            cur_proto = identify_next_proto(hdr, data, offset);
        end
    endfunction

    // =========================================================================
    // to_proto_chain
    // =========================================================================
    function string to_proto_chain();
        string s = "";
        foreach (layer_stack[i]) begin
            if (i > 0) s = {s, " -> "};
            s = {s, layer_stack[i].proto_type.name()};
        end
        return s;
    endfunction

    // =========================================================================
    // to_brief
    // =========================================================================
    function string to_brief();
        string s;
        s = $sformatf("Packet [%0d layers, %0d bytes]: ", layer_stack.size(), raw_data.size());
        s = {s, to_proto_chain()};
        return s;
    endfunction

    // =========================================================================
    // to_detail
    // =========================================================================
    function string to_detail();
        string s = "";
        s = {s, to_brief(), "\n"};
        foreach (layer_stack[i]) begin
            s = {s, layer_stack[i].to_string()};
        end
        if (raw_data.size() > 0) begin
            s = {s, "--- Raw Data ---\n"};
            s = {s, packet_utils::hex_dump(raw_data), "\n"};
        end
        return s;
    endfunction

    // =========================================================================
    // load_params — load all header params from cmdline path
    // =========================================================================
    // load_params — 遍历 layer_stack 中的实际实例加载参数
    // 路径规则：{p}.{proto_name}.{field} — 同类协议第二次出现用 inner_ 前缀
    // 例：eth_tx.outer_eth.dst_mac, eth_tx.inner_ipv4.src_addr, eth_tx.tcp.dst_port
    function void load_params(string p);
`ifdef AIP_CMDLINE_SV
        int __w;
        string __v;
        int proto_seen[protocol_type_e];

        // 1. 模板参数（可选）：set_param eth_tx.tmpl ETH_IPV4_TCP
        __v = aip_cmdline#(int)::get_cmdline_string("tmpl", p);
        if (__v != "") begin
            packet_template_e t = t.first();
            string __lower_v = aip_str::lower(__v);
            forever begin
                if (aip_str::lower(t.name()) == __lower_v) begin
                    build_from_template(t);
                    break;
                end
                if (t == t.last()) break;
                t = t.next();
            end
        end

        // 2. 报文长度
        __v = aip_cmdline#(int)::get_cmdline_string("pkt_len", p);
        if (__v != "") pkt_len = int'(aip_str::str_to_num(__v, __w));

        // 3. 遍历 layer_stack — 对实际使用的协议头实例调 load_params
        foreach (layer_stack[i]) begin
            string layer_path;
            string proto_name;
            protocol_type_e pt = layer_stack[i].proto_type;

            // 协议名简写
            case (pt)
                PROTO_ETHERNET: proto_name = "eth";
                PROTO_VLAN:     proto_name = "vlan";
                PROTO_QINQ:     proto_name = "qinq";
                PROTO_MPLS:     proto_name = "mpls";
                PROTO_IPV4:     proto_name = "ipv4";
                PROTO_IPV6:     proto_name = "ipv6";
                PROTO_ARP:      proto_name = "arp";
                PROTO_TCP:      proto_name = "tcp";
                PROTO_UDP:      proto_name = "udp";
                PROTO_ICMP:     proto_name = "icmp";
                PROTO_IGMP:     proto_name = "igmp";
                PROTO_LLDP:        proto_name = "lldp";
                PROTO_LACP:        proto_name = "lacp";
                PROTO_STP:         proto_name = "stp";
                PROTO_MAC_CONTROL: proto_name = "mac_control";
                PROTO_DHCP:        proto_name = "dhcp";
                PROTO_DHCPV6:      proto_name = "dhcpv6";
                PROTO_DNS:         proto_name = "dns";
                PROTO_BFD:         proto_name = "bfd";
                PROTO_NVME_RDMA:   proto_name = "nvme_rdma";
                PROTO_ICMPV6:   proto_name = "icmpv6";
                PROTO_SCTP:     proto_name = "sctp";
                PROTO_VXLAN:    proto_name = "vxlan";
                PROTO_GRE:      proto_name = "gre";
                PROTO_GENEVE:   proto_name = "geneve";
                PROTO_GTP_U:    proto_name = "gtp";
                PROTO_ERSPAN_II:  proto_name = "erspan_ii";
                PROTO_ERSPAN_III: proto_name = "erspan_iii";
                PROTO_VXLAN_GPE:  proto_name = "vxlan_gpe";
                PROTO_ESP:      proto_name = "esp";
                PROTO_ROCEV2:   proto_name = "rocev2";
                PROTO_IWARP:    proto_name = "iwarp";
                PROTO_NVME_TCP: proto_name = "nvme_tcp";
                PROTO_ISCSI:    proto_name = "iscsi";
                PROTO_PTP:      proto_name = "ptp";
                default:        proto_name = pt.name();
            endcase

            // outer/inner 区分：第一次出现 = outer_，第二次 = inner_
            // 只出现一次的协议（tcp/vxlan 等）不加前缀
            if (!proto_seen.exists(pt)) begin
                proto_seen[pt] = 1;
                layer_path = {p, ".outer_", proto_name};
            end else begin
                layer_path = {p, ".inner_", proto_name};
            end

            layer_stack[i].load_params(layer_path);
        end

        // 4. 对只出现一次的协议，也支持不带 outer_ 前缀的简写路径
        //    例：eth_tx.tcp.dst_port 等价于 eth_tx.outer_tcp.dst_port
        foreach (layer_stack[i]) begin
            protocol_type_e pt = layer_stack[i].proto_type;
            if (proto_seen.exists(pt) && proto_seen[pt] == 1) begin
                string proto_name;
                case (pt)
                    PROTO_ETHERNET: proto_name = "eth";
                    PROTO_VLAN:     proto_name = "vlan";
                    PROTO_IPV4:     proto_name = "ipv4";
                    PROTO_IPV6:     proto_name = "ipv6";
                    PROTO_TCP:      proto_name = "tcp";
                    PROTO_UDP:      proto_name = "udp";
                    PROTO_ICMP:     proto_name = "icmp";
                    PROTO_IGMP:     proto_name = "igmp";
                    PROTO_LLDP:        proto_name = "lldp";
                    PROTO_LACP:        proto_name = "lacp";
                    PROTO_STP:         proto_name = "stp";
                    PROTO_MAC_CONTROL: proto_name = "mac_control";
                    PROTO_DHCP:        proto_name = "dhcp";
                    PROTO_DHCPV6:      proto_name = "dhcpv6";
                    PROTO_DNS:         proto_name = "dns";
                    PROTO_BFD:         proto_name = "bfd";
                    PROTO_NVME_RDMA:   proto_name = "nvme_rdma";
                    PROTO_SCTP:     proto_name = "sctp";
                    PROTO_VXLAN:    proto_name = "vxlan";
                    PROTO_GRE:      proto_name = "gre";
                    PROTO_GENEVE:   proto_name = "geneve";
                    PROTO_GTP_U:    proto_name = "gtp";
                    PROTO_ROCEV2:   proto_name = "rocev2";
                    PROTO_ARP:      proto_name = "arp";
                    PROTO_PTP:      proto_name = "ptp";
                    default:        proto_name = "";
                endcase
                if (proto_name != "")
                    layer_stack[i].load_params({p, ".", proto_name});
            end
        end
`endif
    endfunction

endclass

`endif // PACKET_SV

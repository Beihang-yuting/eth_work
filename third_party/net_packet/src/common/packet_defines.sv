// src/common/packet_defines.sv
`ifndef PACKET_DEFINES_SV
`define PACKET_DEFINES_SV

typedef byte unsigned byte_queue[$];

typedef enum int {
    // L2
    PROTO_ETHERNET      = 0,
    PROTO_VLAN          = 1,
    PROTO_QINQ          = 2,
    PROTO_MPLS          = 3,
    PROTO_MAC_CONTROL   = 4,
    PROTO_LLDP          = 5,
    PROTO_LACP          = 6,
    PROTO_STP           = 7,
    PROTO_MACSEC        = 8,
    PROTO_EAP           = 9,
    // L3
    PROTO_IPV4          = 10,
    PROTO_IPV6          = 11,
    PROTO_ARP           = 12,
    PROTO_IGMP          = 13,
    PROTO_IPV6_HBH      = 14,
    PROTO_IPV6_ROUTING  = 15,
    PROTO_IPV6_FRAGMENT = 16,
    PROTO_IPV6_DEST     = 17,
    PROTO_DHCP          = 18,
    PROTO_DHCPV6        = 19,
    PROTO_OSPF          = 20,
    PROTO_BGP           = 21,
    PROTO_ISIS          = 22,
    // L4
    PROTO_TCP           = 30,
    PROTO_UDP           = 31,
    PROTO_ICMP          = 32,
    PROTO_ICMPV6        = 33,
    PROTO_SCTP          = 34,
    // Tunnel
    PROTO_VXLAN         = 40,
    PROTO_GRE           = 41,
    PROTO_NVGRE         = 42,
    PROTO_GENEVE        = 43,
    PROTO_ERSPAN_I      = 44,
    PROTO_ERSPAN_II     = 45,
    PROTO_ERSPAN_III    = 46,
    PROTO_IP_IN_IP      = 47,
    PROTO_L2TP          = 48,
    PROTO_GTP_U         = 49,
    PROTO_GTP_C         = 50,
    PROTO_MPLS_GRE      = 51,
    PROTO_MPLS_UDP      = 52,
    PROTO_VXLAN_GPE     = 53,
    PROTO_ESP           = 54,
    // App/Mgmt
    PROTO_DNS           = 60,
    PROTO_HTTP          = 61,
    PROTO_SNMP          = 62,
    PROTO_BFD           = 63,
    PROTO_PTP           = 64,
    // Storage/RDMA
    PROTO_ROCEV2        = 70,
    PROTO_IWARP         = 71,
    PROTO_NVME_TCP      = 72,
    PROTO_NVME_RDMA     = 73,
    PROTO_ISCSI         = 74,
    // Special
    PROTO_RAW_PAYLOAD   = 99
} protocol_type_e;
typedef protocol_type_e proto_chain_t[$];

typedef enum int {
    // =========================================================
    // Basic: ETH + L3 + L4 (no tunnel)
    // =========================================================
    ETH_IPV4_TCP                            = 0,
    ETH_IPV4_UDP                            = 1,
    ETH_IPV4_ICMP                           = 2,
    ETH_IPV4_SCTP                           = 3,
    ETH_IPV6_TCP                            = 4,
    ETH_IPV6_UDP                            = 5,
    ETH_IPV6_ICMPV6                         = 6,
    ETH_IPV6_SCTP                           = 7,
    ETH_ARP                                 = 8,
    ETH_IPV4_IGMP                                = 9,

    // =========================================================
    // VLAN: ETH + VLAN + L3 + L4
    // =========================================================
    ETH_VLAN_IPV4_TCP                       = 120,
    ETH_VLAN_IPV4_UDP                       = 121,
    ETH_VLAN_IPV6_TCP                       = 122,
    ETH_VLAN_IPV6_UDP                       = 123,
    ETH_VLAN_IPV4_UDP_VXLAN_ETH_IPV4_TCP    = 124,
    ETH_VLAN_IPV4_UDP_ROCEV2                = 125,

    // =========================================================
    // MPLS: ETH + MPLS + L3 + L4
    // =========================================================
    ETH_MPLS_IPV4_TCP                       = 10,
    ETH_MPLS_IPV4_UDP                       = 11,
    ETH_MPLS_IPV4_ICMP                      = 12,
    ETH_MPLS_IPV4_SCTP                      = 13,
    ETH_MPLS_IPV6_TCP                       = 14,
    ETH_MPLS_IPV6_UDP                       = 15,
    ETH_MPLS_IPV6_ICMPV6                    = 16,
    ETH_MPLS_IPV6_SCTP                      = 17,

    // =========================================================
    // IPsec ESP: ETH + L3 + ESP
    // =========================================================
    ETH_IPV4_ESP                            = 18,
    ETH_IPV6_ESP                            = 19,

    // =========================================================
    // VXLAN: ETH + outer_L3 + UDP + VXLAN + ETH + inner_L3 + inner_L4
    // =========================================================
    // Outer IPv4
    ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP         = 20,
    ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP         = 21,
    ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP         = 22,
    ETH_IPV4_UDP_VXLAN_ETH_IPV6_UDP         = 23,
    // Outer IPv6
    ETH_IPV6_UDP_VXLAN_ETH_IPV4_TCP         = 24,
    ETH_IPV6_UDP_VXLAN_ETH_IPV4_UDP         = 25,
    ETH_IPV6_UDP_VXLAN_ETH_IPV6_TCP         = 26,
    ETH_IPV6_UDP_VXLAN_ETH_IPV6_UDP         = 27,

    // =========================================================
    // Geneve: ETH + outer_L3 + UDP + Geneve + ETH + inner_L3 + inner_L4
    // =========================================================
    // Outer IPv4
    ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP        = 30,
    ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP        = 31,
    ETH_IPV4_UDP_GENEVE_ETH_IPV6_TCP        = 32,
    ETH_IPV4_UDP_GENEVE_ETH_IPV6_UDP        = 33,
    // Outer IPv6
    ETH_IPV6_UDP_GENEVE_ETH_IPV4_TCP        = 34,
    ETH_IPV6_UDP_GENEVE_ETH_IPV4_UDP        = 35,
    ETH_IPV6_UDP_GENEVE_ETH_IPV6_TCP        = 36,
    ETH_IPV6_UDP_GENEVE_ETH_IPV6_UDP        = 37,

    // =========================================================
    // GRE L3: ETH + outer_L3 + GRE + inner_L3 + inner_L4 (no inner ETH)
    // =========================================================
    // Outer IPv4
    ETH_IPV4_GRE_IPV4_TCP                   = 40,
    ETH_IPV4_GRE_IPV4_UDP                   = 41,
    ETH_IPV4_GRE_IPV6_TCP                   = 42,
    ETH_IPV4_GRE_IPV6_UDP                   = 43,
    // Outer IPv6
    ETH_IPV6_GRE_IPV4_TCP                   = 44,
    ETH_IPV6_GRE_IPV4_UDP                   = 45,
    ETH_IPV6_GRE_IPV6_TCP                   = 46,
    ETH_IPV6_GRE_IPV6_UDP                   = 47,

    // =========================================================
    // NVGRE (GRE L2): ETH + outer_L3 + GRE + ETH + inner_L3 + inner_L4
    // =========================================================
    // Outer IPv4
    ETH_IPV4_GRE_ETH_IPV4_TCP               = 50,
    ETH_IPV4_GRE_ETH_IPV4_UDP               = 51,
    ETH_IPV4_GRE_ETH_IPV6_TCP               = 52,
    ETH_IPV4_GRE_ETH_IPV6_UDP               = 53,
    // Outer IPv6
    ETH_IPV6_GRE_ETH_IPV4_TCP               = 54,
    ETH_IPV6_GRE_ETH_IPV4_UDP               = 55,
    ETH_IPV6_GRE_ETH_IPV6_TCP               = 56,
    ETH_IPV6_GRE_ETH_IPV6_UDP               = 57,

    // =========================================================
    // GTP-U: ETH + outer_L3 + UDP + GTP-U + inner_L3 + inner_L4
    // =========================================================
    // Outer IPv4
    ETH_IPV4_UDP_GTP_U_IPV4_TCP             = 60,
    ETH_IPV4_UDP_GTP_U_IPV4_UDP             = 61,
    ETH_IPV4_UDP_GTP_U_IPV6_TCP             = 62,
    ETH_IPV4_UDP_GTP_U_IPV6_UDP             = 63,
    // Outer IPv6
    ETH_IPV6_UDP_GTP_U_IPV4_TCP             = 64,
    ETH_IPV6_UDP_GTP_U_IPV4_UDP             = 65,
    ETH_IPV6_UDP_GTP_U_IPV6_TCP             = 66,
    ETH_IPV6_UDP_GTP_U_IPV6_UDP             = 67,

    // =========================================================
    // ERSPAN: ETH + outer_L3 + GRE + ERSPAN + ETH + inner_L3 + inner_L4
    // =========================================================
    // ERSPAN Type II
    ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP     = 70,
    ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_UDP     = 71,
    ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_TCP     = 72,
    ETH_IPV6_GRE_ERSPAN_II_ETH_IPV4_UDP     = 73,
    // ERSPAN Type III
    ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_TCP    = 74,
    ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_UDP    = 75,
    ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_TCP    = 76,
    ETH_IPV6_GRE_ERSPAN_III_ETH_IPV4_UDP    = 77,

    // =========================================================
    // VXLAN-GPE: ETH + outer_L3 + UDP + VXLAN-GPE + [ETH] + inner_L3 + inner_L4
    // =========================================================
    // With inner ETH (L2 mode)
    ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_TCP     = 80,
    ETH_IPV4_UDP_VXLAN_GPE_ETH_IPV4_UDP     = 81,
    ETH_IPV6_UDP_VXLAN_GPE_ETH_IPV4_TCP     = 82,
    // Without inner ETH (L3 mode)
    ETH_IPV4_UDP_VXLAN_GPE_IPV4_TCP         = 83,
    ETH_IPV4_UDP_VXLAN_GPE_IPV6_TCP         = 84,

    // =========================================================
    // RDMA: ETH + L3 + UDP + RoCEv2 [+ NVMe-RDMA]
    // =========================================================
    ETH_IPV4_UDP_ROCEV2                      = 90,
    ETH_IPV6_UDP_ROCEV2                      = 91,
    ETH_IPV4_UDP_ROCEV2_NVME_RDMA            = 92,
    ETH_IPV6_UDP_ROCEV2_NVME_RDMA            = 93,

    // =========================================================
    // Storage over TCP: ETH + L3 + TCP + {NVMe-TCP, iSCSI, iWARP}
    // =========================================================
    ETH_IPV4_TCP_NVME_TCP                    = 100,
    ETH_IPV6_TCP_NVME_TCP                    = 101,
    ETH_IPV4_TCP_ISCSI                       = 102,
    ETH_IPV6_TCP_ISCSI                       = 103,
    ETH_IPV4_TCP_IWARP                       = 104,
    ETH_IPV6_TCP_IWARP                       = 105,

    // =========================================================
    // Mgmt/Control
    // =========================================================
    ETH_IPV4_UDP_DHCP                        = 110,
    ETH_IPV6_UDP_DHCPV6                      = 111,
    ETH_IPV4_UDP_DNS                         = 112,
    ETH_IPV4_UDP_BFD                         = 113,
    ETH_IPV4_UDP_PTP                         = 114,
    ETH_PTP_L2                               = 115,
    ETH_LLDP                                 = 116,
    ETH_LACP                                 = 117,
    ETH_STP                                  = 118,
    ETH_MAC_CONTROL                          = 119
} packet_template_e;

typedef enum int {
    PKT_CAT_ALL           = 0,
    PKT_CAT_BASIC         = 1,
    // L4 categories
    PKT_CAT_TCP           = 2,
    PKT_CAT_UDP           = 3,
    PKT_CAT_ICMP          = 4,
    PKT_CAT_SCTP          = 5,
    // L3 categories (outer)
    PKT_CAT_OUTER_IPV4    = 6,
    PKT_CAT_OUTER_IPV6    = 7,
    // L3 categories (inner, tunnel only)
    PKT_CAT_INNER_IPV4    = 8,
    PKT_CAT_INNER_IPV6    = 9,
    // Tunnel categories
    PKT_CAT_TUNNEL        = 10,
    PKT_CAT_VXLAN         = 11,
    PKT_CAT_GRE           = 12,
    PKT_CAT_GENEVE        = 13,
    PKT_CAT_GTP           = 14,
    PKT_CAT_ERSPAN        = 15,
    PKT_CAT_NVGRE         = 16,
    // Application categories
    PKT_CAT_ROCEV2        = 17,
    PKT_CAT_STORAGE       = 18,
    PKT_CAT_MPLS          = 19,
    PKT_CAT_MGMT          = 20,
    PKT_CAT_ESP           = 21,
    PKT_CAT_VXLAN_GPE     = 22
} pkt_category_e;

typedef enum int {
    PAYLOAD_RANDOM    = 0,
    PAYLOAD_FIXED     = 1,
    PAYLOAD_INCREMENT = 2,
    PAYLOAD_PATTERN   = 3
} payload_mode_e;

typedef enum int {
    MOD_INCREMENT = 0,
    MOD_DECREMENT = 1,
    MOD_RANDOM    = 2,
    MOD_LIST      = 3
} modifier_mode_e;

typedef struct {
    bit              valid;
    protocol_type_e  proto_chain[$];
    string           errors[$];
    string           warnings[$];
} parse_result_t;

typedef struct {
    protocol_type_e  layer;
    string           field_name;
    string           val_a;
    string           val_b;
} diff_entry_t;

typedef enum bit [15:0] {
    ETHERTYPE_IPV4        = 16'h0800,
    ETHERTYPE_IPV6        = 16'h86DD,
    ETHERTYPE_ARP         = 16'h0806,
    ETHERTYPE_VLAN        = 16'h8100,
    ETHERTYPE_QINQ        = 16'h88A8,
    ETHERTYPE_MPLS_UNI    = 16'h8847,
    ETHERTYPE_MPLS_MULTI  = 16'h8848,
    ETHERTYPE_LLDP        = 16'h88CC,
    ETHERTYPE_PTP         = 16'h88F7,
    ETHERTYPE_MACSEC      = 16'h88E5,
    ETHERTYPE_EAP         = 16'h888E,
    ETHERTYPE_SLOW        = 16'h8809
} ethertype_e;

typedef enum bit [7:0] {
    IP_PROTO_ICMP     = 8'd1,
    IP_PROTO_IGMP     = 8'd2,
    IP_PROTO_IP_IN_IP = 8'd4,
    IP_PROTO_TCP      = 8'd6,
    IP_PROTO_UDP      = 8'd17,
    IP_PROTO_IPV6     = 8'd41,
    IP_PROTO_GRE      = 8'd47,
    IP_PROTO_ICMPV6   = 8'd58,
    IP_PROTO_OSPF     = 8'd89,
    IP_PROTO_SCTP     = 8'd132,
    IP_PROTO_L2TP     = 8'd115,
    IP_PROTO_ESP      = 8'd50
} ip_protocol_e;

typedef enum bit [7:0] {
    IPV6_NH_HBH       = 8'd0,
    IPV6_NH_TCP        = 8'd6,
    IPV6_NH_UDP        = 8'd17,
    IPV6_NH_IPV6       = 8'd41,
    IPV6_NH_ROUTING    = 8'd43,
    IPV6_NH_FRAGMENT   = 8'd44,
    IPV6_NH_GRE        = 8'd47,
    IPV6_NH_ICMPV6     = 8'd58,
    IPV6_NH_DEST       = 8'd60,
    IPV6_NH_OSPF       = 8'd89,
    IPV6_NH_SCTP       = 8'd132,
    IPV6_NH_ESP        = 8'd50
} ipv6_next_header_e;

`endif // PACKET_DEFINES_SV

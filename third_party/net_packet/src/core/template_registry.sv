// src/core/template_registry.sv
// Auto-parses packet_template_e enum names into protocol chains.
// To add a new template: just add ONE line to packet_template_e in packet_defines.sv.
// The parser uses greedy longest-match to handle multi-word protocol names
// (e.g., VXLAN_GPE, ERSPAN_III, NVME_TCP, MAC_CONTROL).
`ifndef TEMPLATE_REGISTRY_SV
`define TEMPLATE_REGISTRY_SV

`include "packet_defines.sv"

class template_registry;

    protected protocol_type_e chains[packet_template_e][$];

    function new();
        init_all_templates();
    endfunction

    function void register_template(packet_template_e tmpl, protocol_type_e chain[$]);
        chains[tmpl] = chain;
    endfunction

    function void get_chain(packet_template_e tmpl, ref protocol_type_e chain[$]);
        chain.delete();
        if (chains.exists(tmpl)) begin
            chain = chains[tmpl];
        end
    endfunction

    // =========================================================================
    // Auto-register ALL templates by parsing enum names
    // =========================================================================
    protected function void init_all_templates();
        packet_template_e tmpl = tmpl.first();
        forever begin
            protocol_type_e chain[$];
            chain = parse_template_name(tmpl.name());
            if (chain.size() > 0)
                chains[tmpl] = chain;
            if (tmpl == tmpl.last()) break;
            tmpl = tmpl.next();
        end
    endfunction

    // =========================================================================
    // Parse template name string into protocol chain
    // Uses greedy longest-match against known protocol tokens.
    //
    // Tokens are checked longest-first so that e.g. "VXLAN_GPE" matches before
    // "VXLAN", "ERSPAN_III" before "ERSPAN_II" before "ERSPAN_I", "ICMPV6"
    // before "ICMP", "NVME_TCP" before "TCP", "DHCPV6" before "DHCP", etc.
    //
    // After each matched token, pos advances past the token + 1 for the '_'
    // separator. If the token is at the end of the string (no trailing '_'),
    // pos overshoots past len and the while loop exits. This is correct.
    // =========================================================================
    function proto_chain_t parse_template_name(string name);
        protocol_type_e chain[$];
        int pos = 0;
        int len = name.len();

        while (pos < len) begin
            bit matched = 0;

            // ---- 11-char tokens ----
            if (!matched && pos + 11 <= len && name.substr(pos, pos+10) == "MAC_CONTROL") begin
                chain.push_back(PROTO_MAC_CONTROL); pos += 12; matched = 1;
            end
            // ---- 10-char tokens ----
            if (!matched && pos + 10 <= len && name.substr(pos, pos+9) == "ERSPAN_III") begin
                chain.push_back(PROTO_ERSPAN_III); pos += 11; matched = 1;
            end

            // ---- 9-char tokens ----
            if (!matched && pos + 9 <= len && name.substr(pos, pos+8) == "ERSPAN_II") begin
                chain.push_back(PROTO_ERSPAN_II); pos += 10; matched = 1;
            end
            if (!matched && pos + 9 <= len && name.substr(pos, pos+8) == "VXLAN_GPE") begin
                chain.push_back(PROTO_VXLAN_GPE); pos += 10; matched = 1;
            end
            if (!matched && pos + 9 <= len && name.substr(pos, pos+8) == "NVME_RDMA") begin
                chain.push_back(PROTO_NVME_RDMA); pos += 10; matched = 1;
            end

            // ---- 8-char tokens ----
            if (!matched && pos + 8 <= len && name.substr(pos, pos+7) == "NVME_TCP") begin
                chain.push_back(PROTO_NVME_TCP); pos += 9; matched = 1;
            end
            if (!matched && pos + 8 <= len && name.substr(pos, pos+7) == "IP_IN_IP") begin
                chain.push_back(PROTO_IP_IN_IP); pos += 9; matched = 1;
            end
            if (!matched && pos + 8 <= len && name.substr(pos, pos+7) == "MPLS_GRE") begin
                chain.push_back(PROTO_MPLS_GRE); pos += 9; matched = 1;
            end
            if (!matched && pos + 8 <= len && name.substr(pos, pos+7) == "MPLS_UDP") begin
                chain.push_back(PROTO_MPLS_UDP); pos += 9; matched = 1;
            end
            if (!matched && pos + 8 <= len && name.substr(pos, pos+7) == "ERSPAN_I") begin
                chain.push_back(PROTO_ERSPAN_I); pos += 9; matched = 1;
            end

            // ---- 6-char tokens ----
            if (!matched && pos + 6 <= len && name.substr(pos, pos+5) == "ICMPV6") begin
                chain.push_back(PROTO_ICMPV6); pos += 7; matched = 1;
            end
            if (!matched && pos + 6 <= len && name.substr(pos, pos+5) == "ROCEV2") begin
                chain.push_back(PROTO_ROCEV2); pos += 7; matched = 1;
            end
            if (!matched && pos + 6 <= len && name.substr(pos, pos+5) == "DHCPV6") begin
                chain.push_back(PROTO_DHCPV6); pos += 7; matched = 1;
            end
            if (!matched && pos + 6 <= len && name.substr(pos, pos+5) == "GENEVE") begin
                chain.push_back(PROTO_GENEVE); pos += 7; matched = 1;
            end
            if (!matched && pos + 6 <= len && name.substr(pos, pos+5) == "MACSEC") begin
                chain.push_back(PROTO_MACSEC); pos += 7; matched = 1;
            end

            // ---- 5-char tokens ----
            if (!matched && pos + 5 <= len && name.substr(pos, pos+4) == "VXLAN") begin
                chain.push_back(PROTO_VXLAN); pos += 6; matched = 1;
            end
            if (!matched && pos + 5 <= len && name.substr(pos, pos+4) == "GTP_U") begin
                chain.push_back(PROTO_GTP_U); pos += 6; matched = 1;
            end
            if (!matched && pos + 5 <= len && name.substr(pos, pos+4) == "GTP_C") begin
                chain.push_back(PROTO_GTP_C); pos += 6; matched = 1;
            end
            if (!matched && pos + 5 <= len && name.substr(pos, pos+4) == "ISCSI") begin
                chain.push_back(PROTO_ISCSI); pos += 6; matched = 1;
            end
            if (!matched && pos + 5 <= len && name.substr(pos, pos+4) == "IWARP") begin
                chain.push_back(PROTO_IWARP); pos += 6; matched = 1;
            end
            if (!matched && pos + 5 <= len && name.substr(pos, pos+4) == "NVGRE") begin
                chain.push_back(PROTO_NVGRE); pos += 6; matched = 1;
            end
            // ---- 4-char tokens ----
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "IPV4") begin
                chain.push_back(PROTO_IPV4); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "IPV6") begin
                chain.push_back(PROTO_IPV6); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "ICMP") begin
                chain.push_back(PROTO_ICMP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "SCTP") begin
                chain.push_back(PROTO_SCTP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "MPLS") begin
                chain.push_back(PROTO_MPLS); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "VLAN") begin
                chain.push_back(PROTO_VLAN); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "QINQ") begin
                chain.push_back(PROTO_QINQ); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "IGMP") begin
                chain.push_back(PROTO_IGMP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "LLDP") begin
                chain.push_back(PROTO_LLDP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "LACP") begin
                chain.push_back(PROTO_LACP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "DHCP") begin
                chain.push_back(PROTO_DHCP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "OSPF") begin
                chain.push_back(PROTO_OSPF); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "ISIS") begin
                chain.push_back(PROTO_ISIS); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "L2TP") begin
                chain.push_back(PROTO_L2TP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "HTTP") begin
                chain.push_back(PROTO_HTTP); pos += 5; matched = 1;
            end
            if (!matched && pos + 4 <= len && name.substr(pos, pos+3) == "SNMP") begin
                chain.push_back(PROTO_SNMP); pos += 5; matched = 1;
            end

            // ---- 3-char tokens ----
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "ETH") begin
                chain.push_back(PROTO_ETHERNET); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "TCP") begin
                chain.push_back(PROTO_TCP); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "UDP") begin
                chain.push_back(PROTO_UDP); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "GRE") begin
                chain.push_back(PROTO_GRE); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "ARP") begin
                chain.push_back(PROTO_ARP); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "ESP") begin
                chain.push_back(PROTO_ESP); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "BFD") begin
                chain.push_back(PROTO_BFD); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "DNS") begin
                chain.push_back(PROTO_DNS); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "PTP") begin
                chain.push_back(PROTO_PTP); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "STP") begin
                chain.push_back(PROTO_STP); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "EAP") begin
                chain.push_back(PROTO_EAP); pos += 4; matched = 1;
            end
            if (!matched && pos + 3 <= len && name.substr(pos, pos+2) == "BGP") begin
                chain.push_back(PROTO_BGP); pos += 4; matched = 1;
            end

            // ---- 2-char variant markers (not protocols) ----
            if (!matched && pos + 2 <= len && name.substr(pos, pos+1) == "L2") begin
                // Variant marker like "L2" in "ETH_PTP_L2" — skip, not a protocol
                pos += 3; matched = 1;
            end

            // If no match, skip this character (shouldn't happen with valid names)
            if (!matched) begin
                pos++;
            end

            if (pos >= len) break;
        end

        return chain;
    endfunction

endclass

`endif // TEMPLATE_REGISTRY_SV

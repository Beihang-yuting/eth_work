// src/parser/protocol_parser.sv
`ifndef PROTOCOL_PARSER_SV
`define PROTOCOL_PARSER_SV

`include "core/packet.sv"

class protocol_parser;

    // =========================================================================
    // Control switches
    // =========================================================================
    bit verify_en = 0;   // Enable protocol field correctness verification

    // Parse raw bytes into a packet object
    function packet parse(byte unsigned data[$]);
        packet pkt = new();
        pkt.unpack(data);
        return pkt;
    endfunction

    // Validate a packet's protocol chain against the protocol graph
    // When verify_en=1, also checks per-header field correctness and checksums
    function parse_result_t validate(packet pkt);
        parse_result_t result;
        protocol_type_e chain[$];

        result.valid = 1;

        if (pkt.layer_stack.size() == 0) begin
            result.valid = 0;
            result.errors.push_back("Empty packet: no layers");
            return result;
        end

        // Build chain
        foreach (pkt.layer_stack[i])
            chain.push_back(pkt.layer_stack[i].proto_type);
        result.proto_chain = chain;

        // First layer should be Ethernet
        if (chain[0] != PROTO_ETHERNET) begin
            result.warnings.push_back($sformatf("First layer is %s, expected PROTO_ETHERNET", chain[0].name()));
        end

        // Validate transitions
        for (int i = 0; i < int'(chain.size()) - 1; i++) begin
            if (!pkt.s_graph.is_valid_next(chain[i], chain[i+1])) begin
                result.valid = 0;
                result.errors.push_back($sformatf("Invalid transition: %s -> %s at layer %0d",
                    chain[i].name(), chain[i+1].name(), i));
            end
        end

        // Check for minimum header sizes
        foreach (pkt.layer_stack[i]) begin
            if (pkt.layer_stack[i].get_header_length() < 0) begin
                result.valid = 0;
                result.errors.push_back($sformatf("Invalid header length at layer %0d (%s)",
                    i, chain[i].name()));
            end
        end

        // =====================================================================
        // Protocol field correctness verification (when verify_en=1)
        // =====================================================================
        if (verify_en) begin
            // Per-header field verification
            foreach (pkt.layer_stack[i]) begin
                string hdr_errors[$], hdr_warnings[$];
                pkt.layer_stack[i].verify(hdr_errors, hdr_warnings);
                foreach (hdr_errors[e]) begin
                    result.valid = 0;
                    result.errors.push_back($sformatf("layer[%0d] %s", i, hdr_errors[e]));
                end
                foreach (hdr_warnings[w])
                    result.warnings.push_back($sformatf("layer[%0d] %s", i, hdr_warnings[w]));
            end

            // Cross-layer checksum verification (TCP/UDP/ICMPv6 pseudo-header checksums)
            verify_transport_checksums(pkt, result);

            // Cross-layer length consistency
            verify_length_consistency(pkt, result);

            // Ethertype / IP protocol / port consistency with actual next layer
            verify_type_field_consistency(pkt, result);
        end

        return result;
    endfunction

    // =========================================================================
    // Transport checksum verification (TCP, UDP, ICMPv6)
    // These require pseudo-header from parent IP layer
    // =========================================================================
    protected function void verify_transport_checksums(packet pkt, ref parse_result_t result);
        for (int i = 0; i < pkt.layer_stack.size(); i++) begin
            protocol_type_e ptype;
            int ip_idx;
            ptype = pkt.layer_stack[i].proto_type;
            if (ptype != PROTO_TCP && ptype != PROTO_UDP && ptype != PROTO_ICMPV6) continue;

            // Find parent IP layer
            ip_idx = -1;
            for (int j = i - 1; j >= 0; j--) begin
                if (pkt.layer_stack[j].proto_type == PROTO_IPV4 ||
                    pkt.layer_stack[j].proto_type == PROTO_IPV6) begin
                    ip_idx = j;
                    break;
                end
            end
            if (ip_idx < 0) begin
                result.warnings.push_back($sformatf("layer[%0d] %s: no parent IP layer for checksum verification",
                                          i, ptype.name()));
                continue;
            end

            // Get stored checksum
            begin
                bit [15:0] stored_cksum;
                string proto_name;

                if (ptype == PROTO_TCP) begin
                    tcp_header tcp;
                    if (!$cast(tcp, pkt.layer_stack[i])) continue;
                    stored_cksum = tcp.checksum;
                    proto_name = "TCP";
                end else if (ptype == PROTO_UDP) begin
                    udp_header udp;
                    if (!$cast(udp, pkt.layer_stack[i])) continue;
                    stored_cksum = udp.checksum;
                    proto_name = "UDP";
                    // UDP checksum 0 is valid (means not computed)
                    if (stored_cksum == 0) continue;
                end else begin
                    icmpv6_header icmpv6;
                    if (!$cast(icmpv6, pkt.layer_stack[i])) continue;
                    stored_cksum = icmpv6.checksum;
                    proto_name = "ICMPv6";
                end

                // Recompute checksum using pseudo-header
                begin
                    byte unsigned pseudo_hdr[$];
                    byte unsigned transport_data[$];
                    int transport_len;

                    // Pack transport header with checksum zeroed
                    begin
                        // Temporarily zero checksum for computation
                        if (ptype == PROTO_TCP) begin
                            tcp_header tcp;
                            $cast(tcp, pkt.layer_stack[i]);
                            tcp.checksum = 0;
                            tcp.pack_header(transport_data);
                            tcp.checksum = stored_cksum;
                        end else if (ptype == PROTO_UDP) begin
                            udp_header udp;
                            $cast(udp, pkt.layer_stack[i]);
                            udp.checksum = 0;
                            udp.pack_header(transport_data);
                            udp.checksum = stored_cksum;
                        end else begin
                            icmpv6_header icmpv6;
                            $cast(icmpv6, pkt.layer_stack[i]);
                            icmpv6.checksum = 0;
                            icmpv6.pack_header(transport_data);
                            icmpv6.checksum = stored_cksum;
                        end
                    end

                    // Append payload from raw_data
                    begin
                        int hdr_offset = 0;
                        for (int k = 0; k <= i; k++)
                            hdr_offset += pkt.layer_stack[k].get_header_length();
                        for (int k = hdr_offset; k < pkt.raw_data.size(); k++)
                            transport_data.push_back(pkt.raw_data[k]);
                    end

                    transport_len = transport_data.size();

                    // Build pseudo-header
                    if (pkt.layer_stack[ip_idx].proto_type == PROTO_IPV4) begin
                        ipv4_header ip4;
                        if (!$cast(ip4, pkt.layer_stack[ip_idx])) continue;
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
                        if (!$cast(ip6, pkt.layer_stack[ip_idx])) continue;
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

                    // Combine and compute
                    foreach (transport_data[k])
                        pseudo_hdr.push_back(transport_data[k]);

                    begin
                        bit [15:0] computed = packet_utils::ones_complement_checksum(pseudo_hdr);
                        if (stored_cksum != computed) begin
                            result.valid = 0;
                            result.errors.push_back($sformatf("layer[%0d] %s: checksum=0x%04x, expected 0x%04x",
                                                    i, proto_name, stored_cksum, computed));
                        end
                    end
                end
            end
        end
    endfunction

    // =========================================================================
    // Length consistency verification
    // =========================================================================
    protected function void verify_length_consistency(packet pkt, ref parse_result_t result);
        foreach (pkt.layer_stack[i]) begin
            case (pkt.layer_stack[i].proto_type)
                PROTO_IPV4: begin
                    ipv4_header ip4;
                    if ($cast(ip4, pkt.layer_stack[i])) begin
                        // IP total_length vs actual data from this layer onward
                        int remaining = pkt.raw_data.size();
                        int ip_start = 0;
                        for (int k = 0; k < i; k++)
                            ip_start += pkt.layer_stack[k].get_header_length();
                        remaining = pkt.raw_data.size() - ip_start;
                        if (ip4.total_length > remaining)
                            result.errors.push_back($sformatf(
                                "layer[%0d] IPv4: total_length=%0d > remaining data=%0d",
                                i, ip4.total_length, remaining));
                    end
                end
                PROTO_IPV6: begin
                    ipv6_header ip6;
                    if ($cast(ip6, pkt.layer_stack[i])) begin
                        int remaining = pkt.raw_data.size();
                        int ip_start = 0;
                        for (int k = 0; k < i; k++)
                            ip_start += pkt.layer_stack[k].get_header_length();
                        remaining = pkt.raw_data.size() - ip_start - 40;  // subtract IPv6 fixed header
                        if (ip6.payload_length > remaining)
                            result.errors.push_back($sformatf(
                                "layer[%0d] IPv6: payload_length=%0d > remaining data=%0d",
                                i, ip6.payload_length, remaining));
                    end
                end
                PROTO_UDP: begin
                    udp_header udp;
                    if ($cast(udp, pkt.layer_stack[i])) begin
                        int remaining = pkt.raw_data.size();
                        int udp_start = 0;
                        for (int k = 0; k < i; k++)
                            udp_start += pkt.layer_stack[k].get_header_length();
                        remaining = pkt.raw_data.size() - udp_start;
                        if (udp.length > remaining)
                            result.errors.push_back($sformatf(
                                "layer[%0d] UDP: length=%0d > remaining data=%0d",
                                i, udp.length, remaining));
                    end
                end
            endcase
        end
    endfunction

    // =========================================================================
    // Type field consistency: ethertype, IP protocol, port vs actual next layer
    // =========================================================================
    protected function void verify_type_field_consistency(packet pkt, ref parse_result_t result);
        for (int i = 0; i < int'(pkt.layer_stack.size()) - 1; i++) begin
            protocol_type_e actual_next = pkt.layer_stack[i+1].proto_type;

            case (pkt.layer_stack[i].proto_type)
                PROTO_ETHERNET: begin
                    eth_header eth;
                    if ($cast(eth, pkt.layer_stack[i])) begin
                        protocol_type_e expected = packet::ethertype_to_proto(eth.ethertype);
                        if (expected != PROTO_RAW_PAYLOAD && expected != actual_next)
                            result.errors.push_back($sformatf(
                                "layer[%0d] Ethernet: ethertype=0x%04x implies %s but next layer is %s",
                                i, eth.ethertype, expected.name(), actual_next.name()));
                    end
                end
                PROTO_VLAN, PROTO_QINQ: begin
                    vlan_header v;
                    if ($cast(v, pkt.layer_stack[i])) begin
                        protocol_type_e expected = packet::ethertype_to_proto(v.ethertype);
                        if (expected != PROTO_RAW_PAYLOAD && expected != actual_next)
                            result.errors.push_back($sformatf(
                                "layer[%0d] VLAN: ethertype=0x%04x implies %s but next layer is %s",
                                i, v.ethertype, expected.name(), actual_next.name()));
                    end
                end
                PROTO_IPV4: begin
                    ipv4_header ip4;
                    if ($cast(ip4, pkt.layer_stack[i])) begin
                        protocol_type_e expected = packet::ip_proto_to_proto(ip4.protocol);
                        if (expected != PROTO_RAW_PAYLOAD && expected != actual_next)
                            result.errors.push_back($sformatf(
                                "layer[%0d] IPv4: protocol=%0d implies %s but next layer is %s",
                                i, ip4.protocol, expected.name(), actual_next.name()));
                    end
                end
                PROTO_IPV6: begin
                    ipv6_header ip6;
                    if ($cast(ip6, pkt.layer_stack[i])) begin
                        protocol_type_e expected = packet::ipv6_nh_to_proto(ip6.next_header);
                        if (expected != PROTO_RAW_PAYLOAD && expected != actual_next)
                            result.errors.push_back($sformatf(
                                "layer[%0d] IPv6: next_header=%0d implies %s but next layer is %s",
                                i, ip6.next_header, expected.name(), actual_next.name()));
                    end
                end
            endcase
        end
    endfunction

    // =========================================================================
    // Print validation result
    // =========================================================================
    function string result_to_string(parse_result_t result);
        string s = "";
        if (result.valid)
            s = "VALIDATE: PASS\n";
        else
            s = $sformatf("VALIDATE: FAIL — %0d error(s)\n", result.errors.size());

        // Chain
        begin
            string chain_str = "";
            foreach (result.proto_chain[i]) begin
                if (i > 0) chain_str = {chain_str, " -> "};
                chain_str = {chain_str, result.proto_chain[i].name()};
            end
            s = {s, $sformatf("  Chain: %s\n", chain_str)};
        end

        // Errors
        foreach (result.errors[i])
            s = {s, $sformatf("  ERROR: %s\n", result.errors[i])};

        // Warnings
        foreach (result.warnings[i])
            s = {s, $sformatf("  WARNING: %s\n", result.warnings[i])};

        return s;
    endfunction

endclass

`endif // PROTOCOL_PARSER_SV

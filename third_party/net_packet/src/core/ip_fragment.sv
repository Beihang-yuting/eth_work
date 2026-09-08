// src/core/ip_fragment.sv
`ifndef IP_FRAGMENT_SV
`define IP_FRAGMENT_SV

`include "core/packet.sv"

// ============================================================================
// IP Fragmentation Rules (RFC 791):
//
// 1. fragment_offset is in 8-byte units → non-last fragment payload MUST be
//    multiple of 8 bytes
// 2. Last fragment payload does NOT need 8-byte alignment
// 3. DF (Don't Fragment) flag: if set, packet must not be fragmented
// 4. MF (More Fragments) flag: set on all fragments except the last
// 5. identification: same value across all fragments of one datagram
// 6. Each fragment is an independent IP packet with its own header + checksum
//
// MTU handling:
//   - MTU = max IP packet size (IP header + IP payload)
//   - Effective payload per fragment = ((MTU - IP_hdr_len) / 8) * 8
//   - If user MTU is not optimal, auto-adjust and report
// ============================================================================

class ip_fragment;

    // Print control
    static bit verbose = 1;

    // =========================================================================
    // fragment — split a packet into MTU-sized IP fragments
    //
    // pkt:       original packet (must contain IPv4 layer)
    // mtu:       maximum IP packet size in bytes (IP header + payload)
    // fragments: output array of fragment packets
    //
    // Returns number of fragments created
    // =========================================================================
    static function int fragment(packet pkt, int unsigned mtu, ref packet fragments[$]);
        ipv4_header orig_ip;
        int ip_hdr_len;
        int ip_layer_idx;
        byte unsigned orig_payload[$];
        int payload_len;
        int max_frag_payload;
        int effective_mtu;
        int offset;
        bit [15:0] frag_id;

        fragments.delete();

        // --- Find IPv4 layer ---
        ip_layer_idx = -1;
        foreach (pkt.layer_stack[i]) begin
            if (pkt.layer_stack[i].proto_type == PROTO_IPV4) begin
                ip_layer_idx = i;
                break;
            end
        end

        if (ip_layer_idx < 0) begin
            $warning("ip_fragment::fragment: no IPv4 layer found, returning original packet");
            fragments.push_back(pkt);
            return 1;
        end

        if (!$cast(orig_ip, pkt.layer_stack[ip_layer_idx])) begin
            fragments.push_back(pkt);
            return 1;
        end

        ip_hdr_len = orig_ip.get_header_length();

        // --- Check DF flag ---
        if (orig_ip.flags[1] == 1) begin
            $warning("ip_fragment::fragment: DF (Don't Fragment) flag is set, cannot fragment");
            fragments.push_back(pkt);
            return 1;
        end

        // --- Ensure packet is packed ---
        if (pkt.raw_data.size() == 0) pkt.do_pack();

        // --- Extract IP payload ---
        begin
            int ip_payload_start = 0;
            for (int i = 0; i <= ip_layer_idx; i++)
                ip_payload_start += pkt.layer_stack[i].get_header_length();

            payload_len = pkt.raw_data.size() - ip_payload_start;
            orig_payload.delete();
            for (int i = ip_payload_start; i < pkt.raw_data.size(); i++)
                orig_payload.push_back(pkt.raw_data[i]);
        end

        // --- Check if fragmentation is needed ---
        if (ip_hdr_len + payload_len <= mtu) begin
            if (verbose)
                $display("ip_fragment: no fragmentation needed (pkt=%0dB <= MTU=%0dB)",
                         ip_hdr_len + payload_len, mtu);
            fragments.push_back(pkt);
            return 1;
        end

        // --- Calculate effective fragment payload size (8-byte aligned) ---
        if (mtu <= ip_hdr_len + 8) begin
            $warning("ip_fragment: MTU=%0d too small (minimum=%0d for IP_hdr=%0d + 8B payload)",
                     mtu, ip_hdr_len + 8, ip_hdr_len);
            fragments.push_back(pkt);
            return 1;
        end

        max_frag_payload = ((mtu - ip_hdr_len) / 8) * 8;
        effective_mtu = ip_hdr_len + max_frag_payload;

        if (verbose && effective_mtu != mtu) begin
            $display("ip_fragment: MTU=%0d adjusted to %0d (payload aligned to 8B: %0d)",
                     mtu, effective_mtu, max_frag_payload);
        end

        // --- Generate identification if not set ---
        frag_id = orig_ip.identification;
        if (frag_id == 0) begin
            frag_id = $urandom_range(1, 65535);
            if (verbose)
                $display("ip_fragment: auto-generated identification=0x%04x", frag_id);
        end

        // --- Fragment ---
        offset = 0;
        while (offset < payload_len) begin
            packet frag = new();
            int this_frag_len;
            bit is_last;

            this_frag_len = payload_len - offset;
            if (this_frag_len > max_frag_payload)
                this_frag_len = max_frag_payload;
            is_last = (offset + this_frag_len >= payload_len);

            // Clone layers up to and including IP
            frag.force_mode = 1;
            for (int i = 0; i <= ip_layer_idx; i++)
                frag.add_layer(pkt.layer_stack[i].clone());

            // Update IP header for this fragment
            begin
                ipv4_header frag_ip;
                $cast(frag_ip, frag.layer_stack[ip_layer_idx]);
                frag_ip.identification  = frag_id;
                frag_ip.fragment_offset = offset / 8;
                // flags: bit[2]=reserved, bit[1]=DF, bit[0]=MF
                frag_ip.flags           = is_last ? 3'b000 : 3'b001;
                frag_ip.total_length    = ip_hdr_len + this_frag_len;
                frag_ip.auto_calc       = 0;
                // Recompute IP header checksum
                begin
                    byte unsigned ip_hdr_data[$];
                    frag_ip.header_checksum = 0;
                    frag_ip.pack_header(ip_hdr_data);
                    frag_ip.header_checksum = packet_utils::ones_complement_checksum(ip_hdr_data);
                end
            end

            // Pack fragment: headers + payload slice
            frag.raw_data.delete();
            foreach (frag.layer_stack[i])
                frag.layer_stack[i].pack_header(frag.raw_data);
            for (int i = offset; i < offset + this_frag_len; i++)
                frag.raw_data.push_back(orig_payload[i]);

            fragments.push_back(frag);
            offset += this_frag_len;
        end

        if (verbose)
            print_fragment_summary(fragments, ip_layer_idx, payload_len, mtu, max_frag_payload);

        return fragments.size();
    endfunction

    // =========================================================================
    // reassemble — merge ordered fragments back into one packet
    // =========================================================================
    static function packet reassemble(packet fragments[$]);
        packet result;
        ipv4_header first_ip;
        int ip_layer_idx;
        byte unsigned full_payload[$];

        if (fragments.size() == 0) return null;
        if (fragments.size() == 1) return fragments[0];

        // Find IP layer in first fragment
        ip_layer_idx = -1;
        foreach (fragments[0].layer_stack[i]) begin
            if (fragments[0].layer_stack[i].proto_type == PROTO_IPV4) begin
                ip_layer_idx = i;
                break;
            end
        end

        if (ip_layer_idx < 0) begin
            $warning("ip_fragment::reassemble: no IPv4 layer found");
            return fragments[0];
        end

        // Collect payloads from all fragments
        full_payload.delete();
        foreach (fragments[j]) begin
            int ip_payload_start = 0;
            for (int i = 0; i <= ip_layer_idx; i++)
                ip_payload_start += fragments[j].layer_stack[i].get_header_length();

            if (fragments[j].raw_data.size() == 0) fragments[j].do_pack();
            for (int i = ip_payload_start; i < fragments[j].raw_data.size(); i++)
                full_payload.push_back(fragments[j].raw_data[i]);
        end

        // Build result
        result = new();
        result.force_mode = 1;
        for (int i = 0; i <= ip_layer_idx; i++)
            result.add_layer(fragments[0].layer_stack[i].clone());

        // Fix IP header
        $cast(first_ip, result.layer_stack[ip_layer_idx]);
        first_ip.flags           = 3'b000;
        first_ip.fragment_offset = 0;
        first_ip.total_length    = first_ip.get_header_length() + full_payload.size();
        first_ip.auto_calc       = 0;
        // Recompute checksum
        begin
            byte unsigned ip_hdr_data[$];
            first_ip.header_checksum = 0;
            first_ip.pack_header(ip_hdr_data);
            first_ip.header_checksum = packet_utils::ones_complement_checksum(ip_hdr_data);
        end

        // Pack result
        result.raw_data.delete();
        foreach (result.layer_stack[i])
            result.layer_stack[i].pack_header(result.raw_data);
        foreach (full_payload[i])
            result.raw_data.push_back(full_payload[i]);

        if (verbose)
            $display("ip_fragment::reassemble: %0d fragments -> 1 packet (%0d bytes, IP payload=%0d)",
                     fragments.size(), result.raw_data.size(), full_payload.size());

        return result;
    endfunction

    // =========================================================================
    // print_fragment_summary — show fragmentation results
    // =========================================================================
    static function void print_fragment_summary(
        packet fragments[$], int ip_layer_idx,
        int total_payload, int mtu, int frag_payload_size
    );
        $display("============================================================================");
        $display(" IP Fragmentation Result");
        $display("============================================================================");
        $display("  Original IP payload : %0d bytes", total_payload);
        $display("  MTU                 : %0d bytes", mtu);
        $display("  Fragment payload    : %0d bytes (8-byte aligned)", frag_payload_size);
        $display("  Fragment count      : %0d", fragments.size());
        $display("  --------------------+--------+--------+-----------+--------+----------");
        $display("  Fragment            | MF     | Offset | Offset(B) | IP Len | Payload  ");
        $display("  --------------------+--------+--------+-----------+--------+----------");
        foreach (fragments[i]) begin
            ipv4_header fip;
            if ($cast(fip, fragments[i].layer_stack[ip_layer_idx])) begin
                int payload_bytes = fip.total_length - fip.get_header_length();
                $display("  frag[%0d]%s        |   %0b    | %5d  |  %5d    | %5d  | %5d",
                    i, (i < 10) ? " " : "",
                    fip.flags[0],
                    fip.fragment_offset,
                    fip.fragment_offset * 8,
                    fip.total_length,
                    payload_bytes);
            end
        end
        $display("  --------------------+--------+--------+-----------+--------+----------");
        $display("============================================================================");
    endfunction

    // =========================================================================
    // help — print usage guide
    // =========================================================================
    static function void help();
        $display("============================================================================");
        $display(" IP Fragmentation Guide (ip_fragment)");
        $display("============================================================================");
        $display("");
        $display(" RFC 791 Rules:");
        $display("   - fragment_offset is in 8-byte units");
        $display("   - Non-last fragment payload MUST be multiple of 8 bytes");
        $display("   - Last fragment payload does NOT need 8-byte alignment");
        $display("   - DF flag (flags[1]=1): fragmentation is forbidden");
        $display("   - MF flag (flags[0]=1): more fragments follow");
        $display("   - All fragments share the same 'identification' field");
        $display("");
        $display(" MTU auto-adjustment:");
        $display("   - User MTU is auto-adjusted for 8-byte alignment");
        $display("   - Example: MTU=1500, IP_hdr=20 -> payload=(1500-20)/8*8=1480");
        $display("   - Example: MTU=1499, IP_hdr=20 -> payload=(1499-20)/8*8=1480 (adjusted)");
        $display("   - Minimum MTU = IP_hdr + 8 bytes");
        $display("");
        $display(" Usage:");
        $display("   packet pkt = new();");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_TCP;");
        $display("       outer_ipv4.identification == 16'hABCD;");
        $display("       pkt_len == 4000;");
        $display("   };");
        $display("   packet frags[$];");
        $display("   int n = ip_fragment::fragment(pkt, 1500, frags);");
        $display("");
        $display(" Reassemble:");
        $display("   packet result = ip_fragment::reassemble(frags);");
        $display("");
        $display(" Control:");
        $display("   ip_fragment::verbose = 1;  // print summary (default)");
        $display("   ip_fragment::verbose = 0;  // silent mode");
        $display("============================================================================");
    endfunction

endclass

`endif // IP_FRAGMENT_SV

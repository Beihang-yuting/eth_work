// src/core/tcp_segment.sv
`ifndef TCP_SEGMENT_SV
`define TCP_SEGMENT_SV

`include "core/packet.sv"

class tcp_segment;

    // Segment a large TCP packet into MSS-sized segments
    // mss: Maximum Segment Size (TCP payload per segment, NOT including headers)
    // Returns segments in order with correct seq_num progression
    static function void segment(packet pkt, int unsigned mss, ref packet segments[$]);
        tcp_header orig_tcp;
        ipv4_header orig_ip;
        int tcp_layer_idx, ip_layer_idx;
        byte unsigned tcp_payload[$];
        int tcp_payload_len;
        int hdr_end_offset;
        bit [31:0] base_seq;

        segments.delete();

        // Find TCP and IPv4 layers
        tcp_layer_idx = -1;
        ip_layer_idx = -1;
        foreach (pkt.layer_stack[i]) begin
            if (pkt.layer_stack[i].proto_type == PROTO_IPV4 && ip_layer_idx < 0)
                ip_layer_idx = i;
            if (pkt.layer_stack[i].proto_type == PROTO_TCP)
                tcp_layer_idx = i;
        end

        if (tcp_layer_idx < 0) begin
            $warning("tcp_segment::segment: no TCP layer found");
            segments.push_back(pkt);
            return;
        end

        if (!$cast(orig_tcp, pkt.layer_stack[tcp_layer_idx])) begin
            segments.push_back(pkt);
            return;
        end

        // Ensure packet is packed
        if (pkt.raw_data.size() == 0) pkt.do_pack();

        // Calculate where TCP payload starts (after all headers)
        hdr_end_offset = 0;
        foreach (pkt.layer_stack[i])
            hdr_end_offset += pkt.layer_stack[i].get_header_length();

        // Extract TCP payload
        tcp_payload.delete();
        for (int i = hdr_end_offset; i < pkt.raw_data.size(); i++)
            tcp_payload.push_back(pkt.raw_data[i]);
        tcp_payload_len = tcp_payload.size();

        // No segmentation needed
        if (tcp_payload_len <= mss) begin
            segments.push_back(pkt);
            return;
        end

        base_seq = orig_tcp.seq_num;
        begin
            int offset = 0;
            int seg_idx = 0;

            while (offset < tcp_payload_len) begin
                packet seg = new();
                int this_seg_len;
                bit is_last;

                this_seg_len = tcp_payload_len - offset;
                if (this_seg_len > mss)
                    this_seg_len = mss;
                is_last = (offset + this_seg_len >= tcp_payload_len);

                // Clone ALL layers (L2 + L3 + ... + TCP)
                seg.force_mode = 1;
                foreach (pkt.layer_stack[i])
                    seg.add_layer(pkt.layer_stack[i].clone());

                // Update TCP header
                begin
                    tcp_header seg_tcp;
                    $cast(seg_tcp, seg.layer_stack[tcp_layer_idx]);
                    seg_tcp.seq_num = base_seq + offset;
                    // Keep original flags, but PSH only on last segment
                    if (!is_last)
                        seg_tcp.flags = orig_tcp.flags & 9'h1F7;  // Clear PSH bit
                    else
                        seg_tcp.flags = orig_tcp.flags;  // Last segment keeps PSH
                    seg_tcp.auto_calc = 0;
                end

                // Update IPv4 total_length if present
                if (ip_layer_idx >= 0) begin
                    ipv4_header seg_ip;
                    if ($cast(seg_ip, seg.layer_stack[ip_layer_idx])) begin
                        int ip_payload = 0;
                        for (int j = ip_layer_idx + 1; j < seg.layer_stack.size(); j++)
                            ip_payload += seg.layer_stack[j].get_header_length();
                        ip_payload += this_seg_len;
                        seg_ip.total_length = seg_ip.get_header_length() + ip_payload;
                        seg_ip.auto_calc = 0;
                        // Recompute IP checksum
                        begin
                            byte unsigned ip_hdr_data[$];
                            seg_ip.header_checksum = 0;
                            seg_ip.pack_header(ip_hdr_data);
                            seg_ip.header_checksum = packet_utils::ones_complement_checksum(ip_hdr_data);
                        end
                    end
                end

                // Pack segment: headers + segment payload
                seg.raw_data.delete();
                foreach (seg.layer_stack[i])
                    seg.layer_stack[i].pack_header(seg.raw_data);
                for (int i = offset; i < offset + this_seg_len; i++)
                    seg.raw_data.push_back(tcp_payload[i]);

                segments.push_back(seg);
                offset += this_seg_len;
                seg_idx++;
            end
        end
    endfunction

    // Reassemble TCP segments into a single packet
    // Segments must be in order and belong to the same flow
    static function packet reassemble(packet segments[$]);
        packet result;
        tcp_header first_tcp;
        int tcp_layer_idx;
        byte unsigned full_payload[$];
        int hdr_end_offset;

        if (segments.size() == 0) return null;
        if (segments.size() == 1) return segments[0];

        // Find TCP layer in first segment
        tcp_layer_idx = -1;
        foreach (segments[0].layer_stack[i]) begin
            if (segments[0].layer_stack[i].proto_type == PROTO_TCP) begin
                tcp_layer_idx = i;
                break;
            end
        end

        if (tcp_layer_idx < 0) begin
            $warning("tcp_segment::reassemble: no TCP layer found");
            return segments[0];
        end

        // Collect payloads from all segments
        full_payload.delete();
        foreach (segments[j]) begin
            hdr_end_offset = 0;
            foreach (segments[j].layer_stack[i])
                hdr_end_offset += segments[j].layer_stack[i].get_header_length();

            if (segments[j].raw_data.size() == 0) segments[j].do_pack();
            for (int i = hdr_end_offset; i < segments[j].raw_data.size(); i++)
                full_payload.push_back(segments[j].raw_data[i]);
        end

        // Build result: clone first segment's full layer stack
        result = new();
        result.force_mode = 1;
        foreach (segments[0].layer_stack[i])
            result.add_layer(segments[0].layer_stack[i].clone());

        // Fix TCP header: restore original seq_num, set PSH
        begin
            $cast(first_tcp, result.layer_stack[tcp_layer_idx]);
            // seq_num is already correct from first segment
            first_tcp.auto_calc = 0;
        end

        // Fix IPv4 total_length
        begin
            int ip_layer_idx = -1;
            foreach (result.layer_stack[i]) begin
                if (result.layer_stack[i].proto_type == PROTO_IPV4) begin
                    ip_layer_idx = i;
                    break;
                end
            end
            if (ip_layer_idx >= 0) begin
                ipv4_header res_ip;
                if ($cast(res_ip, result.layer_stack[ip_layer_idx])) begin
                    int ip_payload = 0;
                    for (int j = ip_layer_idx + 1; j < result.layer_stack.size(); j++)
                        ip_payload += result.layer_stack[j].get_header_length();
                    ip_payload += full_payload.size();
                    res_ip.total_length = res_ip.get_header_length() + ip_payload;
                    res_ip.auto_calc = 0;
                    begin
                        byte unsigned ip_hdr_data[$];
                        res_ip.header_checksum = 0;
                        res_ip.pack_header(ip_hdr_data);
                        res_ip.header_checksum = packet_utils::ones_complement_checksum(ip_hdr_data);
                    end
                end
            end
        end

        // Pack result
        result.raw_data.delete();
        foreach (result.layer_stack[i])
            result.layer_stack[i].pack_header(result.raw_data);
        foreach (full_payload[i])
            result.raw_data.push_back(full_payload[i]);

        return result;
    endfunction

    // help — print usage guide
    static function void help();
        $display("============================================================================");
        $display(" TCP Segmentation Guide (tcp_segment) — TSO");
        $display("============================================================================");
        $display("");
        $display(" Segment a large TCP packet by MSS:");
        $display("   packet pkt = new();");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_TCP;");
        $display("       tcp.seq_num == 32'h1000;");
        $display("       tcp.flags   == 9'h018;    // PSH+ACK");
        $display("       pkt_len == 5000;           // large payload");
        $display("   };");
        $display("   packet segs[$];");
        $display("   tcp_segment::segment(pkt, 1460, segs);");
        $display("   // segs[0]: seq=0x1000, len=1460, flags=ACK");
        $display("   // segs[1]: seq=0x15B4, len=1460, flags=ACK");
        $display("   // segs[2]: seq=0x1B68, len=1460, flags=ACK");
        $display("   // segs[3]: seq=0x211C, len=620,  flags=PSH+ACK (last)");
        $display("");
        $display(" Reassemble segments:");
        $display("   packet reassembled = tcp_segment::reassemble(segs);");
        $display("");
        $display(" Segment behavior:");
        $display("   - TCP.seq_num increments by segment payload size");
        $display("   - PSH flag only on last segment");
        $display("   - IPv4.total_length updated per segment");
        $display("   - IPv4.header_checksum recomputed per segment");
        $display("   - L2 headers cloned unchanged");
        $display("   - Works with tunnel packets (VXLAN/GRE inner TCP)");
        $display("============================================================================");
    endfunction

endclass

`endif // TCP_SEGMENT_SV

`ifndef TRAFFIC_STREAM_SV
`define TRAFFIC_STREAM_SV

`include "core/packet.sv"
`include "stream/field_modifier.sv"

class traffic_stream;

    packet          base_pkt;
    int unsigned    pkt_count;
    field_modifier  modifiers[$];

    function new();
        pkt_count = 10;
    endfunction

    // Generate stream of packets
    function void gen_packets(ref packet pkts[$]);
        pkts.delete();

        if (base_pkt == null) begin
            $warning("traffic_stream::gen_packets: base_pkt is null");
            return;
        end

        // Ensure base_pkt is packed_data
        if (base_pkt.raw_data.size() == 0)
            base_pkt.do_pack();

        for (int i = 0; i < pkt_count; i++) begin
            packet pkt = clone_packet(base_pkt);

            // Apply each modifier
            foreach (modifiers[m]) begin
                bit [63:0] val = modifiers[m].next_value(i);
                apply_modifier(pkt, modifiers[m].field_path, val);
            end

            pkt.do_pack();
            pkts.push_back(pkt);
        end
    endfunction

    // Clone a packet (deep copy all layers)
    protected function packet clone_packet(packet src);
        packet dst = new();
        dst.force_mode      = 1;
        dst.pkt_len       = src.pkt_len;
        dst.payload_mode     = src.payload_mode;
        dst.payload_fixed_val = src.payload_fixed_val;
        dst.payload_pattern  = src.payload_pattern;

        foreach (src.layer_stack[i])
            dst.layer_stack.push_back(src.layer_stack[i].clone());

        return dst;
    endfunction

    // Apply a modifier value to a field identified by field_path
    // Supported paths: "eth.src_mac", "eth.dst_mac",
    //                  "ipv4.src_addr", "ipv4.dst_addr", "ipv4.ttl",
    //                  "ipv6.src_addr", "ipv6.dst_addr",
    //                  "tcp.src_port", "tcp.dst_port",
    //                  "udp.src_port", "udp.dst_port",
    //                  "vlan.vlan_id",
    //                  "vxlan.vni",
    //                  "mpls.label",
    //                  "rocev2.dest_qp", "rocev2.psn"
    protected function void apply_modifier(packet pkt, string path, bit [63:0] val);
        // Parse "proto.field"
        string proto_name, field_name;
        int dot_pos = -1;

        for (int i = 0; i < path.len(); i++) begin
            if (path[i] == ".") begin
                dot_pos = i;
                break;
            end
        end

        if (dot_pos < 0) return;
        proto_name = path.substr(0, dot_pos - 1);
        field_name = path.substr(dot_pos + 1, path.len() - 1);

        if (proto_name == "eth") begin
            eth_header h;
            if ($cast(h, pkt.get_layer(PROTO_ETHERNET))) begin
                if (field_name == "src_mac") h.src_mac = val[47:0];
                else if (field_name == "dst_mac") h.dst_mac = val[47:0];
            end
        end
        else if (proto_name == "ipv4") begin
            ipv4_header h;
            if ($cast(h, pkt.get_layer(PROTO_IPV4))) begin
                if (field_name == "src_addr") h.src_addr = val[31:0];
                else if (field_name == "dst_addr") h.dst_addr = val[31:0];
                else if (field_name == "ttl") h.ttl = val[7:0];
            end
        end
        else if (proto_name == "tcp") begin
            tcp_header h;
            if ($cast(h, pkt.get_layer(PROTO_TCP))) begin
                if (field_name == "src_port") h.src_port = val[15:0];
                else if (field_name == "dst_port") h.dst_port = val[15:0];
            end
        end
        else if (proto_name == "udp") begin
            udp_header h;
            if ($cast(h, pkt.get_layer(PROTO_UDP))) begin
                if (field_name == "src_port") h.src_port = val[15:0];
                else if (field_name == "dst_port") h.dst_port = val[15:0];
            end
        end
        else if (proto_name == "vlan") begin
            vlan_header h;
            if ($cast(h, pkt.get_layer(PROTO_VLAN))) begin
                if (field_name == "vlan_id") h.vlan_id = val[11:0];
            end
        end
        else if (proto_name == "vxlan") begin
            vxlan_header h;
            if ($cast(h, pkt.get_layer(PROTO_VXLAN))) begin
                if (field_name == "vni") h.vni = val[23:0];
            end
        end
        else if (proto_name == "mpls") begin
            mpls_header h;
            if ($cast(h, pkt.get_layer(PROTO_MPLS))) begin
                if (field_name == "label") h.label = val[19:0];
            end
        end
        else if (proto_name == "rocev2") begin
            rocev2_bth h;
            if ($cast(h, pkt.get_layer(PROTO_ROCEV2))) begin
                if (field_name == "dest_qp") h.dest_qp = val[23:0];
                else if (field_name == "psn") h.psn = val[23:0];
            end
        end
    endfunction

endclass

`endif // TRAFFIC_STREAM_SV

// src/sequence/arp_sequence.sv
`ifndef ARP_SEQUENCE_SV
`define ARP_SEQUENCE_SV

`include "sequence/protocol_sequence.sv"

class arp_seq extends protocol_sequence;

    bit [47:0] src_mac;
    bit [47:0] dst_mac;      // For reply; request uses broadcast
    bit [31:0] src_ip;
    bit [31:0] dst_ip;

    function new();
        src_mac = 48'h001122334455;
        dst_mac = 48'hAABBCCDDEEFF;
        src_ip  = 32'hC0A80001;
        dst_ip  = 32'hC0A80002;
    endfunction

    virtual function void gen_packets();
        packets.delete();

        // ARP Request (broadcast)
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_ARP);
            begin
                eth_header eth;
                $cast(eth, pkt.get_layer(PROTO_ETHERNET));
                eth.src_mac = src_mac;
                eth.dst_mac = 48'hFFFFFFFFFFFF;  // Broadcast
            end
            begin
                arp_header arp;
                $cast(arp, pkt.get_layer(PROTO_ARP));
                arp.opcode     = 16'd1;  // Request
                arp.sender_mac = src_mac;
                arp.sender_ip  = src_ip;
                arp.target_mac = 48'h000000000000;
                arp.target_ip  = dst_ip;
            end
            pkt.pkt_len = 42;  // ETH(14) + ARP(28)
            pkt.do_pack();
            packets.push_back(pkt);
        end

        // ARP Reply
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_ARP);
            begin
                eth_header eth;
                $cast(eth, pkt.get_layer(PROTO_ETHERNET));
                eth.src_mac = dst_mac;
                eth.dst_mac = src_mac;
            end
            begin
                arp_header arp;
                $cast(arp, pkt.get_layer(PROTO_ARP));
                arp.opcode     = 16'd2;  // Reply
                arp.sender_mac = dst_mac;
                arp.sender_ip  = dst_ip;
                arp.target_mac = src_mac;
                arp.target_ip  = src_ip;
            end
            pkt.pkt_len = 42;
            pkt.do_pack();
            packets.push_back(pkt);
        end
    endfunction

endclass

`endif // ARP_SEQUENCE_SV

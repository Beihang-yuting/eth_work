// src/sequence/icmp_sequence.sv
`ifndef ICMP_SEQUENCE_SV
`define ICMP_SEQUENCE_SV

`include "sequence/protocol_sequence.sv"

class icmp_ping_seq extends protocol_sequence;

    bit [47:0] src_mac;
    bit [47:0] dst_mac;
    bit [31:0] src_ip;
    bit [31:0] dst_ip;
    bit [15:0] identifier;
    bit [15:0] sequence_number;
    int unsigned ping_length;

    function new();
        src_mac         = 48'h001122334455;
        dst_mac         = 48'hAABBCCDDEEFF;
        src_ip          = 32'hC0A80001;
        dst_ip          = 32'hC0A80002;
        identifier      = 16'h1234;
        sequence_number = 16'h0001;
        ping_length     = 64;
    endfunction

    virtual function void gen_packets();
        packets.delete();

        // Echo Request (type=8, code=0)
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_ICMP);
            begin
                eth_header eth;
                $cast(eth, pkt.get_layer(PROTO_ETHERNET));
                eth.src_mac = src_mac;
                eth.dst_mac = dst_mac;
            end
            begin
                ipv4_header ip;
                $cast(ip, pkt.get_layer(PROTO_IPV4));
                ip.src_addr = src_ip;
                ip.dst_addr = dst_ip;
            end
            begin
                icmp_header icmp;
                $cast(icmp, pkt.get_layer(PROTO_ICMP));
                icmp.icmp_type   = 8;  // Echo Request
                icmp.icmp_code   = 0;
                icmp.identifier  = identifier;
                icmp.sequence_num = sequence_number;
            end
            pkt.pkt_len = ping_length;
            pkt.do_pack();
            packets.push_back(pkt);
        end

        // Echo Reply (type=0, code=0) — reversed src/dst
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_ICMP);
            begin
                eth_header eth;
                $cast(eth, pkt.get_layer(PROTO_ETHERNET));
                eth.src_mac = dst_mac;
                eth.dst_mac = src_mac;
            end
            begin
                ipv4_header ip;
                $cast(ip, pkt.get_layer(PROTO_IPV4));
                ip.src_addr = dst_ip;
                ip.dst_addr = src_ip;
            end
            begin
                icmp_header icmp;
                $cast(icmp, pkt.get_layer(PROTO_ICMP));
                icmp.icmp_type    = 0;  // Echo Reply
                icmp.icmp_code    = 0;
                icmp.identifier   = identifier;
                icmp.sequence_num = sequence_number;
            end
            pkt.pkt_len = ping_length;
            pkt.do_pack();
            packets.push_back(pkt);
        end
    endfunction

endclass

`endif // ICMP_SEQUENCE_SV

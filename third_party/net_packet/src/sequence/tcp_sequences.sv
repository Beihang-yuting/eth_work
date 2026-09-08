// src/sequence/tcp_sequences.sv
`ifndef TCP_SEQUENCES_SV
`define TCP_SEQUENCES_SV

`include "sequence/protocol_sequence.sv"

class tcp_handshake_seq extends protocol_sequence;

    // Configurable parameters
    bit [47:0] src_mac;
    bit [47:0] dst_mac;
    bit [31:0] src_ip;
    bit [31:0] dst_ip;
    bit [15:0] src_port;
    bit [15:0] dst_port;
    bit [31:0] isn_client;   // Initial sequence number (client)
    bit [31:0] isn_server;   // Initial sequence number (server)

    function new();
        src_mac    = 48'h001122334455;
        dst_mac    = 48'hAABBCCDDEEFF;
        src_ip     = 32'hC0A80001;
        dst_ip     = 32'hC0A80002;
        src_port   = 16'd12345;
        dst_port   = 16'd80;
        isn_client = 32'd1000;
        isn_server = 32'd2000;
    endfunction

    virtual function void gen_packets();
        packets.delete();

        // Packet 1: SYN (client -> server)
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_TCP);
            set_l2_l3(pkt, src_mac, dst_mac, src_ip, dst_ip);
            begin
                tcp_header tcp;
                $cast(tcp, pkt.get_layer(PROTO_TCP));
                tcp.src_port = src_port;
                tcp.dst_port = dst_port;
                tcp.seq_num  = isn_client;
                tcp.ack_num  = 0;
                tcp.flags    = 9'h002;  // SYN
            end
            pkt.pkt_len = 54;  // ETH(14) + IPv4(20) + TCP(20)
            pkt.do_pack();
            packets.push_back(pkt);
        end

        // Packet 2: SYN-ACK (server -> client)
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_TCP);
            set_l2_l3(pkt, dst_mac, src_mac, dst_ip, src_ip);
            begin
                tcp_header tcp;
                $cast(tcp, pkt.get_layer(PROTO_TCP));
                tcp.src_port = dst_port;
                tcp.dst_port = src_port;
                tcp.seq_num  = isn_server;
                tcp.ack_num  = isn_client + 1;
                tcp.flags    = 9'h012;  // SYN+ACK
            end
            pkt.pkt_len = 54;
            pkt.do_pack();
            packets.push_back(pkt);
        end

        // Packet 3: ACK (client -> server)
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_TCP);
            set_l2_l3(pkt, src_mac, dst_mac, src_ip, dst_ip);
            begin
                tcp_header tcp;
                $cast(tcp, pkt.get_layer(PROTO_TCP));
                tcp.src_port = src_port;
                tcp.dst_port = dst_port;
                tcp.seq_num  = isn_client + 1;
                tcp.ack_num  = isn_server + 1;
                tcp.flags    = 9'h010;  // ACK
            end
            pkt.pkt_len = 54;
            pkt.do_pack();
            packets.push_back(pkt);
        end
    endfunction

    // Helper to set L2/L3 fields
    protected function void set_l2_l3(packet pkt,
                                       bit [47:0] smac, bit [47:0] dmac,
                                       bit [31:0] sip, bit [31:0] dip);
        begin
            eth_header eth;
            $cast(eth, pkt.get_layer(PROTO_ETHERNET));
            eth.src_mac = smac;
            eth.dst_mac = dmac;
        end
        begin
            ipv4_header ip;
            $cast(ip, pkt.get_layer(PROTO_IPV4));
            ip.src_addr = sip;
            ip.dst_addr = dip;
        end
    endfunction

endclass

class tcp_full_session_seq extends protocol_sequence;

    // Configurable parameters
    bit [47:0] src_mac;
    bit [47:0] dst_mac;
    bit [31:0] src_ip;
    bit [31:0] dst_ip;
    bit [15:0] src_port;
    bit [15:0] dst_port;
    bit [31:0] isn_client;
    bit [31:0] isn_server;
    int unsigned data_pkt_count;
    int unsigned data_pkt_len;

    function new();
        src_mac         = 48'h001122334455;
        dst_mac         = 48'hAABBCCDDEEFF;
        src_ip          = 32'hC0A80001;
        dst_ip          = 32'hC0A80002;
        src_port        = 16'd12345;
        dst_port        = 16'd80;
        isn_client      = 32'd1000;
        isn_server      = 32'd2000;
        data_pkt_count  = 3;
        data_pkt_len = 100;
    endfunction

    virtual function void gen_packets();
        bit [31:0] client_seq;
        bit [31:0] server_seq;
        int payload_per_pkt;

        packets.delete();
        payload_per_pkt = data_pkt_len - 54;  // minus ETH+IP+TCP headers
        if (payload_per_pkt < 0) payload_per_pkt = 0;

        client_seq = isn_client;
        server_seq = isn_server;

        // === Three-way handshake ===

        // SYN
        begin
            packet pkt = build_tcp_pkt(src_mac, dst_mac, src_ip, dst_ip,
                                        src_port, dst_port, client_seq, 0, 9'h002, 54);
            packets.push_back(pkt);
        end
        client_seq += 1;  // SYN consumes 1 seq

        // SYN-ACK
        begin
            packet pkt = build_tcp_pkt(dst_mac, src_mac, dst_ip, src_ip,
                                        dst_port, src_port, server_seq, client_seq, 9'h012, 54);
            packets.push_back(pkt);
        end
        server_seq += 1;

        // ACK
        begin
            packet pkt = build_tcp_pkt(src_mac, dst_mac, src_ip, dst_ip,
                                        src_port, dst_port, client_seq, server_seq, 9'h010, 54);
            packets.push_back(pkt);
        end

        // === Data packets (client -> server) ===
        for (int i = 0; i < data_pkt_count; i++) begin
            packet pkt = build_tcp_pkt(src_mac, dst_mac, src_ip, dst_ip,
                                        src_port, dst_port, client_seq, server_seq,
                                        9'h018, data_pkt_len);  // PSH+ACK
            packets.push_back(pkt);
            client_seq += payload_per_pkt;
        end

        // === Four-way teardown ===

        // FIN (client -> server)
        begin
            packet pkt = build_tcp_pkt(src_mac, dst_mac, src_ip, dst_ip,
                                        src_port, dst_port, client_seq, server_seq, 9'h011, 54);  // FIN+ACK
            packets.push_back(pkt);
        end
        client_seq += 1;

        // ACK (server -> client)
        begin
            packet pkt = build_tcp_pkt(dst_mac, src_mac, dst_ip, src_ip,
                                        dst_port, src_port, server_seq, client_seq, 9'h010, 54);
            packets.push_back(pkt);
        end

        // FIN (server -> client)
        begin
            packet pkt = build_tcp_pkt(dst_mac, src_mac, dst_ip, src_ip,
                                        dst_port, src_port, server_seq, client_seq, 9'h011, 54);
            packets.push_back(pkt);
        end
        server_seq += 1;

        // ACK (client -> server)
        begin
            packet pkt = build_tcp_pkt(src_mac, dst_mac, src_ip, dst_ip,
                                        src_port, dst_port, client_seq, server_seq, 9'h010, 54);
            packets.push_back(pkt);
        end
    endfunction

    // Helper to build a TCP packet
    protected function packet build_tcp_pkt(
        bit [47:0] smac, bit [47:0] dmac,
        bit [31:0] sip, bit [31:0] dip,
        bit [15:0] sport, bit [15:0] dport,
        bit [31:0] seq, bit [31:0] ack,
        bit [8:0] tcp_flags, int pkt_len
    );
        packet pkt = new();
        pkt.build_from_template(ETH_IPV4_TCP);
        begin
            eth_header eth;
            $cast(eth, pkt.get_layer(PROTO_ETHERNET));
            eth.src_mac = smac;
            eth.dst_mac = dmac;
        end
        begin
            ipv4_header ip;
            $cast(ip, pkt.get_layer(PROTO_IPV4));
            ip.src_addr = sip;
            ip.dst_addr = dip;
        end
        begin
            tcp_header tcp;
            $cast(tcp, pkt.get_layer(PROTO_TCP));
            tcp.src_port = sport;
            tcp.dst_port = dport;
            tcp.seq_num  = seq;
            tcp.ack_num  = ack;
            tcp.flags    = tcp_flags;
        end
        pkt.pkt_len = pkt_len;
        pkt.do_pack();
        return pkt;
    endfunction

endclass

`endif // TCP_SEQUENCES_SV

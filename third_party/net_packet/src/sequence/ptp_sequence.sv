// src/sequence/ptp_sequence.sv
`ifndef PTP_SEQUENCE_SV
`define PTP_SEQUENCE_SV

`include "sequence/protocol_sequence.sv"

class ptp_sync_seq extends protocol_sequence;

    bit [47:0] master_mac;
    bit [47:0] slave_mac;
    bit [63:0] clock_identity;
    bit [15:0] port_number;
    bit [15:0] sequence_id;
    bit [7:0]  domain;

    function new();
        master_mac     = 48'h001122334455;
        slave_mac      = 48'hAABBCCDDEEFF;
        clock_identity = 64'h0011223344556677;
        port_number    = 16'd1;
        sequence_id    = 16'd0;
        domain         = 0;
    endfunction

    virtual function void gen_packets();
        packets.delete();

        // Sync (message_type = 0x0)
        packets.push_back(build_ptp_pkt(master_mac, slave_mac, 4'd0, sequence_id));

        // Follow_Up (message_type = 0x8)
        packets.push_back(build_ptp_pkt(master_mac, slave_mac, 4'd8, sequence_id));

        // Delay_Req (message_type = 0x1, slave -> master)
        packets.push_back(build_ptp_pkt(slave_mac, master_mac, 4'd1, sequence_id));

        // Delay_Resp (message_type = 0x9, master -> slave)
        packets.push_back(build_ptp_pkt(master_mac, slave_mac, 4'd9, sequence_id));
    endfunction

    protected function packet build_ptp_pkt(bit [47:0] smac, bit [47:0] dmac,
                                             bit [3:0] msg_type, bit [15:0] seq);
        packet pkt = new();
        pkt.build_from_template(ETH_PTP_L2);
        begin
            eth_header eth;
            $cast(eth, pkt.get_layer(PROTO_ETHERNET));
            eth.src_mac = smac;
            eth.dst_mac = dmac;
        end
        begin
            ptp_header ptp;
            $cast(ptp, pkt.get_layer(PROTO_PTP));
            ptp.message_type  = msg_type;
            ptp.domain_number = domain;
            ptp.clock_identity = clock_identity;
            ptp.port_number   = port_number;
            ptp.sequence_id   = seq;
        end
        pkt.pkt_len = 48;  // ETH(14) + PTP(34)
        pkt.do_pack();
        return pkt;
    endfunction

endclass

`endif // PTP_SEQUENCE_SV

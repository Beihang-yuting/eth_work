// src/sequence/protocol_sequence.sv
`ifndef PROTOCOL_SEQUENCE_SV
`define PROTOCOL_SEQUENCE_SV

`include "core/packet.sv"

virtual class protocol_sequence;

    packet packets[$];

    // Generate the sequence of packets
    pure virtual function void gen_packets();

    // Get all generated packets
    function void get_packets(ref packet pkts[$]);
        pkts = packets;
    endfunction

    // Get packet count
    function int get_count();
        return packets.size();
    endfunction

endclass

`endif // PROTOCOL_SEQUENCE_SV

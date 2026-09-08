// src/uvm_wrapper/protocol_seq_wrapper.sv
`ifndef PROTOCOL_SEQ_WRAPPER_SV
`define PROTOCOL_SEQ_WRAPPER_SV

`include "uvm_wrapper/packet_item.sv"
`include "sequence/protocol_sequence.sv"

`ifdef UVM
`include "uvm_macros.svh"
import uvm_pkg::*;

class protocol_seq_wrapper extends uvm_sequence #(packet_item);
    `uvm_object_utils(protocol_seq_wrapper)

    protocol_sequence inner_seq;

    function new(string name = "protocol_seq_wrapper");
        super.new(name);
    endfunction

    virtual task body();
        packet pkts[$];
        if (inner_seq == null) begin
            `uvm_error("PROTOCOL_SEQ_WRAPPER", "inner_seq is null")
            return;
        end
        inner_seq.gen_packets();
        inner_seq.get_packets(pkts);
        foreach (pkts[i]) begin
            packet_item item = packet_item::type_id::create($sformatf("item_%0d", i));
            item.pkt = pkts[i];
            `uvm_send(item)
        end
    endtask

endclass

`else
// Non-UVM stub
class protocol_seq_wrapper;
    protocol_sequence inner_seq;
    packet_item       items[$];

    function new(string name = "protocol_seq_wrapper");
    endfunction

    function void execute();
        packet pkts[$];
        items.delete();
        if (inner_seq == null) return;
        inner_seq.gen_packets();
        inner_seq.get_packets(pkts);
        foreach (pkts[i]) begin
            packet_item item = new($sformatf("item_%0d", i));
            item.pkt = pkts[i];
            items.push_back(item);
        end
    endfunction
endclass
`endif

`endif // PROTOCOL_SEQ_WRAPPER_SV

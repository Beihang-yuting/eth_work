// src/uvm_wrapper/packet_sequence.sv
`ifndef PACKET_SEQUENCE_SV
`define PACKET_SEQUENCE_SV

`include "uvm_wrapper/packet_item.sv"

`ifdef UVM
`include "uvm_macros.svh"
import uvm_pkg::*;

class packet_sequence extends uvm_sequence #(packet_item);
    `uvm_object_utils(packet_sequence)

    rand packet_template_e tmpl;
    rand int unsigned      pkt_len;

    constraint c_default {
        pkt_len inside {[64:1518]};
    }

    function new(string name = "packet_sequence");
        super.new(name);
        tmpl       = ETH_IPV4_TCP;
        pkt_len = 64;
    endfunction

    virtual task body();
        packet_item item = packet_item::type_id::create("item");
        item.pkt = new();
        item.pkt.build_from_template(tmpl);
        item.pkt.pkt_len = pkt_len;
        item.pkt.do_pack();
        `uvm_send(item)
    endtask

endclass

`else
// Non-UVM stub
class packet_sequence;
    packet_template_e tmpl;
    int unsigned      pkt_len;
    packet_item       item;

    function new(string name = "packet_sequence");
        tmpl       = ETH_IPV4_TCP;
        pkt_len = 64;
    endfunction

    function void execute();
        item = new();
        item.pkt = new();
        item.pkt.build_from_template(tmpl);
        item.pkt.pkt_len = pkt_len;
        item.pkt.do_pack();
    endfunction
endclass
`endif

`endif // PACKET_SEQUENCE_SV

// src/uvm_wrapper/packet_item.sv
`ifndef PACKET_ITEM_SV
`define PACKET_ITEM_SV

`include "core/packet.sv"

`ifdef UVM
`include "uvm_macros.svh"
import uvm_pkg::*;

class packet_item extends uvm_sequence_item;
    `uvm_object_utils(packet_item)

    packet pkt;

    function new(string name = "packet_item");
        super.new(name);
        pkt = new();
    endfunction

    virtual function void do_copy(uvm_object rhs);
        packet_item rhs_item;
        super.do_copy(rhs);
        if ($cast(rhs_item, rhs)) begin
            // Deep copy: clone all layers
            pkt = new();
            pkt.pkt_len       = rhs_item.pkt.pkt_len;
            pkt.payload_mode     = rhs_item.pkt.payload_mode;
            pkt.payload_fixed_val = rhs_item.pkt.payload_fixed_val;
            pkt.payload_pattern  = rhs_item.pkt.payload_pattern;
            pkt.force_mode       = rhs_item.pkt.force_mode;
            pkt.raw_data         = rhs_item.pkt.raw_data;
            foreach (rhs_item.pkt.layer_stack[i])
                pkt.layer_stack.push_back(rhs_item.pkt.layer_stack[i].clone());
        end
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        packet_item rhs_item;
        if (!$cast(rhs_item, rhs)) return 0;
        // Compare layer by layer
        if (pkt.layer_stack.size() != rhs_item.pkt.layer_stack.size()) return 0;
        foreach (pkt.layer_stack[i]) begin
            if (!pkt.layer_stack[i].compare(rhs_item.pkt.layer_stack[i])) return 0;
        end
        return 1;
    endfunction

    virtual function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_string("proto_chain", pkt.to_proto_chain());
        printer.print_int("raw_data_size", pkt.raw_data.size(), 32);
        printer.print_string("detail", pkt.to_detail());
    endfunction

    virtual function void do_pack(uvm_packer packer);
        super.do_pack(packer);
        if (pkt.raw_data.size() == 0) pkt.do_pack();
        packer.pack_field_int(pkt.raw_data.size(), 32);
        foreach (pkt.raw_data[i])
            packer.pack_field_int(pkt.raw_data[i], 8);
    endfunction

    virtual function void do_unpack(uvm_packer packer);
        int unsigned size;
        byte unsigned data[$];
        super.do_unpack(packer);
        size = packer.unpack_field_int(32);
        for (int i = 0; i < size; i++)
            data.push_back(packer.unpack_field_int(8));
        pkt = new();
        pkt.unpack(data);
    endfunction

endclass

`else
// Non-UVM stub: packet_item is a simple wrapper
class packet_item;
    packet pkt;

    function new(string name = "packet_item");
        pkt = new();
    endfunction
endclass
`endif

`endif // PACKET_ITEM_SV

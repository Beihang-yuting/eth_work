// src/protocols/protocol_base.sv
`ifndef PROTOCOL_BASE_SV
`define PROTOCOL_BASE_SV

`include "packet_defines.sv"
`include "packet_utils.sv"

virtual class protocol_base;

    protocol_type_e  proto_type;
    bit              auto_calc = 1;

    pure virtual function void pack_header(ref byte unsigned data[$]);
    pure virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
    pure virtual function int get_header_length();
    pure virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
    pure virtual function protocol_base clone();
    pure virtual function bit compare(protocol_base other);
    pure virtual function string to_string();
    pure virtual function string to_brief();

    // Verify protocol field correctness — override in subclasses
    // Returns errors (hard violations) and warnings (suspicious but allowed)
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // Default: no checks (leaf protocols without verify override)
    endfunction

    function void print(int verbosity = 0);
        if (verbosity == 0)
            $display("  [%s] %s", proto_type.name(), to_brief());
        else
            $display("%s", to_string());
    endfunction

    virtual function void load_params(string path);
    endfunction

endclass

`endif // PROTOCOL_BASE_SV

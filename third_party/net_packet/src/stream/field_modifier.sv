`ifndef FIELD_MODIFIER_SV
`define FIELD_MODIFIER_SV

`include "packet_defines.sv"

class field_modifier;

    string          field_path;     // e.g., "ipv4.src_addr", "udp.dst_port", "eth.src_mac"
    modifier_mode_e mode;
    bit [63:0]      step;
    bit [63:0]      min_val;
    bit [63:0]      max_val;
    bit [63:0]      value_list[$];  // For MOD_LIST mode
    bit [63:0]      current_val;    // Internal state

    function new(string path = "", modifier_mode_e m = MOD_INCREMENT);
        field_path  = path;
        mode        = m;
        step        = 1;
        min_val     = 0;
        max_val     = 64'hFFFFFFFFFFFFFFFF;
        current_val = 0;
    endfunction

    // Initialize current_val to min_val
    function void reset();
        current_val = min_val;
    endfunction

    // Get next value based on mode
    function bit [63:0] next_value(int index);
        bit [63:0] val;
        case (mode)
            MOD_INCREMENT: begin
                val = min_val + (step * index);
                if (val > max_val)
                    val = min_val + ((val - min_val) % (max_val - min_val + 1));
            end
            MOD_DECREMENT: begin
                bit [63:0] range = max_val - min_val + 1;
                bit [63:0] dec = (step * index) % range;
                if (dec <= max_val - min_val)
                    val = max_val - dec;
                else
                    val = max_val;
            end
            MOD_RANDOM: begin
                val = {$urandom(), $urandom()};
                if (max_val > min_val)
                    val = min_val + (val % (max_val - min_val + 1));
            end
            MOD_LIST: begin
                if (value_list.size() > 0)
                    val = value_list[index % value_list.size()];
                else
                    val = 0;
            end
        endcase
        return val;
    endfunction

endclass

`endif // FIELD_MODIFIER_SV

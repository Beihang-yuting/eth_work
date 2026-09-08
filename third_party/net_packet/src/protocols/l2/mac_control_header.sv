// src/protocols/l2/mac_control_header.sv
// MAC Control (802.3x PAUSE frame payload) — opcode / pause_time + pad to 46 字节
`ifndef MAC_CONTROL_HEADER_SV
`define MAC_CONTROL_HEADER_SV

`include "protocol_base.sv"

class mac_control_header extends protocol_base;

    rand bit [15:0] opcode;      // 0x0001 = PAUSE
    rand bit [15:0] pause_time;  // 暂停时间 (pause_quanta 单位)

    function new();
        proto_type = PROTO_MAC_CONTROL;
        opcode     = 16'h0001;  // PAUSE
        pause_time = 16'hFFFF;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, opcode);
        packet_utils::pack_bytes_16(data, pause_time);
        for (int i = 0; i < 42; i++) data.push_back(8'h00);  // pad to 46-byte min MAC Control payload
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        opcode     = packet_utils::unpack_bytes_16(data, offset);
        pause_time = packet_utils::unpack_bytes_16(data, offset);
        offset += 42;
    endfunction

    virtual function int get_header_length();
        return 46;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        mac_control_header h = new();
        h.opcode     = opcode;
        h.pause_time = pause_time;
        h.auto_calc  = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        mac_control_header o;
        if (!$cast(o, other)) return 0;
        return (opcode == o.opcode) && (pause_time == o.pause_time);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  opcode    : 0x%04x\n", opcode)};
        s = {s, $sformatf("  pause_time: 0x%04x\n", pause_time)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("MAC_CONTROL opcode:0x%04x pause_time:0x%04x", opcode, pause_time);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opcode", path);
            if (__v != "") opcode = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("pause_time", path);
            if (__v != "") pause_time = 16'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // MAC_CONTROL_HEADER_SV

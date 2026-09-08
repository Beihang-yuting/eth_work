// src/protocols/l2/lldp_header.sv
// LLDP (IEEE 802.1AB) — 3 mandatory TLVs (Chassis ID / Port ID / TTL) + End TLV
`ifndef LLDP_HEADER_SV
`define LLDP_HEADER_SV

`include "protocol_base.sv"

class lldp_header extends protocol_base;

    rand bit [47:0] chassis_id;   // chassis subtype 4 (MAC)
    rand bit [47:0] port_id;      // port subtype 3 (MAC)
    rand bit [15:0] ttl;

    function new();
        proto_type = PROTO_LLDP;
        chassis_id = 48'h001122334455;
        port_id    = 48'h0011223344AA;
        ttl        = 16'd120;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // TLV 头 (type<<9 | length); 用变量避免 VCS Q-2020 字面量->ref 形参的 IRPC
        bit [15:0] tlv_chassis = 16'h0207;  // (1<<9)|7
        bit [15:0] tlv_port    = 16'h0407;  // (2<<9)|7
        bit [15:0] tlv_ttl     = 16'h0602;  // (3<<9)|2
        bit [15:0] tlv_end     = 16'h0000;
        bit [7:0]  sub_chassis = 8'd4;       // chassis subtype = MAC
        bit [7:0]  sub_port    = 8'd3;       // port subtype = MAC
        // Chassis ID TLV
        packet_utils::pack_bytes_16(data, tlv_chassis);
        data.push_back(sub_chassis);
        packet_utils::pack_bytes_48(data, chassis_id);
        // Port ID TLV
        packet_utils::pack_bytes_16(data, tlv_port);
        data.push_back(sub_port);
        packet_utils::pack_bytes_48(data, port_id);
        // TTL TLV
        packet_utils::pack_bytes_16(data, tlv_ttl);
        packet_utils::pack_bytes_16(data, ttl);
        // End TLV
        packet_utils::pack_bytes_16(data, tlv_end);
        // total = 2+1+6 + 2+1+6 + 2+2 + 2 = 24 bytes
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        offset += 2; offset += 1; chassis_id = packet_utils::unpack_bytes_48(data, offset);
        offset += 2; offset += 1; port_id    = packet_utils::unpack_bytes_48(data, offset);
        offset += 2; ttl = packet_utils::unpack_bytes_16(data, offset);
        offset += 2;  // end TLV
    endfunction

    virtual function int get_header_length();
        return 24;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        lldp_header h = new();
        h.chassis_id = chassis_id;
        h.port_id    = port_id;
        h.ttl        = ttl;
        h.auto_calc  = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        lldp_header o;
        if (!$cast(o, other)) return 0;
        return (chassis_id == o.chassis_id) && (port_id == o.port_id) && (ttl == o.ttl);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  chassis_id : %012x\n", chassis_id)};
        s = {s, $sformatf("  port_id    : %012x\n", port_id)};
        s = {s, $sformatf("  ttl        : %0d\n", ttl)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("LLDP chassis:%012x port:%012x ttl:%0d", chassis_id, port_id, ttl);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("chassis_id", path);
            if (__v != "") chassis_id = 48'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("port_id", path);
            if (__v != "") port_id = 48'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ttl", path);
            if (__v != "") ttl = 16'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // LLDP_HEADER_SV

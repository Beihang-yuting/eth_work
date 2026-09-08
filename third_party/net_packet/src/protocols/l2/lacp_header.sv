// src/protocols/l2/lacp_header.sv
// LACPDU (IEEE 802.3ad) 子集 — padded to 128 字节
`ifndef LACP_HEADER_SV
`define LACP_HEADER_SV

`include "protocol_base.sv"

class lacp_header extends protocol_base;

    rand bit [7:0]  subtype;          // 0x01 LACP
    rand bit [7:0]  version;          // 0x01
    rand bit [47:0] actor_system;
    rand bit [15:0] actor_key;
    rand bit [15:0] actor_port;
    rand bit [47:0] partner_system;
    rand bit [15:0] partner_key;
    rand bit [15:0] partner_port;

    function new();
        proto_type     = PROTO_LACP;
        subtype        = 8'd1;
        version        = 8'd1;
        actor_system   = 48'h00AABBCCDD01;
        actor_key      = 16'h0001;
        actor_port     = 16'h0001;
        partner_system = 48'h00AABBCCDD02;
        partner_key    = 16'h0001;
        partner_port   = 16'h0001;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(subtype);
        data.push_back(version);
        packet_utils::pack_bytes_48(data, actor_system);
        packet_utils::pack_bytes_16(data, actor_key);
        packet_utils::pack_bytes_16(data, actor_port);
        packet_utils::pack_bytes_48(data, partner_system);
        packet_utils::pack_bytes_16(data, partner_key);
        packet_utils::pack_bytes_16(data, partner_port);
        // bytes so far = 2 + 6+2+2 + 6+2+2 = 22; pad to 128
        for (int i = 22; i < 128; i++) data.push_back(8'h00);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        subtype        = data[offset]; offset++;
        version        = data[offset]; offset++;
        actor_system   = packet_utils::unpack_bytes_48(data, offset);
        actor_key      = packet_utils::unpack_bytes_16(data, offset);
        actor_port     = packet_utils::unpack_bytes_16(data, offset);
        partner_system = packet_utils::unpack_bytes_48(data, offset);
        partner_key    = packet_utils::unpack_bytes_16(data, offset);
        partner_port   = packet_utils::unpack_bytes_16(data, offset);
        offset += (128 - 22);  // skip padding
    endfunction

    virtual function int get_header_length();
        return 128;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        lacp_header h = new();
        h.subtype        = subtype;
        h.version        = version;
        h.actor_system   = actor_system;
        h.actor_key      = actor_key;
        h.actor_port     = actor_port;
        h.partner_system = partner_system;
        h.partner_key    = partner_key;
        h.partner_port   = partner_port;
        h.auto_calc      = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        lacp_header o;
        if (!$cast(o, other)) return 0;
        return (actor_system == o.actor_system) && (actor_port == o.actor_port) &&
               (partner_system == o.partner_system) && (partner_port == o.partner_port);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  subtype     : 0x%02x\n", subtype)};
        s = {s, $sformatf("  version     : 0x%02x\n", version)};
        s = {s, $sformatf("  actor_sys   : %s\n", packet_utils::format_mac(actor_system))};
        s = {s, $sformatf("  actor_key   : 0x%04x\n", actor_key)};
        s = {s, $sformatf("  actor_port  : 0x%04x\n", actor_port)};
        s = {s, $sformatf("  partner_sys : %s\n", packet_utils::format_mac(partner_system))};
        s = {s, $sformatf("  partner_key : 0x%04x\n", partner_key)};
        s = {s, $sformatf("  partner_port: 0x%04x\n", partner_port)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("LACP actor:%s partner:%s",
                         packet_utils::format_mac(actor_system),
                         packet_utils::format_mac(partner_system));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("actor_system", path);
            if (__v != "") actor_system = 48'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("actor_key", path);
            if (__v != "") actor_key = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("actor_port", path);
            if (__v != "") actor_port = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("partner_system", path);
            if (__v != "") partner_system = 48'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // LACP_HEADER_SV

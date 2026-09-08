// src/protocols/l3/arp_header.sv
`ifndef ARP_HEADER_SV
`define ARP_HEADER_SV

`include "protocol_base.sv"

class arp_header extends protocol_base;

    rand bit [15:0] hw_type;
    rand bit [15:0] proto_type_field;
    rand bit [7:0]  hw_len;
    rand bit [7:0]  proto_len;
    rand bit [15:0] opcode;
    rand bit [47:0] sender_mac;
    rand bit [31:0] sender_ip;
    rand bit [47:0] target_mac;
    rand bit [31:0] target_ip;

    constraint c_default {
        soft hw_type == 1;
        soft proto_type_field == 16'h0800;
        soft hw_len == 6;
        soft proto_len == 4;
        soft opcode inside {1, 2};
    }

    function new();
        proto_type       = PROTO_ARP;
        hw_type          = 1;
        proto_type_field = 16'h0800;
        hw_len           = 6;
        proto_len        = 4;
        opcode           = 1;
        sender_mac       = 0;
        sender_ip        = 0;
        target_mac       = 0;
        target_ip        = 0;
    endfunction

    static function arp_header create(bit [15:0] op = 1,
                                       bit [47:0] smac = 0, bit [31:0] sip = 0,
                                       bit [47:0] tmac = 0, bit [31:0] tip = 0);
        arp_header h = new();
        h.opcode     = op;
        h.sender_mac = smac;
        h.sender_ip  = sip;
        h.target_mac = tmac;
        h.target_ip  = tip;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, hw_type);
        packet_utils::pack_bytes_16(data, proto_type_field);
        data.push_back(hw_len);
        data.push_back(proto_len);
        packet_utils::pack_bytes_16(data, opcode);
        packet_utils::pack_bytes_48(data, sender_mac);
        packet_utils::pack_bytes_32(data, sender_ip);
        packet_utils::pack_bytes_48(data, target_mac);
        packet_utils::pack_bytes_32(data, target_ip);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        hw_type          = packet_utils::unpack_bytes_16(data, offset);
        proto_type_field = packet_utils::unpack_bytes_16(data, offset);
        hw_len           = data[offset]; offset++;
        proto_len        = data[offset]; offset++;
        opcode           = packet_utils::unpack_bytes_16(data, offset);
        sender_mac       = packet_utils::unpack_bytes_48(data, offset);
        sender_ip        = packet_utils::unpack_bytes_32(data, offset);
        target_mac       = packet_utils::unpack_bytes_48(data, offset);
        target_ip        = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 28;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        // No-op for ARP
    endfunction

    virtual function protocol_base clone();
        arp_header h = new();
        h.hw_type          = hw_type;
        h.proto_type_field = proto_type_field;
        h.hw_len           = hw_len;
        h.proto_len        = proto_len;
        h.opcode           = opcode;
        h.sender_mac       = sender_mac;
        h.sender_ip        = sender_ip;
        h.target_mac       = target_mac;
        h.target_ip        = target_ip;
        h.auto_calc        = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        arp_header o;
        if (!$cast(o, other)) return 0;
        return (hw_type == o.hw_type) && (proto_type_field == o.proto_type_field) &&
               (hw_len == o.hw_len) && (proto_len == o.proto_len) &&
               (opcode == o.opcode) && (sender_mac == o.sender_mac) &&
               (sender_ip == o.sender_ip) && (target_mac == o.target_mac) &&
               (target_ip == o.target_ip);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  hw_type  : %0d\n", hw_type)};
        s = {s, $sformatf("  proto    : 0x%04x\n", proto_type_field)};
        s = {s, $sformatf("  hw_len   : %0d\n", hw_len)};
        s = {s, $sformatf("  proto_len: %0d\n", proto_len)};
        s = {s, $sformatf("  opcode   : %0d\n", opcode)};
        s = {s, $sformatf("  sender   : %s / %s\n", packet_utils::format_mac(sender_mac), packet_utils::format_ipv4(sender_ip))};
        s = {s, $sformatf("  target   : %s / %s\n", packet_utils::format_mac(target_mac), packet_utils::format_ipv4(target_ip))};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ARP op:%0d %s->%s",
                         opcode,
                         packet_utils::format_ipv4(sender_ip),
                         packet_utils::format_ipv4(target_ip));
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (hw_type != 1)
            warnings.push_back($sformatf("ARP: hw_type=%0d, expected 1 (Ethernet)", hw_type));
        if (proto_type != 16'h0800)
            warnings.push_back($sformatf("ARP: proto_type=0x%04x, expected 0x0800 (IPv4)", proto_type));
        if (hw_len != 6)
            errors.push_back($sformatf("ARP: hw_len=%0d, expected 6 (MAC address)", hw_len));
        if (proto_len != 4)
            errors.push_back($sformatf("ARP: proto_len=%0d, expected 4 (IPv4 address)", proto_len));
        if (opcode != 1 && opcode != 2)
            warnings.push_back($sformatf("ARP: opcode=%0d, expected 1 (request) or 2 (reply)", opcode));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hw_type", path);
            if (__v != "") hw_type = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("proto_type_field", path);
            if (__v != "") proto_type_field = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hw_len", path);
            if (__v != "") hw_len = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("proto_len", path);
            if (__v != "") proto_len = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opcode", path);
            if (__v != "") opcode = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("sender_mac", path);
            if (__v != "") sender_mac = 48'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("sender_ip", path);
            if (__v != "") sender_ip = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("target_mac", path);
            if (__v != "") target_mac = 48'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("target_ip", path);
            if (__v != "") target_ip = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // ARP_HEADER_SV

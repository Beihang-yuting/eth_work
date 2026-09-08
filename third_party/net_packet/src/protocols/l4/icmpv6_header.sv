// src/protocols/l4/icmpv6_header.sv
`ifndef ICMPV6_HEADER_SV
`define ICMPV6_HEADER_SV

`include "protocol_base.sv"

class icmpv6_header extends protocol_base;

    rand bit [7:0]  icmp_type;
    rand bit [7:0]  icmp_code;
    rand bit [15:0] checksum;
    rand bit [15:0] identifier;
    rand bit [15:0] sequence_num;

    constraint c_default {
        soft icmp_type == 128;  // ICMPv6 Echo Request
        soft icmp_code == 0;
    }

    function new();
        proto_type   = PROTO_ICMPV6;
        icmp_type    = 128;
        icmp_code    = 0;
        checksum     = 0;
        identifier   = 0;
        sequence_num = 0;
    endfunction

    static function icmpv6_header create(bit [7:0] itype = 128, bit [7:0] icode = 0,
                                          bit [15:0] id = 0, bit [15:0] seq = 0);
        icmpv6_header h = new();
        h.icmp_type    = itype;
        h.icmp_code    = icode;
        h.identifier   = id;
        h.sequence_num = seq;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(icmp_type);
        data.push_back(icmp_code);
        packet_utils::pack_bytes_16(data, checksum);
        packet_utils::pack_bytes_16(data, identifier);
        packet_utils::pack_bytes_16(data, sequence_num);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        icmp_type    = data[offset]; offset++;
        icmp_code    = data[offset]; offset++;
        checksum     = packet_utils::unpack_bytes_16(data, offset);
        identifier   = packet_utils::unpack_bytes_16(data, offset);
        sequence_num = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // ICMPv6 checksum requires pseudo-header — zero it here
        checksum = 0;
    endfunction

    virtual function protocol_base clone();
        icmpv6_header h = new();
        h.icmp_type    = icmp_type;
        h.icmp_code    = icmp_code;
        h.checksum     = checksum;
        h.identifier   = identifier;
        h.sequence_num = sequence_num;
        h.auto_calc    = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        icmpv6_header o;
        if (!$cast(o, other)) return 0;
        return (icmp_type == o.icmp_type) && (icmp_code == o.icmp_code) &&
               (checksum == o.checksum) && (identifier == o.identifier) &&
               (sequence_num == o.sequence_num);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  type     : %0d\n", icmp_type)};
        s = {s, $sformatf("  code     : %0d\n", icmp_code)};
        s = {s, $sformatf("  checksum : 0x%04x\n", checksum)};
        s = {s, $sformatf("  ident    : 0x%04x\n", identifier)};
        s = {s, $sformatf("  seq_num  : %0d\n", sequence_num)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ICMPv6 type:%0d code:%0d id:0x%04x seq:%0d",
                         icmp_type, icmp_code, identifier, sequence_num);
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // ICMPv6 type: error messages 0-127, informational 128-255
        if (icmp_type >= 1 && icmp_type <= 4) begin
            // Error types: valid
        end else if (icmp_type == 128 || icmp_type == 129) begin
            // Echo request/reply: valid
        end else if (icmp_type == 133 || icmp_type == 134 || icmp_type == 135 || icmp_type == 136 || icmp_type == 137) begin
            // NDP: valid
        end else begin
            warnings.push_back($sformatf("ICMPv6: type=%0d may be uncommon", icmp_type));
        end
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("icmp_type", path);
            if (__v != "") icmp_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("icmp_code", path);
            if (__v != "") icmp_code = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("identifier", path);
            if (__v != "") identifier = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("sequence_num", path);
            if (__v != "") sequence_num = 16'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // ICMPV6_HEADER_SV

// src/protocols/l4/icmp_header.sv
`ifndef ICMP_HEADER_SV
`define ICMP_HEADER_SV

`include "protocol_base.sv"

class icmp_header extends protocol_base;

    rand bit [7:0]  icmp_type;
    rand bit [7:0]  icmp_code;
    rand bit [15:0] checksum;
    rand bit [15:0] identifier;
    rand bit [15:0] sequence_num;

    constraint c_default {
        soft icmp_type == 8;  // Echo Request
        soft icmp_code == 0;
    }

    function new();
        proto_type   = PROTO_ICMP;
        icmp_type    = 8;
        icmp_code    = 0;
        checksum     = 0;
        identifier   = 0;
        sequence_num = 0;
    endfunction

    static function icmp_header create(bit [7:0] itype = 8, bit [7:0] icode = 0,
                                        bit [15:0] id = 0, bit [15:0] seq = 0);
        icmp_header h = new();
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
        // Compute checksum over header + payload
        begin
            byte unsigned all_data[$];
            checksum = 0;
            pack_header(all_data);
            foreach (payload_data[i]) all_data.push_back(payload_data[i]);
            checksum = packet_utils::ones_complement_checksum(all_data);
        end
    endfunction

    virtual function protocol_base clone();
        icmp_header h = new();
        h.icmp_type    = icmp_type;
        h.icmp_code    = icmp_code;
        h.checksum     = checksum;
        h.identifier   = identifier;
        h.sequence_num = sequence_num;
        h.auto_calc    = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        icmp_header o;
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
        return $sformatf("ICMP type:%0d code:%0d id:0x%04x seq:%0d",
                         icmp_type, icmp_code, identifier, sequence_num);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("icmp_type", path);
            if (__v != "") icmp_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("code", path);
            if (__v != "") icmp_code = 8'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // ICMP checksum (covers entire ICMP message, no pseudo-header)
        begin
            byte unsigned icmp_data[$];
            bit [15:0] saved_cksum = checksum;
            bit [15:0] computed;
            checksum = 0;
            pack_header(icmp_data);
            computed = packet_utils::ones_complement_checksum(icmp_data);
            checksum = saved_cksum;
            if (saved_cksum != 0 && saved_cksum != computed)
                warnings.push_back($sformatf("ICMP: checksum=0x%04x, computed=0x%04x (may differ due to payload)",
                                   saved_cksum, computed));
        end
        // Type/code validity
        if (icmp_type > 18 && icmp_type < 30)
            warnings.push_back($sformatf("ICMP: type=%0d is reserved/unassigned", icmp_type));
    endfunction

endclass

`endif // ICMP_HEADER_SV

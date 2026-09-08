// src/protocols/l4/dhcpv6_header.sv
// DHCPv6 (RFC 8415) — 最小 4 字节头: msg_type / transaction_id
`ifndef DHCPV6_HEADER_SV
`define DHCPV6_HEADER_SV

`include "protocol_base.sv"

class dhcpv6_header extends protocol_base;

    rand bit [7:0]  msg_type;        // 1 = SOLICIT
    rand bit [23:0] transaction_id;

    function new();
        proto_type     = PROTO_DHCPV6;
        msg_type       = 8'd1;        // SOLICIT
        transaction_id = 24'h010203;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(msg_type);
        data.push_back(transaction_id[23:16]);
        data.push_back(transaction_id[15:8]);
        data.push_back(transaction_id[7:0]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        msg_type             = data[offset]; offset++;
        transaction_id[23:16] = data[offset]; offset++;
        transaction_id[15:8]  = data[offset]; offset++;
        transaction_id[7:0]   = data[offset]; offset++;
    endfunction

    virtual function int get_header_length();
        return 4;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        dhcpv6_header h = new();
        h.msg_type       = msg_type;
        h.transaction_id = transaction_id;
        h.auto_calc      = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        dhcpv6_header o;
        if (!$cast(o, other)) return 0;
        return (msg_type == o.msg_type) && (transaction_id == o.transaction_id);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  msg_type  : 0x%02x\n", msg_type)};
        s = {s, $sformatf("  xid       : 0x%06x\n", transaction_id)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("DHCPv6 msg_type:0x%02x xid:0x%06x", msg_type, transaction_id);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("msg_type", path);
            if (__v != "") msg_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("transaction_id", path);
            if (__v != "") transaction_id = 24'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // DHCPV6_HEADER_SV

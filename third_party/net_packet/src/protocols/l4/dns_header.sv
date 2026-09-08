// src/protocols/l4/dns_header.sv
// DNS (RFC 1035) — 12 字节固定头: id / flags / qdcount / ancount / nscount / arcount
`ifndef DNS_HEADER_SV
`define DNS_HEADER_SV

`include "protocol_base.sv"

class dns_header extends protocol_base;

    rand bit [15:0] id;        // 事务 ID
    rand bit [15:0] flags;     // QR/Opcode/AA/TC/RD/RA/Z/RCODE
    rand bit [15:0] qdcount;   // 问题数
    rand bit [15:0] ancount;   // 回答记录数
    rand bit [15:0] nscount;   // 权威记录数
    rand bit [15:0] arcount;   // 附加记录数

    function new();
        proto_type = PROTO_DNS;
        id         = 16'h1234;
        flags      = 16'h0100;  // standard query, RD set
        qdcount    = 16'd1;
        ancount    = 0;
        nscount    = 0;
        arcount    = 0;
    endfunction

    static function dns_header create(bit [15:0] tid = 16'h1234, bit [15:0] f = 16'h0100,
                                       bit [15:0] qd = 16'd1);
        dns_header h = new();
        h.id      = tid;
        h.flags   = f;
        h.qdcount = qd;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, id);
        packet_utils::pack_bytes_16(data, flags);
        packet_utils::pack_bytes_16(data, qdcount);
        packet_utils::pack_bytes_16(data, ancount);
        packet_utils::pack_bytes_16(data, nscount);
        packet_utils::pack_bytes_16(data, arcount);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        id      = packet_utils::unpack_bytes_16(data, offset);
        flags   = packet_utils::unpack_bytes_16(data, offset);
        qdcount = packet_utils::unpack_bytes_16(data, offset);
        ancount = packet_utils::unpack_bytes_16(data, offset);
        nscount = packet_utils::unpack_bytes_16(data, offset);
        arcount = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 12;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        dns_header h = new();
        h.id        = id;
        h.flags     = flags;
        h.qdcount   = qdcount;
        h.ancount   = ancount;
        h.nscount   = nscount;
        h.arcount   = arcount;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        dns_header o;
        if (!$cast(o, other)) return 0;
        return (id == o.id) && (flags == o.flags) && (qdcount == o.qdcount) &&
               (ancount == o.ancount) && (nscount == o.nscount) && (arcount == o.arcount);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  id        : 0x%04x\n", id)};
        s = {s, $sformatf("  flags     : 0x%04x\n", flags)};
        s = {s, $sformatf("  qdcount   : %0d\n", qdcount)};
        s = {s, $sformatf("  ancount   : %0d\n", ancount)};
        s = {s, $sformatf("  nscount   : %0d\n", nscount)};
        s = {s, $sformatf("  arcount   : %0d\n", arcount)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("DNS id:0x%04x flags:0x%04x qd:%0d an:%0d",
                         id, flags, qdcount, ancount);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("id", path);
            if (__v != "") id = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("flags", path);
            if (__v != "") flags = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("qdcount", path);
            if (__v != "") qdcount = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ancount", path);
            if (__v != "") ancount = 16'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // DNS_HEADER_SV

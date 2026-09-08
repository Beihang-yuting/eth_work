// src/protocols/l4/dhcp_header.sv
// BOOTP/DHCP (RFC 2131) — 固定 240 字节头部 (含 magic cookie, 不含 options)
`ifndef DHCP_HEADER_SV
`define DHCP_HEADER_SV

`include "protocol_base.sv"

class dhcp_header extends protocol_base;

    rand bit [7:0]  op;       // 1 = BOOTREQUEST, 2 = BOOTREPLY
    rand bit [7:0]  htype;    // 1 = Ethernet
    rand bit [7:0]  hlen;     // 6 = MAC 长度
    rand bit [7:0]  hops;
    rand bit [31:0] xid;      // 事务 ID
    rand bit [15:0] secs;
    rand bit [15:0] flags;    // 0x8000 = broadcast
    rand bit [31:0] ciaddr;   // client IP
    rand bit [31:0] yiaddr;   // your IP
    rand bit [31:0] siaddr;   // server IP
    rand bit [31:0] giaddr;   // gateway IP
    rand bit [47:0] chaddr;   // client MAC (16 字节 chaddr 字段中前 6 字节)
    rand bit [31:0] magic;    // magic cookie 0x63825363

    function new();
        proto_type = PROTO_DHCP;
        op         = 1;
        htype      = 1;
        hlen       = 6;
        hops       = 0;
        xid        = 32'h12345678;
        secs       = 0;
        flags      = 16'h8000;
        ciaddr     = 0;
        yiaddr     = 0;
        siaddr     = 0;
        giaddr     = 0;
        chaddr     = 0;
        magic      = 32'h63825363;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(op);
        data.push_back(htype);
        data.push_back(hlen);
        data.push_back(hops);
        packet_utils::pack_bytes_32(data, xid);
        packet_utils::pack_bytes_16(data, secs);
        packet_utils::pack_bytes_16(data, flags);
        packet_utils::pack_bytes_32(data, ciaddr);
        packet_utils::pack_bytes_32(data, yiaddr);
        packet_utils::pack_bytes_32(data, siaddr);
        packet_utils::pack_bytes_32(data, giaddr);
        packet_utils::pack_bytes_48(data, chaddr);          // 6 bytes of MAC
        for (int i = 0; i < 10;  i++) data.push_back(8'h00); // remaining 10 bytes of chaddr field
        for (int i = 0; i < 64;  i++) data.push_back(8'h00); // sname (64 zeros)
        for (int i = 0; i < 128; i++) data.push_back(8'h00); // file (128 zeros)
        packet_utils::pack_bytes_32(data, magic);
        // total = 4+4+2+2+16+6+10+64+128+4 = 240
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        op    = data[offset]; offset++;
        htype = data[offset]; offset++;
        hlen  = data[offset]; offset++;
        hops  = data[offset]; offset++;
        xid    = packet_utils::unpack_bytes_32(data, offset);
        secs   = packet_utils::unpack_bytes_16(data, offset);
        flags  = packet_utils::unpack_bytes_16(data, offset);
        ciaddr = packet_utils::unpack_bytes_32(data, offset);
        yiaddr = packet_utils::unpack_bytes_32(data, offset);
        siaddr = packet_utils::unpack_bytes_32(data, offset);
        giaddr = packet_utils::unpack_bytes_32(data, offset);
        chaddr = packet_utils::unpack_bytes_48(data, offset);
        offset += 10;   // skip rest of chaddr
        offset += 64;   // skip sname
        offset += 128;  // skip file
        magic  = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 240;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        dhcp_header h = new();
        h.op        = op;
        h.htype     = htype;
        h.hlen      = hlen;
        h.hops      = hops;
        h.xid       = xid;
        h.secs      = secs;
        h.flags     = flags;
        h.ciaddr    = ciaddr;
        h.yiaddr    = yiaddr;
        h.siaddr    = siaddr;
        h.giaddr    = giaddr;
        h.chaddr    = chaddr;
        h.magic     = magic;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        dhcp_header o;
        if (!$cast(o, other)) return 0;
        return (op == o.op) && (htype == o.htype) && (xid == o.xid) &&
               (ciaddr == o.ciaddr) && (yiaddr == o.yiaddr) &&
               (chaddr == o.chaddr) && (magic == o.magic);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  op     : %0d\n", op)};
        s = {s, $sformatf("  htype  : %0d\n", htype)};
        s = {s, $sformatf("  hlen   : %0d\n", hlen)};
        s = {s, $sformatf("  hops   : %0d\n", hops)};
        s = {s, $sformatf("  xid    : 0x%08x\n", xid)};
        s = {s, $sformatf("  secs   : %0d\n", secs)};
        s = {s, $sformatf("  flags  : 0x%04x\n", flags)};
        s = {s, $sformatf("  ciaddr : %s\n", packet_utils::format_ipv4(ciaddr))};
        s = {s, $sformatf("  yiaddr : %s\n", packet_utils::format_ipv4(yiaddr))};
        s = {s, $sformatf("  siaddr : %s\n", packet_utils::format_ipv4(siaddr))};
        s = {s, $sformatf("  giaddr : %s\n", packet_utils::format_ipv4(giaddr))};
        s = {s, $sformatf("  chaddr : %s\n", packet_utils::format_mac(chaddr))};
        s = {s, $sformatf("  magic  : 0x%08x\n", magic)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("DHCP op:%0d xid:0x%08x chaddr:%s", op, xid,
                         packet_utils::format_mac(chaddr));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("op", path);
            if (__v != "") op = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("xid", path);
            if (__v != "") xid = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ciaddr", path);
            if (__v != "") ciaddr = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("yiaddr", path);
            if (__v != "") yiaddr = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("chaddr", path);
            if (__v != "") chaddr = 48'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // DHCP_HEADER_SV

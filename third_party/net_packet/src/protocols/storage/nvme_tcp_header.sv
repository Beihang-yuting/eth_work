// src/protocols/storage/nvme_tcp_header.sv
`ifndef NVME_TCP_HEADER_SV
`define NVME_TCP_HEADER_SV

`include "protocol_base.sv"

// NVMe-oF TCP PDU Common Header (8 bytes)
// Wire format: pdu_type(8), flags(8), hlen(8), pdo(8), plen(32)

class nvme_tcp_header extends protocol_base;

    rand bit [7:0]  pdu_type;  // 0x00=ICReq, 0x01=ICResp, 0x04=CapsuleCmd, 0x05=CapsuleResp
    rand bit [7:0]  flags;
    rand bit [7:0]  hlen;      // Header length in bytes
    rand bit [7:0]  pdo;       // PDU Data Offset
    rand bit [31:0] plen;      // Entire PDU length

    constraint c_default {
        soft pdu_type inside {8'h00, 8'h01, 8'h02, 8'h03,  // ICReq, ICResp, H2CTermReq, C2HTermReq
                              8'h04, 8'h05, 8'h06, 8'h07};  // CapsuleCmd, CapsuleResp, H2CData, C2HData
        soft flags == 8'h00;
        soft hlen  == 8'd8;
        soft pdo   == 8'h00;
    }

    function new();
        proto_type = PROTO_NVME_TCP;
        pdu_type   = 8'h04;
        flags      = 8'h00;
        hlen       = 8'd8;
        pdo        = 8'h00;
        plen       = 32'd0;
    endfunction

    static function nvme_tcp_header create(bit [7:0] ptype = 8'h04);
        nvme_tcp_header h = new();
        h.pdu_type = ptype;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(pdu_type);
        data.push_back(flags);
        data.push_back(hlen);
        data.push_back(pdo);
        packet_utils::pack_bytes_32(data, plen);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        pdu_type = data[offset]; offset++;
        flags    = data[offset]; offset++;
        hlen     = data[offset]; offset++;
        pdo      = data[offset]; offset++;
        plen     = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        plen = 32'(payload_data.size() + 8);
        hlen = 8'd8;
    endfunction

    virtual function protocol_base clone();
        nvme_tcp_header h = new();
        h.pdu_type  = pdu_type;
        h.flags     = flags;
        h.hlen      = hlen;
        h.pdo       = pdo;
        h.plen      = plen;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        nvme_tcp_header o;
        if (!$cast(o, other)) return 0;
        return (pdu_type == o.pdu_type) &&
               (flags    == o.flags)    &&
               (hlen     == o.hlen)     &&
               (plen     == o.plen);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  pdu_type: 0x%02x\n", pdu_type)};
        s = {s, $sformatf("  flags   : 0x%02x\n", flags)};
        s = {s, $sformatf("  hlen    : %0d\n",    hlen)};
        s = {s, $sformatf("  pdo     : %0d\n",    pdo)};
        s = {s, $sformatf("  plen    : %0d\n",    plen)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("NVMe-TCP pdu_type:0x%02x flags:0x%02x hlen:%0d plen:%0d",
                         pdu_type, flags, hlen, plen);
    endfunction

    // NVMe-oF TCP Transport Specification 1.0/1.1
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // PDU type must be a valid NVMe-TCP PDU type (0x00-0x07)
        if (!(pdu_type inside {8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07}))
            errors.push_back($sformatf("NVMe-TCP: pdu_type=0x%02x is not a valid PDU type", pdu_type));
        // hlen must be >= 8 (minimum common header size)
        if (hlen < 8)
            errors.push_back($sformatf("NVMe-TCP: hlen=%0d < 8 (minimum header)", hlen));
        // plen must be >= hlen
        if (plen < {24'd0, hlen})
            errors.push_back($sformatf("NVMe-TCP: plen=%0d < hlen=%0d", plen, hlen));
        // PDO (PDU Data Offset): if non-zero, must be 4-byte aligned
        if (pdo != 0 && pdo % 4 != 0)
            warnings.push_back($sformatf("NVMe-TCP: PDO=%0d not 4-byte aligned", pdo));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("pdu_type", path);
            if (__v != "") pdu_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("flags", path);
            if (__v != "") flags = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hlen", path);
            if (__v != "") hlen = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("pdo", path);
            if (__v != "") pdo = 8'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // NVME_TCP_HEADER_SV

// src/protocols/rdma/iwarp_header.sv
`ifndef IWARP_HEADER_SV
`define IWARP_HEADER_SV

`include "protocol_base.sv"

// iWARP MPA+DDP+RDMAP combined simplified header (28 bytes)
// MPA:   6 bytes
// DDP:  14 bytes
// RDMAP: 8 bytes

class iwarp_header extends protocol_base;

    // === MPA fields (6 bytes) ===
    rand bit [15:0] mpa_length;
    rand bit [15:0] mpa_reserved;
    rand bit [15:0] mpa_crc;

    // === DDP fields (14 bytes) ===
    rand bit        tagged_bit;
    rand bit        last;
    rand bit [5:0]  ddp_reserved;
    rand bit [7:0]  ddp_version;
    rand bit [15:0] queue_number;
    rand bit [31:0] msn;
    rand bit [47:0] msg_offset;   // upper32 + lower16

    // === RDMAP fields (8 bytes) ===
    rand bit [3:0]  rdmap_version;
    rand bit [3:0]  rdmap_opcode;
    rand bit [7:0]  padding;
    rand bit [15:0] rdmap_reserved;
    rand bit [31:0] sink_stag;

    constraint c_default {
        soft ddp_version    == 8'd1;
        soft rdmap_version  == 4'd1;
        soft mpa_reserved   == 16'h0;
        soft ddp_reserved   == 6'h0;
        soft padding        == 8'h0;
        soft rdmap_reserved == 16'h0;
    }

    function new();
        proto_type     = PROTO_IWARP;
        mpa_length     = 16'd0;
        mpa_reserved   = 16'h0;
        mpa_crc        = 16'h0;
        tagged_bit         = 1'b0;
        last           = 1'b0;
        ddp_reserved   = 6'h0;
        ddp_version    = 8'd1;
        queue_number   = 16'd0;
        msn            = 32'd0;
        msg_offset     = 48'd0;
        rdmap_version  = 4'd1;
        rdmap_opcode   = 4'd0;
        padding        = 8'h0;
        rdmap_reserved = 16'h0;
        sink_stag      = 32'h0;
    endfunction

    static function iwarp_header create(bit [3:0] op = 4'd0);
        iwarp_header h = new();
        h.rdmap_opcode = op;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // MPA (6 bytes)
        packet_utils::pack_bytes_16(data, mpa_length);
        packet_utils::pack_bytes_16(data, mpa_reserved);
        packet_utils::pack_bytes_16(data, mpa_crc);

        // DDP (14 bytes)
        data.push_back({tagged_bit, last, ddp_reserved});
        data.push_back(ddp_version);
        packet_utils::pack_bytes_16(data, queue_number);
        packet_utils::pack_bytes_32(data, msn);
        begin
            bit [31:0] _tmp = msg_offset[47:16];
            packet_utils::pack_bytes_32(data, _tmp);  // upper 32 bits
        end
        begin
            bit [15:0] _tmp = msg_offset[15:0];
            packet_utils::pack_bytes_16(data, _tmp);   // lower 16 bits
        end

        // RDMAP (8 bytes)
        data.push_back({rdmap_version, rdmap_opcode});
        data.push_back(8'h00);  // padding
        packet_utils::pack_bytes_16(data, rdmap_reserved);
        packet_utils::pack_bytes_32(data, sink_stag);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] byte0;

        // MPA (6 bytes)
        mpa_length   = packet_utils::unpack_bytes_16(data, offset);
        mpa_reserved = packet_utils::unpack_bytes_16(data, offset);
        mpa_crc      = packet_utils::unpack_bytes_16(data, offset);

        // DDP (14 bytes)
        byte0        = data[offset]; offset++;
        tagged_bit       = byte0[7];
        last         = byte0[6];
        ddp_reserved = byte0[5:0];
        ddp_version  = data[offset]; offset++;
        queue_number = packet_utils::unpack_bytes_16(data, offset);
        msn          = packet_utils::unpack_bytes_32(data, offset);
        msg_offset[47:16] = packet_utils::unpack_bytes_32(data, offset);
        msg_offset[15:0]  = packet_utils::unpack_bytes_16(data, offset);

        // RDMAP (8 bytes)
        byte0          = data[offset]; offset++;
        rdmap_version  = byte0[7:4];
        rdmap_opcode   = byte0[3:0];
        padding        = data[offset]; offset++;  // skip padding byte
        rdmap_reserved = packet_utils::unpack_bytes_16(data, offset);
        sink_stag      = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 28;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // mpa_length = DDP(14) + RDMAP(8) + payload = 22 + payload
        mpa_length = 16'(payload_data.size() + 22);
    endfunction

    virtual function protocol_base clone();
        iwarp_header h = new();
        h.mpa_length     = mpa_length;
        h.mpa_reserved   = mpa_reserved;
        h.mpa_crc        = mpa_crc;
        h.tagged_bit         = tagged_bit;
        h.last           = last;
        h.ddp_reserved   = ddp_reserved;
        h.ddp_version    = ddp_version;
        h.queue_number   = queue_number;
        h.msn            = msn;
        h.msg_offset     = msg_offset;
        h.rdmap_version  = rdmap_version;
        h.rdmap_opcode   = rdmap_opcode;
        h.padding        = padding;
        h.rdmap_reserved = rdmap_reserved;
        h.sink_stag      = sink_stag;
        h.auto_calc      = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        iwarp_header o;
        if (!$cast(o, other)) return 0;
        return (rdmap_opcode  == o.rdmap_opcode)  &&
               (queue_number  == o.queue_number)  &&
               (msn           == o.msn)           &&
               (sink_stag     == o.sink_stag)     &&
               (tagged_bit        == o.tagged_bit);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, "  --- MPA ---\n"};
        s = {s, $sformatf("  mpa_length  : %0d\n",   mpa_length)};
        s = {s, $sformatf("  mpa_reserved: 0x%04x\n", mpa_reserved)};
        s = {s, $sformatf("  mpa_crc     : 0x%04x\n", mpa_crc)};
        s = {s, "  --- DDP ---\n"};
        s = {s, $sformatf("  tagged_bit      : %0b\n",   tagged_bit)};
        s = {s, $sformatf("  last        : %0b\n",   last)};
        s = {s, $sformatf("  ddp_version : %0d\n",   ddp_version)};
        s = {s, $sformatf("  queue_number: %0d\n",   queue_number)};
        s = {s, $sformatf("  msn         : 0x%08x\n", msn)};
        s = {s, $sformatf("  msg_offset  : 0x%012x\n", msg_offset)};
        s = {s, "  --- RDMAP ---\n"};
        s = {s, $sformatf("  rdmap_ver   : %0d\n",   rdmap_version)};
        s = {s, $sformatf("  rdmap_opcode: 0x%01x\n", rdmap_opcode)};
        s = {s, $sformatf("  sink_stag   : 0x%08x\n", sink_stag)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("iWARP op:0x%01x qn:%0d msn:0x%08x stag:0x%08x",
                         rdmap_opcode, queue_number, msn, sink_stag);
    endfunction

    // RFC 5040 (DDP), RFC 5041 (MPA), RFC 5042 (RDMAP)
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // DDP version must be 1 (RFC 5040 Section 4)
        if (ddp_version != 1)
            errors.push_back($sformatf("iWARP: DDP version=%0d, expected 1 (RFC 5040)", ddp_version));
        // RDMAP version must be 1 (RFC 5042 Section 4)
        if (rdmap_version != 1)
            errors.push_back($sformatf("iWARP: RDMAP version=%0d, expected 1 (RFC 5042)", rdmap_version));
        // MPA length consistency: should be >= 22 (DDP 14 + RDMAP 8)
        if (mpa_length < 22)
            errors.push_back($sformatf("iWARP: MPA length=%0d < 22 (minimum DDP+RDMAP)", mpa_length));
        // Reserved fields must be zero
        if (mpa_reserved != 0)
            warnings.push_back($sformatf("iWARP: MPA reserved=0x%04x, expected 0", mpa_reserved));
        if (ddp_reserved != 0)
            warnings.push_back($sformatf("iWARP: DDP reserved=0x%02x, expected 0", ddp_reserved));
        if (rdmap_reserved != 0)
            warnings.push_back($sformatf("iWARP: RDMAP reserved=0x%04x, expected 0", rdmap_reserved));
        // RDMAP opcode range (RFC 5042 Section 4): valid opcodes 0-4
        if (rdmap_opcode > 4)
            warnings.push_back($sformatf("iWARP: RDMAP opcode=0x%01x > 4 (unknown)", rdmap_opcode));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("mpa_length", path);
            if (__v != "") mpa_length = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("tagged_bit", path);
            if (__v != "") tagged_bit = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("last", path);
            if (__v != "") last = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ddp_version", path);
            if (__v != "") ddp_version = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("queue_number", path);
            if (__v != "") queue_number = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("msn", path);
            if (__v != "") msn = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("msg_offset", path);
            if (__v != "") msg_offset = 48'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("rdmap_version", path);
            if (__v != "") rdmap_version = 4'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("rdmap_opcode", path);
            if (__v != "") rdmap_opcode = 4'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("sink_stag", path);
            if (__v != "") sink_stag = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // IWARP_HEADER_SV

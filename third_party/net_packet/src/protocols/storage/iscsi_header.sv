// src/protocols/storage/iscsi_header.sv
`ifndef ISCSI_HEADER_SV
`define ISCSI_HEADER_SV

`include "protocol_base.sv"

// iSCSI Basic Header Segment (48 bytes)
// Wire format:
//   Byte 0:    {reserved_bit, immediate, opcode[5:0]}
//   Byte 1:    flags
//   Bytes 2-3: reserved1 (16-bit)
//   Byte 4:    total_ahs_len
//   Bytes 5-7: data_segment_len (24-bit)
//   Bytes 8-15:  lun (64-bit)
//   Bytes 16-19: initiator_task_tag (32-bit)
//   Bytes 20-47: opcode_specific (28 bytes raw)

class iscsi_header extends protocol_base;

    rand bit        reserved_bit;
    rand bit        immediate;
    rand bit [5:0]  opcode;
    rand bit [7:0]  flags;
    rand bit [15:0] reserved1;
    rand bit [7:0]  total_ahs_len;
    rand bit [23:0] data_segment_len;
    rand bit [63:0] lun;
    rand bit [31:0] initiator_task_tag;
    byte unsigned   opcode_specific[28];

    constraint c_default {
        soft reserved_bit == 1'b0;
        soft reserved1    == 16'h0000;
        // RFC 7143 Section 11.1: valid opcode ranges
        soft opcode inside {[6'h00:6'h06], [6'h20:6'h26]};
    }

    function new();
        proto_type         = PROTO_ISCSI;
        reserved_bit       = 1'b0;
        immediate          = 1'b0;
        opcode             = 6'h01;  // SCSI Command
        flags              = 8'h00;
        reserved1          = 16'h0000;
        total_ahs_len      = 8'h00;
        data_segment_len   = 24'h000000;
        lun                = 64'h0;
        initiator_task_tag = 32'h00000000;
        foreach (opcode_specific[i]) opcode_specific[i] = 8'h00;
    endfunction

    static function iscsi_header create(bit [5:0] op = 6'h01);
        iscsi_header h = new();
        h.opcode = op;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // Byte 0: {reserved_bit, immediate, opcode[5:0]}
        data.push_back({reserved_bit, immediate, opcode});
        // Byte 1: flags
        data.push_back(flags);
        // Bytes 2-3: reserved1
        packet_utils::pack_bytes_16(data, reserved1);
        // Byte 4: total_ahs_len
        data.push_back(total_ahs_len);
        // Bytes 5-7: data_segment_len (24-bit, big-endian)
        data.push_back(data_segment_len[23:16]);
        data.push_back(data_segment_len[15:8]);
        data.push_back(data_segment_len[7:0]);
        // Bytes 8-15: lun (64-bit as 2x 32-bit)
        begin
            bit [31:0] _tmp = lun[63:32];
            packet_utils::pack_bytes_32(data, _tmp);
        end
        begin
            bit [31:0] _tmp = lun[31:0];
            packet_utils::pack_bytes_32(data, _tmp);
        end
        // Bytes 16-19: initiator_task_tag
        packet_utils::pack_bytes_32(data, initiator_task_tag);
        // Bytes 20-47: opcode_specific (28 bytes)
        foreach (opcode_specific[i]) data.push_back(opcode_specific[i]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] byte0;
        // Byte 0
        byte0        = data[offset]; offset++;
        reserved_bit = byte0[7];
        immediate    = byte0[6];
        opcode       = byte0[5:0];
        // Byte 1
        flags        = data[offset]; offset++;
        // Bytes 2-3
        reserved1    = packet_utils::unpack_bytes_16(data, offset);
        // Byte 4
        total_ahs_len = data[offset]; offset++;
        // Bytes 5-7: data_segment_len (24-bit big-endian)
        data_segment_len[23:16] = data[offset]; offset++;
        data_segment_len[15:8]  = data[offset]; offset++;
        data_segment_len[7:0]   = data[offset]; offset++;
        // Bytes 8-15: lun
        lun[63:32] = packet_utils::unpack_bytes_32(data, offset);
        lun[31:0]  = packet_utils::unpack_bytes_32(data, offset);
        // Bytes 16-19: initiator_task_tag
        initiator_task_tag = packet_utils::unpack_bytes_32(data, offset);
        // Bytes 20-47: opcode_specific (28 bytes)
        foreach (opcode_specific[i]) begin
            opcode_specific[i] = data[offset]; offset++;
        end
    endfunction

    virtual function int get_header_length();
        return 48;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        data_segment_len = 24'(payload_data.size());
    endfunction

    virtual function protocol_base clone();
        iscsi_header h = new();
        h.reserved_bit       = reserved_bit;
        h.immediate          = immediate;
        h.opcode             = opcode;
        h.flags              = flags;
        h.reserved1          = reserved1;
        h.total_ahs_len      = total_ahs_len;
        h.data_segment_len   = data_segment_len;
        h.lun                = lun;
        h.initiator_task_tag = initiator_task_tag;
        foreach (opcode_specific[i]) h.opcode_specific[i] = opcode_specific[i];
        h.auto_calc          = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        iscsi_header o;
        if (!$cast(o, other)) return 0;
        return (opcode             == o.opcode)             &&
               (flags              == o.flags)              &&
               (initiator_task_tag == o.initiator_task_tag) &&
               (lun                == o.lun);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  reserved_bit      : %0b\n",   reserved_bit)};
        s = {s, $sformatf("  immediate         : %0b\n",   immediate)};
        s = {s, $sformatf("  opcode            : 0x%02x\n", opcode)};
        s = {s, $sformatf("  flags             : 0x%02x\n", flags)};
        s = {s, $sformatf("  reserved1         : 0x%04x\n", reserved1)};
        s = {s, $sformatf("  total_ahs_len     : %0d\n",   total_ahs_len)};
        s = {s, $sformatf("  data_segment_len  : %0d\n",   data_segment_len)};
        s = {s, $sformatf("  lun               : 0x%016x\n", lun)};
        s = {s, $sformatf("  initiator_task_tag: 0x%08x\n", initiator_task_tag)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("iSCSI op:0x%02x itt:0x%08x lun:0x%016x dsl:%0d",
                         opcode, initiator_task_tag, lun, data_segment_len);
    endfunction

    // RFC 7143 (iSCSI)
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // Reserved bit must be 0 (RFC 7143 Section 11.2.1)
        if (reserved_bit != 0)
            errors.push_back("iSCSI: reserved bit is set (must be 0)");
        // Reserved field must be 0
        if (reserved1 != 0)
            warnings.push_back($sformatf("iSCSI: reserved1=0x%04x, expected 0", reserved1));
        // Opcode range: initiator opcodes 0x00-0x06, target opcodes 0x20-0x26 (RFC 7143 Sec 11.1)
        if (!(opcode inside {[6'h00:6'h06], [6'h20:6'h26]}))
            warnings.push_back($sformatf("iSCSI: opcode=0x%02x not in standard range", opcode));
        // Data segment length should be 4-byte aligned for most PDUs
        if (data_segment_len % 4 != 0)
            warnings.push_back($sformatf("iSCSI: data_segment_len=%0d not 4-byte aligned", data_segment_len));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opcode", path);
            if (__v != "") opcode = 6'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("flags", path);
            if (__v != "") flags = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("total_ahs_len", path);
            if (__v != "") total_ahs_len = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("data_segment_len", path);
            if (__v != "") data_segment_len = 24'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("lun", path);
            if (__v != "") lun = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("initiator_task_tag", path);
            if (__v != "") initiator_task_tag = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // ISCSI_HEADER_SV

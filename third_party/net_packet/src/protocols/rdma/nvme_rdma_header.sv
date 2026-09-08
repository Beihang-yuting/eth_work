// src/protocols/rdma/nvme_rdma_header.sv
// NVMe-over-RDMA command capsule = 64-byte NVMe SQE
`ifndef NVME_RDMA_HEADER_SV
`define NVME_RDMA_HEADER_SV

`include "protocol_base.sv"

class nvme_rdma_header extends protocol_base;

    rand bit [7:0]  opcode;       // 0x01 write
    rand bit [7:0]  flags;
    rand bit [15:0] command_id;
    rand bit [31:0] nsid;
    rand bit [63:0] rsvd2;
    rand bit [63:0] mptr;
    rand bit [63:0] prp1;
    rand bit [63:0] prp2;
    rand bit [31:0] cdw10;
    rand bit [31:0] cdw11;
    rand bit [31:0] cdw12;
    rand bit [31:0] cdw13;
    rand bit [31:0] cdw14;
    rand bit [31:0] cdw15;

    function new();
        proto_type = PROTO_NVME_RDMA;
        opcode     = 8'h01;
        flags      = 0;
        command_id = 16'h0001;
        nsid       = 32'h1;
        rsvd2      = 0;
        mptr       = 0;
        prp1       = 0;
        prp2       = 0;
        cdw10      = 0;
        cdw11      = 0;
        cdw12      = 0;
        cdw13      = 0;
        cdw14      = 0;
        cdw15      = 0;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(opcode);
        data.push_back(flags);
        packet_utils::pack_bytes_16(data, command_id);
        packet_utils::pack_bytes_32(data, nsid);
        packet_utils::pack_bytes_64(data, rsvd2);
        packet_utils::pack_bytes_64(data, mptr);
        packet_utils::pack_bytes_64(data, prp1);
        packet_utils::pack_bytes_64(data, prp2);
        packet_utils::pack_bytes_32(data, cdw10);
        packet_utils::pack_bytes_32(data, cdw11);
        packet_utils::pack_bytes_32(data, cdw12);
        packet_utils::pack_bytes_32(data, cdw13);
        packet_utils::pack_bytes_32(data, cdw14);
        packet_utils::pack_bytes_32(data, cdw15);
        // total = 1+1+2+4 + 8+8+8+8 + 6*4 = 64
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        opcode     = data[offset]; offset++;
        flags      = data[offset]; offset++;
        command_id = packet_utils::unpack_bytes_16(data, offset);
        nsid       = packet_utils::unpack_bytes_32(data, offset);
        rsvd2      = packet_utils::unpack_bytes_64(data, offset);
        mptr       = packet_utils::unpack_bytes_64(data, offset);
        prp1       = packet_utils::unpack_bytes_64(data, offset);
        prp2       = packet_utils::unpack_bytes_64(data, offset);
        cdw10      = packet_utils::unpack_bytes_32(data, offset);
        cdw11      = packet_utils::unpack_bytes_32(data, offset);
        cdw12      = packet_utils::unpack_bytes_32(data, offset);
        cdw13      = packet_utils::unpack_bytes_32(data, offset);
        cdw14      = packet_utils::unpack_bytes_32(data, offset);
        cdw15      = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 64;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        nvme_rdma_header h = new();
        h.opcode     = opcode;
        h.flags      = flags;
        h.command_id = command_id;
        h.nsid       = nsid;
        h.rsvd2      = rsvd2;
        h.mptr       = mptr;
        h.prp1       = prp1;
        h.prp2       = prp2;
        h.cdw10      = cdw10;
        h.cdw11      = cdw11;
        h.cdw12      = cdw12;
        h.cdw13      = cdw13;
        h.cdw14      = cdw14;
        h.cdw15      = cdw15;
        h.auto_calc  = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        nvme_rdma_header o;
        if (!$cast(o, other)) return 0;
        return (opcode == o.opcode) && (command_id == o.command_id) &&
               (nsid == o.nsid) && (prp1 == o.prp1);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  opcode    : 0x%02x\n", opcode)};
        s = {s, $sformatf("  flags     : 0x%02x\n", flags)};
        s = {s, $sformatf("  command_id: 0x%04x\n", command_id)};
        s = {s, $sformatf("  nsid      : 0x%08x\n", nsid)};
        s = {s, $sformatf("  prp1      : 0x%016x\n", prp1)};
        s = {s, $sformatf("  prp2      : 0x%016x\n", prp2)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("NVMe-RDMA opcode:0x%02x cid:0x%04x nsid:0x%08x",
                         opcode, command_id, nsid);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opcode", path);
            if (__v != "") opcode = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("command_id", path);
            if (__v != "") command_id = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("nsid", path);
            if (__v != "") nsid = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("prp1", path);
            if (__v != "") prp1 = 64'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // NVME_RDMA_HEADER_SV

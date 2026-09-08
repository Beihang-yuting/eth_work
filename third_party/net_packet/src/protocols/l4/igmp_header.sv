// src/protocols/l4/igmp_header.sv
// IGMPv2 (RFC 2236) — 8 字节: type / max_resp_time / checksum / group_address
`ifndef IGMP_HEADER_SV
`define IGMP_HEADER_SV

`include "protocol_base.sv"

class igmp_header extends protocol_base;

    rand bit [7:0]  igmp_type;       // 0x11 query, 0x16 v2 report, 0x17 leave, 0x12 v1 report
    rand bit [7:0]  max_resp_time;   // 0.1s 单位, 仅 query 有意义
    rand bit [15:0] checksum;
    rand bit [31:0] group_address;   // 组播组地址 (IPv4)

    constraint c_default {
        soft igmp_type inside {8'h11, 8'h12, 8'h16, 8'h17};
        soft max_resp_time == 8'd100;  // 10s 默认
    }

    function new();
        proto_type    = PROTO_IGMP;
        igmp_type     = 8'h16;  // V2 Membership Report
        max_resp_time = 0;
        checksum      = 0;
        group_address = 0;
    endfunction

    static function igmp_header create(bit [7:0] itype = 8'h16, bit [31:0] grp = 0,
                                        bit [7:0] mrt = 0);
        igmp_header h = new();
        h.igmp_type     = itype;
        h.group_address = grp;
        h.max_resp_time = mrt;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(igmp_type);
        data.push_back(max_resp_time);
        packet_utils::pack_bytes_16(data, checksum);
        packet_utils::pack_bytes_32(data, group_address);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        igmp_type     = data[offset]; offset++;
        max_resp_time = data[offset]; offset++;
        checksum      = packet_utils::unpack_bytes_16(data, offset);
        group_address = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Checksum 覆盖整个 IGMP 报文 (无伪头)
        begin
            byte unsigned all_data[$];
            checksum = 0;
            pack_header(all_data);
            foreach (payload_data[i]) all_data.push_back(payload_data[i]);
            checksum = packet_utils::ones_complement_checksum(all_data);
        end
    endfunction

    virtual function protocol_base clone();
        igmp_header h = new();
        h.igmp_type     = igmp_type;
        h.max_resp_time = max_resp_time;
        h.checksum      = checksum;
        h.group_address = group_address;
        h.auto_calc     = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        igmp_header o;
        if (!$cast(o, other)) return 0;
        return (igmp_type == o.igmp_type) && (max_resp_time == o.max_resp_time) &&
               (checksum == o.checksum) && (group_address == o.group_address);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  type      : 0x%02x\n", igmp_type)};
        s = {s, $sformatf("  max_resp  : %0d\n", max_resp_time)};
        s = {s, $sformatf("  checksum  : 0x%04x\n", checksum)};
        s = {s, $sformatf("  group     : %s\n", packet_utils::format_ipv4(group_address))};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("IGMP type:0x%02x group:%s", igmp_type,
                         packet_utils::format_ipv4(group_address));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("igmp_type", path);
            if (__v != "") igmp_type = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("max_resp_time", path);
            if (__v != "") max_resp_time = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("group_address", path);
            if (__v != "") group_address = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        begin
            byte unsigned igmp_data[$];
            bit [15:0] saved_cksum = checksum;
            bit [15:0] computed;
            checksum = 0;
            pack_header(igmp_data);
            computed = packet_utils::ones_complement_checksum(igmp_data);
            checksum = saved_cksum;
            if (saved_cksum != 0 && saved_cksum != computed)
                warnings.push_back($sformatf("IGMP: checksum=0x%04x, computed=0x%04x",
                                   saved_cksum, computed));
        end
        if (!(igmp_type inside {8'h11, 8'h12, 8'h16, 8'h17, 8'h22}))
            warnings.push_back($sformatf("IGMP: type=0x%02x not a standard IGMP type", igmp_type));
    endfunction

endclass

`endif // IGMP_HEADER_SV

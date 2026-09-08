// src/protocols/l4/udp_header.sv
`ifndef UDP_HEADER_SV
`define UDP_HEADER_SV

`include "protocol_base.sv"

class udp_header extends protocol_base;

    rand bit [15:0] src_port;
    rand bit [15:0] dst_port;
    rand bit [15:0] length;
    rand bit [15:0] checksum;

    constraint c_default {
        soft src_port inside {[1024:65535]};
        soft dst_port inside {[1:65535]};
        // Exclude well-known tunnel/overlay dst_ports so that when UDP is the
        // last layer, the parser does not mistakenly expect a tunnel header.
        // calc_fields() will override dst_port with the correct well-known value
        // when a tunnel layer actually follows.
        soft !(dst_port inside {16'd4789, 16'd6081, 16'd2152, 16'd2123,
                                16'd4791, 16'd4790});
    }

    function new();
        proto_type = PROTO_UDP;
        src_port   = 0;
        dst_port   = 0;
        length     = 8;
        checksum   = 0;
    endfunction

    static function udp_header create(bit [15:0] sp = 0, bit [15:0] dp = 0);
        udp_header h = new();
        h.src_port = sp;
        h.dst_port = dp;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, src_port);
        packet_utils::pack_bytes_16(data, dst_port);
        packet_utils::pack_bytes_16(data, length);
        packet_utils::pack_bytes_16(data, checksum);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        src_port = packet_utils::unpack_bytes_16(data, offset);
        dst_port = packet_utils::unpack_bytes_16(data, offset);
        length   = packet_utils::unpack_bytes_16(data, offset);
        checksum = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Auto-set well-known dst_port if not already set by user
        if (dst_port == 0) begin
            case (next_proto)
                PROTO_VXLAN:     dst_port = 16'd4789;
                PROTO_GENEVE:    dst_port = 16'd6081;
                PROTO_GTP_U:     dst_port = 16'd2152;
                PROTO_GTP_C:     dst_port = 16'd2123;
                PROTO_ROCEV2:    dst_port = 16'd4791;
                PROTO_VXLAN_GPE: dst_port = 16'd4790;
                default: ;
            endcase
        end
        length   = 8 + payload_data.size();
        checksum = 0;
    endfunction

    virtual function protocol_base clone();
        udp_header h = new();
        h.src_port = src_port;
        h.dst_port = dst_port;
        h.length   = length;
        h.checksum = checksum;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        udp_header o;
        if (!$cast(o, other)) return 0;
        return (src_port == o.src_port) && (dst_port == o.dst_port) &&
               (length == o.length) && (checksum == o.checksum);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  src_port : %0d\n", src_port)};
        s = {s, $sformatf("  dst_port : %0d\n", dst_port)};
        s = {s, $sformatf("  length   : %0d\n", length)};
        s = {s, $sformatf("  checksum : 0x%04x\n", checksum)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%0d -> %0d len:%0d", src_port, dst_port, length);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("src_port", path);
            if (__v != "") src_port = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("dst_port", path);
            if (__v != "") dst_port = 16'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    // RFC 768 (UDP)
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (length < 8)
            errors.push_back($sformatf("UDP: length=%0d < 8 (minimum UDP header size)", length));
        if (src_port == 0)
            warnings.push_back("UDP: src_port=0");
        if (dst_port == 0)
            warnings.push_back("UDP: dst_port=0");
        // Checksum==0 means not computed (valid for IPv4, invalid for IPv6 per RFC 6935)
        // We warn since it may indicate missing computation
        if (checksum == 0)
            warnings.push_back("UDP: checksum=0 (not computed — invalid over IPv6 per RFC 6935)");
    endfunction

endclass

`endif // UDP_HEADER_SV

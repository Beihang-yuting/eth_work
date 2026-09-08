// src/protocols/l4/bfd_header.sv
// BFD (RFC 5880) 控制包 — 24 字节
`ifndef BFD_HEADER_SV
`define BFD_HEADER_SV

`include "protocol_base.sv"

class bfd_header extends protocol_base;

    rand bit [7:0]  vers_diag;             // 版本(高3位)/诊断
    rand bit [7:0]  sta_flags;             // 状态/标志字节
    rand bit [7:0]  detect_mult;           // 检测倍数
    rand bit [7:0]  length;                // 报文长度
    rand bit [31:0] my_discriminator;
    rand bit [31:0] your_discriminator;
    rand bit [31:0] desired_min_tx;
    rand bit [31:0] required_min_rx;
    rand bit [31:0] required_min_echo_rx;

    function new();
        proto_type           = PROTO_BFD;
        vers_diag            = 8'h20;
        sta_flags            = 8'h00;
        detect_mult          = 8'd3;
        length               = 8'd24;
        my_discriminator     = 32'h1;
        your_discriminator   = 0;
        desired_min_tx       = 32'd1000000;
        required_min_rx      = 32'd1000000;
        required_min_echo_rx = 0;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(vers_diag);
        data.push_back(sta_flags);
        data.push_back(detect_mult);
        data.push_back(length);
        packet_utils::pack_bytes_32(data, my_discriminator);
        packet_utils::pack_bytes_32(data, your_discriminator);
        packet_utils::pack_bytes_32(data, desired_min_tx);
        packet_utils::pack_bytes_32(data, required_min_rx);
        packet_utils::pack_bytes_32(data, required_min_echo_rx);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        vers_diag            = data[offset]; offset++;
        sta_flags            = data[offset]; offset++;
        detect_mult          = data[offset]; offset++;
        length               = data[offset]; offset++;
        my_discriminator     = packet_utils::unpack_bytes_32(data, offset);
        your_discriminator   = packet_utils::unpack_bytes_32(data, offset);
        desired_min_tx       = packet_utils::unpack_bytes_32(data, offset);
        required_min_rx      = packet_utils::unpack_bytes_32(data, offset);
        required_min_echo_rx = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function int get_header_length();
        return 24;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        bfd_header h = new();
        h.vers_diag            = vers_diag;
        h.sta_flags            = sta_flags;
        h.detect_mult          = detect_mult;
        h.length               = length;
        h.my_discriminator     = my_discriminator;
        h.your_discriminator   = your_discriminator;
        h.desired_min_tx       = desired_min_tx;
        h.required_min_rx      = required_min_rx;
        h.required_min_echo_rx = required_min_echo_rx;
        h.auto_calc            = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        bfd_header o;
        if (!$cast(o, other)) return 0;
        return (vers_diag == o.vers_diag) && (sta_flags == o.sta_flags) &&
               (detect_mult == o.detect_mult) && (length == o.length) &&
               (my_discriminator == o.my_discriminator) &&
               (your_discriminator == o.your_discriminator) &&
               (desired_min_tx == o.desired_min_tx) &&
               (required_min_rx == o.required_min_rx) &&
               (required_min_echo_rx == o.required_min_echo_rx);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  vers_diag    : 0x%02x\n", vers_diag)};
        s = {s, $sformatf("  sta_flags    : 0x%02x\n", sta_flags)};
        s = {s, $sformatf("  detect_mult  : %0d\n", detect_mult)};
        s = {s, $sformatf("  length       : %0d\n", length)};
        s = {s, $sformatf("  my_discrim   : 0x%08x\n", my_discriminator)};
        s = {s, $sformatf("  your_discrim : 0x%08x\n", your_discriminator)};
        s = {s, $sformatf("  desired_tx   : %0d\n", desired_min_tx)};
        s = {s, $sformatf("  required_rx  : %0d\n", required_min_rx)};
        s = {s, $sformatf("  req_echo_rx  : %0d\n", required_min_echo_rx)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("BFD my:0x%08x your:0x%08x mult:%0d", my_discriminator,
                         your_discriminator, detect_mult);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("my_discriminator", path);
            if (__v != "") my_discriminator = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("your_discriminator", path);
            if (__v != "") your_discriminator = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("detect_mult", path);
            if (__v != "") detect_mult = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("desired_min_tx", path);
            if (__v != "") desired_min_tx = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // BFD_HEADER_SV

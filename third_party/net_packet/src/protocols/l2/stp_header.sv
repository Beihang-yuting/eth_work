// src/protocols/l2/stp_header.sv
// STP BPDU (IEEE 802.1D) — 35 字节: protocol_id / version / bpdu_type / flags /
//   root_id / root_path_cost / bridge_id / port_id / msg_age / max_age /
//   hello_time / forward_delay
`ifndef STP_HEADER_SV
`define STP_HEADER_SV

`include "protocol_base.sv"

class stp_header extends protocol_base;

    rand bit [15:0] protocol_id;
    rand bit [7:0]  version;
    rand bit [7:0]  bpdu_type;
    rand bit [7:0]  flags;
    rand bit [63:0] root_id;
    rand bit [31:0] root_path_cost;
    rand bit [63:0] bridge_id;
    rand bit [15:0] port_id;
    rand bit [15:0] msg_age;
    rand bit [15:0] max_age;
    rand bit [15:0] hello_time;
    rand bit [15:0] forward_delay;

    function new();
        proto_type     = PROTO_STP;
        protocol_id    = 0;
        version        = 0;
        bpdu_type      = 0;
        flags          = 0;
        root_id        = 64'h8000_0000_0000_0001;
        root_path_cost = 0;
        bridge_id      = 64'h8000_0000_0000_0002;
        port_id        = 16'h8001;
        msg_age        = 0;
        max_age        = 16'd5120;  // 20s (1/256s 单位)
        hello_time     = 16'd512;   // 2s
        forward_delay  = 16'd3840;  // 15s
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, protocol_id);
        data.push_back(version);
        data.push_back(bpdu_type);
        data.push_back(flags);
        packet_utils::pack_bytes_64(data, root_id);
        packet_utils::pack_bytes_32(data, root_path_cost);
        packet_utils::pack_bytes_64(data, bridge_id);
        packet_utils::pack_bytes_16(data, port_id);
        packet_utils::pack_bytes_16(data, msg_age);
        packet_utils::pack_bytes_16(data, max_age);
        packet_utils::pack_bytes_16(data, hello_time);
        packet_utils::pack_bytes_16(data, forward_delay);
        // total = 2+1+1+1+8+4+8+2+2+2+2+2 = 35
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        protocol_id    = packet_utils::unpack_bytes_16(data, offset);
        version        = data[offset]; offset++;
        bpdu_type      = data[offset]; offset++;
        flags          = data[offset]; offset++;
        root_id        = packet_utils::unpack_bytes_64(data, offset);
        root_path_cost = packet_utils::unpack_bytes_32(data, offset);
        bridge_id      = packet_utils::unpack_bytes_64(data, offset);
        port_id        = packet_utils::unpack_bytes_16(data, offset);
        msg_age        = packet_utils::unpack_bytes_16(data, offset);
        max_age        = packet_utils::unpack_bytes_16(data, offset);
        hello_time     = packet_utils::unpack_bytes_16(data, offset);
        forward_delay  = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 35;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
    endfunction

    virtual function protocol_base clone();
        stp_header h = new();
        h.protocol_id    = protocol_id;
        h.version        = version;
        h.bpdu_type      = bpdu_type;
        h.flags          = flags;
        h.root_id        = root_id;
        h.root_path_cost = root_path_cost;
        h.bridge_id      = bridge_id;
        h.port_id        = port_id;
        h.msg_age        = msg_age;
        h.max_age        = max_age;
        h.hello_time     = hello_time;
        h.forward_delay  = forward_delay;
        h.auto_calc      = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        stp_header o;
        if (!$cast(o, other)) return 0;
        return (root_id == o.root_id) && (bridge_id == o.bridge_id) &&
               (port_id == o.port_id) && (flags == o.flags);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  protocol_id   : 0x%04x\n", protocol_id)};
        s = {s, $sformatf("  version       : 0x%02x\n", version)};
        s = {s, $sformatf("  bpdu_type     : 0x%02x\n", bpdu_type)};
        s = {s, $sformatf("  flags         : 0x%02x\n", flags)};
        s = {s, $sformatf("  root_id       : 0x%016x\n", root_id)};
        s = {s, $sformatf("  root_path_cost: %0d\n", root_path_cost)};
        s = {s, $sformatf("  bridge_id     : 0x%016x\n", bridge_id)};
        s = {s, $sformatf("  port_id       : 0x%04x\n", port_id)};
        s = {s, $sformatf("  msg_age       : %0d\n", msg_age)};
        s = {s, $sformatf("  max_age       : %0d\n", max_age)};
        s = {s, $sformatf("  hello_time    : %0d\n", hello_time)};
        s = {s, $sformatf("  forward_delay : %0d\n", forward_delay)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("STP root:0x%016x bridge:0x%016x port:0x%04x",
                         root_id, bridge_id, port_id);
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("root_id", path);
            if (__v != "") root_id = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("bridge_id", path);
            if (__v != "") bridge_id = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("port_id", path);
            if (__v != "") port_id = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("flags", path);
            if (__v != "") flags = 8'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
    endfunction

endclass

`endif // STP_HEADER_SV

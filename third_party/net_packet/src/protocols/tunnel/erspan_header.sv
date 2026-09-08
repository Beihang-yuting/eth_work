// src/protocols/tunnel/erspan_header.sv
`ifndef ERSPAN_HEADER_SV
`define ERSPAN_HEADER_SV

`include "protocol_base.sv"

// ============================================================
// ERSPAN Type II header (8 bytes)
// Wire format:
//   Word 0: {version[3:0], vlan[11:0], cos[2:0], en[1:0], truncated[0], session_id[9:0]}
//   Word 1: {reserved[11:0], index[19:0]}
// ============================================================
class erspan_ii_header extends protocol_base;

    rand bit [3:0]  version;
    rand bit [11:0] vlan;
    rand bit [2:0]  cos;
    rand bit [1:0]  en;
    rand bit        truncated;
    rand bit [9:0]  session_id;
    rand bit [11:0] reserved;
    rand bit [19:0] index;

    constraint c_default {
        soft version  == 4'd1;
        soft en       == 2'd0;
        soft reserved == 12'd0;
    }

    function new();
        proto_type = PROTO_ERSPAN_II;
        version    = 4'd1;
        vlan       = 12'd0;
        cos        = 3'd0;
        en         = 2'd0;
        truncated  = 1'd0;
        session_id = 10'd0;
        reserved   = 12'd0;
        index      = 20'd0;
    endfunction

    static function erspan_ii_header create(bit [9:0] sid = 10'd0, bit [11:0] v = 12'd0);
        erspan_ii_header h = new();
        h.session_id = sid;
        h.vlan       = v;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [31:0] w0, w1;
        w0 = {version, vlan, cos, en, truncated, session_id};
        w1 = {reserved, index};
        packet_utils::pack_bytes_32(data, w0);
        packet_utils::pack_bytes_32(data, w1);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] w0, w1;
        w0        = packet_utils::unpack_bytes_32(data, offset);
        w1        = packet_utils::unpack_bytes_32(data, offset);
        version    = w0[31:28];
        vlan       = w0[27:16];
        cos        = w0[15:13];
        en         = w0[12:11];
        truncated  = w0[10];
        session_id = w0[9:0];
        reserved   = w1[31:20];
        index      = w1[19:0];
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        version = 4'd1;
    endfunction

    virtual function protocol_base clone();
        erspan_ii_header h = new();
        h.version    = version;
        h.vlan       = vlan;
        h.cos        = cos;
        h.en         = en;
        h.truncated  = truncated;
        h.session_id = session_id;
        h.reserved   = reserved;
        h.index      = index;
        h.auto_calc  = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        erspan_ii_header o;
        if (!$cast(o, other)) return 0;
        if (version    != o.version)    return 0;
        if (vlan       != o.vlan)       return 0;
        if (cos        != o.cos)        return 0;
        if (en         != o.en)         return 0;
        if (truncated  != o.truncated)  return 0;
        if (session_id != o.session_id) return 0;
        if (index      != o.index)      return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version    : %0d\n",    version)};
        s = {s, $sformatf("  vlan       : %0d\n",    vlan)};
        s = {s, $sformatf("  cos        : %0d\n",    cos)};
        s = {s, $sformatf("  en         : %0d\n",    en)};
        s = {s, $sformatf("  truncated  : %0d\n",    truncated)};
        s = {s, $sformatf("  session_id : %0d\n",    session_id)};
        s = {s, $sformatf("  index      : 0x%05x\n", index)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ERSPAN-II sid:%0d vlan:%0d idx:0x%05x", session_id, vlan, index);
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (version != 1)
            errors.push_back($sformatf("ERSPAN-II: version=%0d, expected 1", version));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("version", path);
            if (__v != "") version = 4'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("vlan", path);
            if (__v != "") vlan = 12'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("cos", path);
            if (__v != "") cos = 3'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("en", path);
            if (__v != "") en = 2'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("truncated", path);
            if (__v != "") truncated = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("session_id", path);
            if (__v != "") session_id = 10'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("index", path);
            if (__v != "") index = 20'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

// ============================================================
// ERSPAN Type III header (12 bytes)
// Wire format:
//   Word 0: {version[3:0], vlan[11:0], cos[2:0], bso[1:0], truncated[0], session_id[9:0]}
//   Word 1: timestamp (32-bit)
//   Word 2: {sgt[15:0], p_flag[0], ft[5:0], hw_id[5:0], direction[0], gra[1:0], o_flag[0]}
// ============================================================
class erspan_iii_header extends protocol_base;

    rand bit [3:0]  version;
    rand bit [11:0] vlan;
    rand bit [2:0]  cos;
    rand bit [1:0]  bso;
    rand bit        truncated;
    rand bit [9:0]  session_id;
    rand bit [31:0] timestamp;
    rand bit [15:0] sgt;
    rand bit        p_flag;
    rand bit [5:0]  ft;
    rand bit [5:0]  hw_id;
    rand bit        direction;
    rand bit [1:0]  gra;
    rand bit        o_flag;

    constraint c_default {
        soft version == 4'd2;
        soft bso     == 2'd0;
    }

    function new();
        proto_type = PROTO_ERSPAN_III;
        version    = 4'd2;
        vlan       = 12'd0;
        cos        = 3'd0;
        bso        = 2'd0;
        truncated  = 1'd0;
        session_id = 10'd0;
        timestamp  = 32'd0;
        sgt        = 16'd0;
        p_flag     = 1'd0;
        ft         = 6'd0;
        hw_id      = 6'd0;
        direction  = 1'd0;
        gra        = 2'd0;
        o_flag     = 1'd0;
    endfunction

    static function erspan_iii_header create(bit [9:0] sid = 10'd0);
        erspan_iii_header h = new();
        h.session_id = sid;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [31:0] w0, w1, w2;
        w0 = {version, vlan, cos, bso, truncated, session_id};
        w1 = timestamp;
        // Word 2: sgt[15:0] | p_flag | ft[4:0] | hw_id[5:0] | direction | gra[1:0] | o_flag
        // ft is declared 6-bit; only lower 5 bits are placed on wire
        w2 = {sgt, p_flag, ft[4:0], hw_id, direction, gra, o_flag};
        packet_utils::pack_bytes_32(data, w0);
        packet_utils::pack_bytes_32(data, w1);
        packet_utils::pack_bytes_32(data, w2);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] w0, w1, w2;
        w0        = packet_utils::unpack_bytes_32(data, offset);
        w1        = packet_utils::unpack_bytes_32(data, offset);
        w2        = packet_utils::unpack_bytes_32(data, offset);
        version    = w0[31:28];
        vlan       = w0[27:16];
        cos        = w0[15:13];
        bso        = w0[12:11];
        truncated  = w0[10];
        session_id = w0[9:0];
        timestamp  = w1;
        sgt        = w2[31:16];
        p_flag     = w2[15];
        ft         = {1'b0, w2[14:10]};
        hw_id      = w2[9:4];
        direction  = w2[3];
        gra        = w2[2:1];
        o_flag     = w2[0];
    endfunction

    virtual function int get_header_length();
        return 12;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        version = 4'd2;
    endfunction

    virtual function protocol_base clone();
        erspan_iii_header h = new();
        h.version    = version;
        h.vlan       = vlan;
        h.cos        = cos;
        h.bso        = bso;
        h.truncated  = truncated;
        h.session_id = session_id;
        h.timestamp  = timestamp;
        h.sgt        = sgt;
        h.p_flag     = p_flag;
        h.ft         = ft;
        h.hw_id      = hw_id;
        h.direction  = direction;
        h.gra        = gra;
        h.o_flag     = o_flag;
        h.auto_calc  = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        erspan_iii_header o;
        if (!$cast(o, other)) return 0;
        if (version    != o.version)    return 0;
        if (vlan       != o.vlan)       return 0;
        if (cos        != o.cos)        return 0;
        if (session_id != o.session_id) return 0;
        if (timestamp  != o.timestamp)  return 0;
        if (sgt        != o.sgt)        return 0;
        if (hw_id      != o.hw_id)      return 0;
        if (direction  != o.direction)  return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version    : %0d\n",    version)};
        s = {s, $sformatf("  vlan       : %0d\n",    vlan)};
        s = {s, $sformatf("  cos        : %0d\n",    cos)};
        s = {s, $sformatf("  bso        : %0d\n",    bso)};
        s = {s, $sformatf("  truncated  : %0d\n",    truncated)};
        s = {s, $sformatf("  session_id : %0d\n",    session_id)};
        s = {s, $sformatf("  timestamp  : 0x%08x\n", timestamp)};
        s = {s, $sformatf("  sgt        : 0x%04x\n", sgt)};
        s = {s, $sformatf("  hw_id      : %0d\n",    hw_id)};
        s = {s, $sformatf("  direction  : %0d\n",    direction)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ERSPAN-III sid:%0d vlan:%0d ts:0x%08x hw_id:%0d dir:%0d",
                         session_id, vlan, timestamp, hw_id, direction);
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (version != 2)
            errors.push_back($sformatf("ERSPAN-III: version=%0d, expected 2", version));
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("version", path);
            if (__v != "") version = 4'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("vlan", path);
            if (__v != "") vlan = 12'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("cos", path);
            if (__v != "") cos = 3'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("bso", path);
            if (__v != "") bso = 2'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("truncated", path);
            if (__v != "") truncated = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("session_id", path);
            if (__v != "") session_id = 10'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("timestamp", path);
            if (__v != "") timestamp = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("sgt", path);
            if (__v != "") sgt = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("p_flag", path);
            if (__v != "") p_flag = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ft", path);
            if (__v != "") ft = 6'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("hw_id", path);
            if (__v != "") hw_id = 6'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("direction", path);
            if (__v != "") direction = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("gra", path);
            if (__v != "") gra = 2'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("o_flag", path);
            if (__v != "") o_flag = 1'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // ERSPAN_HEADER_SV

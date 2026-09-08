// src/common/packet_utils.sv
`ifndef PACKET_UTILS_SV
`define PACKET_UTILS_SV

class packet_utils;

    static function bit [15:0] ones_complement_checksum(byte unsigned data[$]);
        bit [31:0] sum = 0;
        int len = data.size();
        int i = 0;
        while (i < len - 1) begin
            sum += {data[i], data[i+1]};
            i += 2;
        end
        if (i < len) begin
            sum += {data[i], 8'h00};
        end
        while (sum[31:16] != 0) begin
            sum = sum[15:0] + sum[31:16];
        end
        return ~sum[15:0];
    endfunction

    static function bit [15:0] byte_swap_16(bit [15:0] val);
        return {val[7:0], val[15:8]};
    endfunction

    static function bit [31:0] byte_swap_32(bit [31:0] val);
        return {val[7:0], val[15:8], val[23:16], val[31:24]};
    endfunction

    static function void pack_bytes_16(ref byte unsigned data[$], bit [15:0] val);
        data.push_back(val[15:8]);
        data.push_back(val[7:0]);
    endfunction

    static function void pack_bytes_32(ref byte unsigned data[$], bit [31:0] val);
        data.push_back(val[31:24]);
        data.push_back(val[23:16]);
        data.push_back(val[15:8]);
        data.push_back(val[7:0]);
    endfunction

    static function void pack_bytes_48(ref byte unsigned data[$], bit [47:0] val);
        data.push_back(val[47:40]);
        data.push_back(val[39:32]);
        data.push_back(val[31:24]);
        data.push_back(val[23:16]);
        data.push_back(val[15:8]);
        data.push_back(val[7:0]);
    endfunction

    static function bit [15:0] unpack_bytes_16(byte unsigned data[$], ref int offset);
        bit [15:0] val = {data[offset], data[offset+1]};
        offset += 2;
        return val;
    endfunction

    static function bit [31:0] unpack_bytes_32(byte unsigned data[$], ref int offset);
        bit [31:0] val = {data[offset], data[offset+1], data[offset+2], data[offset+3]};
        offset += 4;
        return val;
    endfunction

    static function bit [47:0] unpack_bytes_48(byte unsigned data[$], ref int offset);
        bit [47:0] val = {data[offset], data[offset+1], data[offset+2],
                          data[offset+3], data[offset+4], data[offset+5]};
        offset += 6;
        return val;
    endfunction

    static function void pack_bytes_64(ref byte unsigned data[$], bit [63:0] val);
        data.push_back(val[63:56]);
        data.push_back(val[55:48]);
        data.push_back(val[47:40]);
        data.push_back(val[39:32]);
        data.push_back(val[31:24]);
        data.push_back(val[23:16]);
        data.push_back(val[15:8]);
        data.push_back(val[7:0]);
    endfunction

    static function bit [63:0] unpack_bytes_64(byte unsigned data[$], ref int offset);
        bit [63:0] val = {data[offset],   data[offset+1], data[offset+2], data[offset+3],
                          data[offset+4], data[offset+5], data[offset+6], data[offset+7]};
        offset += 8;
        return val;
    endfunction

    static function string format_mac(bit [47:0] mac);
        return $sformatf("%02x:%02x:%02x:%02x:%02x:%02x",
                         mac[47:40], mac[39:32], mac[31:24],
                         mac[23:16], mac[15:8], mac[7:0]);
    endfunction

    static function string format_ipv4(bit [31:0] ip);
        return $sformatf("%0d.%0d.%0d.%0d",
                         ip[31:24], ip[23:16], ip[15:8], ip[7:0]);
    endfunction

    static function string format_ipv6(bit [127:0] ip);
        return $sformatf("%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x",
                         ip[127:112], ip[111:96], ip[95:80], ip[79:64],
                         ip[63:48], ip[47:32], ip[31:16], ip[15:0]);
    endfunction

    // ---- IPv6 地址字符串 -> 128bit（str_to_num 仅 64bit, 这里自包含解析）----
    // 支持: 冒号十六进制 "2001:db8::1"/"::1"/"::"; 纯 hex "0x2001..."/全 hex 串
    // ok=0 表示格式非法（调用方应保留原值）
    local static function int hex_nibble(byte c);  // 返回 0-15, 非法 -1
        if (c >= 48 && c <= 57)  return c - 48;        // 0-9
        if (c >= 97 && c <= 102) return 10 + (c - 97); // a-f
        if (c >= 65 && c <= 70)  return 10 + (c - 65); // A-F
        return -1;
    endfunction

    local static function bit _has_colon(string s);
        foreach (s[i]) if (s[i] == ":") return 1;
        return 0;
    endfunction

    // 解析单个 16bit 组（1-4 位 hex）
    local static function bit [15:0] parse_group16(string tok, output bit ok);
        bit [15:0] v = 0;
        int n;
        ok = 1;
        if (tok.len() == 0 || tok.len() > 4) begin ok = 0; return 0; end
        foreach (tok[i]) begin
            n = hex_nibble(tok[i]);
            if (n < 0) begin ok = 0; return 0; end
            v = (v << 4) | n[15:0];
        end
        return v;
    endfunction

    // 把无 "::" 的冒号串拆成 16bit 组队列; s=="" -> 空队列
    local static function void split_groups(string s, ref bit [15:0] groups[$], output bit ok);
        string tok = "";
        bit gok;
        groups = {};
        ok = 1;
        if (s == "") return;
        foreach (s[i]) begin
            if (s[i] == ":") begin
                groups.push_back(parse_group16(tok, gok));
                if (!gok) begin ok = 0; return; end
                tok = "";
            end else begin
                tok = {tok, s.substr(i, i)};
            end
        end
        groups.push_back(parse_group16(tok, gok));  // 末组
        if (!gok) ok = 0;
    endfunction

    static function bit [127:0] parse_ipv6(string s, output bit ok);
        bit [127:0] result = 0;
        int dbl = -1;
        ok = 1;

        if (s == "") begin ok = 0; return 0; end

        // 纯 hex 形式（无冒号）: 可带 0x/0X 前缀, 最多 32 nibble
        if (!_has_colon(s)) begin
            int start = 0;
            int n;
            if (s.len() >= 2 && s[0] == "0" && (s[1] == "x" || s[1] == "X")) start = 2;
            if (start >= s.len() || (s.len() - start) > 32) begin ok = 0; return 0; end
            for (int i = start; i < s.len(); i++) begin
                n = hex_nibble(s[i]);
                if (n < 0) begin ok = 0; return 0; end
                result = (result << 4) | n;  // n 为 0-15, 零扩展到 128
            end
            return result;
        end

        // 冒号形式: 最多一处 "::"
        for (int i = 0; i + 1 < s.len(); i++) begin
            if (s[i] == ":" && s[i+1] == ":") begin
                if (dbl != -1) begin ok = 0; return 0; end  // 多个 "::" 非法
                dbl = i;
            end
        end

        begin
            bit [15:0] head[$], tail[$], all[$];
            bit hok, tok2;
            int total, zeros;

            if (dbl == -1) begin
                // 无 "::" -> 必须正好 8 组
                split_groups(s, all, hok);
                if (!hok || all.size() != 8) begin ok = 0; return 0; end
            end else begin
                string head_s = (dbl == 0)            ? "" : s.substr(0, dbl-1);
                string tail_s = (dbl+2 > s.len()-1)    ? "" : s.substr(dbl+2, s.len()-1);
                split_groups(head_s, head, hok);
                split_groups(tail_s, tail, tok2);
                if (!hok || !tok2) begin ok = 0; return 0; end
                total = head.size() + tail.size();
                if (total > 7) begin ok = 0; return 0; end  // "::" 至少补 1 组
                zeros = 8 - total;
                all = {};
                foreach (head[i]) all.push_back(head[i]);
                repeat (zeros) all.push_back(16'h0);
                foreach (tail[i]) all.push_back(tail[i]);
            end

            for (int i = 0; i < 8; i++)
                result[127 - 16*i -: 16] = all[i];
        end
        return result;
    endfunction

    static function string hex_dump(byte unsigned data[$], int bytes_per_line = 16);
        string result = "";
        for (int i = 0; i < data.size(); i++) begin
            if (i % bytes_per_line == 0) begin
                if (i > 0) result = {result, "\n"};
                result = {result, $sformatf("  %04x: ", i)};
            end
            result = {result, $sformatf("%02x ", data[i])};
        end
        return result;
    endfunction

endclass

`endif // PACKET_UTILS_SV

// src/protocols/l4/tcp_header.sv
`ifndef TCP_HEADER_SV
`define TCP_HEADER_SV

`include "protocol_base.sv"

class tcp_header extends protocol_base;

    rand bit [15:0] src_port;
    rand bit [15:0] dst_port;
    rand bit [31:0] seq_num;
    rand bit [31:0] ack_num;
    rand bit [3:0]  data_offset;
    rand bit [2:0]  reserved;
    rand bit [8:0]  flags;
         byte unsigned options[$];
    rand bit [15:0] window_size;
    rand bit [15:0] checksum;
    rand bit [15:0] urgent_ptr;

    // ----- TCP Option rand controls -----
    // Enable flags (soft default: disabled)
    rand bit        opt_mss_en;
    rand bit        opt_wscale_en;
    rand bit        opt_sack_perm_en;
    rand bit        opt_ts_en;
    // Option values
    rand bit [15:0] opt_mss_val;
    rand bit [7:0]  opt_wscale_val;
    rand bit [31:0] opt_ts_val;
    rand bit [31:0] opt_ts_ecr;

    // Flag bit positions within the 9-bit flags field
    // flags[8]=NS, [7]=CWR, [6]=ECE, [5]=URG, [4]=ACK, [3]=PSH, [2]=RST, [1]=SYN, [0]=FIN

    constraint c_default {
        soft src_port inside {[1024:65535]};
        soft dst_port inside {[1:65535]};
        soft reserved == 0;
        soft window_size == 16'hFFFF;
        // Exclude well-known application dst_ports so that when TCP is the
        // last layer, the parser does not mistakenly expect an upper-layer header.
        // calc_fields() will set the correct port when an app layer follows.
        soft !(dst_port inside {16'd4420, 16'd3260, 16'd5044});
    }

    constraint c_opt_default {
        soft opt_mss_en      == 0;
        soft opt_wscale_en   == 0;
        soft opt_sack_perm_en == 0;
        soft opt_ts_en       == 0;
        soft opt_mss_val     == 16'd1460;
        soft opt_wscale_val  inside {[0:14]};
        soft opt_ts_val      == 0;
        soft opt_ts_ecr      == 0;
    }

    function new();
        proto_type   = PROTO_TCP;
        src_port     = 0;
        dst_port     = 0;
        seq_num      = 0;
        ack_num      = 0;
        data_offset  = 5;
        reserved     = 0;
        flags        = 0;
        window_size  = 16'hFFFF;
        checksum     = 0;
        urgent_ptr   = 0;
        opt_mss_en      = 0;
        opt_wscale_en   = 0;
        opt_sack_perm_en = 0;
        opt_ts_en       = 0;
        opt_mss_val     = 16'd1460;
        opt_wscale_val  = 8'd7;
        opt_ts_val      = 0;
        opt_ts_ecr      = 0;
    endfunction

    static function tcp_header create(bit [15:0] sp = 0, bit [15:0] dp = 0,
                                       bit [8:0] f = 0);
        tcp_header h = new();
        h.src_port = sp;
        h.dst_port = dp;
        h.flags    = f;
        return h;
    endfunction

    // Flag accessors
    function bit get_fin(); return flags[0]; endfunction
    function bit get_syn(); return flags[1]; endfunction
    function bit get_rst(); return flags[2]; endfunction
    function bit get_psh(); return flags[3]; endfunction
    function bit get_ack(); return flags[4]; endfunction
    function bit get_urg(); return flags[5]; endfunction
    function bit get_ece(); return flags[6]; endfunction
    function bit get_cwr(); return flags[7]; endfunction
    function bit get_ns();  return flags[8]; endfunction

    function void set_fin(bit v); flags[0] = v; endfunction
    function void set_syn(bit v); flags[1] = v; endfunction
    function void set_rst(bit v); flags[2] = v; endfunction
    function void set_psh(bit v); flags[3] = v; endfunction
    function void set_ack(bit v); flags[4] = v; endfunction
    function void set_urg(bit v); flags[5] = v; endfunction
    function void set_ece(bit v); flags[6] = v; endfunction
    function void set_cwr(bit v); flags[7] = v; endfunction
    function void set_ns(bit v);  flags[8] = v; endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [7:0] doff_res_flags_hi;
        bit [7:0] flags_lo;

        packet_utils::pack_bytes_16(data, src_port);
        packet_utils::pack_bytes_16(data, dst_port);
        packet_utils::pack_bytes_32(data, seq_num);
        packet_utils::pack_bytes_32(data, ack_num);

        // data_offset(4) + reserved(3) + NS(1) = byte 12
        // CWR,ECE,URG,ACK,PSH,RST,SYN,FIN = byte 13
        doff_res_flags_hi = {data_offset, reserved, flags[8]};
        flags_lo = flags[7:0];
        data.push_back(doff_res_flags_hi);
        data.push_back(flags_lo);

        packet_utils::pack_bytes_16(data, window_size);
        packet_utils::pack_bytes_16(data, checksum);
        packet_utils::pack_bytes_16(data, urgent_ptr);
        foreach (options[i]) data.push_back(options[i]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] doff_res_ns;
        bit [7:0] flags_lo;
        int opt_bytes;

        src_port = packet_utils::unpack_bytes_16(data, offset);
        dst_port = packet_utils::unpack_bytes_16(data, offset);
        seq_num  = packet_utils::unpack_bytes_32(data, offset);
        ack_num  = packet_utils::unpack_bytes_32(data, offset);

        doff_res_ns = data[offset]; offset++;
        flags_lo    = data[offset]; offset++;
        data_offset = doff_res_ns[7:4];
        reserved    = doff_res_ns[3:1];
        flags       = {doff_res_ns[0], flags_lo};

        window_size = packet_utils::unpack_bytes_16(data, offset);
        checksum    = packet_utils::unpack_bytes_16(data, offset);
        urgent_ptr  = packet_utils::unpack_bytes_16(data, offset);

        // Read options if data_offset > 5
        options.delete();
        if (data_offset > 5) begin
            opt_bytes = (data_offset - 5) * 4;
            for (int i = 0; i < opt_bytes; i++) begin
                options.push_back(data[offset]);
                offset++;
            end
        end
    endfunction

    virtual function int get_header_length();
        return 20 + options.size();
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Auto-set well-known dst_port if not already set by user
        if (dst_port == 0) begin
            case (next_proto)
                PROTO_NVME_TCP: dst_port = 16'd4420;
                PROTO_ISCSI:    dst_port = 16'd3260;
                PROTO_IWARP:    dst_port = 16'd5044;
                PROTO_HTTP:     dst_port = 16'd80;
                PROTO_BGP:      dst_port = 16'd179;
                default: ;
            endcase
        end
        // Auto-build options from rand enable/value fields
        build_options_from_fields();
        data_offset = 5 + options.size() / 4;
        checksum = 0;
    endfunction

    // Build options[] byte array from rand opt_xxx_en/val fields
    protected function void build_options_from_fields();
        // Only rebuild if any option is enabled AND options is currently empty
        // (if user manually set options, don't overwrite)
        if (!opt_mss_en && !opt_wscale_en && !opt_sack_perm_en && !opt_ts_en) begin
            // No options enabled — if options was set manually, keep it
            return;
        end

        options.delete();

        // MSS (Kind=2, Len=4) — 4 bytes
        if (opt_mss_en) begin
            options.push_back(8'd2);
            options.push_back(8'd4);
            options.push_back(opt_mss_val[15:8]);
            options.push_back(opt_mss_val[7:0]);
        end

        // SACK Permitted (Kind=4, Len=2) — 2 bytes
        if (opt_sack_perm_en) begin
            options.push_back(8'd4);
            options.push_back(8'd2);
        end

        // Timestamps (Kind=8, Len=10) — need NOP+NOP before for 4-byte alignment
        if (opt_ts_en) begin
            options.push_back(8'd1);  // NOP
            options.push_back(8'd1);  // NOP
            options.push_back(8'd8);
            options.push_back(8'd10);
            options.push_back(opt_ts_val[31:24]);
            options.push_back(opt_ts_val[23:16]);
            options.push_back(opt_ts_val[15:8]);
            options.push_back(opt_ts_val[7:0]);
            options.push_back(opt_ts_ecr[31:24]);
            options.push_back(opt_ts_ecr[23:16]);
            options.push_back(opt_ts_ecr[15:8]);
            options.push_back(opt_ts_ecr[7:0]);
        end

        // Window Scale (Kind=3, Len=3) — need NOP before for alignment
        if (opt_wscale_en) begin
            options.push_back(8'd1);  // NOP
            options.push_back(8'd3);
            options.push_back(8'd3);
            options.push_back(opt_wscale_val);
        end

        // Pad to 4-byte boundary with EOL
        while (options.size() % 4 != 0)
            options.push_back(8'd0);
    endfunction

    virtual function protocol_base clone();
        tcp_header h = new();
        h.src_port    = src_port;
        h.dst_port    = dst_port;
        h.seq_num     = seq_num;
        h.ack_num     = ack_num;
        h.data_offset = data_offset;
        h.reserved    = reserved;
        h.flags       = flags;
        h.window_size = window_size;
        h.checksum    = checksum;
        h.urgent_ptr  = urgent_ptr;
        h.options     = options;
        h.opt_mss_en      = opt_mss_en;
        h.opt_wscale_en   = opt_wscale_en;
        h.opt_sack_perm_en = opt_sack_perm_en;
        h.opt_ts_en       = opt_ts_en;
        h.opt_mss_val     = opt_mss_val;
        h.opt_wscale_val  = opt_wscale_val;
        h.opt_ts_val      = opt_ts_val;
        h.opt_ts_ecr      = opt_ts_ecr;
        h.auto_calc   = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        tcp_header o;
        if (!$cast(o, other)) return 0;
        if (!((src_port == o.src_port) && (dst_port == o.dst_port) &&
               (seq_num == o.seq_num) && (ack_num == o.ack_num) &&
               (data_offset == o.data_offset) && (reserved == o.reserved) &&
               (flags == o.flags) && (window_size == o.window_size) &&
               (checksum == o.checksum) && (urgent_ptr == o.urgent_ptr))) return 0;
        // Compare options
        if (options.size() != o.options.size()) return 0;
        foreach (options[i]) if (options[i] != o.options[i]) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  src_port : %0d\n", src_port)};
        s = {s, $sformatf("  dst_port : %0d\n", dst_port)};
        s = {s, $sformatf("  seq_num  : 0x%08x\n", seq_num)};
        s = {s, $sformatf("  ack_num  : 0x%08x\n", ack_num)};
        s = {s, $sformatf("  doff     : %0d\n", data_offset)};
        s = {s, $sformatf("  flags    : 0x%03x [%s%s%s%s%s%s%s%s%s]\n", flags,
            get_ns()  ? "NS "  : "",
            get_cwr() ? "CWR " : "",
            get_ece() ? "ECE " : "",
            get_urg() ? "URG " : "",
            get_ack() ? "ACK " : "",
            get_psh() ? "PSH " : "",
            get_rst() ? "RST " : "",
            get_syn() ? "SYN " : "",
            get_fin() ? "FIN " : "")};
        s = {s, $sformatf("  win_size : %0d\n", window_size)};
        s = {s, $sformatf("  checksum : 0x%04x\n", checksum)};
        s = {s, $sformatf("  urg_ptr  : %0d\n", urgent_ptr)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%0d -> %0d seq:0x%08x flags:0x%03x", src_port, dst_port, seq_num, flags);
    endfunction

    // =========================================================================
    // TCP Option Construction Helpers
    // Assign result to tcp.options, e.g.:
    //   tcp.options = tcp_header::opt_mss(1460);
    //   tcp.options = tcp_header::build_options('{...});
    // =========================================================================

    // Individual option builders — return byte arrays

    // MSS (Kind=2, Len=4): Maximum Segment Size
    static function byte_queue opt_mss(bit [15:0] mss_val);
        byte unsigned opt[$];
        opt = '{8'd2, 8'd4, mss_val[15:8], mss_val[7:0]};
        return opt;
    endfunction

    // Window Scale (Kind=3, Len=3): Window scaling factor
    static function byte_queue opt_window_scale(bit [7:0] shift_count);
        byte unsigned opt[$];
        opt = '{8'd3, 8'd3, shift_count};
        return opt;
    endfunction

    // SACK Permitted (Kind=4, Len=2)
    static function byte_queue opt_sack_permitted();
        byte unsigned opt[$];
        opt = '{8'd4, 8'd2};
        return opt;
    endfunction

    // Timestamps (Kind=8, Len=10): TSval + TSecr
    static function byte_queue opt_timestamps(bit [31:0] ts_val, bit [31:0] ts_ecr);
        byte unsigned opt[$];
        opt = '{8'd8, 8'd10,
                ts_val[31:24], ts_val[23:16], ts_val[15:8], ts_val[7:0],
                ts_ecr[31:24], ts_ecr[23:16], ts_ecr[15:8], ts_ecr[7:0]};
        return opt;
    endfunction

    // NOP (Kind=1): single byte padding
    static function byte_queue opt_nop();
        byte unsigned opt[$];
        opt = '{8'd1};
        return opt;
    endfunction

    // EOL (Kind=0): end of options list
    static function byte_queue opt_eol();
        byte unsigned opt[$];
        opt = '{8'd0};
        return opt;
    endfunction

    // SACK (Kind=5, Len=variable): Selective ACK blocks
    // Each block = {left_edge(32), right_edge(32)}
    static function byte_queue opt_sack(bit [31:0] blocks[$]);
        byte unsigned opt[$];
        int num_blocks = blocks.size() / 2;
        opt.push_back(8'd5);
        opt.push_back(2 + num_blocks * 8);  // len
        foreach (blocks[i]) begin
            opt.push_back(blocks[i][31:24]);
            opt.push_back(blocks[i][23:16]);
            opt.push_back(blocks[i][15:8]);
            opt.push_back(blocks[i][7:0]);
        end
        return opt;
    endfunction

    // Build combined options with automatic NOP padding to 4-byte boundary
    // Input: array of individual option byte arrays concatenated
    // Pads with NOP/EOL to make total length multiple of 4
    static function byte_queue build_options(byte unsigned raw_opts[$]);
        byte unsigned result[$];
        int pad_needed;
        result = raw_opts;
        pad_needed = (4 - (result.size() % 4)) % 4;
        for (int i = 0; i < pad_needed; i++)
            result.push_back(8'd0);  // EOL padding
        return result;
    endfunction

    // Convenience: build common SYN options (MSS + WScale + SACK-Permitted + Timestamps + NOP padding)
    static function byte_queue opt_syn_default(
        bit [15:0] mss_val = 1460,
        bit [7:0]  wscale = 7,
        bit [31:0] ts_val = 0,
        bit [31:0] ts_ecr = 0
    );
        byte unsigned opts[$];
        byte unsigned tmp[$];
        // MSS (4 bytes)
        tmp = opt_mss(mss_val);
        foreach (tmp[i]) opts.push_back(tmp[i]);
        // SACK Permitted (2 bytes)
        tmp = opt_sack_permitted();
        foreach (tmp[i]) opts.push_back(tmp[i]);
        // Timestamps (10 bytes) — need 2 NOP before for alignment
        tmp = opt_nop();
        foreach (tmp[i]) opts.push_back(tmp[i]);
        tmp = opt_nop();
        foreach (tmp[i]) opts.push_back(tmp[i]);
        tmp = opt_timestamps(ts_val, ts_ecr);
        foreach (tmp[i]) opts.push_back(tmp[i]);
        // NOP + Window Scale (1+3 = 4 bytes)
        tmp = opt_nop();
        foreach (tmp[i]) opts.push_back(tmp[i]);
        tmp = opt_window_scale(wscale);
        foreach (tmp[i]) opts.push_back(tmp[i]);
        // Total: 4+2+1+1+10+1+3 = 22 → pad to 24
        return build_options(opts);
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
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("seq_num", path);
            if (__v != "") seq_num = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ack_num", path);
            if (__v != "") ack_num = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("flags", path);
            if (__v != "") flags = 9'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("window_size", path);
            if (__v != "") window_size = 16'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    // help — print TCP options usage guide
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // data_offset
        if (data_offset < 5)
            errors.push_back($sformatf("TCP: data_offset=%0d < 5 (minimum)", data_offset));
        if (data_offset != 5 + options.size() / 4)
            errors.push_back($sformatf("TCP: data_offset=%0d inconsistent with options size=%0d (expected %0d)",
                             data_offset, options.size(), 5 + options.size() / 4));
        // Options 4-byte aligned
        if (options.size() % 4 != 0)
            errors.push_back($sformatf("TCP: options size=%0d not 4-byte aligned", options.size()));
        // Reserved bits
        if (reserved != 0)
            warnings.push_back($sformatf("TCP: reserved=%0d, should be 0", reserved));
        // SYN + FIN
        if (flags[1] && flags[0])
            warnings.push_back("TCP: SYN+FIN both set (unusual, possible attack)");
        // SYN + RST
        if (flags[1] && flags[2])
            warnings.push_back("TCP: SYN+RST both set (invalid combination)");
        // Port 0
        if (src_port == 0)
            warnings.push_back("TCP: src_port=0");
        if (dst_port == 0)
            warnings.push_back("TCP: dst_port=0");
        // URG flag without urgent pointer
        if (flags[5] && urgent_ptr == 0)
            warnings.push_back("TCP: URG flag set but urgent_ptr=0");
    endfunction

    static function void help();
        $display("============================================================================");
        $display(" TCP Options Construction Guide");
        $display("============================================================================");
        $display("");
        $display(" Usage with randomize (recommended):");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_TCP;");
        $display("       tcp.opt_mss_en      == 1;        // enable MSS");
        $display("       tcp.opt_mss_val     == 16'd1460; // MSS value");
        $display("       tcp.opt_wscale_en   == 1;        // enable Window Scale");
        $display("       tcp.opt_wscale_val  == 8'd7;     // shift count");
        $display("       tcp.opt_ts_en       == 1;        // enable Timestamps");
        $display("       tcp.opt_ts_val      == 32'h1234; // TSval");
        $display("       tcp.opt_sack_perm_en == 1;       // enable SACK Permitted");
        $display("   };");
        $display("   // options auto-built, data_offset auto-computed");
        $display("");
        $display(" Error testing (override soft defaults):");
        $display("   pkt.randomize() with {");
        $display("       tcp.opt_mss_en  == 1;");
        $display("       tcp.opt_mss_val == 0;  // invalid MSS=0");
        $display("       tcp.opt_wscale_en  == 1;");
        $display("       tcp.opt_wscale_val == 20; // invalid scale > 14");
        $display("   };");
        $display("");
        $display(" Available static helpers (manual approach):");
        $display("   opt_mss(1460)                          — MSS (Kind=2, 4B)");
        $display("   opt_window_scale(7)                    — Window Scale (Kind=3, 3B)");
        $display("   opt_sack_permitted()                   — SACK Permitted (Kind=4, 2B)");
        $display("   opt_timestamps(ts_val, ts_ecr)         — Timestamps (Kind=8, 10B)");
        $display("   opt_sack('{left, right, ...})          — SACK blocks (Kind=5, var)");
        $display("   opt_nop()                              — NOP padding (Kind=1, 1B)");
        $display("   opt_eol()                              — End of List (Kind=0, 1B)");
        $display("   build_options(raw_bytes)               — Pad to 4-byte boundary");
        $display("   opt_syn_default(mss, wscale, ts, tsr)  — Common SYN options combo");
        $display("");
        $display(" Manual option building:");
        $display("   byte unsigned opts[$];");
        $display("   byte unsigned tmp[$];");
        $display("   tmp = tcp_header::opt_mss(1460);");
        $display("   foreach (tmp[i]) opts.push_back(tmp[i]);");
        $display("   tmp = tcp_header::opt_timestamps(32'h12345678, 0);");
        $display("   foreach (tmp[i]) opts.push_back(tmp[i]);");
        $display("   pkt.tcp.options = tcp_header::build_options(opts);");
        $display("   pkt.do_pack();");
        $display("============================================================================");
    endfunction

endclass

`endif // TCP_HEADER_SV

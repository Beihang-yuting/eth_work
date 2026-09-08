// src/protocols/l3/ipv4_header.sv
`ifndef IPV4_HEADER_SV
`define IPV4_HEADER_SV

`include "protocol_base.sv"

class ipv4_header extends protocol_base;

    rand bit [3:0]  version;
    rand bit [3:0]  ihl;
    rand bit [5:0]  dscp;
    rand bit [1:0]  ecn;
    rand bit [15:0] total_length;
    rand bit [15:0] identification;
    rand bit [2:0]  flags;
    rand bit [12:0] fragment_offset;
    rand bit [7:0]  ttl;
    rand bit [7:0]  protocol;
    rand bit [15:0] header_checksum;
    rand bit [31:0] src_addr;
    rand bit [31:0] dst_addr;
         byte unsigned options[$];

    // ----- IPv4 Option rand controls -----
    rand bit        opt_rr_en;       // Record Route
    rand bit [3:0]  opt_rr_slots;    // Number of IP address slots (1-9)
    rand bit        opt_ts_en;       // Timestamp
    rand bit [3:0]  opt_ts_slots;    // Number of timestamp slots (1-9)
    rand bit        opt_lsr_en;      // Loose Source Route
    rand bit [31:0] opt_lsr_addrs[4]; // Up to 4 route addresses
    rand bit [2:0]  opt_lsr_count;   // Number of LSR addresses (1-4)

    constraint c_default {
        soft version == 4;
        soft ihl == 5;
        soft ttl inside {[1:255]};
        soft flags == 0;
        soft fragment_offset == 0;
        soft dscp == 0;
        soft ecn == 0;
        // Protocol: exclude values that the parser maps to a known next-layer protocol.
        // calc_fields() will override with the correct value (6/17/1/47/...) when
        // a next layer exists. When IPv4 is the last layer (PROTO_RAW_PAYLOAD),
        // the random value must not match a known IP protocol number that would
        // cause the parser to expect another header.
        soft !(protocol inside {8'd1, 8'd2, 8'd4, 8'd6, 8'd17,   // ICMP, IGMP, IP-in-IP, TCP, UDP
                                 8'd41, 8'd47, 8'd50, 8'd58,       // IPv6, GRE, ESP, ICMPv6
                                 8'd89, 8'd115, 8'd132});           // OSPF, L2TP, SCTP
    }

    constraint c_opt_default {
        soft opt_rr_en    == 0;
        soft opt_rr_slots inside {[1:9]};
        soft opt_ts_en    == 0;
        soft opt_ts_slots inside {[1:4]};
        soft opt_lsr_en   == 0;
        soft opt_lsr_count inside {[1:4]};
    }

    function new();
        proto_type       = PROTO_IPV4;
        version          = 4;
        ihl              = 5;
        dscp             = 0;
        ecn              = 0;
        total_length     = 20;
        identification   = 0;
        flags            = 0;
        fragment_offset  = 0;
        ttl              = 64;
        protocol         = IP_PROTO_TCP;
        header_checksum  = 0;
        src_addr         = 0;
        dst_addr         = 0;
        opt_rr_en    = 0;
        opt_rr_slots = 4'd9;
        opt_ts_en    = 0;
        opt_ts_slots = 4'd4;
        opt_lsr_en   = 0;
        opt_lsr_count = 3'd0;
        foreach (opt_lsr_addrs[i]) opt_lsr_addrs[i] = 0;
    endfunction

    static function ipv4_header create(bit [31:0] src = 0, bit [31:0] dst = 0,
                                        bit [7:0] proto = IP_PROTO_TCP, bit [7:0] t = 64);
        ipv4_header h = new();
        h.src_addr  = src;
        h.dst_addr  = dst;
        h.protocol  = proto;
        h.ttl       = t;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [7:0] ver_ihl = {version, ihl};
        bit [7:0] dscp_ecn = {dscp, ecn};
        bit [15:0] flags_frag = {flags, fragment_offset};

        data.push_back(ver_ihl);
        data.push_back(dscp_ecn);
        packet_utils::pack_bytes_16(data, total_length);
        packet_utils::pack_bytes_16(data, identification);
        packet_utils::pack_bytes_16(data, flags_frag);
        data.push_back(ttl);
        data.push_back(protocol);
        packet_utils::pack_bytes_16(data, header_checksum);
        packet_utils::pack_bytes_32(data, src_addr);
        packet_utils::pack_bytes_32(data, dst_addr);
        foreach (options[i]) data.push_back(options[i]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] ver_ihl;
        bit [7:0] dscp_ecn;
        bit [15:0] flags_frag;
        int opt_bytes;

        ver_ihl = data[offset]; offset++;
        dscp_ecn = data[offset]; offset++;

        version = ver_ihl[7:4];
        ihl     = ver_ihl[3:0];
        dscp    = dscp_ecn[7:2];
        ecn     = dscp_ecn[1:0];

        total_length    = packet_utils::unpack_bytes_16(data, offset);
        identification  = packet_utils::unpack_bytes_16(data, offset);
        flags_frag      = packet_utils::unpack_bytes_16(data, offset);
        flags           = flags_frag[15:13];
        fragment_offset = flags_frag[12:0];
        ttl             = data[offset]; offset++;
        protocol        = data[offset]; offset++;
        header_checksum = packet_utils::unpack_bytes_16(data, offset);
        src_addr        = packet_utils::unpack_bytes_32(data, offset);
        dst_addr        = packet_utils::unpack_bytes_32(data, offset);

        // Read options if ihl > 5
        options.delete();
        if (ihl > 5) begin
            opt_bytes = (ihl - 5) * 4;
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

        // Set protocol from next_proto
        case (next_proto)
            PROTO_TCP:      protocol = IP_PROTO_TCP;
            PROTO_UDP:      protocol = IP_PROTO_UDP;
            PROTO_ICMP:     protocol = IP_PROTO_ICMP;
            PROTO_IGMP:     protocol = IP_PROTO_IGMP;
            PROTO_GRE:      protocol = IP_PROTO_GRE;
            PROTO_SCTP:     protocol = IP_PROTO_SCTP;
            PROTO_IP_IN_IP: protocol = IP_PROTO_IP_IN_IP;
            PROTO_IPV6:     protocol = IP_PROTO_IPV6;
            PROTO_OSPF:     protocol = IP_PROTO_OSPF;
            PROTO_L2TP:     protocol = IP_PROTO_L2TP;
            PROTO_ESP:      protocol = IP_PROTO_ESP;
            PROTO_ICMPV6:   protocol = IP_PROTO_ICMPV6;
            default: ;
        endcase

        // Auto-build options from rand enable fields
        build_options_from_fields();

        // Compute IHL
        ihl = 5 + options.size() / 4;

        // Compute total_length
        total_length = get_header_length() + payload_data.size();

        // Compute checksum: zero checksum, pack header, compute
        begin
            byte unsigned hdr_data[$];
            header_checksum = 0;
            pack_header(hdr_data);
            header_checksum = packet_utils::ones_complement_checksum(hdr_data);
        end
    endfunction

    protected function void build_options_from_fields();
        int len;
        if (!opt_rr_en && !opt_ts_en && !opt_lsr_en) return;

        options.delete();

        // Record Route (Type=7)
        if (opt_rr_en) begin
            len = 3 + opt_rr_slots * 4;
            options.push_back(8'd7);
            options.push_back(len[7:0]);
            options.push_back(8'd4);  // pointer
            for (int i = 0; i < opt_rr_slots * 4; i++)
                options.push_back(8'd0);
        end

        // Timestamp (Type=68)
        if (opt_ts_en) begin
            len = 4 + opt_ts_slots * 4;
            options.push_back(8'd68);
            options.push_back(len[7:0]);
            options.push_back(8'd5);  // pointer
            options.push_back(8'd0);  // overflow + flag
            for (int i = 0; i < opt_ts_slots * 4; i++)
                options.push_back(8'd0);
        end

        // Loose Source Route (Type=131)
        if (opt_lsr_en) begin
            len = 3 + opt_lsr_count * 4;
            options.push_back(8'd131);
            options.push_back(len[7:0]);
            options.push_back(8'd4);  // pointer
            for (int i = 0; i < opt_lsr_count; i++) begin
                options.push_back(opt_lsr_addrs[i][31:24]);
                options.push_back(opt_lsr_addrs[i][23:16]);
                options.push_back(opt_lsr_addrs[i][15:8]);
                options.push_back(opt_lsr_addrs[i][7:0]);
            end
        end

        // Pad to 4-byte boundary
        while (options.size() % 4 != 0)
            options.push_back(8'd0);
    endfunction

    virtual function protocol_base clone();
        ipv4_header h = new();
        h.version         = version;
        h.ihl             = ihl;
        h.dscp            = dscp;
        h.ecn             = ecn;
        h.total_length    = total_length;
        h.identification  = identification;
        h.flags           = flags;
        h.fragment_offset = fragment_offset;
        h.ttl             = ttl;
        h.protocol        = protocol;
        h.header_checksum = header_checksum;
        h.src_addr        = src_addr;
        h.dst_addr        = dst_addr;
        h.options         = options;
        h.opt_rr_en    = opt_rr_en;
        h.opt_rr_slots = opt_rr_slots;
        h.opt_ts_en    = opt_ts_en;
        h.opt_ts_slots = opt_ts_slots;
        h.opt_lsr_en   = opt_lsr_en;
        h.opt_lsr_count = opt_lsr_count;
        h.opt_lsr_addrs = opt_lsr_addrs;
        h.auto_calc       = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv4_header o;
        if (!$cast(o, other)) return 0;
        if (!((version == o.version) && (ihl == o.ihl) && (dscp == o.dscp) &&
               (ecn == o.ecn) && (total_length == o.total_length) &&
               (identification == o.identification) && (flags == o.flags) &&
               (fragment_offset == o.fragment_offset) && (ttl == o.ttl) &&
               (protocol == o.protocol) && (header_checksum == o.header_checksum) &&
               (src_addr == o.src_addr) && (dst_addr == o.dst_addr))) return 0;
        if (options.size() != o.options.size()) return 0;
        foreach (options[i]) if (options[i] != o.options[i]) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version  : %0d\n", version)};
        s = {s, $sformatf("  ihl      : %0d\n", ihl)};
        s = {s, $sformatf("  dscp     : %0d\n", dscp)};
        s = {s, $sformatf("  ecn      : %0d\n", ecn)};
        s = {s, $sformatf("  total_len: %0d\n", total_length)};
        s = {s, $sformatf("  ident    : 0x%04x\n", identification)};
        s = {s, $sformatf("  flags    : %03b\n", flags)};
        s = {s, $sformatf("  frag_off : %0d\n", fragment_offset)};
        s = {s, $sformatf("  ttl      : %0d\n", ttl)};
        s = {s, $sformatf("  protocol : %0d\n", protocol)};
        s = {s, $sformatf("  checksum : 0x%04x\n", header_checksum)};
        s = {s, $sformatf("  src_addr : %s\n", packet_utils::format_ipv4(src_addr))};
        s = {s, $sformatf("  dst_addr : %s\n", packet_utils::format_ipv4(dst_addr))};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%s -> %s proto:%0d ttl:%0d len:%0d",
                         packet_utils::format_ipv4(src_addr),
                         packet_utils::format_ipv4(dst_addr),
                         protocol, ttl, total_length);
    endfunction

    // =========================================================================
    // IPv4 Option Construction Helpers
    // =========================================================================

    // NOP (Type=1, 1 byte)
    static function byte_queue opt_nop();
        byte unsigned opt[$];
        opt = '{8'd1};
        return opt;
    endfunction

    // EOL (Type=0, 1 byte)
    static function byte_queue opt_eol();
        byte unsigned opt[$];
        opt = '{8'd0};
        return opt;
    endfunction

    // Record Route (Type=7): pointer starts at 4
    static function byte_queue opt_record_route(int num_slots = 9);
        byte unsigned opt[$];
        int len = 3 + num_slots * 4;
        opt.push_back(8'd7);       // type
        opt.push_back(len[7:0]);   // length
        opt.push_back(8'd4);       // pointer (starts at 4)
        for (int i = 0; i < num_slots * 4; i++)
            opt.push_back(8'd0);
        return opt;
    endfunction

    // Timestamp (Type=68)
    static function byte_queue opt_timestamp(int num_slots = 4, bit [3:0] oflw_flag = 0);
        byte unsigned opt[$];
        int len = 4 + num_slots * 4;
        opt.push_back(8'd68);      // type
        opt.push_back(len[7:0]);   // length
        opt.push_back(8'd5);       // pointer
        opt.push_back({oflw_flag, 4'd0});  // overflow + flag
        for (int i = 0; i < num_slots * 4; i++)
            opt.push_back(8'd0);
        return opt;
    endfunction

    // Loose Source Route (Type=131)
    static function byte_queue opt_loose_source_route(bit [31:0] route_addrs[$]);
        byte unsigned opt[$];
        int len = 3 + route_addrs.size() * 4;
        opt.push_back(8'd131);     // type
        opt.push_back(len[7:0]);   // length
        opt.push_back(8'd4);       // pointer
        foreach (route_addrs[i]) begin
            opt.push_back(route_addrs[i][31:24]);
            opt.push_back(route_addrs[i][23:16]);
            opt.push_back(route_addrs[i][15:8]);
            opt.push_back(route_addrs[i][7:0]);
        end
        return opt;
    endfunction

    // Strict Source Route (Type=137)
    static function byte_queue opt_strict_source_route(bit [31:0] route_addrs[$]);
        byte unsigned opt[$];
        int len = 3 + route_addrs.size() * 4;
        opt.push_back(8'd137);     // type
        opt.push_back(len[7:0]);   // length
        opt.push_back(8'd4);       // pointer
        foreach (route_addrs[i]) begin
            opt.push_back(route_addrs[i][31:24]);
            opt.push_back(route_addrs[i][23:16]);
            opt.push_back(route_addrs[i][15:8]);
            opt.push_back(route_addrs[i][7:0]);
        end
        return opt;
    endfunction

    // Pad options to 4-byte boundary
    static function byte_queue build_options(byte unsigned raw_opts[$]);
        byte unsigned result[$];
        int pad_needed;
        result = raw_opts;
        pad_needed = (4 - (result.size() % 4)) % 4;
        for (int i = 0; i < pad_needed; i++)
            result.push_back(8'd0);
        return result;
    endfunction

    // help — print IPv4 options usage guide
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // Version
        if (version != 4)
            errors.push_back($sformatf("IPv4: version=%0d, expected 4", version));
        // IHL
        if (ihl < 5)
            errors.push_back($sformatf("IPv4: IHL=%0d < 5 (minimum)", ihl));
        if (ihl != 5 + options.size() / 4)
            errors.push_back($sformatf("IPv4: IHL=%0d inconsistent with options size=%0d (expected IHL=%0d)",
                             ihl, options.size(), 5 + options.size() / 4));
        // Options must be 4-byte aligned
        if (options.size() % 4 != 0)
            errors.push_back($sformatf("IPv4: options size=%0d not 4-byte aligned", options.size()));
        // Total length
        if (total_length < get_header_length())
            errors.push_back($sformatf("IPv4: total_length=%0d < header_length=%0d",
                             total_length, get_header_length()));
        // TTL
        if (ttl == 0)
            warnings.push_back("IPv4: TTL=0 (packet will be dropped by routers)");
        // Flags: reserved bit (RFC 791: bit 0 of flags MUST be zero)
        if (flags[2] != 0)
            errors.push_back($sformatf("IPv4: flags reserved bit set (flags=%03b), MUST be 0 (RFC 791)", flags));
        // DF + MF conflict
        if (flags[1] && flags[0])
            warnings.push_back("IPv4: both DF and MF flags set (unusual)");
        // Fragment offset with DF
        if (flags[1] && fragment_offset != 0)
            errors.push_back($sformatf("IPv4: DF set but fragment_offset=%0d (should be 0)", fragment_offset));
        // Header checksum
        begin
            byte unsigned hdr_data[$];
            bit [15:0] saved_cksum = header_checksum;
            bit [15:0] computed;
            header_checksum = 0;
            pack_header(hdr_data);
            computed = packet_utils::ones_complement_checksum(hdr_data);
            header_checksum = saved_cksum;
            if (saved_cksum != computed)
                errors.push_back($sformatf("IPv4: header_checksum=0x%04x, expected 0x%04x",
                                 saved_cksum, computed));
        end
        // Source addr
        if (src_addr == 32'hFFFFFFFF)
            warnings.push_back("IPv4: src_addr is broadcast (255.255.255.255)");
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("src_addr", path);
            if (__v != "") src_addr = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("dst_addr", path);
            if (__v != "") dst_addr = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ttl", path);
            if (__v != "") ttl = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("dscp", path);
            if (__v != "") dscp = 6'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("identification", path);
            if (__v != "") identification = 16'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    static function void help();
        $display("============================================================================");
        $display(" IPv4 Options Construction Guide");
        $display("============================================================================");
        $display("");
        $display(" Usage with randomize (recommended):");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_TCP;");
        $display("       outer_ipv4.opt_rr_en    == 1;    // enable Record Route");
        $display("       outer_ipv4.opt_rr_slots == 9;    // 9 address slots");
        $display("   };");
        $display("   // options auto-built, ihl auto-computed");
        $display("");
        $display("   pkt.randomize() with {");
        $display("       outer_ipv4.opt_ts_en    == 1;    // enable Timestamp");
        $display("       outer_ipv4.opt_ts_slots == 4;    // 4 timestamp slots");
        $display("   };");
        $display("");
        $display("   pkt.randomize() with {");
        $display("       outer_ipv4.opt_lsr_en    == 1;   // enable Loose Source Route");
        $display("       outer_ipv4.opt_lsr_count == 3;   // 3 route addresses");
        $display("   };");
        $display("");
        $display(" Available static helpers (manual approach):");
        $display("   opt_nop()                               — NOP (Type=1, 1B)");
        $display("   opt_eol()                               — End (Type=0, 1B)");
        $display("   opt_record_route(num_slots)             — Record Route (Type=7)");
        $display("   opt_timestamp(num_slots, oflw_flag)     — Timestamp (Type=68)");
        $display("   opt_loose_source_route(addrs[$])        — LSR (Type=131)");
        $display("   opt_strict_source_route(addrs[$])       — SSR (Type=137)");
        $display("   build_options(raw_bytes)                 — Pad to 4-byte boundary");
        $display("");
        $display(" Manual option building:");
        $display("   pkt.outer_ipv4.options = ipv4_header::opt_record_route(9);");
        $display("   pkt.do_pack();  // ihl auto-updates to account for options");
        $display("============================================================================");
    endfunction

endclass

`endif // IPV4_HEADER_SV

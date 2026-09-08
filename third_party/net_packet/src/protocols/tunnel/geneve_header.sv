// src/protocols/tunnel/geneve_header.sv
`ifndef GENEVE_HEADER_SV
`define GENEVE_HEADER_SV

`include "protocol_base.sv"

class geneve_header extends protocol_base;

    rand bit [1:0]  version;
    rand bit [5:0]  opt_len;
    rand bit        o_flag;
    rand bit        c_flag;
    rand bit [5:0]  reserved0;
    rand bit [15:0] protocol_type;
    rand bit [23:0] vni;
    rand bit [7:0]  reserved1;
    byte unsigned   options[$];

    // ----- Geneve Option rand controls -----
    rand bit        opt_en;          // Enable auto-generating options
    rand bit [1:0]  opt_num;         // Number of TLV options to generate (0-3)
    rand bit [15:0] opt_class0;      // Option 0 class
    rand bit [6:0]  opt_type0;       // Option 0 type (7-bit, bit7=critical auto 0)
    rand bit [31:0] opt_data0;       // Option 0 data (4 bytes)
    rand bit [15:0] opt_class1;
    rand bit [6:0]  opt_type1;
    rand bit [31:0] opt_data1;
    rand bit [15:0] opt_class2;
    rand bit [6:0]  opt_type2;
    rand bit [31:0] opt_data2;

    constraint c_default {
        soft version   == 2'h0;
        soft o_flag    == 1'b0;
        soft c_flag    == 1'b0;
        soft reserved0 == 6'h0;
        soft reserved1 == 8'h0;
        soft opt_len   == 6'h0;
        // protocol_type: exclude values that the parser maps to a known next-layer.
        // calc_fields() overrides with the correct value when a next layer exists.
        soft !(protocol_type inside {16'h0800, 16'h86DD, 16'h6558}); // IPv4, IPv6, Ethernet
    }

    constraint c_opt_ctrl {
        soft opt_en   == 0;
        soft opt_num  == 0;
        soft opt_class0 == 16'h0100;  // Linux
        soft opt_class1 == 16'h0100;
        soft opt_class2 == 16'h0100;
        opt_num inside {[0:3]};
    }

    function new();
        proto_type    = PROTO_GENEVE;
        version       = 2'h0;
        opt_len       = 6'h0;
        o_flag        = 1'b0;
        c_flag        = 1'b0;
        reserved0     = 6'h0;
        protocol_type = 16'h6558;
        vni           = 24'd100;
        reserved1     = 8'h0;
        options = '{};
        opt_en = 0; opt_num = 0;
        opt_class0 = 16'h0100; opt_type0 = 0; opt_data0 = 0;
        opt_class1 = 16'h0100; opt_type1 = 0; opt_data1 = 0;
        opt_class2 = 16'h0100; opt_type2 = 0; opt_data2 = 0;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        int i;
        data.push_back({version, opt_len});
        data.push_back({o_flag, c_flag, reserved0});
        data.push_back(protocol_type[15:8]);
        data.push_back(protocol_type[7:0]);
        data.push_back(vni[23:16]);
        data.push_back(vni[15:8]);
        data.push_back(vni[7:0]);
        data.push_back(reserved1);
        for (i = 0; i < options.size(); i++) begin
            data.push_back(options[i]);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        byte unsigned b0, b1;
        int i;
        int opt_bytes;
        b0            = data[offset]; offset++;
        version       = b0[7:6];
        opt_len       = b0[5:0];
        b1            = data[offset]; offset++;
        o_flag        = b1[7];
        c_flag        = b1[6];
        reserved0     = b1[5:0];
        protocol_type[15:8] = data[offset]; offset++;
        protocol_type[7:0]  = data[offset]; offset++;
        vni[23:16]    = data[offset]; offset++;
        vni[15:8]     = data[offset]; offset++;
        vni[7:0]      = data[offset]; offset++;
        reserved1     = data[offset]; offset++;
        opt_bytes = int'(opt_len) * 4;
        options.delete();
        for (i = 0; i < opt_bytes; i++) begin
            options.push_back(data[offset]); offset++;
        end
    endfunction

    virtual function int get_header_length();
        return 8 + int'(opt_len) * 4;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Auto-build options from rand fields
        if (opt_en && opt_num > 0) begin
            options.delete();
            if (opt_num >= 1) begin  // TLV 0: class(2) + type(1) + R+len(1) + data(4) = 8 bytes
                options.push_back(opt_class0[15:8]); options.push_back(opt_class0[7:0]);
                options.push_back({1'b0, opt_type0}); options.push_back({3'b000, 5'd1}); // len=1 (4 bytes)
                options.push_back(opt_data0[31:24]); options.push_back(opt_data0[23:16]);
                options.push_back(opt_data0[15:8]);  options.push_back(opt_data0[7:0]);
            end
            if (opt_num >= 2) begin
                options.push_back(opt_class1[15:8]); options.push_back(opt_class1[7:0]);
                options.push_back({1'b0, opt_type1}); options.push_back({3'b000, 5'd1});
                options.push_back(opt_data1[31:24]); options.push_back(opt_data1[23:16]);
                options.push_back(opt_data1[15:8]);  options.push_back(opt_data1[7:0]);
            end
            if (opt_num >= 3) begin
                options.push_back(opt_class2[15:8]); options.push_back(opt_class2[7:0]);
                options.push_back({1'b0, opt_type2}); options.push_back({3'b000, 5'd1});
                options.push_back(opt_data2[31:24]); options.push_back(opt_data2[23:16]);
                options.push_back(opt_data2[15:8]);  options.push_back(opt_data2[7:0]);
            end
        end
        opt_len = options.size() / 4;
        case (next_proto)
            PROTO_ETHERNET: protocol_type = 16'h6558;
            PROTO_IPV4:     protocol_type = ETHERTYPE_IPV4;
            PROTO_IPV6:     protocol_type = ETHERTYPE_IPV6;
            default:        protocol_type = 16'h6558;
        endcase
    endfunction

    virtual function protocol_base clone();
        geneve_header h = new();
        h.version       = version;
        h.opt_len       = opt_len;
        h.o_flag        = o_flag;
        h.c_flag        = c_flag;
        h.reserved0     = reserved0;
        h.protocol_type = protocol_type;
        h.vni           = vni;
        h.reserved1     = reserved1;
        h.options = options;
        h.opt_en        = opt_en;
        h.opt_num       = opt_num;
        h.opt_class0    = opt_class0;
        h.opt_type0     = opt_type0;
        h.opt_data0     = opt_data0;
        h.opt_class1    = opt_class1;
        h.opt_type1     = opt_type1;
        h.opt_data1     = opt_data1;
        h.opt_class2    = opt_class2;
        h.opt_type2     = opt_type2;
        h.opt_data2     = opt_data2;
        h.auto_calc     = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        geneve_header o;
        if (!$cast(o, other)) return 0;
        if (version       != o.version)       return 0;
        if (opt_len       != o.opt_len)       return 0;
        if (protocol_type != o.protocol_type) return 0;
        if (vni           != o.vni)           return 0;
        if (options.size() != o.options.size()) return 0;
        for (int i = 0; i < options.size(); i++) begin
            if (options[i] != o.options[i]) return 0;
        end
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version      : %0d\n",    version)};
        s = {s, $sformatf("  opt_len      : %0d\n",    opt_len)};
        s = {s, $sformatf("  o_flag       : %0b\n",    o_flag)};
        s = {s, $sformatf("  c_flag       : %0b\n",    c_flag)};
        s = {s, $sformatf("  protocol_type: 0x%04x\n", protocol_type)};
        s = {s, $sformatf("  vni          : %0d\n",    vni)};
        s = {s, $sformatf("  options_bytes: %0d\n",    options.size())};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("Geneve vni:%0d proto:0x%04x opt_len:%0d", vni, protocol_type, opt_len);
    endfunction

    // =========================================================================
    // Geneve TLV Option Construction Helpers
    // Build option byte arrays and assign to geneve.options
    // =========================================================================

    // Build a single Geneve TLV option
    // opt_class: 16-bit option class (0x0100=Linux, 0x0000=unassigned)
    // opt_type:  7-bit type code (bit 7 = critical flag)
    // opt_data:  option data (must be multiple of 4 bytes)
    static function byte_queue build_tlv(
        bit [15:0] opt_class,
        bit [7:0]  opt_type,
        byte unsigned opt_data[$]
    );
        byte unsigned tlv[$];
        int data_len_words = opt_data.size() / 4;
        // Option header: class(16) + type(8) + R(3)+Len(5)
        tlv.push_back(opt_class[15:8]);
        tlv.push_back(opt_class[7:0]);
        tlv.push_back(opt_type);
        tlv.push_back({3'b000, data_len_words[4:0]});
        // Data
        foreach (opt_data[i]) tlv.push_back(opt_data[i]);
        return tlv;
    endfunction

    // Build multiple TLV options and concatenate
    // After building, assign to geneve.options and geneve.opt_len will auto-compute in calc_fields
    static function byte_queue build_options(byte unsigned tlv_list[$]);
        // TLV list is already concatenated; just ensure 4-byte alignment
        byte unsigned result[$];
        result = tlv_list;
        while (result.size() % 4 != 0)
            result.push_back(8'd0);
        return result;
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("vni", path);
            if (__v != "") vni = 24'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

    // help — print Geneve options usage guide
    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (version != 0)
            errors.push_back($sformatf("Geneve: version=%0d, expected 0", version));
        if (reserved0 != 0)
            warnings.push_back($sformatf("Geneve: reserved0=%0d, should be 0", reserved0));
        if (reserved1 != 0)
            warnings.push_back($sformatf("Geneve: reserved1=%0d, should be 0", reserved1));
        // opt_len consistency: opt_len is in 4-byte units
        if (opt_len * 4 != options.size())
            errors.push_back($sformatf("Geneve: opt_len=%0d (=%0dB) but options size=%0dB",
                             opt_len, opt_len * 4, options.size()));
        if (vni == 0)
            warnings.push_back("Geneve: VNI=0");
    endfunction

    static function void help();
        $display("============================================================================");
        $display(" Geneve TLV Options Guide (RFC 8926)");
        $display("============================================================================");
        $display("");
        $display(" TLV format: Class(16b) | Type(8b) | R(3b)+Len(5b) | Data(Len*4 bytes)");
        $display("");
        $display(" Build options:");
        $display("   byte unsigned opts[$], tlv[$];");
        $display("   // Option 1: class=0x0100, type=1, data=4 bytes");
        $display("   byte unsigned data1[$] = '{8'hAA, 8'hBB, 8'hCC, 8'hDD};");
        $display("   tlv = geneve_header::build_tlv(16'h0100, 8'h01, data1);");
        $display("   foreach (tlv[i]) opts.push_back(tlv[i]);");
        $display("   // Option 2: class=0x0100, type=2, data=8 bytes");
        $display("   byte unsigned data2[$] = '{8'h01,8'h02,8'h03,8'h04,8'h05,8'h06,8'h07,8'h08};");
        $display("   tlv = geneve_header::build_tlv(16'h0100, 8'h02, data2);");
        $display("   foreach (tlv[i]) opts.push_back(tlv[i]);");
        $display("");
        $display(" Assign to packet:");
        $display("   pkt.randomize() with { pkt_kind == ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP; };");
        $display("   pkt.geneve.options = geneve_header::build_options(opts);");
        $display("   pkt.geneve.opt_len = pkt.geneve.options.size() / 4;");
        $display("   pkt.do_pack();  // re-pack with options");
        $display("============================================================================");
    endfunction

endclass

`endif // GENEVE_HEADER_SV

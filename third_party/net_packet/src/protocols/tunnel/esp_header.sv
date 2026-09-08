// src/protocols/tunnel/esp_header.sv
`ifndef ESP_HEADER_SV
`define ESP_HEADER_SV

`include "protocol_base.sv"

// ============================================================
// IPsec ESP (Encapsulating Security Payload) header: 8 bytes.
// RFC 4303.  IP protocol number 50.
//
// Wire format:
//   Bytes 0-3: spi             [31:0] — Security Parameters Index
//   Bytes 4-7: sequence_number [31:0]
//
// Note: The encrypted payload, padding, trailer, and ICV follow
// the header but are not modelled here (only the unencrypted
// header portion is generated).
// ============================================================
class esp_header extends protocol_base;

    rand bit [31:0] spi;
    rand bit [31:0] sequence_number;

    function new();
        proto_type      = PROTO_ESP;
        spi             = 32'd0;
        sequence_number = 32'd0;
    endfunction

    static function esp_header create(bit [31:0] s = 32'd0);
        esp_header h = new();
        h.spi = s;
        return h;
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(spi[31:24]);
        data.push_back(spi[23:16]);
        data.push_back(spi[15:8]);
        data.push_back(spi[7:0]);
        data.push_back(sequence_number[31:24]);
        data.push_back(sequence_number[23:16]);
        data.push_back(sequence_number[15:8]);
        data.push_back(sequence_number[7:0]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        spi[31:24]             = data[offset]; offset++;
        spi[23:16]             = data[offset]; offset++;
        spi[15:8]              = data[offset]; offset++;
        spi[7:0]               = data[offset]; offset++;
        sequence_number[31:24] = data[offset]; offset++;
        sequence_number[23:16] = data[offset]; offset++;
        sequence_number[15:8]  = data[offset]; offset++;
        sequence_number[7:0]   = data[offset]; offset++;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        // ESP does not auto-calculate any header fields
    endfunction

    virtual function protocol_base clone();
        esp_header h = new();
        h.spi             = spi;
        h.sequence_number = sequence_number;
        h.auto_calc       = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        esp_header o;
        if (!$cast(o, other)) return 0;
        return (spi == o.spi) && (sequence_number == o.sequence_number);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  spi            : 0x%08x\n", spi)};
        s = {s, $sformatf("  sequence_number: %0d\n", sequence_number)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ESP spi:0x%08x seq:%0d", spi, sequence_number);
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        if (spi == 0)
            warnings.push_back("ESP: SPI=0 (reserved, implementation specific)");
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("spi", path);
            if (__v != "") spi = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("sequence_number", path);
            if (__v != "") sequence_number = 32'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // ESP_HEADER_SV

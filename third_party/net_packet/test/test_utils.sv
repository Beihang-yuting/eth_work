// test/test_utils.sv
`include "packet_defines.sv"
`include "packet_utils.sv"

program test_utils;

    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string name, bit condition);
        if (condition) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask

    initial begin
        byte unsigned data[$];
        bit [15:0] csum;
        string s;

        $display("=== test_utils ===");

        // Test: ones_complement_checksum on known IPv4 header
        data = '{8'h45, 8'h00, 8'h00, 8'h3c,
                 8'h1c, 8'h46, 8'h40, 8'h00,
                 8'h40, 8'h06, 8'h00, 8'h00,
                 8'hac, 8'h10, 8'h0a, 8'h63,
                 8'hac, 8'h10, 8'h0a, 8'h0c};
        csum = packet_utils::ones_complement_checksum(data);
        check("ones_complement_checksum IPv4 header", csum == 16'hb1e6);

        // Test: checksum of all zeros -> 0xFFFF
        data = '{8'h00, 8'h00, 8'h00, 8'h00};
        csum = packet_utils::ones_complement_checksum(data);
        check("ones_complement_checksum all zeros", csum == 16'hFFFF);

        // Test: byte_swap_16
        check("byte_swap_16", packet_utils::byte_swap_16(16'h0102) == 16'h0201);

        // Test: byte_swap_32
        check("byte_swap_32", packet_utils::byte_swap_32(32'h01020304) == 32'h04030201);

        // Test: format_mac
        s = packet_utils::format_mac(48'h001122334455);
        check("format_mac", s == "00:11:22:33:44:55");

        // Test: format_ipv4
        s = packet_utils::format_ipv4(32'hC0A80001);
        check("format_ipv4", s == "192.168.0.1");

        s = packet_utils::format_ipv4(32'h00000000);
        check("format_ipv4 zeros", s == "0.0.0.0");

        s = packet_utils::format_ipv4(32'hFFFFFFFF);
        check("format_ipv4 broadcast", s == "255.255.255.255");

        // Test: pack_bytes_16
        data = {};
        packet_utils::pack_bytes_16(data, 16'hABCD);
        check("pack_bytes_16", data[0] == 8'hAB && data[1] == 8'hCD);

        // Test: pack_bytes_32
        data = {};
        packet_utils::pack_bytes_32(data, 32'h12345678);
        check("pack_bytes_32", data[0] == 8'h12 && data[1] == 8'h34 && data[2] == 8'h56 && data[3] == 8'h78);

        // Test: unpack_bytes_16
        data = '{8'hAB, 8'hCD, 8'h00};
        begin
            int offset = 0;
            bit [15:0] val = packet_utils::unpack_bytes_16(data, offset);
            check("unpack_bytes_16 value", val == 16'hABCD);
            check("unpack_bytes_16 offset advance", offset == 2);
        end

        // Test: unpack_bytes_32
        data = '{8'h12, 8'h34, 8'h56, 8'h78, 8'h00};
        begin
            int offset = 0;
            bit [31:0] val = packet_utils::unpack_bytes_32(data, offset);
            check("unpack_bytes_32 value", val == 32'h12345678);
            check("unpack_bytes_32 offset advance", offset == 4);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end
endprogram

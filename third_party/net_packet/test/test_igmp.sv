// test_igmp.sv — 验证 IGMP header + ETH_IPV4_IGMP 模板可建/可传参/可打包
`include "aip_core_pkg.sv"
`include "packet.sv"

module test_igmp;
    int pass_cnt = 0, fail_cnt = 0;

    task check(string name, longint unsigned actual, longint unsigned expected);
        if (actual == expected) begin $display("[PASS] %s = 0x%0h", name, actual); pass_cnt++; end
        else begin $display("[FAIL] %s = 0x%0h (exp 0x%0h)", name, actual, expected); fail_cnt++; end
    endtask

    initial begin
        packet      pkt;
        igmp_header ig, ig2;
        ipv4_header ip4;

        // ---- 1. build_from_template(ETH_IPV4_IGMP) + load_params ----
        $display("\n=== IGMP build + load_params ===");
        aip_cmdline_override::clear_all();
        aip_cmdline_override::set_val("g.igmp.igmp_type",     "0x11");        // membership query
        aip_cmdline_override::set_val("g.igmp.group_address", "0xE0000001");  // 224.0.0.1
        aip_cmdline_override::set_val("g.igmp.max_resp_time", "0x64");

        pkt = new();
        pkt.build_from_template(ETH_IPV4_IGMP);
        pkt.load_params("g");
        pkt.do_pack();

        check("layer count", pkt.layer_stack.size(), 3);   // ETH, IPV4, IGMP
        if (!$cast(ig, pkt.layer_stack[2])) begin $display("[FAIL] layer[2] not igmp"); fail_cnt++; end
        else begin
            check("igmp.igmp_type",     ig.igmp_type,     8'h11);
            check("igmp.group_address", ig.group_address, 32'hE0000001);
            check("igmp.max_resp_time", ig.max_resp_time, 8'h64);
        end
        if ($cast(ip4, pkt.layer_stack[1]))
            check("ipv4.protocol==IGMP(2)", ip4.protocol, 8'd2);

        // raw: ETH(14)+IPV4(20)=34 -> IGMP type at byte 34
        check("raw_data not empty", (pkt.raw_data.size() > 0) ? 1 : 0, 1);
        check("raw[34]=igmp_type",  pkt.raw_data[34], 8'h11);

        // ---- 2. pack/unpack roundtrip ----
        $display("\n=== IGMP roundtrip ===");
        begin
            byte unsigned pkbuf[$];
            int off = 0;
            ig.pack_header(pkbuf);
            ig2 = new();
            ig2.unpack_header(pkbuf, off);
            check("rt.type",  ig2.igmp_type,     ig.igmp_type);
            check("rt.group", ig2.group_address, ig.group_address);
            check("rt.mrt",   ig2.max_resp_time, ig.max_resp_time);
            check("rt.len",   ig.get_header_length(), 8);
        end

        aip_cmdline_override::clear_all();

        // ---- 3. 500x 默认 randomize: IGMP 现在可建, 仍应 0 warning ----
        $display("\n=== 500x default randomize (IGMP buildable) ===");
        begin
            int n_ok = 0;
            for (int i = 0; i < 500; i++) begin
                automatic packet rp = new();
                if (rp.randomize()) n_ok++;
            end
            check("randomize 500/500", n_ok, 500);
        end

        $display("\n===== IGMP: %0d passed, %0d failed =====", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL IGMP TESTS PASSED");
        else               $display("SOME IGMP TESTS FAILED");
        $finish;
    end
endmodule

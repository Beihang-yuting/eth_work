// test_load_params_wide.sv — 验证宽字段(48/64/128bit)与新增 header 的 load_params 满宽设置
//   重点: "整除设置" — 每个可传参数读回与传入完全相等, 无截断
//   编译(单编译单元, 勿加 +define+AIP_CMDLINE_SV, aip_core_pkg 自定义该宏):
//     vcs -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps \
//         +incdir+src ... +incdir+<aip_core> test/test_load_params_wide.sv && ./simv
`include "aip_core_pkg.sv"
`include "packet.sv"

module test_load_params_wide;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task check(string name, longint unsigned actual, longint unsigned expected);
        if (actual == expected) begin
            $display("[PASS] %s = 0x%0h", name, actual);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s = 0x%0h (expected 0x%0h)", name, actual, expected);
            fail_cnt++;
        end
    endtask

    task check128(string name, bit [127:0] actual, bit [127:0] expected);
        if (actual == expected) begin
            $display("[PASS] %s = 0x%032h", name, actual);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s = 0x%032h (expected 0x%032h)", name, actual, expected);
            fail_cnt++;
        end
    endtask

    task check_ok(string name, bit actual, bit expected);
        if (actual == expected) begin
            $display("[PASS] %s ok=%0d", name, actual);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s ok=%0d (expected %0d)", name, actual, expected);
            fail_cnt++;
        end
    endtask

    initial begin
        // ============================================================
        // A. packet_utils::parse_ipv6 直接单测
        // ============================================================
        $display("\n=== A: parse_ipv6 unit ===");
        begin
            bit ok;
            bit [127:0] a;
            a = packet_utils::parse_ipv6("2001:0db8:0000:0000:0000:0000:0000:0001", ok);
            check_ok("full 8-group", ok, 1);
            check128("full 8-group", a, 128'h2001_0db8_0000_0000_0000_0000_0000_0001);

            a = packet_utils::parse_ipv6("2001:db8::1", ok);
            check_ok(":: compress", ok, 1);
            check128(":: compress", a, 128'h2001_0db8_0000_0000_0000_0000_0000_0001);

            a = packet_utils::parse_ipv6("::1", ok);
            check_ok("::1", ok, 1);
            check128("::1", a, 128'h1);

            a = packet_utils::parse_ipv6("::", ok);
            check_ok("::", ok, 1);
            check128("::", a, 128'h0);

            a = packet_utils::parse_ipv6("fe80::abcd", ok);
            check_ok("fe80::abcd", ok, 1);
            check128("fe80::abcd", a, 128'hfe80_0000_0000_0000_0000_0000_0000_abcd);

            a = packet_utils::parse_ipv6("0x00112233445566778899aabbccddeeff", ok);
            check_ok("pure hex 0x", ok, 1);
            check128("pure hex 0x", a, 128'h00112233445566778899aabbccddeeff);

            // 非法: 多个 ::
            a = packet_utils::parse_ipv6("2001::db8::1", ok);
            check_ok("invalid double ::", ok, 0);
            // 非法: 组超 4 hex
            a = packet_utils::parse_ipv6("12345::1", ok);
            check_ok("invalid 5-digit group", ok, 0);
            // 非法: 非 :: 但组数不足 8
            a = packet_utils::parse_ipv6("2001:db8:1", ok);
            check_ok("invalid short no-::", ok, 0);
        end

        // ============================================================
        // B. IPv6 header — 128bit 地址 load_params (Bug 主修)
        // ============================================================
        $display("\n=== B: ipv6_header 128bit load_params ===");
        begin
            ipv6_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("ip6.src_addr", "2001:db8::dead:beef");
            aip_cmdline_override::set_val("ip6.dst_addr", "0xfe800000000000000000000000000001");
            aip_cmdline_override::set_val("ip6.hop_limit", "64");
            aip_cmdline_override::set_val("ip6.flow_label", "0xfffff");
            h.load_params("ip6");
            check128("ipv6.src_addr", h.src_addr, 128'h2001_0db8_0000_0000_0000_0000_dead_beef);
            check128("ipv6.dst_addr", h.dst_addr, 128'hfe80_0000_0000_0000_0000_0000_0000_0001);
            check("ipv6.hop_limit", h.hop_limit, 64);
            check("ipv6.flow_label(20bit full)", h.flow_label, 20'hfffff);
        end

        // ============================================================
        // C. 48bit 满宽 — eth MAC, iwarp msg_offset
        // ============================================================
        $display("\n=== C: 48bit full-width ===");
        begin
            eth_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("e.dst_mac", "0xFFFFFFFFFFFF");
            aip_cmdline_override::set_val("e.src_mac", "0xA1B2C3D4E5F6");
            h.load_params("e");
            check("eth.dst_mac(48bit max)", h.dst_mac, 48'hFFFFFFFFFFFF);
            check("eth.src_mac(48bit)",     h.src_mac, 48'hA1B2C3D4E5F6);
        end
        begin
            iwarp_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("iw.msg_offset", "0x1122334455");
            aip_cmdline_override::set_val("iw.msn", "0xdeadbeef");
            h.load_params("iw");
            check("iwarp.msg_offset(48bit)", h.msg_offset, 48'h1122334455);
            check("iwarp.msn(32bit)",        h.msn, 32'hdeadbeef);
        end

        // ============================================================
        // D. 64bit 满宽 — iscsi lun, ptp, rocev2
        // ============================================================
        $display("\n=== D: 64bit full-width ===");
        begin
            iscsi_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("sc.lun", "0xFFFFFFFFFFFFFFFF");
            aip_cmdline_override::set_val("sc.initiator_task_tag", "0x12345678");
            h.load_params("sc");
            check("iscsi.lun(64bit max)", h.lun, 64'hFFFFFFFFFFFFFFFF);
            check("iscsi.init_task_tag",  h.initiator_task_tag, 32'h12345678);
        end
        begin
            ptp_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("pt.correction_field", "0x1122334455667788");
            aip_cmdline_override::set_val("pt.clock_identity",   "0x00aabbfffe112233");
            aip_cmdline_override::set_val("pt.domain_number",    "7");
            h.load_params("pt");
            check("ptp.correction_field(64)", h.correction_field, 64'h1122334455667788);
            check("ptp.clock_identity(64)",   h.clock_identity,   64'h00aabbfffe112233);
            check("ptp.domain_number",        h.domain_number, 7);
        end
        begin
            rocev2_bth h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("rc.reth_va",         "0xCAFEBABEDEADBEEF");
            aip_cmdline_override::set_val("rc.atomic_swap_add", "0xFFFFFFFF00000000");
            aip_cmdline_override::set_val("rc.dest_qp",         "0xABCDEF");
            aip_cmdline_override::set_val("rc.opcode",          "0x0A");
            h.load_params("rc");
            check("rocev2.reth_va(64)",        h.reth_va, 64'hCAFEBABEDEADBEEF);
            check("rocev2.atomic_swap_add(64)",h.atomic_swap_add, 64'hFFFFFFFF00000000);
            check("rocev2.dest_qp(24)",        h.dest_qp, 24'hABCDEF);
            check("rocev2.opcode(enum)",       h.opcode, 8'h0A);
        end

        // ============================================================
        // E. 新增 header load_params 触发 (每个取代表字段)
        // ============================================================
        $display("\n=== E: new headers wired ===");
        begin
            arp_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("a.opcode", "2");
            aip_cmdline_override::set_val("a.sender_mac", "0x001122334455");
            aip_cmdline_override::set_val("a.target_ip", "0xC0A80101");
            h.load_params("a");
            check("arp.opcode", h.opcode, 2);
            check("arp.sender_mac(48)", h.sender_mac, 48'h001122334455);
            check("arp.target_ip", h.target_ip, 32'hC0A80101);
        end
        begin
            sctp_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("s.verification_tag", "0xABCD1234");
            h.load_params("s");
            check("sctp.verification_tag", h.verification_tag, 32'hABCD1234);
        end
        begin
            esp_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("es.spi", "0x10000001");
            h.load_params("es");
            check("esp.spi", h.spi, 32'h10000001);
        end
        begin
            gtp_u_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("g.teid", "0xDEADC0DE");
            aip_cmdline_override::set_val("g.message_type", "0xFF");
            h.load_params("g");
            check("gtp.teid", h.teid, 32'hDEADC0DE);
            check("gtp.message_type", h.message_type, 8'hFF);
        end
        begin
            vxlan_gpe_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("vg.vni", "0xABCDEF");
            aip_cmdline_override::set_val("vg.next_protocol", "3");
            h.load_params("vg");
            check("vxlan_gpe.vni(24)", h.vni, 24'hABCDEF);
            check("vxlan_gpe.next_protocol", h.next_protocol, 3);
        end
        begin
            nvme_tcp_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("nv.pdu_type", "0x05");
            aip_cmdline_override::set_val("nv.hlen", "0x18");
            h.load_params("nv");
            check("nvme_tcp.pdu_type", h.pdu_type, 8'h05);
            check("nvme_tcp.hlen", h.hlen, 8'h18);
        end
        begin
            ipv6_routing_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("rt.routing_type", "4");
            aip_cmdline_override::set_val("rt.segments_left", "3");
            h.load_params("rt");
            check("ipv6_routing.routing_type", h.routing_type, 4);
            check("ipv6_routing.segments_left", h.segments_left, 3);
        end
        begin
            ipv6_fragment_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("fr.fragment_offset", "0x1FFF");
            aip_cmdline_override::set_val("fr.identification", "0x99887766");
            h.load_params("fr");
            check("ipv6_frag.fragment_offset(13)", h.fragment_offset, 13'h1FFF);
            check("ipv6_frag.identification", h.identification, 32'h99887766);
        end
        begin
            erspan_iii_header h = new();
            aip_cmdline_override::clear_all();
            aip_cmdline_override::set_val("er.session_id", "0x3FF");
            aip_cmdline_override::set_val("er.timestamp", "0x55667788");
            aip_cmdline_override::set_val("er.gra", "2");
            h.load_params("er");
            check("erspan3.session_id(10)", h.session_id, 10'h3FF);
            check("erspan3.timestamp", h.timestamp, 32'h55667788);
            check("erspan3.gra", h.gra, 2);
        end

        aip_cmdline_override::clear_all();

        // ============================================================
        // Summary
        // ============================================================
        $display("\n==========================================");
        $display("  PASS: %0d", pass_cnt);
        $display("  FAIL: %0d", fail_cnt);
        if (fail_cnt == 0) $display("  ALL WIDE-FIELD TESTS PASSED");
        else               $display("  SOME TESTS FAILED");
        $display("==========================================");
        $finish;
    end

endmodule

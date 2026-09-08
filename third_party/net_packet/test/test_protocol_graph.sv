`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "core/protocol_graph.sv"
`include "core/template_registry.sv"

program test_protocol_graph;
    int pass_count = 0;
    int fail_count = 0;

    function automatic bit has_proto(protocol_type_e q[$], protocol_type_e p);
        foreach (q[i]) if (q[i] == p) return 1;
        return 0;
    endfunction

    task automatic check(string name, bit condition);
        if (condition) begin $display("[PASS] %s", name); pass_count++; end
        else begin $display("[FAIL] %s", name); fail_count++; end
    endtask

    initial begin
        protocol_graph g = new();
        template_registry reg_inst = new();
        protocol_type_e result[$], chain[$];

        $display("=== test_protocol_graph ===");

        // Graph tests
        check("graph: eth->ipv4 valid", g.is_valid_next(PROTO_ETHERNET, PROTO_IPV4));
        check("graph: eth->ipv6 valid", g.is_valid_next(PROTO_ETHERNET, PROTO_IPV6));
        check("graph: eth->tcp invalid", !g.is_valid_next(PROTO_ETHERNET, PROTO_TCP));
        check("graph: ipv4->tcp valid", g.is_valid_next(PROTO_IPV4, PROTO_TCP));
        check("graph: ipv4->udp valid", g.is_valid_next(PROTO_IPV4, PROTO_UDP));
        check("graph: udp->vxlan valid", g.is_valid_next(PROTO_UDP, PROTO_VXLAN));
        check("graph: vxlan->eth valid", g.is_valid_next(PROTO_VXLAN, PROTO_ETHERNET));
        check("graph: vxlan->tcp invalid", !g.is_valid_next(PROTO_VXLAN, PROTO_TCP));

        g.get_valid_next(PROTO_IPV4, result);
        check("graph: ipv4 has TCP", has_proto(result, PROTO_TCP));
        check("graph: ipv4 has UDP", has_proto(result, PROTO_UDP));
        check("graph: ipv4 has GRE", has_proto(result, PROTO_GRE));

        check("graph: validate ETH/IP/TCP", g.validate_chain('{PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP}));
        check("graph: validate VXLAN chain", g.validate_chain('{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_VXLAN, PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP}));
        check("graph: validate ETH/TCP invalid", !g.validate_chain('{PROTO_ETHERNET, PROTO_TCP}));
        check("graph: validate single ETH", g.validate_chain('{PROTO_ETHERNET}));
        check("graph: vlan->vlan valid", g.is_valid_next(PROTO_VLAN, PROTO_VLAN));
        check("graph: ipv6->hbh valid", g.is_valid_next(PROTO_IPV6, PROTO_IPV6_HBH));
        check("graph: hbh->tcp valid", g.is_valid_next(PROTO_IPV6_HBH, PROTO_TCP));

        // Template tests
        reg_inst.get_chain(ETH_IPV4_TCP, chain);
        check("tmpl: ETH_IPV4_TCP len", chain.size() == 3);
        check("tmpl: ETH_IPV4_TCP[0]", chain[0] == PROTO_ETHERNET);
        check("tmpl: ETH_IPV4_TCP[2]", chain[2] == PROTO_TCP);

        reg_inst.get_chain(ETH_ARP, chain);
        check("tmpl: ETH_ARP len", chain.size() == 2);
        check("tmpl: ETH_ARP[1]", chain[1] == PROTO_ARP);

        reg_inst.get_chain(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, chain);
        check("tmpl: VXLAN len", chain.size() == 7);
        check("tmpl: VXLAN[3]", chain[3] == PROTO_VXLAN);
        check("tmpl: VXLAN[4]", chain[4] == PROTO_ETHERNET);

        reg_inst.get_chain(ETH_VLAN_IPV4_TCP, chain);
        check("tmpl: VLAN len", chain.size() == 4);
        check("tmpl: VLAN[1]", chain[1] == PROTO_VLAN);

        // Validate ALL templates against graph
        begin
            bit all_valid = 1;
            protocol_type_e tmpl_chain[$];
            packet_template_e t = t.first();
            do begin
                reg_inst.get_chain(t, tmpl_chain);
                if (tmpl_chain.size() > 0 && !g.validate_chain(tmpl_chain)) begin
                    $display("[FAIL] template %s fails graph validation", t.name());
                    all_valid = 0;
                end
                t = t.next();
            end while (t != t.first());
            check("tmpl: all templates valid in graph", all_valid);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end
endprogram

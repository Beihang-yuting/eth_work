// test/test_rdma_storage_packet.sv
`include "core/packet.sv"

program test_rdma_storage_packet;

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
        $display("=== test_rdma_storage_packet ===");

        // ---- RoCEv2 Send Only template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_ROCEV2);
            check("rocev2_send: layer count", pkt.layer_stack.size() == 4);
            check("rocev2_send: layer[3] RoCEv2", pkt.layer_stack[3].proto_type == PROTO_ROCEV2);

            // Default is Send Only (0x04)
            pkt.pkt_len = 100;
            pkt.do_pack();
            check("rocev2_send: raw_data size", pkt.raw_data.size() == 100);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("rocev2_send: unpack layer count", pkt2.layer_stack.size() == 4);
                check("rocev2_send: unpack RoCEv2", pkt2.layer_stack[3].proto_type == PROTO_ROCEV2);
            end
        end

        // ---- RoCEv2 RDMA Write (opcode 0x0A, BTH+RETH) ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_ROCEV2);

            begin
                rocev2_bth bth;
                $cast(bth, pkt.get_layer(PROTO_ROCEV2));
                bth.opcode       = 8'h0A;  // Write Only
                bth.dest_qp      = 24'h000100;
                bth.psn           = 24'h000001;
                bth.reth_va       = 64'hDEAD_BEEF_0000_0000;
                bth.reth_r_key    = 32'h12340000;
                bth.reth_dma_len  = 32'd512;
                bth.icrc_enable   = 0;  // Disable ICRC for simpler size check
            end

            pkt.pkt_len = 120;
            pkt.do_pack();
            check("rocev2_write: raw_data size", pkt.raw_data.size() == 120);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("rocev2_write: unpack layer count", pkt2.layer_stack.size() == 4);
                begin
                    rocev2_bth bth2;
                    $cast(bth2, pkt2.get_layer(PROTO_ROCEV2));
                    check("rocev2_write: unpack opcode", bth2.opcode == 8'h0A);
                    check("rocev2_write: unpack reth_r_key", bth2.reth_r_key == 32'h12340000);
                    check("rocev2_write: unpack reth_dma_len", bth2.reth_dma_len == 32'd512);
                end
            end
        end

        // ---- RoCEv2 ACK (opcode 0x11, BTH+AETH) ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_ROCEV2);

            begin
                rocev2_bth bth;
                $cast(bth, pkt.get_layer(PROTO_ROCEV2));
                bth.opcode        = 8'h11;
                bth.dest_qp       = 24'h000200;
                bth.aeth_syndrome  = 8'h00;
                bth.aeth_msn       = 24'h000010;
                bth.icrc_enable    = 0;
            end

            pkt.pkt_len = 80;
            pkt.do_pack();
            check("rocev2_ack: raw_data size", pkt.raw_data.size() == 80);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                begin
                    rocev2_bth bth2;
                    $cast(bth2, pkt2.get_layer(PROTO_ROCEV2));
                    check("rocev2_ack: unpack opcode", bth2.opcode == 8'h11);
                    check("rocev2_ack: unpack syndrome", bth2.aeth_syndrome == 8'h00);
                    check("rocev2_ack: unpack msn", bth2.aeth_msn == 24'h000010);
                end
            end
        end

        // ---- VLAN + RoCEv2 template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_VLAN_IPV4_UDP_ROCEV2);
            check("vlan_rocev2: layer count", pkt.layer_stack.size() == 5);
            check("vlan_rocev2: layer[1] VLAN", pkt.layer_stack[1].proto_type == PROTO_VLAN);
            check("vlan_rocev2: layer[4] RoCEv2", pkt.layer_stack[4].proto_type == PROTO_ROCEV2);
        end

        // ---- NVMe-TCP template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_TCP_NVME_TCP);
            check("nvme_tcp: layer count", pkt.layer_stack.size() == 4);
            check("nvme_tcp: layer[3] NVMe-TCP", pkt.layer_stack[3].proto_type == PROTO_NVME_TCP);

            begin
                nvme_tcp_header nvme;
                $cast(nvme, pkt.get_layer(PROTO_NVME_TCP));
                nvme.pdu_type = 8'h04;
            end

            pkt.pkt_len = 100;
            pkt.do_pack();
            check("nvme_tcp: raw_data size", pkt.raw_data.size() == 100);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("nvme_tcp: unpack layer count", pkt2.layer_stack.size() == 4);
                begin
                    nvme_tcp_header nvme2;
                    $cast(nvme2, pkt2.get_layer(PROTO_NVME_TCP));
                    check("nvme_tcp: unpack pdu_type", nvme2.pdu_type == 8'h04);
                end
            end
        end

        // ---- iSCSI template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_TCP_ISCSI);
            check("iscsi: layer count", pkt.layer_stack.size() == 4);
            check("iscsi: layer[3] iSCSI", pkt.layer_stack[3].proto_type == PROTO_ISCSI);

            begin
                iscsi_header iscsi;
                $cast(iscsi, pkt.get_layer(PROTO_ISCSI));
                iscsi.initiator_task_tag = 32'hDEADBEEF;
            end

            pkt.pkt_len = 110;
            pkt.do_pack();
            check("iscsi: raw_data size", pkt.raw_data.size() == 110);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("iscsi: unpack layer count", pkt2.layer_stack.size() == 4);
                begin
                    iscsi_header iscsi2;
                    $cast(iscsi2, pkt2.get_layer(PROTO_ISCSI));
                    check("iscsi: unpack itt", iscsi2.initiator_task_tag == 32'hDEADBEEF);
                end
            end
        end

        // ---- iWARP template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_TCP_IWARP);
            check("iwarp: layer count", pkt.layer_stack.size() == 4);
            check("iwarp: layer[3] iWARP", pkt.layer_stack[3].proto_type == PROTO_IWARP);

            begin
                iwarp_header iw;
                $cast(iw, pkt.get_layer(PROTO_IWARP));
                iw.rdmap_opcode = 4'h1;
                iw.sink_stag = 32'h12345678;
            end

            pkt.pkt_len = 110;
            pkt.do_pack();
            check("iwarp: raw_data size", pkt.raw_data.size() == 110);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("iwarp: unpack layer count", pkt2.layer_stack.size() == 4);
                begin
                    iwarp_header iw2;
                    if ($cast(iw2, pkt2.get_layer(PROTO_IWARP)) && iw2 != null) begin
                        check("iwarp: unpack opcode", iw2.rdmap_opcode == 4'h1);
                        check("iwarp: unpack stag", iw2.sink_stag == 32'h12345678);
                    end else begin
                        check("iwarp: unpack opcode", 0);
                        check("iwarp: unpack stag", 0);
                    end
                end
            end
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

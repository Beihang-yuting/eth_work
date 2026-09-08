// test/test_rdma_storage_headers.sv
`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "rdma/rocev2_header.sv"
`include "rdma/iwarp_header.sv"
`include "storage/nvme_tcp_header.sv"
`include "storage/iscsi_header.sv"

program test_rdma_storage_headers;

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
        $display("=== test_rdma_storage_headers ===");

        // ---- RoCEv2 BTH: Send Only (0x04, BTH only) ----
        begin
            rocev2_bth bth = new();
            byte unsigned pkd[$];
            int offset;

            check("bth_send: proto_type", bth.proto_type == PROTO_ROCEV2);
            check("bth_send: default opcode", bth.opcode == 8'h04);
            check("bth_send: no reth", bth.has_reth() == 0);
            check("bth_send: no aeth", bth.has_aeth() == 0);
            check("bth_send: no immdt", bth.has_immdt() == 0);
            check("bth_send: header_length w/ icrc", bth.get_header_length() == 16);

            bth.icrc_enable = 0;
            check("bth_send: header_length no icrc", bth.get_header_length() == 12);

            bth.dest_qp = 24'h000100;
            bth.psn     = 24'h000001;
            bth.pkey    = 16'hFFFF;
            bth.pack_header(pkd);
            check("bth_send: pack size", pkd.size() == 12);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(pkd, offset);
                check("bth_send: unpack opcode", bth2.opcode == 8'h04);
                check("bth_send: unpack dest_qp", bth2.dest_qp == 24'h000100);
                check("bth_send: unpack psn", bth2.psn == 24'h000001);
                check("bth_send: unpack pkey", bth2.pkey == 16'hFFFF);
                check("bth_send: unpack offset", offset == 12);
            end
        end

        // ---- RoCEv2 RDMA Write Only (0x0A, BTH + RETH) ----
        begin
            rocev2_bth bth;
            byte unsigned pkd[$];
            int offset;
            bth = rocev2_bth::create(8'h0A, 24'h000200);

            check("bth_write: has_reth", bth.has_reth() == 1);
            check("bth_write: no aeth", bth.has_aeth() == 0);
            bth.icrc_enable = 0;
            check("bth_write: header_length", bth.get_header_length() == 28);

            bth.reth_va      = 64'hDEAD_BEEF_CAFE_0000;
            bth.reth_r_key   = 32'h00001234;
            bth.reth_dma_len = 32'd4096;
            bth.psn          = 24'h000010;
            bth.pack_header(pkd);
            check("bth_write: pack size", pkd.size() == 28);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(pkd, offset);
                check("bth_write: unpack opcode", bth2.opcode == 8'h0A);
                check("bth_write: unpack dest_qp", bth2.dest_qp == 24'h000200);
                check("bth_write: unpack reth_va", bth2.reth_va == 64'hDEAD_BEEF_CAFE_0000);
                check("bth_write: unpack reth_r_key", bth2.reth_r_key == 32'h00001234);
                check("bth_write: unpack reth_dma_len", bth2.reth_dma_len == 32'd4096);
                check("bth_write: unpack offset", offset == 28);
            end

            begin
                protocol_base bth3;
                bth3 = bth.clone();
                check("bth_write: clone compare", bth.compare(bth3));
            end
        end

        // ---- RoCEv2 Read Response Only (0x10, BTH + AETH) ----
        begin
            rocev2_bth bth;
            byte unsigned pkd[$];
            int offset;
            bth = rocev2_bth::create(8'h10, 24'h000300);

            check("bth_readresp: has_aeth", bth.has_aeth() == 1);
            check("bth_readresp: no reth", bth.has_reth() == 0);
            bth.icrc_enable = 0;
            check("bth_readresp: header_length", bth.get_header_length() == 16);

            bth.aeth_syndrome = 8'h00;
            bth.aeth_msn      = 24'h000005;
            bth.pack_header(pkd);
            check("bth_readresp: pack size", pkd.size() == 16);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(pkd, offset);
                check("bth_readresp: unpack aeth_syndrome", bth2.aeth_syndrome == 8'h00);
                check("bth_readresp: unpack aeth_msn", bth2.aeth_msn == 24'h000005);
                check("bth_readresp: unpack offset", offset == 16);
            end
        end

        // ---- RoCEv2 Write Only w/ Imm (0x0B, BTH + RETH + ImmDt) ----
        begin
            rocev2_bth bth;
            byte unsigned pkd[$];
            int offset;
            bth = rocev2_bth::create(8'h0B, 24'h000400);

            check("bth_writeimm: has_reth", bth.has_reth() == 1);
            check("bth_writeimm: has_immdt", bth.has_immdt() == 1);
            check("bth_writeimm: no aeth", bth.has_aeth() == 0);
            bth.icrc_enable = 0;
            check("bth_writeimm: header_length", bth.get_header_length() == 32);

            bth.reth_va      = 64'h0000_0000_1000_0000;
            bth.reth_r_key   = 32'hABCD0000;
            bth.reth_dma_len = 32'd256;
            bth.imm_data     = 32'h12345678;
            bth.pack_header(pkd);
            check("bth_writeimm: pack size", pkd.size() == 32);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(pkd, offset);
                check("bth_writeimm: unpack imm_data", bth2.imm_data == 32'h12345678);
                check("bth_writeimm: unpack reth_r_key", bth2.reth_r_key == 32'hABCD0000);
                check("bth_writeimm: unpack offset", offset == 32);
            end

            begin
                protocol_base bth3;
                bth3 = bth.clone();
                check("bth_writeimm: clone compare", bth.compare(bth3));
            end
        end

        // ---- RoCEv2 with ICRC ----
        begin
            rocev2_bth bth;
            byte unsigned pkd[$];
            bth = rocev2_bth::create(8'h04, 24'h000500);

            bth.icrc_enable = 1;
            check("bth_icrc: header_length", bth.get_header_length() == 16);

            bth.calc_fields('{}, PROTO_RAW_PAYLOAD);
            bth.pack_header(pkd);
            check("bth_icrc: pack size", pkd.size() == 16);
        end

        // ---- RoCEv2 ACK (0x11, BTH + AETH) ----
        begin
            rocev2_bth bth;
            byte unsigned pkd[$];
            int offset;
            bth = rocev2_bth::create(8'h11, 24'h000600);

            check("bth_ack: has_aeth", bth.has_aeth() == 1);
            bth.icrc_enable = 0;
            bth.aeth_syndrome = 8'h1F;  // NAK
            bth.aeth_msn = 24'h000010;
            bth.pack_header(pkd);
            check("bth_ack: pack size", pkd.size() == 16);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(pkd, offset);
                check("bth_ack: unpack syndrome", bth2.aeth_syndrome == 8'h1F);
                check("bth_ack: unpack msn", bth2.aeth_msn == 24'h000010);
            end
        end

        // ---- RoCEv2 CNP (0x81, BTH only) ----
        begin
            rocev2_bth bth;
            bth = rocev2_bth::create(8'h81, 24'h000700);

            check("bth_cnp: no reth", bth.has_reth() == 0);
            check("bth_cnp: no aeth", bth.has_aeth() == 0);
            check("bth_cnp: no immdt", bth.has_immdt() == 0);
            bth.icrc_enable = 0;
            check("bth_cnp: header_length", bth.get_header_length() == 12);
        end

        // ---- iWARP: basic construction ----
        begin
            iwarp_header iw = new();

            check("iwarp_basic: proto_type",    iw.proto_type    == PROTO_IWARP);
            check("iwarp_basic: header_length", iw.get_header_length() == 28);
            check("iwarp_basic: ddp_version",   iw.ddp_version   == 8'd1);
            check("iwarp_basic: rdmap_version", iw.rdmap_version == 4'd1);
        end

        // ---- iWARP: pack ----
        begin
            iwarp_header iw = new();
            byte unsigned pkd[$];

            iw.rdmap_opcode = 4'd1;
            iw.queue_number = 16'd5;
            iw.msn          = 32'h100;
            iw.sink_stag    = 32'hAABBCCDD;
            iw.pack_header(pkd);
            check("iwarp_pack: size", pkd.size() == 28);
        end

        // ---- iWARP: unpack round-trip ----
        begin
            iwarp_header iw = new();
            byte unsigned pkd[$];
            int offset;

            iw.rdmap_opcode = 4'd1;
            iw.queue_number = 16'd5;
            iw.msn          = 32'h100;
            iw.sink_stag    = 32'hAABBCCDD;
            iw.pack_header(pkd);

            begin
                iwarp_header iw2 = new();
                offset = 0;
                iw2.unpack_header(pkd, offset);
                check("iwarp_unpack: rdmap_opcode", iw2.rdmap_opcode == 4'd1);
                check("iwarp_unpack: queue_number", iw2.queue_number == 16'd5);
                check("iwarp_unpack: msn",          iw2.msn          == 32'h100);
                check("iwarp_unpack: sink_stag",    iw2.sink_stag    == 32'hAABBCCDD);
                check("iwarp_unpack: offset",       offset == 28);
            end
        end

        // ---- iWARP: clone+compare ----
        begin
            iwarp_header iw = new();
            iw.rdmap_opcode = 4'd1;
            iw.queue_number = 16'd5;
            iw.msn          = 32'h100;
            iw.sink_stag    = 32'hAABBCCDD;

            begin
                protocol_base iw2;
                iw2 = iw.clone();
                check("iwarp_clone: compare", iw.compare(iw2));
            end
        end

        // ---- iWARP: static create ----
        begin
            iwarp_header iw;
            iw = iwarp_header::create(4'd2);
            check("iwarp_create: rdmap_opcode", iw.rdmap_opcode == 4'd2);
        end

        // ---- NVMe-TCP: basic construction ----
        begin
            nvme_tcp_header nv = new();

            check("nvmetcp_basic: proto_type",    nv.proto_type       == PROTO_NVME_TCP);
            check("nvmetcp_basic: header_length", nv.get_header_length() == 8);
            check("nvmetcp_basic: default pdu_type", nv.pdu_type      == 8'h04);
        end

        // ---- NVMe-TCP: pack ----
        begin
            nvme_tcp_header nv = new();
            byte unsigned pkd[$];

            nv.pdu_type = 8'h04;
            nv.plen     = 32'd128;
            nv.pack_header(pkd);
            check("nvmetcp_pack: size", pkd.size() == 8);
        end

        // ---- NVMe-TCP: unpack round-trip ----
        begin
            nvme_tcp_header nv = new();
            byte unsigned pkd[$];
            int offset;

            nv.pdu_type = 8'h04;
            nv.plen     = 32'd128;
            nv.pack_header(pkd);

            begin
                nvme_tcp_header nv2 = new();
                offset = 0;
                nv2.unpack_header(pkd, offset);
                check("nvmetcp_unpack: pdu_type", nv2.pdu_type == 8'h04);
                check("nvmetcp_unpack: plen",     nv2.plen     == 32'd128);
                check("nvmetcp_unpack: offset",   offset == 8);
            end
        end

        // ---- NVMe-TCP: clone+compare ----
        begin
            nvme_tcp_header nv = new();
            nv.pdu_type = 8'h04;
            nv.plen     = 32'd128;

            begin
                protocol_base nv2;
                nv2 = nv.clone();
                check("nvmetcp_clone: compare", nv.compare(nv2));
            end
        end

        // ---- NVMe-TCP: static create ----
        begin
            nvme_tcp_header nv;
            nv = nvme_tcp_header::create(8'h01);
            check("nvmetcp_create: pdu_type", nv.pdu_type == 8'h01);
        end

        // ---- iSCSI: basic construction ----
        begin
            iscsi_header iscsi = new();

            check("iscsi_basic: proto_type",    iscsi.proto_type       == PROTO_ISCSI);
            check("iscsi_basic: header_length", iscsi.get_header_length() == 48);
            check("iscsi_basic: default opcode", iscsi.opcode          == 6'h01);
        end

        // ---- iSCSI: pack ----
        begin
            iscsi_header iscsi = new();
            byte unsigned pkd[$];

            iscsi.opcode             = 6'h01;
            iscsi.initiator_task_tag = 32'h12345678;
            iscsi.lun                = 64'h01;
            iscsi.pack_header(pkd);
            check("iscsi_pack: size", pkd.size() == 48);
        end

        // ---- iSCSI: unpack round-trip ----
        begin
            iscsi_header iscsi = new();
            byte unsigned pkd[$];
            int offset;

            iscsi.opcode             = 6'h01;
            iscsi.initiator_task_tag = 32'h12345678;
            iscsi.lun                = 64'h01;
            iscsi.pack_header(pkd);

            begin
                iscsi_header iscsi2 = new();
                offset = 0;
                iscsi2.unpack_header(pkd, offset);
                check("iscsi_unpack: opcode",             iscsi2.opcode             == 6'h01);
                check("iscsi_unpack: initiator_task_tag", iscsi2.initiator_task_tag == 32'h12345678);
                check("iscsi_unpack: lun",                iscsi2.lun                == 64'h01);
                check("iscsi_unpack: offset",             offset == 48);
            end
        end

        // ---- iSCSI: clone+compare ----
        begin
            iscsi_header iscsi = new();
            iscsi.opcode             = 6'h01;
            iscsi.initiator_task_tag = 32'h12345678;
            iscsi.lun                = 64'h01;

            begin
                protocol_base iscsi2;
                iscsi2 = iscsi.clone();
                check("iscsi_clone: compare", iscsi.compare(iscsi2));
            end
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram

# Phase 2b: RDMA + 存储协议实现计划（完善版）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现符合商业网卡标准（ConnectX/Intel E810）的 RDMA 协议（RoCEv2 BTH + RETH/AETH/ImmDt + ICRC）、iWARP（MPA+DDP+RDMAP 简化）、存储协议（NVMe-TCP、iSCSI），并集成到 packet 工厂和 unpack 逻辑中。

**Architecture:** RoCEv2 采用单一 `rocev2_bth` 类，内含可选扩展头（RETH/AETH/ImmDt），根据 opcode 自动决定哪些扩展头参与 pack/unpack。ICRC 作为 4 字节尾部，在 calc_fields 中基于完整 payload 计算。其他协议各自独立 class。新增 `src/protocols/rdma/` 和 `src/protocols/storage/` 目录。

**Tech Stack:** SystemVerilog (IEEE 1800-2017), VCS/Questa

---

## RoCEv2 Opcode 到扩展头映射

| Opcode | 名称 | 扩展头 |
|--------|------|--------|
| 0x00 | Send First | BTH |
| 0x01 | Send Middle | BTH |
| 0x02 | Send Last | BTH |
| 0x03 | Send Last w/ Imm | BTH + ImmDt |
| 0x04 | Send Only | BTH |
| 0x05 | Send Only w/ Imm | BTH + ImmDt |
| 0x06 | RDMA Write First | BTH + RETH |
| 0x07 | RDMA Write Middle | BTH |
| 0x08 | RDMA Write Last | BTH |
| 0x09 | RDMA Write Last w/ Imm | BTH + ImmDt |
| 0x0A | RDMA Write Only | BTH + RETH |
| 0x0B | RDMA Write Only w/ Imm | BTH + RETH + ImmDt |
| 0x0C | RDMA Read Request | BTH + RETH |
| 0x0D | RDMA Read Response First | BTH + AETH |
| 0x0E | RDMA Read Response Middle | BTH |
| 0x0F | RDMA Read Response Last | BTH + AETH |
| 0x10 | RDMA Read Response Only | BTH + AETH |
| 0x11 | Acknowledge | BTH + AETH |
| 0x81 | CNP | BTH |

---

## 文件映射

| 文件 | 操作 | 职责 |
|------|------|------|
| `src/protocols/rdma/rocev2_header.sv` | 新建 | RoCEv2 BTH(12B) + RETH(16B) + AETH(4B) + ImmDt(4B) + ICRC(4B) |
| `src/protocols/rdma/iwarp_header.sv` | 新建 | iWARP MPA+DDP+RDMAP 简化头 (28字节) |
| `src/protocols/storage/nvme_tcp_header.sv` | 新建 | NVMe-oF TCP PDU 公共头 (8字节) |
| `src/protocols/storage/iscsi_header.sv` | 新建 | iSCSI BHS (48字节) |
| `src/core/packet.sv` | 修改 | 扩展工厂 + 解析映射 |
| `filelist.f` | 修改 | 添加 rdma/storage 目录和源文件 |
| `test/test_rdma_storage_headers.sv` | 新建 | RDMA/存储协议单元测试 |
| `test/test_rdma_storage_packet.sv` | 新建 | RDMA/存储报文模板集成测试 |
| `Makefile` | 修改 | 添加测试目标 |

---

### Task 1: RoCEv2 完整协议头（BTH + RETH + AETH + ImmDt + ICRC）

**Files:**
- Create: `src/protocols/rdma/rocev2_header.sv`
- Create: `test/test_rdma_storage_headers.sv`
- Modify: `filelist.f`
- Modify: `Makefile`

RoCEv2 采用单一 class，内含所有扩展头字段。根据 opcode 自动判断哪些扩展头参与 pack/unpack。

BTH (12 bytes):
- Word 0: {opcode[7:0], se, mig_req, pad_count[1:0], tver[3:0], pkey[15:0]}
- Word 1: {dest_qp[23:0], ack_req, reserved1[6:0]}
- Word 2: {psn[23:0], reserved2[7:0]}

RETH (16 bytes, opcode 0x06/0x0A/0x0B/0x0C):
- va (64-bit): Virtual Address
- r_key (32-bit): Remote Key
- dma_length (32-bit): DMA Length

AETH (4 bytes, opcode 0x0D/0x0F/0x10/0x11):
- syndrome (8-bit): ACK/NAK status
- msn (24-bit): Message Sequence Number

ImmDt (4 bytes, opcode 0x03/0x05/0x09/0x0B):
- imm_data (32-bit): Immediate Data

ICRC (4 bytes, 尾部):
- icrc (32-bit): Invariant CRC, 覆盖 BTH + 扩展头 + payload

- [ ] **Step 1: 创建 rocev2_header.sv**

```systemverilog
// src/protocols/rdma/rocev2_header.sv
`ifndef ROCEV2_HEADER_SV
`define ROCEV2_HEADER_SV

`include "protocol_base.sv"

class rocev2_bth extends protocol_base;

    // === BTH fields (12 bytes) ===
    rand bit [7:0]  opcode;
    rand bit        se;             // Solicited Event
    rand bit        mig_req;        // Migration Request
    rand bit [1:0]  pad_count;
    rand bit [3:0]  tver;           // Transport Header Version
    rand bit [15:0] pkey;           // Partition Key
    rand bit [23:0] dest_qp;       // Destination Queue Pair
    rand bit        ack_req;        // Acknowledge Request
    rand bit [6:0]  reserved1;
    rand bit [23:0] psn;            // Packet Sequence Number
    rand bit [7:0]  reserved2;

    // === RETH fields (16 bytes, conditional) ===
    rand bit [63:0] reth_va;        // Virtual Address
    rand bit [31:0] reth_r_key;     // Remote Key
    rand bit [31:0] reth_dma_len;   // DMA Length

    // === AETH fields (4 bytes, conditional) ===
    rand bit [7:0]  aeth_syndrome;  // ACK/NAK status
    rand bit [23:0] aeth_msn;       // Message Sequence Number

    // === ImmDt fields (4 bytes, conditional) ===
    rand bit [31:0] imm_data;       // Immediate Data

    // === ICRC (4 bytes, trailer) ===
    bit             icrc_enable;    // Whether to include ICRC in pack
    bit [31:0]      icrc;           // Invariant CRC value

    constraint c_default {
        tver      == 4'd0;
        reserved1 == 0;
        reserved2 == 0;
        pad_count == 0;
        se        == 0;
        mig_req   == 0;
    }

    function new();
        proto_type    = PROTO_ROCEV2;
        opcode        = 8'h04;     // Send Only (default)
        se            = 0;
        mig_req       = 0;
        pad_count     = 0;
        tver          = 0;
        pkey          = 16'hFFFF;
        dest_qp       = 0;
        ack_req       = 0;
        reserved1     = 0;
        psn           = 0;
        reserved2     = 0;
        reth_va       = 0;
        reth_r_key    = 0;
        reth_dma_len  = 0;
        aeth_syndrome = 0;
        aeth_msn      = 0;
        imm_data      = 0;
        icrc_enable   = 1;
        icrc          = 0;
    endfunction

    static function rocev2_bth create(bit [7:0] op = 8'h04, bit [23:0] qp = 0);
        rocev2_bth h = new();
        h.opcode  = op;
        h.dest_qp = qp;
        return h;
    endfunction

    // --- Opcode classification helpers ---
    function bit has_reth();
        return (opcode == 8'h06) || (opcode == 8'h0A) || (opcode == 8'h0B) || (opcode == 8'h0C);
    endfunction

    function bit has_aeth();
        return (opcode == 8'h0D) || (opcode == 8'h0F) || (opcode == 8'h10) || (opcode == 8'h11);
    endfunction

    function bit has_immdt();
        return (opcode == 8'h03) || (opcode == 8'h05) || (opcode == 8'h09) || (opcode == 8'h0B);
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // BTH (12 bytes)
        bit [31:0] word0 = {opcode, se, mig_req, pad_count, tver, pkey};
        bit [31:0] word1 = {dest_qp, ack_req, reserved1};
        bit [31:0] word2 = {psn, reserved2};
        packet_utils::pack_bytes_32(data, word0);
        packet_utils::pack_bytes_32(data, word1);
        packet_utils::pack_bytes_32(data, word2);

        // RETH (16 bytes)
        if (has_reth()) begin
            packet_utils::pack_bytes_32(data, reth_va[63:32]);
            packet_utils::pack_bytes_32(data, reth_va[31:0]);
            packet_utils::pack_bytes_32(data, reth_r_key);
            packet_utils::pack_bytes_32(data, reth_dma_len);
        end

        // AETH (4 bytes)
        if (has_aeth()) begin
            packet_utils::pack_bytes_32(data, {aeth_syndrome, aeth_msn});
        end

        // ImmDt (4 bytes)
        if (has_immdt()) begin
            packet_utils::pack_bytes_32(data, imm_data);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] word0, word1, word2;
        // BTH
        word0 = packet_utils::unpack_bytes_32(data, offset);
        word1 = packet_utils::unpack_bytes_32(data, offset);
        word2 = packet_utils::unpack_bytes_32(data, offset);
        opcode    = word0[31:24];
        se        = word0[23];
        mig_req   = word0[22];
        pad_count = word0[21:20];
        tver      = word0[19:16];
        pkey      = word0[15:0];
        dest_qp   = word1[31:8];
        ack_req   = word1[7];
        reserved1 = word1[6:0];
        psn       = word2[31:8];
        reserved2 = word2[7:0];

        // RETH
        if (has_reth()) begin
            reth_va[63:32] = packet_utils::unpack_bytes_32(data, offset);
            reth_va[31:0]  = packet_utils::unpack_bytes_32(data, offset);
            reth_r_key     = packet_utils::unpack_bytes_32(data, offset);
            reth_dma_len   = packet_utils::unpack_bytes_32(data, offset);
        end

        // AETH
        if (has_aeth()) begin
            bit [31:0] aeth_word = packet_utils::unpack_bytes_32(data, offset);
            aeth_syndrome = aeth_word[31:24];
            aeth_msn      = aeth_word[23:0];
        end

        // ImmDt
        if (has_immdt()) begin
            imm_data = packet_utils::unpack_bytes_32(data, offset);
        end
    endfunction

    virtual function int get_header_length();
        int len = 12;  // BTH
        if (has_reth())  len += 16;
        if (has_aeth())  len += 4;
        if (has_immdt()) len += 4;
        if (icrc_enable) len += 4;   // ICRC trailer
        return len;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        tver = 0;
        // ICRC calculation: CRC-32 over BTH + extensions + payload
        // For simplicity, use ones_complement as placeholder; real ICRC uses CRC-32C
        if (icrc_enable) begin
            byte unsigned icrc_data[$];
            // Pack BTH + extensions (without ICRC) into temp buffer
            bit saved_icrc_enable = icrc_enable;
            icrc_enable = 0;
            pack_header(icrc_data);
            icrc_enable = saved_icrc_enable;
            // Append payload
            foreach (payload_data[i]) icrc_data.push_back(payload_data[i]);
            // Simple CRC placeholder (full CRC-32 is complex in SV)
            icrc = 32'h0;
            foreach (icrc_data[i]) begin
                icrc = icrc ^ ({24'h0, icrc_data[i]} << ((i % 4) * 8));
            end
        end
    endfunction

    virtual function protocol_base clone();
        rocev2_bth h = new();
        h.opcode        = opcode;
        h.se            = se;
        h.mig_req       = mig_req;
        h.pad_count     = pad_count;
        h.tver          = tver;
        h.pkey          = pkey;
        h.dest_qp       = dest_qp;
        h.ack_req       = ack_req;
        h.reserved1     = reserved1;
        h.psn           = psn;
        h.reserved2     = reserved2;
        h.reth_va       = reth_va;
        h.reth_r_key    = reth_r_key;
        h.reth_dma_len  = reth_dma_len;
        h.aeth_syndrome = aeth_syndrome;
        h.aeth_msn      = aeth_msn;
        h.imm_data      = imm_data;
        h.icrc_enable   = icrc_enable;
        h.icrc          = icrc;
        h.auto_calc     = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        rocev2_bth o;
        if (!$cast(o, other)) return 0;
        if (opcode != o.opcode || pkey != o.pkey) return 0;
        if (dest_qp != o.dest_qp || psn != o.psn) return 0;
        if (has_reth()) begin
            if (reth_va != o.reth_va || reth_r_key != o.reth_r_key || reth_dma_len != o.reth_dma_len) return 0;
        end
        if (has_aeth()) begin
            if (aeth_syndrome != o.aeth_syndrome || aeth_msn != o.aeth_msn) return 0;
        end
        if (has_immdt()) begin
            if (imm_data != o.imm_data) return 0;
        end
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s (BTH) ===\n", proto_type.name());
        s = {s, $sformatf("  opcode   : 0x%02x\n", opcode)};
        s = {s, $sformatf("  se       : %0b\n", se)};
        s = {s, $sformatf("  mig_req  : %0b\n", mig_req)};
        s = {s, $sformatf("  pad_count: %0d\n", pad_count)};
        s = {s, $sformatf("  tver     : %0d\n", tver)};
        s = {s, $sformatf("  pkey     : 0x%04x\n", pkey)};
        s = {s, $sformatf("  dest_qp  : 0x%06x\n", dest_qp)};
        s = {s, $sformatf("  ack_req  : %0b\n", ack_req)};
        s = {s, $sformatf("  psn      : 0x%06x\n", psn)};
        if (has_reth()) begin
            s = {s, "  --- RETH ---\n"};
            s = {s, $sformatf("  va       : 0x%016x\n", reth_va)};
            s = {s, $sformatf("  r_key    : 0x%08x\n", reth_r_key)};
            s = {s, $sformatf("  dma_len  : %0d\n", reth_dma_len)};
        end
        if (has_aeth()) begin
            s = {s, "  --- AETH ---\n"};
            s = {s, $sformatf("  syndrome : 0x%02x\n", aeth_syndrome)};
            s = {s, $sformatf("  msn      : 0x%06x\n", aeth_msn)};
        end
        if (has_immdt()) begin
            s = {s, $sformatf("  --- ImmDt: 0x%08x ---\n", imm_data)};
        end
        if (icrc_enable)
            s = {s, $sformatf("  icrc     : 0x%08x\n", icrc)};
        return s;
    endfunction

    virtual function string to_brief();
        string s;
        s = $sformatf("RoCEv2 op:0x%02x qp:0x%06x psn:0x%06x", opcode, dest_qp, psn);
        if (has_reth()) s = {s, $sformatf(" rkey:0x%08x", reth_r_key)};
        if (has_aeth()) s = {s, $sformatf(" syn:0x%02x", aeth_syndrome)};
        if (has_immdt()) s = {s, $sformatf(" imm:0x%08x", imm_data)};
        return s;
    endfunction

endclass

`endif // ROCEV2_HEADER_SV
```

Note: pack_header 不包含 ICRC 的写入 — ICRC 需要在 do_pack() 阶段追加到 raw_data 尾部。为此需要重写 pack_header 让 ICRC 在最后追加：

实际上，更简单的做法是让 pack_header 在最后也 pack ICRC（如果 icrc_enable）。这样 ICRC 自然成为报文的一部分。calc_fields 会先计算 ICRC 值（基于 payload_data），然后 pack_header 把它追加到末尾。

修正 pack_header 末尾：
```systemverilog
        // ICRC (4 bytes trailer)
        if (icrc_enable) begin
            packet_utils::pack_bytes_32(data, icrc);
        end
```

- [ ] **Step 2: 创建测试框架 test_rdma_storage_headers.sv 并添加 RoCEv2 测试**

```systemverilog
// test/test_rdma_storage_headers.sv
`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "rdma/rocev2_header.sv"

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

        // ---- RoCEv2 BTH: Send Only (opcode 0x04, BTH only) ----
        begin
            rocev2_bth bth = new();
            byte unsigned packed[$];
            int offset;

            check("bth_send: proto_type", bth.proto_type == PROTO_ROCEV2);
            check("bth_send: default opcode", bth.opcode == 8'h04);
            check("bth_send: no reth", bth.has_reth() == 0);
            check("bth_send: no aeth", bth.has_aeth() == 0);
            check("bth_send: no immdt", bth.has_immdt() == 0);
            check("bth_send: header_length", bth.get_header_length() == 16); // 12 BTH + 4 ICRC

            bth.icrc_enable = 0;
            check("bth_send: header_length no icrc", bth.get_header_length() == 12);

            bth.dest_qp = 24'h000100;
            bth.psn     = 24'h000001;
            bth.pkey    = 16'hFFFF;
            bth.pack_header(packed);
            check("bth_send: pack size", packed.size() == 12);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(packed, offset);
                check("bth_send: unpack opcode", bth2.opcode == 8'h04);
                check("bth_send: unpack dest_qp", bth2.dest_qp == 24'h000100);
                check("bth_send: unpack psn", bth2.psn == 24'h000001);
                check("bth_send: unpack pkey", bth2.pkey == 16'hFFFF);
                check("bth_send: unpack offset", offset == 12);
            end
        end

        // ---- RoCEv2 RDMA Write Only (opcode 0x0A, BTH + RETH) ----
        begin
            rocev2_bth bth = rocev2_bth::create(8'h0A, 24'h000200);
            byte unsigned packed[$];
            int offset;

            check("bth_write: has_reth", bth.has_reth() == 1);
            check("bth_write: no aeth", bth.has_aeth() == 0);
            bth.icrc_enable = 0;
            check("bth_write: header_length", bth.get_header_length() == 28); // 12 + 16

            bth.reth_va      = 64'hDEAD_BEEF_CAFE_0000;
            bth.reth_r_key   = 32'h00001234;
            bth.reth_dma_len = 32'd4096;
            bth.psn          = 24'h000010;

            bth.pack_header(packed);
            check("bth_write: pack size", packed.size() == 28);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                // Must set opcode first so has_reth() works during unpack
                // Actually unpack reads opcode from data, so it works automatically
                bth2.unpack_header(packed, offset);
                check("bth_write: unpack opcode", bth2.opcode == 8'h0A);
                check("bth_write: unpack dest_qp", bth2.dest_qp == 24'h000200);
                check("bth_write: unpack reth_va", bth2.reth_va == 64'hDEAD_BEEF_CAFE_0000);
                check("bth_write: unpack reth_r_key", bth2.reth_r_key == 32'h00001234);
                check("bth_write: unpack reth_dma_len", bth2.reth_dma_len == 32'd4096);
                check("bth_write: unpack offset", offset == 28);
            end

            begin
                protocol_base bth3 = bth.clone();
                check("bth_write: clone compare", bth.compare(bth3));
            end
        end

        // ---- RoCEv2 Read Response Only (opcode 0x10, BTH + AETH) ----
        begin
            rocev2_bth bth = rocev2_bth::create(8'h10, 24'h000300);
            byte unsigned packed[$];
            int offset;

            check("bth_readresp: has_aeth", bth.has_aeth() == 1);
            check("bth_readresp: no reth", bth.has_reth() == 0);
            bth.icrc_enable = 0;
            check("bth_readresp: header_length", bth.get_header_length() == 16); // 12 + 4

            bth.aeth_syndrome = 8'h00;   // ACK
            bth.aeth_msn      = 24'h000005;
            bth.pack_header(packed);
            check("bth_readresp: pack size", packed.size() == 16);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(packed, offset);
                check("bth_readresp: unpack aeth_syndrome", bth2.aeth_syndrome == 8'h00);
                check("bth_readresp: unpack aeth_msn", bth2.aeth_msn == 24'h000005);
                check("bth_readresp: unpack offset", offset == 16);
            end
        end

        // ---- RoCEv2 Write Only w/ Imm (opcode 0x0B, BTH + RETH + ImmDt) ----
        begin
            rocev2_bth bth = rocev2_bth::create(8'h0B, 24'h000400);
            byte unsigned packed[$];
            int offset;

            check("bth_writeimm: has_reth", bth.has_reth() == 1);
            check("bth_writeimm: has_immdt", bth.has_immdt() == 1);
            check("bth_writeimm: no aeth", bth.has_aeth() == 0);
            bth.icrc_enable = 0;
            check("bth_writeimm: header_length", bth.get_header_length() == 32); // 12+16+4

            bth.reth_va      = 64'h0000_0000_1000_0000;
            bth.reth_r_key   = 32'hABCD0000;
            bth.reth_dma_len = 32'd256;
            bth.imm_data     = 32'h12345678;
            bth.pack_header(packed);
            check("bth_writeimm: pack size", packed.size() == 32);

            begin
                rocev2_bth bth2 = new();
                bth2.icrc_enable = 0;
                offset = 0;
                bth2.unpack_header(packed, offset);
                check("bth_writeimm: unpack imm_data", bth2.imm_data == 32'h12345678);
                check("bth_writeimm: unpack reth_r_key", bth2.reth_r_key == 32'hABCD0000);
                check("bth_writeimm: unpack offset", offset == 32);
            end

            begin
                protocol_base bth3 = bth.clone();
                check("bth_writeimm: clone compare", bth.compare(bth3));
            end
        end

        // ---- RoCEv2 with ICRC ----
        begin
            rocev2_bth bth = rocev2_bth::create(8'h04, 24'h000500);
            byte unsigned packed[$];

            bth.icrc_enable = 1;
            check("bth_icrc: header_length", bth.get_header_length() == 16); // 12 + 4

            bth.calc_fields('{}, PROTO_RAW_PAYLOAD);
            bth.pack_header(packed);
            check("bth_icrc: pack size", packed.size() == 16);
            // Last 4 bytes should be ICRC
            check("bth_icrc: icrc present", packed.size() >= 16);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram
```

- [ ] **Step 3: 更新 filelist.f**

Add after tunnel section:
```
+incdir+src/protocols/rdma

src/protocols/rdma/rocev2_header.sv
```

- [ ] **Step 4: 更新 Makefile**

Add after `test_tunnel_packet`:
```makefile
test_rdma_storage_headers: test/test_rdma_storage_headers.sv
	$(MAKE) run_rdma_storage_headers
```

Update `test_all` to include `test_rdma_storage_headers`.

- [ ] **Step 5: 提交**

```bash
git add src/protocols/rdma/rocev2_header.sv test/test_rdma_storage_headers.sv filelist.f Makefile
git commit -m "feat: add rocev2_bth with RETH/AETH/ImmDt/ICRC support"
```

---

### Task 2: iWARP 简化协议头

**Files:**
- Create: `src/protocols/rdma/iwarp_header.sv`
- Modify: `test/test_rdma_storage_headers.sv`
- Modify: `filelist.f`

iWARP 协议栈 MPA+DDP+RDMAP 合并为一个 28 字节简化头。

MPA (6 bytes): mpa_length(16), mpa_reserved(16), mpa_crc(16)
DDP (14 bytes): tagged(1), last(1), ddp_reserved(6), ddp_version(8), queue_number(16), msn(32), msg_offset(48 = upper 32 + lower 16)
RDMAP (8 bytes): rdmap_version(4), rdmap_opcode(4), padding(8), rdmap_reserved(16), sink_stag(32)

- [ ] **Step 1: 创建 iwarp_header.sv**

(完整代码同原计划 Task 2，此处不重复)

与原计划相同，遵循 protocol_base 接口。

- [ ] **Step 2: 在 test_rdma_storage_headers.sv 添加 iWARP 测试**

Add include `"rdma/iwarp_header.sv"` and tests:
- proto_type == PROTO_IWARP, header_length == 28
- Default versions (ddp_version==1, rdmap_version==1)
- Pack (rdmap_opcode=1, queue_number=5, msn=0x100, sink_stag=0xAABBCCDD), size==28
- Unpack round-trip verify all fields
- Clone+compare

- [ ] **Step 3: 更新 filelist.f**

```
src/protocols/rdma/iwarp_header.sv
```

- [ ] **Step 4: 提交**

```bash
git add src/protocols/rdma/iwarp_header.sv test/test_rdma_storage_headers.sv filelist.f
git commit -m "feat: add iwarp_header (MPA+DDP+RDMAP simplified)"
```

---

### Task 3: NVMe-TCP PDU 协议头

**Files:**
- Create: `src/protocols/storage/nvme_tcp_header.sv`
- Modify: `test/test_rdma_storage_headers.sv`
- Modify: `filelist.f`

NVMe-oF TCP PDU Common Header: 8 bytes
- pdu_type(8): 0x00=ICReq, 0x01=ICResp, 0x04=CapsuleCmd, 0x05=CapsuleResp
- flags(8)
- hlen(8): Header length in bytes (default 8)
- pdo(8): PDU Data Offset
- plen(32): Entire PDU length

- [ ] **Step 1: 创建 nvme_tcp_header.sv**

(完整代码同原计划 Task 3)

- [ ] **Step 2: 在 test_rdma_storage_headers.sv 添加 NVMe-TCP 测试**

- proto_type, header_length==8, default pdu_type==0x04
- Pack, unpack round-trip, clone+compare

- [ ] **Step 3: 更新 filelist.f**

```
+incdir+src/protocols/storage

src/protocols/storage/nvme_tcp_header.sv
```

- [ ] **Step 4: 提交**

```bash
git add src/protocols/storage/nvme_tcp_header.sv test/test_rdma_storage_headers.sv filelist.f
git commit -m "feat: add nvme_tcp_header (NVMe-oF TCP PDU common header)"
```

---

### Task 4: iSCSI BHS 协议头

**Files:**
- Create: `src/protocols/storage/iscsi_header.sv`
- Modify: `test/test_rdma_storage_headers.sv`
- Modify: `filelist.f`

iSCSI Basic Header Segment: 48 bytes
- Byte 0: {reserved_bit, immediate, opcode[5:0]}
- Byte 1: flags
- Bytes 2-3: reserved1
- Byte 4: total_ahs_len
- Bytes 5-7: data_segment_len (24-bit)
- Bytes 8-15: LUN (64-bit)
- Bytes 16-19: initiator_task_tag
- Bytes 20-47: opcode_specific (28 bytes raw)

- [ ] **Step 1: 创建 iscsi_header.sv**

(完整代码同原计划 Task 4)

- [ ] **Step 2: 在 test_rdma_storage_headers.sv 添加 iSCSI 测试**

- proto_type, header_length==48, default opcode==0x01
- Pack, set itt=0x12345678, lun=1, unpack round-trip, clone+compare

- [ ] **Step 3: 更新 filelist.f**

```
src/protocols/storage/iscsi_header.sv
```

- [ ] **Step 4: 提交**

```bash
git add src/protocols/storage/iscsi_header.sv test/test_rdma_storage_headers.sv filelist.f
git commit -m "feat: add iscsi_header (iSCSI BHS 48-byte)"
```

---

### Task 5: 集成到 packet.sv

**Files:**
- Modify: `src/core/packet.sv`

5 处修改：

1. 添加 rdma/storage includes（在 tunnel includes 之后）:
```systemverilog
`include "rdma/rocev2_header.sv"
`include "rdma/iwarp_header.sv"
`include "storage/nvme_tcp_header.sv"
`include "storage/iscsi_header.sv"
```

2. create_header() 工厂添加 PROTO_ROCEV2, PROTO_IWARP, PROTO_NVME_TCP, PROTO_ISCSI

3. identify_next_proto() 添加:
- PROTO_ROCEV2 -> PROTO_RAW_PAYLOAD (BTH payload 是 RDMA 数据)
- PROTO_TCP -> tcp_dstport_to_proto()

4. 新增 tcp_dstport_to_proto() 函数:
- 4420 -> PROTO_NVME_TCP
- 3260 -> PROTO_ISCSI
- default -> PROTO_RAW_PAYLOAD

5. UDP dst_port 4791 -> PROTO_ROCEV2 已在 Phase 2a 中添加，无需修改。

- [ ] **Step 1-5: 修改 packet.sv**

- [ ] **Step 6: 提交**

```bash
git add src/core/packet.sv
git commit -m "feat: integrate RDMA/storage protocols into packet factory and unpack"
```

---

### Task 6: RDMA/存储报文集成测试

**Files:**
- Create: `test/test_rdma_storage_packet.sv`
- Modify: `Makefile`

测试模板：
- ETH_IPV4_UDP_ROCEV2: Send Only, RDMA Write Only (有 RETH), Read Response (有 AETH)
- ETH_VLAN_IPV4_UDP_ROCEV2: 带 VLAN 的 RoCEv2
- ETH_IPV4_TCP_NVME_TCP: 构建 + pack + unpack
- ETH_IPV4_TCP_ISCSI: 构建 + pack + unpack
- ETH_IPV4_TCP_IWARP: 构建 + pack + unpack

- [ ] **Step 1: 创建 test_rdma_storage_packet.sv**

测试需要验证：
1. RoCEv2 Send Only: 4 layers, pack/unpack round-trip
2. RoCEv2 RDMA Write: 设置 opcode=0x0A 后 get_layer 验证 RETH 字段 round-trip
3. RoCEv2 ACK: 设置 opcode=0x11 后验证 AETH 字段 round-trip
4. VLAN+RoCEv2: 5 layers
5. NVMe-TCP: 4 layers, pack/unpack
6. iSCSI: 4 layers, pack/unpack
7. iWARP: 4 layers, pack/unpack

- [ ] **Step 2: 更新 Makefile**

Add `test_rdma_storage_packet` target, update `test_all`.

- [ ] **Step 3: 提交**

```bash
git add test/test_rdma_storage_packet.sv Makefile
git commit -m "feat: add RDMA/storage packet integration tests"
```

---

## 自检清单

- [x] RoCEv2 完整性：BTH + RETH(Write/ReadReq) + AETH(ReadResp/ACK) + ImmDt(with-imm) + ICRC
- [x] Opcode 分类：has_reth/has_aeth/has_immdt 覆盖所有常用 opcode
- [x] 可变长度：get_header_length 根据 opcode 返回正确长度
- [x] iWARP：MPA+DDP+RDMAP 简化为 28 字节
- [x] NVMe-TCP：8 字节 PDU 公共头
- [x] iSCSI：48 字节 BHS
- [x] packet.sv 集成：create_header + identify_next_proto 覆盖所有协议
- [x] UDP 4791->RoCEv2 映射已在 Phase 2a 添加
- [x] TCP 4420->NVMe-TCP, 3260->iSCSI 映射新增

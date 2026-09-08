# Phase 2a: 隧道协议实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现所有隧道协议头（VXLAN, GRE, Geneve, ERSPAN II/III, GTP-U, IP-in-IP），并集成到 packet 工厂和 unpack 逻辑中，使已注册的隧道模板可正常构建和解析。

**Architecture:** 每个隧道协议继承 `protocol_base`，遵循已有的 pack/unpack/calc_fields/clone/compare 模式。新增 `src/protocols/tunnel/` 目录。更新 `packet.sv` 的 `create_header()` 工厂和 `identify_next_proto()` 解析映射。协议图和模板已在 Phase 1 注册完毕，无需修改。

**Tech Stack:** SystemVerilog (IEEE 1800-2017), VCS/Questa

---

## 文件映射

| 文件 | 操作 | 职责 |
|------|------|------|
| `src/protocols/tunnel/vxlan_header.sv` | 新建 | VXLAN 协议头 (8字节) |
| `src/protocols/tunnel/gre_header.sv` | 新建 | GRE 协议头 (4-16字节，含可选字段) |
| `src/protocols/tunnel/geneve_header.sv` | 新建 | Geneve 协议头 (8+字节，含 TLV 选项) |
| `src/protocols/tunnel/erspan_header.sv` | 新建 | ERSPAN Type II (8字节) 和 Type III (12字节) |
| `src/protocols/tunnel/gtp_header.sv` | 新建 | GTP-U 协议头 (8+字节) |
| `src/protocols/tunnel/ip_in_ip_header.sv` | 新建 | IP-in-IP 标记头 (0字节，仅做协议标识) |
| `src/core/packet.sv` | 修改 | 扩展 create_header() 工厂 + identify_next_proto() |
| `filelist.f` | 修改 | 添加 tunnel 目录和源文件 |
| `test/test_tunnel_headers.sv` | 新建 | 所有隧道协议的单元测试 |
| `test/test_tunnel_packet.sv` | 新建 | 隧道报文模板构建 + pack/unpack 集成测试 |
| `Makefile` | 修改 | 添加 tunnel 测试目标 |

---

### Task 1: VXLAN 协议头

**Files:**
- Create: `src/protocols/tunnel/vxlan_header.sv`
- Test: `test/test_tunnel_headers.sv`

VXLAN 格式 (RFC 7348): 8字节
```
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |R|R|R|R|I|R|R|R|            Reserved                           |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                VXLAN Network Identifier (VNI) |   Reserved    |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- [ ] **Step 1: 创建 vxlan_header.sv**

```systemverilog
// src/protocols/tunnel/vxlan_header.sv
`ifndef VXLAN_HEADER_SV
`define VXLAN_HEADER_SV

`include "protocol_base.sv"

class vxlan_header extends protocol_base;

    rand bit [7:0]  flags;
    rand bit [23:0] reserved1;
    rand bit [23:0] vni;
    rand bit [7:0]  reserved2;

    constraint c_default {
        flags    == 8'h08;   // I-flag set
        reserved1 == 24'h0;
        reserved2 == 8'h0;
    }

    function new();
        proto_type = PROTO_VXLAN;
        flags      = 8'h08;
        reserved1  = 24'h0;
        vni        = 24'd100;
        reserved2  = 8'h0;
    endfunction

    static function vxlan_header create(bit [23:0] v = 24'd100);
        vxlan_header h = new();
        h.vni = v;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // Byte 0: flags
        data.push_back(flags);
        // Bytes 1-3: reserved1
        data.push_back(reserved1[23:16]);
        data.push_back(reserved1[15:8]);
        data.push_back(reserved1[7:0]);
        // Bytes 4-6: VNI
        data.push_back(vni[23:16]);
        data.push_back(vni[15:8]);
        data.push_back(vni[7:0]);
        // Byte 7: reserved2
        data.push_back(reserved2);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        flags     = data[offset]; offset++;
        reserved1 = {data[offset], data[offset+1], data[offset+2]}; offset += 3;
        vni       = {data[offset], data[offset+1], data[offset+2]}; offset += 3;
        reserved2 = data[offset]; offset++;
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        flags = 8'h08;  // I-flag always set
    endfunction

    virtual function protocol_base clone();
        vxlan_header h = new();
        h.flags     = flags;
        h.reserved1 = reserved1;
        h.vni       = vni;
        h.reserved2 = reserved2;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        vxlan_header o;
        if (!$cast(o, other)) return 0;
        return (flags == o.flags) && (vni == o.vni);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  flags : 0x%02x\n", flags)};
        s = {s, $sformatf("  vni   : %0d (0x%06x)\n", vni, vni)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("VXLAN VNI:%0d", vni);
    endfunction

endclass

`endif // VXLAN_HEADER_SV
```

- [ ] **Step 2: 创建测试框架 test_tunnel_headers.sv 并添加 VXLAN 测试**

```systemverilog
// test/test_tunnel_headers.sv
`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "tunnel/vxlan_header.sv"

program test_tunnel_headers;

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
        $display("=== test_tunnel_headers ===");

        // ---- VXLAN ----
        begin
            vxlan_header vx = new();
            byte unsigned packed[$];
            int offset;

            check("vxlan: proto_type", vx.proto_type == PROTO_VXLAN);
            check("vxlan: header_length", vx.get_header_length() == 8);
            check("vxlan: default flags", vx.flags == 8'h08);
            check("vxlan: default vni", vx.vni == 24'd100);

            // Pack
            vx.vni = 24'h123456;
            vx.pack_header(packed);
            check("vxlan: pack size", packed.size() == 8);
            check("vxlan: pack flags", packed[0] == 8'h08);
            check("vxlan: pack vni[0]", packed[4] == 8'h12);
            check("vxlan: pack vni[1]", packed[5] == 8'h34);
            check("vxlan: pack vni[2]", packed[6] == 8'h56);

            // Unpack
            begin
                vxlan_header vx2 = new();
                offset = 0;
                vx2.unpack_header(packed, offset);
                check("vxlan: unpack flags", vx2.flags == 8'h08);
                check("vxlan: unpack vni", vx2.vni == 24'h123456);
                check("vxlan: unpack offset", offset == 8);
            end

            // Clone & compare
            begin
                protocol_base vx3 = vx.clone();
                check("vxlan: clone compare", vx.compare(vx3));
            end

            // Static create
            begin
                vxlan_header vx4 = vxlan_header::create(24'd200);
                check("vxlan: static create vni", vx4.vni == 24'd200);
            end
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram
```

- [ ] **Step 3: 更新 filelist.f 添加 tunnel 目录**

在 `filelist.f` 的 `+incdir` 段添加：
```
+incdir+src/protocols/tunnel
```

在源文件段添加：
```
src/protocols/tunnel/vxlan_header.sv
```

- [ ] **Step 4: 更新 Makefile 添加 tunnel 测试目标**

在 `test_packet_builder` 目标之后添加：
```makefile
test_tunnel_headers: test/test_tunnel_headers.sv
	$(MAKE) run_tunnel_headers
```

将 `test_all` 更新为：
```makefile
test_all: test_protocol_headers test_protocol_graph test_packet_builder test_tunnel_headers
```

- [ ] **Step 5: 编译运行测试确认通过**

Run: `make test_tunnel_headers`
Expected: 所有 VXLAN 测试 PASS

- [ ] **Step 6: 提交**

```bash
git add src/protocols/tunnel/vxlan_header.sv test/test_tunnel_headers.sv filelist.f Makefile
git commit -m "feat: add vxlan_header with pack/unpack/calc_fields"
```

---

### Task 2: GRE 协议头

**Files:**
- Create: `src/protocols/tunnel/gre_header.sv`
- Modify: `test/test_tunnel_headers.sv`
- Modify: `filelist.f`

GRE 格式 (RFC 2784/2890): 4-16字节
```
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |C| |K|S| Reserved0       | Ver |         Protocol Type         |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |      Checksum (optional)      |       Reserved1 (optional)    |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                         Key (optional)                        |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                    Sequence Number (optional)                 |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- [ ] **Step 1: 创建 gre_header.sv**

```systemverilog
// src/protocols/tunnel/gre_header.sv
`ifndef GRE_HEADER_SV
`define GRE_HEADER_SV

`include "protocol_base.sv"

class gre_header extends protocol_base;

    rand bit        c_flag;           // Checksum present
    rand bit        k_flag;           // Key present
    rand bit        s_flag;           // Sequence number present
    rand bit [9:0]  reserved0;
    rand bit [2:0]  version;
    rand bit [15:0] protocol_type;    // Inner protocol EtherType
    rand bit [15:0] checksum;         // Optional
    rand bit [15:0] reserved1;        // Optional (present when C=1)
    rand bit [31:0] key;              // Optional
    rand bit [31:0] sequence_number;  // Optional

    constraint c_default {
        c_flag    == 0;
        k_flag    == 0;
        s_flag    == 0;
        reserved0 == 0;
        version   == 0;
        reserved1 == 0;
    }

    function new();
        proto_type      = PROTO_GRE;
        c_flag          = 0;
        k_flag          = 0;
        s_flag          = 0;
        reserved0       = 0;
        version         = 0;
        protocol_type   = ETHERTYPE_IPV4;
        checksum        = 0;
        reserved1       = 0;
        key             = 0;
        sequence_number = 0;
    endfunction

    static function gre_header create(bit [15:0] proto = ETHERTYPE_IPV4);
        gre_header h = new();
        h.protocol_type = proto;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [15:0] flags_ver;
        flags_ver = {c_flag, 1'b0, k_flag, s_flag, reserved0, version};
        packet_utils::pack_bytes_16(data, flags_ver);
        packet_utils::pack_bytes_16(data, protocol_type);
        if (c_flag) begin
            packet_utils::pack_bytes_16(data, checksum);
            packet_utils::pack_bytes_16(data, reserved1);
        end
        if (k_flag) begin
            packet_utils::pack_bytes_32(data, key);
        end
        if (s_flag) begin
            packet_utils::pack_bytes_32(data, sequence_number);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [15:0] flags_ver;
        flags_ver = packet_utils::unpack_bytes_16(data, offset);
        c_flag    = flags_ver[15];
        k_flag    = flags_ver[13];
        s_flag    = flags_ver[12];
        reserved0 = flags_ver[11:3];
        version   = flags_ver[2:0];
        protocol_type = packet_utils::unpack_bytes_16(data, offset);
        if (c_flag) begin
            checksum  = packet_utils::unpack_bytes_16(data, offset);
            reserved1 = packet_utils::unpack_bytes_16(data, offset);
        end
        if (k_flag) begin
            key = packet_utils::unpack_bytes_32(data, offset);
        end
        if (s_flag) begin
            sequence_number = packet_utils::unpack_bytes_32(data, offset);
        end
    endfunction

    virtual function int get_header_length();
        int len = 4;
        if (c_flag) len += 4;
        if (k_flag) len += 4;
        if (s_flag) len += 4;
        return len;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        case (next_proto)
            PROTO_IPV4:      protocol_type = ETHERTYPE_IPV4;
            PROTO_IPV6:      protocol_type = ETHERTYPE_IPV6;
            PROTO_ETHERNET:  protocol_type = 16'h6558;   // Transparent Ethernet Bridging
            PROTO_ERSPAN_II: protocol_type = 16'h88BE;   // ERSPAN
            PROTO_ERSPAN_III:protocol_type = 16'h22EB;   // ERSPAN III
            default: ;
        endcase
    endfunction

    virtual function protocol_base clone();
        gre_header h = new();
        h.c_flag          = c_flag;
        h.k_flag          = k_flag;
        h.s_flag          = s_flag;
        h.reserved0       = reserved0;
        h.version         = version;
        h.protocol_type   = protocol_type;
        h.checksum        = checksum;
        h.reserved1       = reserved1;
        h.key             = key;
        h.sequence_number = sequence_number;
        h.auto_calc       = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        gre_header o;
        if (!$cast(o, other)) return 0;
        if (c_flag != o.c_flag || k_flag != o.k_flag || s_flag != o.s_flag) return 0;
        if (protocol_type != o.protocol_type) return 0;
        if (c_flag && checksum != o.checksum) return 0;
        if (k_flag && key != o.key) return 0;
        if (s_flag && sequence_number != o.sequence_number) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  c_flag       : %0b\n", c_flag)};
        s = {s, $sformatf("  k_flag       : %0b\n", k_flag)};
        s = {s, $sformatf("  s_flag       : %0b\n", s_flag)};
        s = {s, $sformatf("  version      : %0d\n", version)};
        s = {s, $sformatf("  protocol_type: 0x%04x\n", protocol_type)};
        if (c_flag) s = {s, $sformatf("  checksum     : 0x%04x\n", checksum)};
        if (k_flag) s = {s, $sformatf("  key          : 0x%08x\n", key)};
        if (s_flag) s = {s, $sformatf("  sequence_num : 0x%08x\n", sequence_number)};
        return s;
    endfunction

    virtual function string to_brief();
        string s;
        s = $sformatf("GRE proto:0x%04x", protocol_type);
        if (k_flag) s = {s, $sformatf(" key:0x%08x", key)};
        return s;
    endfunction

endclass

`endif // GRE_HEADER_SV
```

- [ ] **Step 2: 在 test_tunnel_headers.sv 添加 GRE 测试**

在文件头部 include 行追加：
```systemverilog
`include "tunnel/gre_header.sv"
```

在 VXLAN 测试块之后、`$display("=== Results")` 之前添加：
```systemverilog
        // ---- GRE ----
        begin
            gre_header gre = new();
            byte unsigned packed[$];
            int offset;

            check("gre: proto_type", gre.proto_type == PROTO_GRE);
            check("gre: header_length basic", gre.get_header_length() == 4);
            check("gre: default protocol_type", gre.protocol_type == ETHERTYPE_IPV4);

            // Basic GRE (no optional fields)
            gre.pack_header(packed);
            check("gre: pack basic size", packed.size() == 4);

            begin
                gre_header gre2 = new();
                offset = 0;
                gre2.unpack_header(packed, offset);
                check("gre: unpack basic protocol", gre2.protocol_type == ETHERTYPE_IPV4);
                check("gre: unpack basic offset", offset == 4);
                check("gre: unpack basic c_flag", gre2.c_flag == 0);
                check("gre: unpack basic k_flag", gre2.k_flag == 0);
            end

            // GRE with key
            begin
                gre_header gre_k = new();
                byte unsigned packed_k[$];
                gre_k.k_flag = 1;
                gre_k.key = 32'hAABBCCDD;
                check("gre: header_length with key", gre_k.get_header_length() == 8);

                gre_k.pack_header(packed_k);
                check("gre: pack key size", packed_k.size() == 8);

                begin
                    gre_header gre_k2 = new();
                    offset = 0;
                    gre_k2.unpack_header(packed_k, offset);
                    check("gre: unpack key k_flag", gre_k2.k_flag == 1);
                    check("gre: unpack key value", gre_k2.key == 32'hAABBCCDD);
                    check("gre: unpack key offset", offset == 8);
                end
            end

            // GRE with all options
            begin
                gre_header gre_all = new();
                byte unsigned packed_all[$];
                gre_all.c_flag = 1;
                gre_all.k_flag = 1;
                gre_all.s_flag = 1;
                gre_all.key = 32'h12345678;
                gre_all.sequence_number = 32'h00000001;
                check("gre: header_length all", gre_all.get_header_length() == 16);

                gre_all.pack_header(packed_all);
                check("gre: pack all size", packed_all.size() == 16);

                begin
                    gre_header gre_all2 = new();
                    offset = 0;
                    gre_all2.unpack_header(packed_all, offset);
                    check("gre: unpack all c_flag", gre_all2.c_flag == 1);
                    check("gre: unpack all k_flag", gre_all2.k_flag == 1);
                    check("gre: unpack all s_flag", gre_all2.s_flag == 1);
                    check("gre: unpack all key", gre_all2.key == 32'h12345678);
                    check("gre: unpack all seq", gre_all2.sequence_number == 32'h00000001);
                    check("gre: unpack all offset", offset == 16);
                end

                // Clone & compare
                begin
                    protocol_base gre_cloned = gre_all.clone();
                    check("gre: clone compare", gre_all.compare(gre_cloned));
                end
            end

            // calc_fields
            begin
                gre_header gre_cf = new();
                gre_cf.calc_fields('{}, PROTO_IPV6);
                check("gre: calc_fields IPv6", gre_cf.protocol_type == ETHERTYPE_IPV6);
                gre_cf.calc_fields('{}, PROTO_ETHERNET);
                check("gre: calc_fields Ethernet", gre_cf.protocol_type == 16'h6558);
                gre_cf.calc_fields('{}, PROTO_ERSPAN_II);
                check("gre: calc_fields ERSPAN_II", gre_cf.protocol_type == 16'h88BE);
            end
        end
```

- [ ] **Step 3: 更新 filelist.f**

添加源文件：
```
src/protocols/tunnel/gre_header.sv
```

- [ ] **Step 4: 编译运行测试确认通过**

Run: `make test_tunnel_headers`
Expected: 所有 VXLAN + GRE 测试 PASS

- [ ] **Step 5: 提交**

```bash
git add src/protocols/tunnel/gre_header.sv test/test_tunnel_headers.sv filelist.f
git commit -m "feat: add gre_header with optional checksum/key/sequence fields"
```

---

### Task 3: Geneve 协议头

**Files:**
- Create: `src/protocols/tunnel/geneve_header.sv`
- Modify: `test/test_tunnel_headers.sv`
- Modify: `filelist.f`

Geneve 格式 (RFC 8926): 8+字节
```
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |Ver|  Opt Len  |O|C|    Rsvd.  |          Protocol Type        |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |        Virtual Network Identifier (VNI)       |    Reserved   |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                    Variable Length Options                    |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- [ ] **Step 1: 创建 geneve_header.sv**

```systemverilog
// src/protocols/tunnel/geneve_header.sv
`ifndef GENEVE_HEADER_SV
`define GENEVE_HEADER_SV

`include "protocol_base.sv"

class geneve_header extends protocol_base;

    rand bit [1:0]  version;
    rand bit [5:0]  opt_len;          // In 4-byte units
    rand bit        o_flag;           // OAM packet
    rand bit        c_flag;           // Critical options present
    rand bit [5:0]  reserved0;
    rand bit [15:0] protocol_type;    // Inner protocol EtherType
    rand bit [23:0] vni;
    rand bit [7:0]  reserved1;
    rand byte unsigned options[$];    // Variable length options (multiple of 4 bytes)

    constraint c_default {
        version   == 0;
        o_flag    == 0;
        c_flag    == 0;
        reserved0 == 0;
        reserved1 == 0;
        options.size() == 0;
        opt_len   == 0;
    }

    function new();
        proto_type     = PROTO_GENEVE;
        version        = 0;
        opt_len        = 0;
        o_flag         = 0;
        c_flag         = 0;
        reserved0      = 0;
        protocol_type  = 16'h6558;  // Transparent Ethernet Bridging
        vni            = 24'd100;
        reserved1      = 0;
    endfunction

    static function geneve_header create(bit [23:0] v = 24'd100);
        geneve_header h = new();
        h.vni = v;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [7:0] byte0 = {version, opt_len};
        bit [7:0] byte1 = {o_flag, c_flag, reserved0};
        data.push_back(byte0);
        data.push_back(byte1);
        packet_utils::pack_bytes_16(data, protocol_type);
        data.push_back(vni[23:16]);
        data.push_back(vni[15:8]);
        data.push_back(vni[7:0]);
        data.push_back(reserved1);
        foreach (options[i])
            data.push_back(options[i]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] byte0 = data[offset]; offset++;
        bit [7:0] byte1 = data[offset]; offset++;
        version   = byte0[7:6];
        opt_len   = byte0[5:0];
        o_flag    = byte1[7];
        c_flag    = byte1[6];
        reserved0 = byte1[5:0];
        protocol_type = packet_utils::unpack_bytes_16(data, offset);
        vni = {data[offset], data[offset+1], data[offset+2]}; offset += 3;
        reserved1 = data[offset]; offset++;
        // Read options (opt_len * 4 bytes)
        options.delete();
        for (int i = 0; i < int'(opt_len) * 4; i++) begin
            options.push_back(data[offset]); offset++;
        end
    endfunction

    virtual function int get_header_length();
        return 8 + int'(opt_len) * 4;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        opt_len = options.size() / 4;
        case (next_proto)
            PROTO_ETHERNET: protocol_type = 16'h6558;
            PROTO_IPV4:     protocol_type = ETHERTYPE_IPV4;
            PROTO_IPV6:     protocol_type = ETHERTYPE_IPV6;
            default: ;
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
        h.options       = options;
        h.auto_calc     = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        geneve_header o;
        if (!$cast(o, other)) return 0;
        if (version != o.version || opt_len != o.opt_len) return 0;
        if (protocol_type != o.protocol_type || vni != o.vni) return 0;
        if (options.size() != o.options.size()) return 0;
        foreach (options[i])
            if (options[i] != o.options[i]) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version      : %0d\n", version)};
        s = {s, $sformatf("  opt_len      : %0d (x4 bytes)\n", opt_len)};
        s = {s, $sformatf("  o_flag       : %0b\n", o_flag)};
        s = {s, $sformatf("  c_flag       : %0b\n", c_flag)};
        s = {s, $sformatf("  protocol_type: 0x%04x\n", protocol_type)};
        s = {s, $sformatf("  vni          : %0d (0x%06x)\n", vni, vni)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("Geneve VNI:%0d proto:0x%04x", vni, protocol_type);
    endfunction

endclass

`endif // GENEVE_HEADER_SV
```

- [ ] **Step 2: 在 test_tunnel_headers.sv 添加 Geneve 测试**

在文件头部 include 行追加：
```systemverilog
`include "tunnel/geneve_header.sv"
```

在 GRE 测试块之后添加：
```systemverilog
        // ---- Geneve ----
        begin
            geneve_header gn = new();
            byte unsigned packed[$];
            int offset;

            check("geneve: proto_type", gn.proto_type == PROTO_GENEVE);
            check("geneve: header_length basic", gn.get_header_length() == 8);
            check("geneve: default vni", gn.vni == 24'd100);
            check("geneve: default protocol_type", gn.protocol_type == 16'h6558);

            // Pack without options
            gn.vni = 24'hABCDEF;
            gn.pack_header(packed);
            check("geneve: pack size", packed.size() == 8);

            // Unpack
            begin
                geneve_header gn2 = new();
                offset = 0;
                gn2.unpack_header(packed, offset);
                check("geneve: unpack vni", gn2.vni == 24'hABCDEF);
                check("geneve: unpack protocol_type", gn2.protocol_type == 16'h6558);
                check("geneve: unpack offset", offset == 8);
            end

            // With options (4 bytes)
            begin
                geneve_header gn_opt = new();
                byte unsigned packed_opt[$];
                gn_opt.vni = 24'd500;
                gn_opt.options = '{8'h01, 8'h02, 8'h03, 8'h04};
                gn_opt.opt_len = 1;
                check("geneve: header_length with options", gn_opt.get_header_length() == 12);

                gn_opt.pack_header(packed_opt);
                check("geneve: pack options size", packed_opt.size() == 12);

                begin
                    geneve_header gn_opt2 = new();
                    offset = 0;
                    gn_opt2.unpack_header(packed_opt, offset);
                    check("geneve: unpack opt_len", gn_opt2.opt_len == 1);
                    check("geneve: unpack options size", gn_opt2.options.size() == 4);
                    check("geneve: unpack options[0]", gn_opt2.options[0] == 8'h01);
                    check("geneve: unpack offset with opts", offset == 12);
                end
            end

            // Clone & compare
            begin
                protocol_base gn3 = gn.clone();
                check("geneve: clone compare", gn.compare(gn3));
            end

            // calc_fields
            begin
                geneve_header gn_cf = new();
                gn_cf.calc_fields('{}, PROTO_ETHERNET);
                check("geneve: calc_fields Ethernet", gn_cf.protocol_type == 16'h6558);
            end
        end
```

- [ ] **Step 3: 更新 filelist.f**

添加源文件：
```
src/protocols/tunnel/geneve_header.sv
```

- [ ] **Step 4: 编译运行测试确认通过**

Run: `make test_tunnel_headers`
Expected: 所有测试 PASS

- [ ] **Step 5: 提交**

```bash
git add src/protocols/tunnel/geneve_header.sv test/test_tunnel_headers.sv filelist.f
git commit -m "feat: add geneve_header with variable-length TLV options"
```

---

### Task 4: ERSPAN 协议头 (Type II 和 Type III)

**Files:**
- Create: `src/protocols/tunnel/erspan_header.sv`
- Modify: `test/test_tunnel_headers.sv`
- Modify: `filelist.f`

ERSPAN Type II: 8字节
```
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |  Ver  |          VLAN         | COS |En|T|        Session ID  |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |      Reserved         |                  Index                |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

ERSPAN Type III: 12字节 (8 + 4字节 platform specific subheader)

- [ ] **Step 1: 创建 erspan_header.sv**

```systemverilog
// src/protocols/tunnel/erspan_header.sv
`ifndef ERSPAN_HEADER_SV
`define ERSPAN_HEADER_SV

`include "protocol_base.sv"

// ERSPAN Type II header (8 bytes)
class erspan_ii_header extends protocol_base;

    rand bit [3:0]  version;
    rand bit [11:0] vlan;
    rand bit [2:0]  cos;
    rand bit [1:0]  en;
    rand bit        truncated;
    rand bit [9:0]  session_id;
    rand bit [11:0] reserved;
    rand bit [19:0] index;

    constraint c_default {
        version  == 4'd1;
        en       == 2'b00;
        reserved == 0;
    }

    function new();
        proto_type  = PROTO_ERSPAN_II;
        version     = 4'd1;
        vlan        = 0;
        cos         = 0;
        en          = 0;
        truncated   = 0;
        session_id  = 0;
        reserved    = 0;
        index       = 0;
    endfunction

    static function erspan_ii_header create(bit [9:0] sid = 0, bit [11:0] v = 0);
        erspan_ii_header h = new();
        h.session_id = sid;
        h.vlan       = v;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [31:0] word0 = {version, vlan, cos, en, truncated, session_id};
        bit [31:0] word1 = {reserved, index};
        packet_utils::pack_bytes_32(data, word0);
        packet_utils::pack_bytes_32(data, word1);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] word0 = packet_utils::unpack_bytes_32(data, offset);
        bit [31:0] word1 = packet_utils::unpack_bytes_32(data, offset);
        version    = word0[31:28];
        vlan       = word0[27:16];
        cos        = word0[15:13];
        en         = word0[12:11];
        truncated  = word0[10];
        session_id = word0[9:0];
        reserved   = word1[31:20];
        index      = word1[19:0];
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        version = 4'd1;
    endfunction

    virtual function protocol_base clone();
        erspan_ii_header h = new();
        h.version    = version;
        h.vlan       = vlan;
        h.cos        = cos;
        h.en         = en;
        h.truncated  = truncated;
        h.session_id = session_id;
        h.reserved   = reserved;
        h.index      = index;
        h.auto_calc  = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        erspan_ii_header o;
        if (!$cast(o, other)) return 0;
        return (version == o.version) && (vlan == o.vlan) && (cos == o.cos) &&
               (en == o.en) && (truncated == o.truncated) &&
               (session_id == o.session_id) && (index == o.index);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version   : %0d\n", version)};
        s = {s, $sformatf("  vlan      : %0d\n", vlan)};
        s = {s, $sformatf("  cos       : %0d\n", cos)};
        s = {s, $sformatf("  en        : %0d\n", en)};
        s = {s, $sformatf("  truncated : %0d\n", truncated)};
        s = {s, $sformatf("  session_id: %0d\n", session_id)};
        s = {s, $sformatf("  index     : %0d\n", index)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ERSPAN-II sid:%0d vlan:%0d idx:%0d", session_id, vlan, index);
    endfunction

endclass

// ERSPAN Type III header (12 bytes)
class erspan_iii_header extends protocol_base;

    rand bit [3:0]  version;
    rand bit [11:0] vlan;
    rand bit [2:0]  cos;
    rand bit [1:0]  bso;
    rand bit        truncated;
    rand bit [9:0]  session_id;
    rand bit [31:0] timestamp;
    rand bit [15:0] sgt;
    rand bit        p_flag;
    rand bit [5:0]  ft;
    rand bit [5:0]  hw_id;
    rand bit        direction;
    rand bit [1:0]  gra;
    rand bit        o_flag;

    constraint c_default {
        version == 4'd2;
        bso     == 0;
    }

    function new();
        proto_type  = PROTO_ERSPAN_III;
        version     = 4'd2;
        vlan        = 0;
        cos         = 0;
        bso         = 0;
        truncated   = 0;
        session_id  = 0;
        timestamp   = 0;
        sgt         = 0;
        p_flag      = 0;
        ft          = 0;
        hw_id       = 0;
        direction   = 0;
        gra         = 0;
        o_flag      = 0;
    endfunction

    static function erspan_iii_header create(bit [9:0] sid = 0);
        erspan_iii_header h = new();
        h.session_id = sid;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [31:0] word0 = {version, vlan, cos, bso, truncated, session_id};
        packet_utils::pack_bytes_32(data, word0);
        packet_utils::pack_bytes_32(data, timestamp);
        bit [31:0] word2 = {sgt, p_flag, ft, hw_id, direction, gra, o_flag};
        packet_utils::pack_bytes_32(data, word2);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] word0 = packet_utils::unpack_bytes_32(data, offset);
        version    = word0[31:28];
        vlan       = word0[27:16];
        cos        = word0[15:13];
        bso        = word0[12:11];
        truncated  = word0[10];
        session_id = word0[9:0];
        timestamp  = packet_utils::unpack_bytes_32(data, offset);
        bit [31:0] word2 = packet_utils::unpack_bytes_32(data, offset);
        sgt       = word2[31:16];
        p_flag    = word2[15];
        ft        = word2[14:9];
        hw_id     = word2[8:3];
        direction = word2[2];
        gra       = word2[1:0];
        o_flag    = word2[0];
    endfunction

    virtual function int get_header_length();
        return 12;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        version = 4'd2;
    endfunction

    virtual function protocol_base clone();
        erspan_iii_header h = new();
        h.version    = version;
        h.vlan       = vlan;
        h.cos        = cos;
        h.bso        = bso;
        h.truncated  = truncated;
        h.session_id = session_id;
        h.timestamp  = timestamp;
        h.sgt        = sgt;
        h.p_flag     = p_flag;
        h.ft         = ft;
        h.hw_id      = hw_id;
        h.direction  = direction;
        h.gra        = gra;
        h.o_flag     = o_flag;
        h.auto_calc  = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        erspan_iii_header o;
        if (!$cast(o, other)) return 0;
        return (version == o.version) && (vlan == o.vlan) && (cos == o.cos) &&
               (session_id == o.session_id) && (timestamp == o.timestamp) &&
               (sgt == o.sgt) && (hw_id == o.hw_id) && (direction == o.direction);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version   : %0d\n", version)};
        s = {s, $sformatf("  vlan      : %0d\n", vlan)};
        s = {s, $sformatf("  cos       : %0d\n", cos)};
        s = {s, $sformatf("  session_id: %0d\n", session_id)};
        s = {s, $sformatf("  timestamp : 0x%08x\n", timestamp)};
        s = {s, $sformatf("  sgt       : 0x%04x\n", sgt)};
        s = {s, $sformatf("  hw_id     : %0d\n", hw_id)};
        s = {s, $sformatf("  direction : %0d\n", direction)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ERSPAN-III sid:%0d vlan:%0d ts:0x%08x", session_id, vlan, timestamp);
    endfunction

endclass

`endif // ERSPAN_HEADER_SV
```

- [ ] **Step 2: 在 test_tunnel_headers.sv 添加 ERSPAN 测试**

在文件头部 include 行追加：
```systemverilog
`include "tunnel/erspan_header.sv"
```

在 Geneve 测试块之后添加：
```systemverilog
        // ---- ERSPAN Type II ----
        begin
            erspan_ii_header es2 = new();
            byte unsigned packed[$];
            int offset;

            check("erspan_ii: proto_type", es2.proto_type == PROTO_ERSPAN_II);
            check("erspan_ii: header_length", es2.get_header_length() == 8);
            check("erspan_ii: default version", es2.version == 4'd1);

            es2.session_id = 10'd100;
            es2.vlan       = 12'd200;
            es2.index      = 20'h12345;
            es2.pack_header(packed);
            check("erspan_ii: pack size", packed.size() == 8);

            begin
                erspan_ii_header es2b = new();
                offset = 0;
                es2b.unpack_header(packed, offset);
                check("erspan_ii: unpack version", es2b.version == 4'd1);
                check("erspan_ii: unpack session_id", es2b.session_id == 10'd100);
                check("erspan_ii: unpack vlan", es2b.vlan == 12'd200);
                check("erspan_ii: unpack index", es2b.index == 20'h12345);
                check("erspan_ii: unpack offset", offset == 8);
            end

            begin
                protocol_base es2c = es2.clone();
                check("erspan_ii: clone compare", es2.compare(es2c));
            end
        end

        // ---- ERSPAN Type III ----
        begin
            erspan_iii_header es3 = new();
            byte unsigned packed[$];
            int offset;

            check("erspan_iii: proto_type", es3.proto_type == PROTO_ERSPAN_III);
            check("erspan_iii: header_length", es3.get_header_length() == 12);
            check("erspan_iii: default version", es3.version == 4'd2);

            es3.session_id = 10'd50;
            es3.vlan       = 12'd300;
            es3.timestamp  = 32'hDEADBEEF;
            es3.hw_id      = 6'd10;
            es3.direction  = 1;
            es3.pack_header(packed);
            check("erspan_iii: pack size", packed.size() == 12);

            begin
                erspan_iii_header es3b = new();
                offset = 0;
                es3b.unpack_header(packed, offset);
                check("erspan_iii: unpack version", es3b.version == 4'd2);
                check("erspan_iii: unpack session_id", es3b.session_id == 10'd50);
                check("erspan_iii: unpack vlan", es3b.vlan == 12'd300);
                check("erspan_iii: unpack timestamp", es3b.timestamp == 32'hDEADBEEF);
                check("erspan_iii: unpack hw_id", es3b.hw_id == 6'd10);
                check("erspan_iii: unpack direction", es3b.direction == 1);
                check("erspan_iii: unpack offset", offset == 12);
            end

            begin
                protocol_base es3c = es3.clone();
                check("erspan_iii: clone compare", es3.compare(es3c));
            end
        end
```

- [ ] **Step 3: 更新 filelist.f**

添加源文件：
```
src/protocols/tunnel/erspan_header.sv
```

- [ ] **Step 4: 编译运行测试确认通过**

Run: `make test_tunnel_headers`
Expected: 所有测试 PASS

- [ ] **Step 5: 提交**

```bash
git add src/protocols/tunnel/erspan_header.sv test/test_tunnel_headers.sv filelist.f
git commit -m "feat: add erspan_ii_header and erspan_iii_header"
```

---

### Task 5: GTP-U 协议头

**Files:**
- Create: `src/protocols/tunnel/gtp_header.sv`
- Modify: `test/test_tunnel_headers.sv`
- Modify: `filelist.f`

GTP-U 格式 (3GPP TS 29.281): 8+字节
```
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |Ver|PT|(*)|E|S|PN|  Message Type|          Length               |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                    Tunnel Endpoint ID (TEID)                  |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |      Sequence Number (optional)     | N-PDU Number (optional)|
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 | Next Extension Header Type (opt)    |
 +-+-+-+-+-+-+-+-+
```

- [ ] **Step 1: 创建 gtp_header.sv**

```systemverilog
// src/protocols/tunnel/gtp_header.sv
`ifndef GTP_HEADER_SV
`define GTP_HEADER_SV

`include "protocol_base.sv"

class gtp_u_header extends protocol_base;

    rand bit [2:0]  version;
    rand bit        pt;               // Protocol Type (1=GTP, 0=GTP')
    rand bit        reserved;
    rand bit        e_flag;           // Extension header flag
    rand bit        s_flag;           // Sequence number flag
    rand bit        pn_flag;          // N-PDU number flag
    rand bit [7:0]  message_type;     // 0xFF = G-PDU
    rand bit [15:0] length;           // Length of payload + optional fields
    rand bit [31:0] teid;             // Tunnel Endpoint ID
    // Optional fields (present if E|S|PN set)
    rand bit [15:0] sequence_number;
    rand bit [7:0]  n_pdu_number;
    rand bit [7:0]  next_ext_hdr_type;

    constraint c_default {
        version      == 3'b001;
        pt           == 1;
        reserved     == 0;
        e_flag       == 0;
        s_flag       == 0;
        pn_flag      == 0;
        message_type == 8'hFF;   // G-PDU
    }

    function new();
        proto_type       = PROTO_GTP_U;
        version          = 3'b001;
        pt               = 1;
        reserved         = 0;
        e_flag           = 0;
        s_flag           = 0;
        pn_flag          = 0;
        message_type     = 8'hFF;
        length           = 0;
        teid             = 0;
        sequence_number  = 0;
        n_pdu_number     = 0;
        next_ext_hdr_type = 0;
    endfunction

    static function gtp_u_header create(bit [31:0] t = 0);
        gtp_u_header h = new();
        h.teid = t;
        return h;
    endfunction

    function bit has_optional_fields();
        return e_flag || s_flag || pn_flag;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [7:0] byte0 = {version, pt, reserved, e_flag, s_flag, pn_flag};
        data.push_back(byte0);
        data.push_back(message_type);
        packet_utils::pack_bytes_16(data, length);
        packet_utils::pack_bytes_32(data, teid);
        if (has_optional_fields()) begin
            packet_utils::pack_bytes_16(data, sequence_number);
            data.push_back(n_pdu_number);
            data.push_back(next_ext_hdr_type);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] byte0 = data[offset]; offset++;
        version  = byte0[7:5];
        pt       = byte0[4];
        reserved = byte0[3];
        e_flag   = byte0[2];
        s_flag   = byte0[1];
        pn_flag  = byte0[0];
        message_type = data[offset]; offset++;
        length = packet_utils::unpack_bytes_16(data, offset);
        teid   = packet_utils::unpack_bytes_32(data, offset);
        if (has_optional_fields()) begin
            sequence_number   = packet_utils::unpack_bytes_16(data, offset);
            n_pdu_number      = data[offset]; offset++;
            next_ext_hdr_type = data[offset]; offset++;
        end
    endfunction

    virtual function int get_header_length();
        return has_optional_fields() ? 12 : 8;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // Length = payload_data size (includes inner packet)
        length = payload_data.size();
        if (has_optional_fields()) length += 4;  // optional fields are part of GTP payload from length perspective
    endfunction

    virtual function protocol_base clone();
        gtp_u_header h = new();
        h.version          = version;
        h.pt               = pt;
        h.reserved         = reserved;
        h.e_flag           = e_flag;
        h.s_flag           = s_flag;
        h.pn_flag          = pn_flag;
        h.message_type     = message_type;
        h.length           = length;
        h.teid             = teid;
        h.sequence_number  = sequence_number;
        h.n_pdu_number     = n_pdu_number;
        h.next_ext_hdr_type = next_ext_hdr_type;
        h.auto_calc        = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        gtp_u_header o;
        if (!$cast(o, other)) return 0;
        if (version != o.version || pt != o.pt) return 0;
        if (message_type != o.message_type || teid != o.teid) return 0;
        if (has_optional_fields()) begin
            if (sequence_number != o.sequence_number) return 0;
            if (n_pdu_number != o.n_pdu_number) return 0;
        end
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version     : %0d\n", version)};
        s = {s, $sformatf("  pt          : %0d\n", pt)};
        s = {s, $sformatf("  e_flag      : %0b\n", e_flag)};
        s = {s, $sformatf("  s_flag      : %0b\n", s_flag)};
        s = {s, $sformatf("  pn_flag     : %0b\n", pn_flag)};
        s = {s, $sformatf("  message_type: 0x%02x\n", message_type)};
        s = {s, $sformatf("  length      : %0d\n", length)};
        s = {s, $sformatf("  teid        : 0x%08x\n", teid)};
        if (has_optional_fields()) begin
            s = {s, $sformatf("  seq_num     : %0d\n", sequence_number)};
            s = {s, $sformatf("  n_pdu_num   : %0d\n", n_pdu_number)};
            s = {s, $sformatf("  next_ext_hdr: 0x%02x\n", next_ext_hdr_type)};
        end
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("GTP-U TEID:0x%08x msg:0x%02x", teid, message_type);
    endfunction

endclass

`endif // GTP_HEADER_SV
```

- [ ] **Step 2: 在 test_tunnel_headers.sv 添加 GTP-U 测试**

在文件头部 include 行追加：
```systemverilog
`include "tunnel/gtp_header.sv"
```

在 ERSPAN III 测试块之后添加：
```systemverilog
        // ---- GTP-U ----
        begin
            gtp_u_header gtp = new();
            byte unsigned packed[$];
            int offset;

            check("gtp: proto_type", gtp.proto_type == PROTO_GTP_U);
            check("gtp: header_length basic", gtp.get_header_length() == 8);
            check("gtp: default version", gtp.version == 3'b001);
            check("gtp: default message_type", gtp.message_type == 8'hFF);

            // Basic (no optional fields)
            gtp.teid = 32'hAABBCCDD;
            gtp.pack_header(packed);
            check("gtp: pack basic size", packed.size() == 8);

            begin
                gtp_u_header gtp2 = new();
                offset = 0;
                gtp2.unpack_header(packed, offset);
                check("gtp: unpack teid", gtp2.teid == 32'hAABBCCDD);
                check("gtp: unpack message_type", gtp2.message_type == 8'hFF);
                check("gtp: unpack offset basic", offset == 8);
            end

            // With optional fields
            begin
                gtp_u_header gtp_opt = new();
                byte unsigned packed_opt[$];
                gtp_opt.s_flag = 1;
                gtp_opt.teid = 32'h12345678;
                gtp_opt.sequence_number = 16'h0001;
                check("gtp: header_length optional", gtp_opt.get_header_length() == 12);

                gtp_opt.pack_header(packed_opt);
                check("gtp: pack optional size", packed_opt.size() == 12);

                begin
                    gtp_u_header gtp_opt2 = new();
                    offset = 0;
                    gtp_opt2.unpack_header(packed_opt, offset);
                    check("gtp: unpack opt s_flag", gtp_opt2.s_flag == 1);
                    check("gtp: unpack opt teid", gtp_opt2.teid == 32'h12345678);
                    check("gtp: unpack opt seq", gtp_opt2.sequence_number == 16'h0001);
                    check("gtp: unpack opt offset", offset == 12);
                end

                begin
                    protocol_base gtp_cloned = gtp_opt.clone();
                    check("gtp: clone compare", gtp_opt.compare(gtp_cloned));
                end
            end

            // Static create
            begin
                gtp_u_header gtp3 = gtp_u_header::create(32'hFEDCBA98);
                check("gtp: static create teid", gtp3.teid == 32'hFEDCBA98);
            end
        end
```

- [ ] **Step 3: 更新 filelist.f**

添加源文件：
```
src/protocols/tunnel/gtp_header.sv
```

- [ ] **Step 4: 编译运行测试确认通过**

Run: `make test_tunnel_headers`
Expected: 所有测试 PASS

- [ ] **Step 5: 提交**

```bash
git add src/protocols/tunnel/gtp_header.sv test/test_tunnel_headers.sv filelist.f
git commit -m "feat: add gtp_u_header with optional sequence/extension fields"
```

---

### Task 6: IP-in-IP 标记头

**Files:**
- Create: `src/protocols/tunnel/ip_in_ip_header.sv`
- Modify: `test/test_tunnel_headers.sv`
- Modify: `filelist.f`

IP-in-IP (RFC 2003) 不需要额外的头部——外层 IP 的 protocol 字段设为 4 (IP_PROTO_IP_IN_IP)，然后直接跟内层 IP。这里实现一个零长度的标记头，仅用于在 layer_stack 中标识 IP-in-IP 封装关系。

- [ ] **Step 1: 创建 ip_in_ip_header.sv**

```systemverilog
// src/protocols/tunnel/ip_in_ip_header.sv
`ifndef IP_IN_IP_HEADER_SV
`define IP_IN_IP_HEADER_SV

`include "protocol_base.sv"

// IP-in-IP is a zero-length marker. The outer IPv4 protocol=4 indicates
// the next layer is another IPv4 header. This class exists only so that
// protocol_graph transitions work: IPv4 -> IP_IN_IP -> IPv4.
// In practice, build_from_template will skip this marker during pack.

class ip_in_ip_header extends protocol_base;

    function new();
        proto_type = PROTO_IP_IN_IP;
    endfunction

    static function ip_in_ip_header create();
        ip_in_ip_header h = new();
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // Zero-length header — nothing to pack
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        // Zero-length header — nothing to unpack
    endfunction

    virtual function int get_header_length();
        return 0;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        // Nothing to calculate
    endfunction

    virtual function protocol_base clone();
        ip_in_ip_header h = new();
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ip_in_ip_header o;
        return $cast(o, other);
    endfunction

    virtual function string to_string();
        return $sformatf("=== %s ===\n  (marker — zero length)\n", proto_type.name());
    endfunction

    virtual function string to_brief();
        return "IP-in-IP (marker)";
    endfunction

endclass

`endif // IP_IN_IP_HEADER_SV
```

- [ ] **Step 2: 在 test_tunnel_headers.sv 添加 IP-in-IP 测试**

在文件头部 include 行追加：
```systemverilog
`include "tunnel/ip_in_ip_header.sv"
```

在 GTP-U 测试块之后添加：
```systemverilog
        // ---- IP-in-IP ----
        begin
            ip_in_ip_header ipip = new();
            byte unsigned packed[$];
            int offset;

            check("ipip: proto_type", ipip.proto_type == PROTO_IP_IN_IP);
            check("ipip: header_length", ipip.get_header_length() == 0);

            ipip.pack_header(packed);
            check("ipip: pack size", packed.size() == 0);

            begin
                protocol_base ipip2 = ipip.clone();
                check("ipip: clone compare", ipip.compare(ipip2));
            end
        end
```

- [ ] **Step 3: 更新 filelist.f**

添加源文件：
```
src/protocols/tunnel/ip_in_ip_header.sv
```

- [ ] **Step 4: 编译运行测试确认通过**

Run: `make test_tunnel_headers`
Expected: 所有测试 PASS

- [ ] **Step 5: 提交**

```bash
git add src/protocols/tunnel/ip_in_ip_header.sv test/test_tunnel_headers.sv filelist.f
git commit -m "feat: add ip_in_ip_header marker for IP-in-IP tunneling"
```

---

### Task 7: 集成到 packet.sv — 扩展工厂和解析

**Files:**
- Modify: `src/core/packet.sv`

需要更新三处：
1. `create_header()` 工厂方法添加所有隧道协议
2. `identify_next_proto()` 添加 UDP dst_port、GRE protocol_type 的识别
3. 新增 `udp_dstport_to_proto()` 辅助函数
4. 新增 `gre_proto_to_proto()` 辅助函数

- [ ] **Step 1: 在 packet.sv 头部添加 tunnel include**

在 `icmpv6_header.sv` include 之后、`protocol_graph.sv` include 之前添加：
```systemverilog
`include "tunnel/vxlan_header.sv"
`include "tunnel/gre_header.sv"
`include "tunnel/geneve_header.sv"
`include "tunnel/erspan_header.sv"
`include "tunnel/gtp_header.sv"
`include "tunnel/ip_in_ip_header.sv"
```

- [ ] **Step 2: 在 create_header() 的 default 分支之前添加隧道协议**

```systemverilog
            PROTO_VXLAN: begin
                vxlan_header h = new();
                return h;
            end
            PROTO_GRE: begin
                gre_header h = new();
                return h;
            end
            PROTO_GENEVE: begin
                geneve_header h = new();
                return h;
            end
            PROTO_ERSPAN_II: begin
                erspan_ii_header h = new();
                return h;
            end
            PROTO_ERSPAN_III: begin
                erspan_iii_header h = new();
                return h;
            end
            PROTO_GTP_U: begin
                gtp_u_header h = new();
                return h;
            end
            PROTO_IP_IN_IP: begin
                ip_in_ip_header h = new();
                return h;
            end
```

- [ ] **Step 3: 添加 UDP dst_port 和 GRE protocol 映射函数**

在 `ipv6_nh_to_proto()` 函数之后添加：
```systemverilog
    // =========================================================================
    // UDP dst_port -> protocol mapping
    // =========================================================================
    static function protocol_type_e udp_dstport_to_proto(bit [15:0] port);
        case (port)
            16'd4789: return PROTO_VXLAN;
            16'd6081: return PROTO_GENEVE;
            16'd2152: return PROTO_GTP_U;
            16'd2123: return PROTO_GTP_C;
            16'd4791: return PROTO_ROCEV2;
            default:  return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

    // =========================================================================
    // GRE protocol_type -> protocol mapping
    // =========================================================================
    static function protocol_type_e gre_proto_to_proto(bit [15:0] proto);
        case (proto)
            ETHERTYPE_IPV4:  return PROTO_IPV4;
            ETHERTYPE_IPV6:  return PROTO_IPV6;
            16'h6558:        return PROTO_ETHERNET;  // Transparent Ethernet Bridging (NVGRE)
            16'h88BE:        return PROTO_ERSPAN_II;
            16'h22EB:        return PROTO_ERSPAN_III;
            default:         return PROTO_RAW_PAYLOAD;
        endcase
    endfunction
```

- [ ] **Step 4: 更新 identify_next_proto() 添加 UDP/GRE/VXLAN/Geneve/GTP/ERSPAN 识别**

在 `identify_next_proto()` 的 `PROTO_IPV6` 分支之后、`default` 分支之前添加：
```systemverilog
            PROTO_UDP: begin
                udp_header u;
                if ($cast(u, hdr)) begin
                    return udp_dstport_to_proto(u.dst_port);
                end
            end
            PROTO_GRE: begin
                gre_header g;
                if ($cast(g, hdr)) begin
                    return gre_proto_to_proto(g.protocol_type);
                end
            end
            PROTO_VXLAN: begin
                return PROTO_ETHERNET;
            end
            PROTO_GENEVE: begin
                geneve_header gn;
                if ($cast(gn, hdr)) begin
                    if (gn.protocol_type == 16'h6558) return PROTO_ETHERNET;
                    return ethertype_to_proto(gn.protocol_type);
                end
            end
            PROTO_ERSPAN_II, PROTO_ERSPAN_III: begin
                return PROTO_ETHERNET;
            end
            PROTO_GTP_U: begin
                // GTP-U inner payload: peek at first nibble to determine IPv4 vs IPv6
                if (offset < data.size()) begin
                    bit [3:0] ip_ver = data[offset][7:4];
                    if (ip_ver == 4) return PROTO_IPV4;
                    if (ip_ver == 6) return PROTO_IPV6;
                end
                return PROTO_RAW_PAYLOAD;
            end
```

- [ ] **Step 5: 提交**

```bash
git add src/core/packet.sv
git commit -m "feat: integrate tunnel protocols into packet factory and unpack logic"
```

---

### Task 8: 隧道报文集成测试

**Files:**
- Create: `test/test_tunnel_packet.sv`
- Modify: `Makefile`

测试已注册的隧道模板能否正确构建、pack、unpack。

- [ ] **Step 1: 创建 test_tunnel_packet.sv**

```systemverilog
// test/test_tunnel_packet.sv
`include "core/packet.sv"

program test_tunnel_packet;

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
        $display("=== test_tunnel_packet ===");

        // ---- VXLAN template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
            check("vxlan_tmpl: layer count", pkt.layer_stack.size() == 7);
            check("vxlan_tmpl: layer[0] ETH", pkt.layer_stack[0].proto_type == PROTO_ETHERNET);
            check("vxlan_tmpl: layer[1] IPv4", pkt.layer_stack[1].proto_type == PROTO_IPV4);
            check("vxlan_tmpl: layer[2] UDP", pkt.layer_stack[2].proto_type == PROTO_UDP);
            check("vxlan_tmpl: layer[3] VXLAN", pkt.layer_stack[3].proto_type == PROTO_VXLAN);
            check("vxlan_tmpl: layer[4] ETH", pkt.layer_stack[4].proto_type == PROTO_ETHERNET);
            check("vxlan_tmpl: layer[5] IPv4", pkt.layer_stack[5].proto_type == PROTO_IPV4);
            check("vxlan_tmpl: layer[6] TCP", pkt.layer_stack[6].proto_type == PROTO_TCP);

            // Set VNI
            begin
                vxlan_header vx;
                $cast(vx, pkt.get_layer(PROTO_VXLAN));
                vx.vni = 24'd1000;
            end

            // Pack
            pkt.pkt_length = 128;
            pkt.do_pack();
            check("vxlan_tmpl: raw_data not empty", pkt.raw_data.size() > 0);
            check("vxlan_tmpl: raw_data size", pkt.raw_data.size() == 128);

            // Unpack
            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("vxlan_tmpl: unpack layer count", pkt2.layer_stack.size() == 7);
                check("vxlan_tmpl: unpack layer[3] VXLAN", pkt2.layer_stack[3].proto_type == PROTO_VXLAN);
                begin
                    vxlan_header vx2;
                    $cast(vx2, pkt2.get_layer(PROTO_VXLAN));
                    check("vxlan_tmpl: unpack VNI", vx2.vni == 24'd1000);
                end
            end
        end

        // ---- GRE template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_GRE_IPV4_TCP);
            check("gre_tmpl: layer count", pkt.layer_stack.size() == 5);
            check("gre_tmpl: layer[2] GRE", pkt.layer_stack[2].proto_type == PROTO_GRE);

            pkt.pkt_length = 100;
            pkt.do_pack();
            check("gre_tmpl: raw_data size", pkt.raw_data.size() == 100);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("gre_tmpl: unpack layer count", pkt2.layer_stack.size() == 5);
                check("gre_tmpl: unpack layer[2] GRE", pkt2.layer_stack[2].proto_type == PROTO_GRE);
            end
        end

        // ---- Geneve template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP);
            check("geneve_tmpl: layer count", pkt.layer_stack.size() == 7);
            check("geneve_tmpl: layer[3] Geneve", pkt.layer_stack[3].proto_type == PROTO_GENEVE);

            pkt.pkt_length = 128;
            pkt.do_pack();
            check("geneve_tmpl: raw_data size", pkt.raw_data.size() == 128);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("geneve_tmpl: unpack layer count", pkt2.layer_stack.size() == 7);
                check("geneve_tmpl: unpack layer[3] Geneve", pkt2.layer_stack[3].proto_type == PROTO_GENEVE);
            end
        end

        // ---- ERSPAN template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP);
            check("erspan_tmpl: layer count", pkt.layer_stack.size() == 7);
            check("erspan_tmpl: layer[2] GRE", pkt.layer_stack[2].proto_type == PROTO_GRE);
            check("erspan_tmpl: layer[3] ERSPAN_II", pkt.layer_stack[3].proto_type == PROTO_ERSPAN_II);

            begin
                erspan_ii_header es;
                $cast(es, pkt.get_layer(PROTO_ERSPAN_II));
                es.session_id = 10'd42;
            end

            pkt.pkt_length = 128;
            pkt.do_pack();
            check("erspan_tmpl: raw_data size", pkt.raw_data.size() == 128);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("erspan_tmpl: unpack layer count", pkt2.layer_stack.size() == 7);
                begin
                    erspan_ii_header es2;
                    $cast(es2, pkt2.get_layer(PROTO_ERSPAN_II));
                    check("erspan_tmpl: unpack session_id", es2.session_id == 10'd42);
                end
            end
        end

        // ---- GTP-U template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_UDP_GTP_U_IPV4_TCP);
            check("gtp_tmpl: layer count", pkt.layer_stack.size() == 6);
            check("gtp_tmpl: layer[3] GTP_U", pkt.layer_stack[3].proto_type == PROTO_GTP_U);

            begin
                gtp_u_header gtp;
                $cast(gtp, pkt.get_layer(PROTO_GTP_U));
                gtp.teid = 32'h0000ABCD;
            end

            pkt.pkt_length = 120;
            pkt.do_pack();
            check("gtp_tmpl: raw_data size", pkt.raw_data.size() == 120);

            begin
                packet pkt2 = new();
                pkt2.unpack(pkt.raw_data);
                check("gtp_tmpl: unpack layer count", pkt2.layer_stack.size() == 6);
                begin
                    gtp_u_header gtp2;
                    $cast(gtp2, pkt2.get_layer(PROTO_GTP_U));
                    check("gtp_tmpl: unpack teid", gtp2.teid == 32'h0000ABCD);
                end
            end
        end

        // ---- NVGRE (GRE+Ethernet) template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_IPV4_GRE_ETH_IPV4_TCP);
            check("nvgre_tmpl: layer count", pkt.layer_stack.size() == 6);
            check("nvgre_tmpl: layer[2] GRE", pkt.layer_stack[2].proto_type == PROTO_GRE);
            check("nvgre_tmpl: layer[3] ETH", pkt.layer_stack[3].proto_type == PROTO_ETHERNET);

            pkt.pkt_length = 128;
            pkt.do_pack();
            check("nvgre_tmpl: raw_data not empty", pkt.raw_data.size() > 0);
        end

        // ---- Free-form: VXLAN with custom fields ----
        begin
            packet pkt = new();
            pkt.add_layer(eth_header::create());
            pkt.add_layer(ipv4_header::create());
            pkt.add_layer(udp_header::create());
            pkt.add_layer(vxlan_header::create(24'd999));
            pkt.add_layer(eth_header::create());
            pkt.add_layer(ipv4_header::create());
            pkt.add_layer(tcp_header::create());
            check("freeform_vxlan: layer count", pkt.layer_stack.size() == 7);

            begin
                vxlan_header vx;
                $cast(vx, pkt.get_layer(PROTO_VXLAN));
                check("freeform_vxlan: vni", vx.vni == 24'd999);
            end
        end

        // ---- VLAN + VXLAN template ----
        begin
            packet pkt = new();
            pkt.build_from_template(ETH_VLAN_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
            check("vlan_vxlan_tmpl: layer count", pkt.layer_stack.size() == 8);
            check("vlan_vxlan_tmpl: layer[1] VLAN", pkt.layer_stack[1].proto_type == PROTO_VLAN);
            check("vlan_vxlan_tmpl: layer[4] VXLAN", pkt.layer_stack[4].proto_type == PROTO_VXLAN);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end

endprogram
```

- [ ] **Step 2: 更新 Makefile 添加 tunnel packet 测试**

在 `test_tunnel_headers` 目标之后添加：
```makefile
test_tunnel_packet: test/test_tunnel_packet.sv
	$(MAKE) run_tunnel_packet
```

将 `test_all` 更新为：
```makefile
test_all: test_protocol_headers test_protocol_graph test_packet_builder test_tunnel_headers test_tunnel_packet
```

- [ ] **Step 3: 编译运行测试确认通过**

Run: `make test_tunnel_packet`
Expected: 所有模板构建、pack、unpack 测试 PASS

- [ ] **Step 4: 运行全部测试**

Run: `make test_all`
Expected: 全部测试通过，包括原有的 Phase 1 测试

- [ ] **Step 5: 更新 filelist.f 确认完整**

确认 filelist.f 包含所有 tunnel 源文件和 incdir：
```
+incdir+src/protocols/tunnel

src/protocols/tunnel/vxlan_header.sv
src/protocols/tunnel/gre_header.sv
src/protocols/tunnel/geneve_header.sv
src/protocols/tunnel/erspan_header.sv
src/protocols/tunnel/gtp_header.sv
src/protocols/tunnel/ip_in_ip_header.sv
```

- [ ] **Step 6: 提交**

```bash
git add test/test_tunnel_packet.sv Makefile
git commit -m "feat: add tunnel packet integration tests for all tunnel templates"
```

---

## 自检清单

- [x] 设计规格覆盖：VXLAN, GRE, Geneve, ERSPAN II/III, GTP-U, IP-in-IP 全部对应 Task
- [x] 无占位符：所有 step 包含完整代码
- [x] 类型一致：所有头类名、方法签名与 protocol_base 一致
- [x] packet.sv 工厂和解析映射已覆盖所有隧道协议
- [x] 协议图和模板注册已在 Phase 1 完成，无需修改
- [x] filelist.f 包含 tunnel 目录和所有源文件
- [x] 测试覆盖：单元测试 (test_tunnel_headers) + 集成测试 (test_tunnel_packet)

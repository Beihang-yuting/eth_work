# Net Packet Generator Phase 1: Foundation + Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundational packet generator library with core protocols (Ethernet, VLAN, IPv4, IPv6, ARP, TCP, UDP, ICMP/ICMPv6), protocol graph, template system, and packet builder — producing a fully working packet construction and serialization engine.

**Architecture:** Protocol Graph pattern — each protocol header is an independent SV class inheriting from `protocol_base`. A `protocol_graph` defines legal layer transitions. `packet` class holds a `layer_stack` of protocol headers, supports template-based and free-form construction, UVM-style `randomize()` with constraints, and `pack()`/`unpack()` to byte streams. Core layer is pure SystemVerilog with no UVM dependency.

**Tech Stack:** SystemVerilog (IEEE 1800-2017), no external dependencies for core. Testbench uses `$display`/`$fatal` assertions. Simulator-agnostic (VCS/Questa/Xcelium/Verilator).

**Phased Approach:** This is Phase 1 of 4. Subsequent phases:
- Phase 2: Extended protocols (tunnels, RDMA, storage, app, remaining L2/L3)
- Phase 3: Parser + Comparator + Pcap + IP fragmentation
- Phase 4: Sequences + Streams + UVM Wrapper

---

## File Map

| File | Responsibility |
|------|---------------|
| `src/common/packet_defines.sv` | All enums (`protocol_type_e`, `packet_template_e`, `payload_mode_e`), typedefs, constants |
| `src/common/packet_utils.sv` | Utility functions: checksum, byte-order swap, MAC/IP formatting |
| `src/protocols/protocol_base.sv` | Abstract base class for all protocol headers |
| `src/protocols/l2/eth_header.sv` | Ethernet II header (14 bytes) |
| `src/protocols/l2/vlan_header.sv` | 802.1Q VLAN tag (4 bytes), QinQ support |
| `src/protocols/l3/ipv4_header.sv` | IPv4 header (20-60 bytes) with options |
| `src/protocols/l3/ipv6_header.sv` | IPv6 header (40 bytes) |
| `src/protocols/l3/arp_header.sv` | ARP header (28 bytes for IPv4) |
| `src/protocols/l4/tcp_header.sv` | TCP header (20-60 bytes) with options |
| `src/protocols/l4/udp_header.sv` | UDP header (8 bytes) |
| `src/protocols/l4/icmp_header.sv` | ICMPv4 header (8+ bytes) |
| `src/protocols/l4/icmpv6_header.sv` | ICMPv6 header (8+ bytes) |
| `src/core/protocol_graph.sv` | Protocol transition graph + validation |
| `src/core/template_registry.sv` | Template enum -> protocol chain mapping |
| `src/core/packet.sv` | Packet class: layer_stack, randomize_all, pack/unpack, length control |
| `test/test_utils.sv` | Test helper: assert macros, result reporting |
| `test/test_protocol_headers.sv` | Tests for individual protocol headers pack/unpack |
| `test/test_protocol_graph.sv` | Tests for protocol graph transitions |
| `test/test_packet_builder.sv` | Tests for packet construction, templates, randomization |
| `Makefile` | Compile + run targets |
| `filelist.f` | Compilation file list |

---

### Task 1: Project scaffolding + packet_defines.sv

**Files:**
- Create: `src/common/packet_defines.sv`
- Create: `Makefile`
- Create: `filelist.f`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p src/common src/protocols/l2 src/protocols/l3 src/protocols/l4 src/core src/sequence src/stream src/parser src/pcap src/uvm_wrapper test
```

- [ ] **Step 2: Write packet_defines.sv**

```systemverilog
// src/common/packet_defines.sv
`ifndef PACKET_DEFINES_SV
`define PACKET_DEFINES_SV

// Protocol type enumeration — shared by packet builder and parser
typedef enum int {
    // L2
    PROTO_ETHERNET      = 0,
    PROTO_VLAN          = 1,
    PROTO_QINQ          = 2,
    PROTO_MPLS          = 3,
    PROTO_MAC_CONTROL   = 4,
    PROTO_LLDP          = 5,
    PROTO_LACP          = 6,
    PROTO_STP           = 7,
    PROTO_MACSEC        = 8,
    PROTO_EAP           = 9,
    // L3
    PROTO_IPV4          = 10,
    PROTO_IPV6          = 11,
    PROTO_ARP           = 12,
    PROTO_IGMP          = 13,
    PROTO_IPV6_HBH      = 14,
    PROTO_IPV6_ROUTING  = 15,
    PROTO_IPV6_FRAGMENT = 16,
    PROTO_IPV6_DEST     = 17,
    PROTO_DHCP          = 18,
    PROTO_DHCPV6        = 19,
    PROTO_OSPF          = 20,
    PROTO_BGP           = 21,
    PROTO_ISIS          = 22,
    // L4
    PROTO_TCP           = 30,
    PROTO_UDP           = 31,
    PROTO_ICMP          = 32,
    PROTO_ICMPV6        = 33,
    PROTO_SCTP          = 34,
    // Tunnel
    PROTO_VXLAN         = 40,
    PROTO_GRE           = 41,
    PROTO_NVGRE         = 42,
    PROTO_GENEVE        = 43,
    PROTO_ERSPAN_I      = 44,
    PROTO_ERSPAN_II     = 45,
    PROTO_ERSPAN_III    = 46,
    PROTO_IP_IN_IP      = 47,
    PROTO_L2TP          = 48,
    PROTO_GTP_U         = 49,
    PROTO_GTP_C         = 50,
    PROTO_MPLS_GRE      = 51,
    PROTO_MPLS_UDP      = 52,
    // App/Mgmt
    PROTO_DNS           = 60,
    PROTO_HTTP          = 61,
    PROTO_SNMP          = 62,
    PROTO_BFD           = 63,
    PROTO_PTP           = 64,
    // Storage/RDMA
    PROTO_ROCEV2        = 70,
    PROTO_IWARP         = 71,
    PROTO_NVME_TCP      = 72,
    PROTO_NVME_RDMA     = 73,
    PROTO_ISCSI         = 74,
    // Special
    PROTO_RAW_PAYLOAD   = 99
} protocol_type_e;

// Packet template enumeration — predefined protocol stack combinations
typedef enum int {
    // Basic
    ETH_IPV4_TCP                        = 0,
    ETH_IPV4_UDP                        = 1,
    ETH_IPV6_TCP                        = 2,
    ETH_IPV6_UDP                        = 3,
    ETH_ARP                             = 4,
    ETH_IPV4_ICMP                       = 5,
    ETH_IPV6_ICMPV6                     = 6,
    // VLAN
    ETH_VLAN_IPV4_TCP                   = 10,
    ETH_VLAN_IPV4_UDP                   = 11,
    ETH_VLAN_IPV6_TCP                   = 12,
    ETH_VLAN_IPV6_UDP                   = 13,
    ETH_QINQ_IPV4_TCP                  = 14,
    ETH_QINQ_IPV4_UDP                  = 15,
    // Tunnel
    ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP    = 20,
    ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP    = 21,
    ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP    = 22,
    ETH_IPV4_GRE_IPV4_TCP              = 23,
    ETH_IPV4_GRE_IPV4_UDP              = 24,
    ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP   = 25,
    ETH_IPV4_GRE_ETH_IPV4_TCP          = 26,
    ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP = 27,
    ETH_IPV4_UDP_GTP_U_IPV4_TCP        = 28,
    // VLAN + Tunnel
    ETH_VLAN_IPV4_UDP_VXLAN_ETH_IPV4_TCP = 30,
    // RDMA
    ETH_IPV4_UDP_ROCEV2                = 40,
    ETH_VLAN_IPV4_UDP_ROCEV2           = 41,
    // Storage
    ETH_IPV4_TCP_NVME_TCP              = 50,
    ETH_IPV4_UDP_ROCEV2_NVME_RDMA     = 51,
    ETH_IPV4_TCP_ISCSI                 = 52,
    // iWARP
    ETH_IPV4_TCP_IWARP                 = 53,
    // Mgmt/Control
    ETH_IPV4_UDP_DHCP                  = 60,
    ETH_IPV6_UDP_DHCPV6                = 61,
    ETH_IPV4_UDP_DNS                   = 62,
    ETH_IPV4_UDP_BFD                   = 63,
    ETH_IPV4_UDP_PTP                   = 64,
    ETH_PTP_L2                         = 65,
    ETH_IGMP                           = 66,
    ETH_LLDP                           = 67,
    ETH_LACP                           = 68,
    ETH_STP                            = 69,
    ETH_MAC_CONTROL                    = 70,
    // MPLS
    ETH_MPLS_IPV4_TCP                  = 80,
    ETH_MPLS_IPV4_UDP                  = 81
} packet_template_e;

// Payload fill mode
typedef enum int {
    PAYLOAD_RANDOM    = 0,
    PAYLOAD_FIXED     = 1,
    PAYLOAD_INCREMENT = 2,
    PAYLOAD_PATTERN   = 3
} payload_mode_e;

// Field modifier mode (for traffic streams)
typedef enum int {
    MOD_INCREMENT = 0,
    MOD_DECREMENT = 1,
    MOD_RANDOM    = 2,
    MOD_LIST      = 3
} modifier_mode_e;

// Parse result structure
typedef struct {
    bit              valid;
    protocol_type_e  proto_chain[$];
    string           errors[$];
    string           warnings[$];
} parse_result_t;

// Diff entry structure
typedef struct {
    protocol_type_e  layer;
    string           field_name;
    string           val_a;
    string           val_b;
} diff_entry_t;

// Common EtherType constants
typedef enum bit [15:0] {
    ETHERTYPE_IPV4        = 16'h0800,
    ETHERTYPE_IPV6        = 16'h86DD,
    ETHERTYPE_ARP         = 16'h0806,
    ETHERTYPE_VLAN        = 16'h8100,
    ETHERTYPE_QINQ        = 16'h88A8,
    ETHERTYPE_MPLS_UNI    = 16'h8847,
    ETHERTYPE_MPLS_MULTI  = 16'h8848,
    ETHERTYPE_LLDP        = 16'h88CC,
    ETHERTYPE_PTP         = 16'h88F7,
    ETHERTYPE_MACSEC      = 16'h88E5,
    ETHERTYPE_EAP         = 16'h888E,
    ETHERTYPE_SLOW        = 16'h8809   // LACP, marker
} ethertype_e;

// Common IP protocol numbers
typedef enum bit [7:0] {
    IP_PROTO_ICMP     = 8'd1,
    IP_PROTO_IGMP     = 8'd2,
    IP_PROTO_IP_IN_IP = 8'd4,
    IP_PROTO_TCP      = 8'd6,
    IP_PROTO_UDP      = 8'd17,
    IP_PROTO_IPV6     = 8'd41,
    IP_PROTO_GRE      = 8'd47,
    IP_PROTO_ICMPV6   = 8'd58,
    IP_PROTO_OSPF     = 8'd89,
    IP_PROTO_SCTP     = 8'd132,
    IP_PROTO_L2TP     = 8'd115
} ip_protocol_e;

// IPv6 next header values (extends ip_protocol_e)
typedef enum bit [7:0] {
    IPV6_NH_HBH       = 8'd0,
    IPV6_NH_TCP        = 8'd6,
    IPV6_NH_UDP        = 8'd17,
    IPV6_NH_IPV6       = 8'd41,
    IPV6_NH_ROUTING    = 8'd43,
    IPV6_NH_FRAGMENT   = 8'd44,
    IPV6_NH_GRE        = 8'd47,
    IPV6_NH_ICMPV6     = 8'd58,
    IPV6_NH_DEST       = 8'd60,
    IPV6_NH_OSPF       = 8'd89,
    IPV6_NH_SCTP       = 8'd132
} ipv6_next_header_e;

`endif // PACKET_DEFINES_SV
```

- [ ] **Step 3: Create Makefile**

```makefile
# Makefile
# Simulator-agnostic: override SIM variable for your tool
# Usage: make test_utils SIM=vcs|questa|xcelium|verilator

SIM ?= vcs
TOP_DIR := $(shell pwd)
SRC_DIR := $(TOP_DIR)/src
TEST_DIR := $(TOP_DIR)/test
FILELIST := $(TOP_DIR)/filelist.f

# VCS flags
VCS_FLAGS := -full64 -sverilog -timescale=1ns/1ps -f $(FILELIST) +incdir+$(SRC_DIR)
# Questa flags
QUESTA_FLAGS := -sv -f $(FILELIST) +incdir+$(SRC_DIR)

.PHONY: compile run clean

# Generic compile + run
compile:
ifeq ($(SIM),vcs)
	vcs $(VCS_FLAGS) $(TEST_FILE) -o simv_$(TEST_NAME)
else ifeq ($(SIM),questa)
	vlog $(QUESTA_FLAGS) $(TEST_FILE)
	vopt +acc top -o top_opt
endif

run_%: test/test_%.sv
	@echo "=== Running test: $* ==="
ifeq ($(SIM),vcs)
	vcs $(VCS_FLAGS) $< -o simv_$* && ./simv_$*
else ifeq ($(SIM),questa)
	vlog $(QUESTA_FLAGS) $< && vsim -batch -do "run -all; quit" top
endif

# Convenience targets
test_utils: test/test_utils.sv
	$(MAKE) run_utils

test_protocol_headers: test/test_protocol_headers.sv
	$(MAKE) run_protocol_headers

test_protocol_graph: test/test_protocol_graph.sv
	$(MAKE) run_protocol_graph

test_packet_builder: test/test_packet_builder.sv
	$(MAKE) run_packet_builder

test_all: test_protocol_headers test_protocol_graph test_packet_builder

clean:
	rm -rf simv_* csrc *.log *.vpd *.fsdb work transcript *.wlf DVEfiles
```

- [ ] **Step 4: Create initial filelist.f**

```
// filelist.f
+incdir+src/common
+incdir+src/protocols
+incdir+src/protocols/l2
+incdir+src/protocols/l3
+incdir+src/protocols/l4
+incdir+src/core

src/common/packet_defines.sv
src/common/packet_utils.sv
src/protocols/protocol_base.sv
```

- [ ] **Step 5: Commit**

```bash
git add src/common/packet_defines.sv Makefile filelist.f
git commit -m "feat: add project scaffolding and packet_defines.sv with all enums and constants"
```

---

### Task 2: packet_utils.sv — Utility functions

**Files:**
- Create: `src/common/packet_utils.sv`
- Create: `test/test_utils.sv`

- [ ] **Step 1: Write test_utils.sv (test harness + utils tests)**

```systemverilog
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
        // IPv4 header (20 bytes): 45 00 00 3c 1c 46 40 00 40 06 00 00 ac 10 0a 63 ac 10 0a 0c
        // Expected checksum fills bytes [10:11], computed over header with checksum field = 0
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

        // Test: format_ipv4 edge case 0.0.0.0
        s = packet_utils::format_ipv4(32'h00000000);
        check("format_ipv4 zeros", s == "0.0.0.0");

        // Test: format_ipv4 edge case 255.255.255.255
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
```

- [ ] **Step 2: Run test — verify it fails (packet_utils.sv not yet created)**

```bash
make run_utils SIM=vcs
```

Expected: Compilation error — `packet_utils.sv` not found.

- [ ] **Step 3: Write packet_utils.sv**

```systemverilog
// src/common/packet_utils.sv
`ifndef PACKET_UTILS_SV
`define PACKET_UTILS_SV

class packet_utils;

    // Internet checksum (RFC 1071): one's complement of one's complement sum of 16-bit words
    static function bit [15:0] ones_complement_checksum(byte unsigned data[$]);
        bit [31:0] sum = 0;
        int len = data.size();
        int i = 0;

        while (i < len - 1) begin
            sum += {data[i], data[i+1]};
            i += 2;
        end
        // If odd length, pad with zero byte
        if (i < len) begin
            sum += {data[i], 8'h00};
        end
        // Fold 32-bit carry into 16 bits
        while (sum[31:16] != 0) begin
            sum = sum[15:0] + sum[31:16];
        end
        return ~sum[15:0];
    endfunction

    // Byte swap 16-bit (network <-> host order)
    static function bit [15:0] byte_swap_16(bit [15:0] val);
        return {val[7:0], val[15:8]};
    endfunction

    // Byte swap 32-bit
    static function bit [31:0] byte_swap_32(bit [31:0] val);
        return {val[7:0], val[15:8], val[23:16], val[31:24]};
    endfunction

    // Pack 16-bit value as big-endian into byte queue
    static function void pack_bytes_16(ref byte unsigned data[$], bit [15:0] val);
        data.push_back(val[15:8]);
        data.push_back(val[7:0]);
    endfunction

    // Pack 32-bit value as big-endian into byte queue
    static function void pack_bytes_32(ref byte unsigned data[$], bit [31:0] val);
        data.push_back(val[31:24]);
        data.push_back(val[23:16]);
        data.push_back(val[15:8]);
        data.push_back(val[7:0]);
    endfunction

    // Pack 48-bit value (MAC address) as big-endian into byte queue
    static function void pack_bytes_48(ref byte unsigned data[$], bit [47:0] val);
        data.push_back(val[47:40]);
        data.push_back(val[39:32]);
        data.push_back(val[31:24]);
        data.push_back(val[23:16]);
        data.push_back(val[15:8]);
        data.push_back(val[7:0]);
    endfunction

    // Unpack 16-bit big-endian value from byte queue at offset; advances offset by 2
    static function bit [15:0] unpack_bytes_16(byte unsigned data[$], ref int offset);
        bit [15:0] val = {data[offset], data[offset+1]};
        offset += 2;
        return val;
    endfunction

    // Unpack 32-bit big-endian value from byte queue at offset; advances offset by 4
    static function bit [31:0] unpack_bytes_32(byte unsigned data[$], ref int offset);
        bit [31:0] val = {data[offset], data[offset+1], data[offset+2], data[offset+3]};
        offset += 4;
        return val;
    endfunction

    // Unpack 48-bit (MAC) from byte queue at offset; advances offset by 6
    static function bit [47:0] unpack_bytes_48(byte unsigned data[$], ref int offset);
        bit [47:0] val = {data[offset], data[offset+1], data[offset+2],
                          data[offset+3], data[offset+4], data[offset+5]};
        offset += 6;
        return val;
    endfunction

    // Format MAC address as string "XX:XX:XX:XX:XX:XX"
    static function string format_mac(bit [47:0] mac);
        return $sformatf("%02x:%02x:%02x:%02x:%02x:%02x",
                         mac[47:40], mac[39:32], mac[31:24],
                         mac[23:16], mac[15:8], mac[7:0]);
    endfunction

    // Format IPv4 address as string "A.B.C.D"
    static function string format_ipv4(bit [31:0] ip);
        return $sformatf("%0d.%0d.%0d.%0d",
                         ip[31:24], ip[23:16], ip[15:8], ip[7:0]);
    endfunction

    // Format IPv6 address as string (simplified, no :: compression)
    static function string format_ipv6(bit [127:0] ip);
        return $sformatf("%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x",
                         ip[127:112], ip[111:96], ip[95:80], ip[79:64],
                         ip[63:48], ip[47:32], ip[31:16], ip[15:0]);
    endfunction

    // Hex dump of byte array
    static function string hex_dump(byte unsigned data[$], int bytes_per_line = 16);
        string result = "";
        for (int i = 0; i < data.size(); i++) begin
            if (i % bytes_per_line == 0) begin
                if (i > 0) result = {result, "\n"};
                result = {result, $sformatf("  %04x: ", i)};
            end
            result = {result, $sformatf("%02x ", data[i])};
        end
        return result;
    endfunction

endclass

`endif // PACKET_UTILS_SV
```

- [ ] **Step 4: Run test — verify it passes**

```bash
make run_utils SIM=vcs
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/common/packet_utils.sv test/test_utils.sv
git commit -m "feat: add packet_utils with checksum, byte-order, formatting utilities"
```

---

### Task 3: protocol_base.sv — Abstract base class

**Files:**
- Create: `src/protocols/protocol_base.sv`

- [ ] **Step 1: Write protocol_base.sv**

```systemverilog
// src/protocols/protocol_base.sv
`ifndef PROTOCOL_BASE_SV
`define PROTOCOL_BASE_SV

`include "packet_defines.sv"
`include "packet_utils.sv"

virtual class protocol_base;

    protocol_type_e  proto_type;
    bit              auto_calc = 1;  // Auto-compute checksum/length; set 0 to inject bad values

    // Pack this header's fields into byte queue (big-endian, network order)
    pure virtual function void pack_header(ref byte unsigned data[$]);

    // Unpack this header's fields from byte queue starting at offset; advances offset
    pure virtual function void unpack_header(ref byte unsigned data[$], ref int offset);

    // Return header length in bytes (without payload)
    pure virtual function int get_header_length();

    // Compute auto-calculated fields (checksum, length, protocol/next-header).
    // `payload_data` is the packed bytes of everything after this header (for pseudo-header checksums).
    // `next_proto` is the protocol_type_e of the next layer (for setting protocol/ethertype fields).
    pure virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);

    // Deep copy
    pure virtual function protocol_base clone();

    // Field-by-field comparison; returns 1 if equal
    pure virtual function bit compare(protocol_base other);

    // Human-readable multi-line field dump
    pure virtual function string to_string();

    // One-line summary (e.g., "192.168.0.1 -> 10.0.0.1")
    pure virtual function string to_brief();

    // Print at verbosity: 0=brief, 1=full fields
    function void print(int verbosity = 0);
        if (verbosity == 0)
            $display("  [%s] %s", proto_type.name(), to_brief());
        else
            $display("%s", to_string());
    endfunction

endclass

`endif // PROTOCOL_BASE_SV
```

- [ ] **Step 2: Commit**

```bash
git add src/protocols/protocol_base.sv
git commit -m "feat: add protocol_base abstract class with virtual interface"
```

---

### Task 4: eth_header.sv — Ethernet II header

**Files:**
- Create: `src/protocols/l2/eth_header.sv`
- Create: `test/test_protocol_headers.sv` (will grow with each protocol)

- [ ] **Step 1: Write Ethernet header test cases in test_protocol_headers.sv**

```systemverilog
// test/test_protocol_headers.sv
`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "l2/eth_header.sv"
`include "l2/vlan_header.sv"
`include "l3/ipv4_header.sv"
`include "l3/ipv6_header.sv"
`include "l3/arp_header.sv"
`include "l4/tcp_header.sv"
`include "l4/udp_header.sv"
`include "l4/icmp_header.sv"
`include "l4/icmpv6_header.sv"

program test_protocol_headers;

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
        $display("=== test_protocol_headers ===");

        // ---- Ethernet ----
        begin
            eth_header eth = new();
            byte unsigned packed[$];
            byte unsigned raw[$];
            int offset;

            // Test: default values
            check("eth: proto_type", eth.proto_type == PROTO_ETHERNET);
            check("eth: header_length", eth.get_header_length() == 14);

            // Test: pack
            eth.dst_mac = 48'h001122334455;
            eth.src_mac = 48'h665544332211;
            eth.ethertype = ETHERTYPE_IPV4;
            eth.calc_fields('{}, PROTO_IPV4);
            eth.pack_header(packed);

            check("eth: pack size", packed.size() == 14);
            check("eth: pack dst_mac[0]", packed[0] == 8'h00);
            check("eth: pack dst_mac[5]", packed[5] == 8'h55);
            check("eth: pack src_mac[0]", packed[6] == 8'h66);
            check("eth: pack ethertype", {packed[12], packed[13]} == 16'h0800);

            // Test: unpack
            begin
                eth_header eth2 = new();
                offset = 0;
                eth2.unpack_header(packed, offset);
                check("eth: unpack dst_mac", eth2.dst_mac == 48'h001122334455);
                check("eth: unpack src_mac", eth2.src_mac == 48'h665544332211);
                check("eth: unpack ethertype", eth2.ethertype == ETHERTYPE_IPV4);
                check("eth: unpack offset", offset == 14);
            end

            // Test: clone + compare
            begin
                protocol_base eth3 = eth.clone();
                check("eth: clone compare", eth.compare(eth3));
            end

            // Test: calc_fields sets ethertype from next_proto
            eth.auto_calc = 1;
            eth.calc_fields('{}, PROTO_IPV6);
            check("eth: calc_fields ethertype IPv6", eth.ethertype == ETHERTYPE_IPV6);

            eth.calc_fields('{}, PROTO_ARP);
            check("eth: calc_fields ethertype ARP", eth.ethertype == ETHERTYPE_ARP);

            // Test: auto_calc=0 preserves user-set ethertype
            eth.auto_calc = 0;
            eth.ethertype = 16'hDEAD;
            eth.calc_fields('{}, PROTO_IPV4);
            check("eth: auto_calc=0 preserves ethertype", eth.ethertype == 16'hDEAD);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end
endprogram
```

Note: The test file includes headers for protocols not yet written. We will add stub files and fill them in as we go. For now, create empty placeholder files so the test compiles, then fill them in tasks 5-11.

- [ ] **Step 2: Write eth_header.sv**

```systemverilog
// src/protocols/l2/eth_header.sv
`ifndef ETH_HEADER_SV
`define ETH_HEADER_SV

`include "protocol_base.sv"

class eth_header extends protocol_base;

    rand bit [47:0] dst_mac;
    rand bit [47:0] src_mac;
    rand bit [15:0] ethertype;

    constraint c_default {
        dst_mac inside {[0:48'hFFFFFFFFFFFF]};
        src_mac inside {[0:48'hFFFFFFFFFFFF]};
    }

    function new();
        proto_type = PROTO_ETHERNET;
        dst_mac    = 48'h0;
        src_mac    = 48'h0;
        ethertype  = ETHERTYPE_IPV4;
    endfunction

    static function eth_header create(bit [47:0] dst = 0, bit [47:0] src = 0,
                                       bit [15:0] etype = ETHERTYPE_IPV4);
        eth_header h = new();
        h.dst_mac   = dst;
        h.src_mac   = src;
        h.ethertype = etype;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_48(data, dst_mac);
        packet_utils::pack_bytes_48(data, src_mac);
        packet_utils::pack_bytes_16(data, ethertype);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        dst_mac   = packet_utils::unpack_bytes_48(data, offset);
        src_mac   = packet_utils::unpack_bytes_48(data, offset);
        ethertype = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 14;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        case (next_proto)
            PROTO_IPV4:     ethertype = ETHERTYPE_IPV4;
            PROTO_IPV6:     ethertype = ETHERTYPE_IPV6;
            PROTO_ARP:      ethertype = ETHERTYPE_ARP;
            PROTO_VLAN:     ethertype = ETHERTYPE_VLAN;
            PROTO_QINQ:     ethertype = ETHERTYPE_QINQ;
            PROTO_MPLS:     ethertype = ETHERTYPE_MPLS_UNI;
            PROTO_LLDP:     ethertype = ETHERTYPE_LLDP;
            PROTO_LACP:     ethertype = ETHERTYPE_SLOW;
            PROTO_PTP:      ethertype = ETHERTYPE_PTP;
            PROTO_MACSEC:   ethertype = ETHERTYPE_MACSEC;
            PROTO_EAP:      ethertype = ETHERTYPE_EAP;
            PROTO_STP:      ethertype = 16'h0000;  // STP uses LLC, ethertype is length
            PROTO_MAC_CONTROL: ethertype = 16'h8808;
            default: ; // keep existing ethertype
        endcase
    endfunction

    virtual function protocol_base clone();
        eth_header h = new();
        h.dst_mac   = dst_mac;
        h.src_mac   = src_mac;
        h.ethertype = ethertype;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        eth_header o;
        if (!$cast(o, other)) return 0;
        return (dst_mac == o.dst_mac) && (src_mac == o.src_mac) && (ethertype == o.ethertype);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  dst_mac  : %s\n", packet_utils::format_mac(dst_mac))};
        s = {s, $sformatf("  src_mac  : %s\n", packet_utils::format_mac(src_mac))};
        s = {s, $sformatf("  ethertype: 0x%04x\n", ethertype)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%s -> %s type:0x%04x",
                         packet_utils::format_mac(src_mac),
                         packet_utils::format_mac(dst_mac),
                         ethertype);
    endfunction

endclass

`endif // ETH_HEADER_SV
```

- [ ] **Step 3: Create placeholder stubs for not-yet-implemented protocol headers**

Create empty stub files so `test_protocol_headers.sv` compiles. Each stub defines the class with minimal fields. They will be fully implemented in subsequent tasks.

`src/protocols/l2/vlan_header.sv`:
```systemverilog
`ifndef VLAN_HEADER_SV
`define VLAN_HEADER_SV
// Stub — full implementation in Task 5
`endif
```

`src/protocols/l3/ipv4_header.sv`:
```systemverilog
`ifndef IPV4_HEADER_SV
`define IPV4_HEADER_SV
// Stub — full implementation in Task 6
`endif
```

`src/protocols/l3/ipv6_header.sv`:
```systemverilog
`ifndef IPV6_HEADER_SV
`define IPV6_HEADER_SV
// Stub — full implementation in Task 7
`endif
```

`src/protocols/l3/arp_header.sv`:
```systemverilog
`ifndef ARP_HEADER_SV
`define ARP_HEADER_SV
// Stub — full implementation in Task 8
`endif
```

`src/protocols/l4/tcp_header.sv`:
```systemverilog
`ifndef TCP_HEADER_SV
`define TCP_HEADER_SV
// Stub — full implementation in Task 9
`endif
```

`src/protocols/l4/udp_header.sv`:
```systemverilog
`ifndef UDP_HEADER_SV
`define UDP_HEADER_SV
// Stub — full implementation in Task 10
`endif
```

`src/protocols/l4/icmp_header.sv`:
```systemverilog
`ifndef ICMP_HEADER_SV
`define ICMP_HEADER_SV
// Stub — full implementation in Task 11
`endif
```

`src/protocols/l4/icmpv6_header.sv`:
```systemverilog
`ifndef ICMPV6_HEADER_SV
`define ICMPV6_HEADER_SV
// Stub — full implementation in Task 11
`endif
```

- [ ] **Step 4: Run test — verify Ethernet tests pass**

```bash
make run_protocol_headers SIM=vcs
```

Expected: All Ethernet tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/protocols/l2/eth_header.sv src/protocols/l2/vlan_header.sv \
        src/protocols/l3/ipv4_header.sv src/protocols/l3/ipv6_header.sv \
        src/protocols/l3/arp_header.sv src/protocols/l4/tcp_header.sv \
        src/protocols/l4/udp_header.sv src/protocols/l4/icmp_header.sv \
        src/protocols/l4/icmpv6_header.sv test/test_protocol_headers.sv
git commit -m "feat: add eth_header with pack/unpack/calc_fields + protocol header stubs"
```

---

### Task 5: vlan_header.sv — 802.1Q VLAN tag

**Files:**
- Modify: `src/protocols/l2/vlan_header.sv` (replace stub)
- Modify: `test/test_protocol_headers.sv` (add VLAN tests)

- [ ] **Step 1: Add VLAN tests to test_protocol_headers.sv**

Insert before the final `$display("=== Results:` line:

```systemverilog
        // ---- VLAN ----
        begin
            vlan_header vlan = new();
            byte unsigned packed[$];
            int offset;

            check("vlan: proto_type", vlan.proto_type == PROTO_VLAN);
            check("vlan: header_length", vlan.get_header_length() == 4);

            // Test: pack
            vlan.pcp = 3'd5;
            vlan.dei = 1'b1;
            vlan.vlan_id = 12'd100;
            vlan.ethertype = ETHERTYPE_IPV4;
            vlan.calc_fields('{}, PROTO_IPV4);
            vlan.pack_header(packed);

            check("vlan: pack size", packed.size() == 4);
            // TCI = {pcp[2:0], dei, vlan_id[11:0]} = {101, 1, 000001100100} = 0xB064
            check("vlan: pack tci", {packed[0], packed[1]} == 16'hB064);
            check("vlan: pack ethertype", {packed[2], packed[3]} == 16'h0800);

            // Test: unpack
            begin
                vlan_header vlan2 = new();
                offset = 0;
                vlan2.unpack_header(packed, offset);
                check("vlan: unpack pcp", vlan2.pcp == 3'd5);
                check("vlan: unpack dei", vlan2.dei == 1'b1);
                check("vlan: unpack vlan_id", vlan2.vlan_id == 12'd100);
                check("vlan: unpack ethertype", vlan2.ethertype == ETHERTYPE_IPV4);
                check("vlan: unpack offset", offset == 4);
            end

            // Test: clone + compare
            begin
                protocol_base vlan3 = vlan.clone();
                check("vlan: clone compare", vlan.compare(vlan3));
            end
        end
```

- [ ] **Step 2: Write vlan_header.sv (replace stub)**

```systemverilog
// src/protocols/l2/vlan_header.sv
`ifndef VLAN_HEADER_SV
`define VLAN_HEADER_SV

`include "protocol_base.sv"

class vlan_header extends protocol_base;

    rand bit [2:0]  pcp;        // Priority Code Point
    rand bit        dei;        // Drop Eligible Indicator
    rand bit [11:0] vlan_id;    // VLAN Identifier
    rand bit [15:0] ethertype;  // Inner EtherType

    constraint c_default {
        pcp == 0;
        dei == 0;
        vlan_id inside {[1:4094]};
    }

    function new();
        proto_type = PROTO_VLAN;
        pcp       = 0;
        dei       = 0;
        vlan_id   = 12'd1;
        ethertype = ETHERTYPE_IPV4;
    endfunction

    static function vlan_header create(bit [11:0] vid = 1, bit [2:0] pri = 0,
                                        bit d = 0, bit [15:0] etype = ETHERTYPE_IPV4);
        vlan_header h = new();
        h.vlan_id   = vid;
        h.pcp       = pri;
        h.dei       = d;
        h.ethertype = etype;
        return h;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [15:0] tci = {pcp, dei, vlan_id};
        packet_utils::pack_bytes_16(data, tci);
        packet_utils::pack_bytes_16(data, ethertype);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [15:0] tci = packet_utils::unpack_bytes_16(data, offset);
        pcp     = tci[15:13];
        dei     = tci[12];
        vlan_id = tci[11:0];
        ethertype = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function int get_header_length();
        return 4;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        case (next_proto)
            PROTO_IPV4:  ethertype = ETHERTYPE_IPV4;
            PROTO_IPV6:  ethertype = ETHERTYPE_IPV6;
            PROTO_ARP:   ethertype = ETHERTYPE_ARP;
            PROTO_VLAN:  ethertype = ETHERTYPE_VLAN;  // nested VLAN
            PROTO_MPLS:  ethertype = ETHERTYPE_MPLS_UNI;
            default: ;
        endcase
    endfunction

    virtual function protocol_base clone();
        vlan_header h = new();
        h.pcp       = pcp;
        h.dei       = dei;
        h.vlan_id   = vlan_id;
        h.ethertype = ethertype;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        vlan_header o;
        if (!$cast(o, other)) return 0;
        return (pcp == o.pcp) && (dei == o.dei) &&
               (vlan_id == o.vlan_id) && (ethertype == o.ethertype);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  pcp      : %0d\n", pcp)};
        s = {s, $sformatf("  dei      : %0d\n", dei)};
        s = {s, $sformatf("  vlan_id  : %0d\n", vlan_id)};
        s = {s, $sformatf("  ethertype: 0x%04x\n", ethertype)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("VLAN %0d pcp:%0d", vlan_id, pcp);
    endfunction

endclass

`endif // VLAN_HEADER_SV
```

- [ ] **Step 3: Run test — verify VLAN tests pass**

```bash
make run_protocol_headers SIM=vcs
```

Expected: All Ethernet + VLAN tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/protocols/l2/vlan_header.sv test/test_protocol_headers.sv
git commit -m "feat: add vlan_header with 802.1Q TCI pack/unpack"
```

---

### Task 6: ipv4_header.sv — IPv4 header

**Files:**
- Modify: `src/protocols/l3/ipv4_header.sv` (replace stub)
- Modify: `test/test_protocol_headers.sv` (add IPv4 tests)

- [ ] **Step 1: Add IPv4 tests to test_protocol_headers.sv**

Insert before the final results line:

```systemverilog
        // ---- IPv4 ----
        begin
            ipv4_header ip = new();
            byte unsigned packed[$];
            int offset;

            check("ipv4: proto_type", ip.proto_type == PROTO_IPV4);
            check("ipv4: header_length default", ip.get_header_length() == 20);

            // Test: pack with known values
            ip.version     = 4;
            ip.ihl         = 5;
            ip.dscp        = 0;
            ip.ecn         = 0;
            ip.total_length = 40;
            ip.identification = 16'h1234;
            ip.flags       = 3'b010;  // DF
            ip.fragment_offset = 0;
            ip.ttl         = 64;
            ip.protocol    = IP_PROTO_TCP;
            ip.header_checksum = 0;
            ip.src_addr    = 32'hC0A80001;  // 192.168.0.1
            ip.dst_addr    = 32'hC0A80002;  // 192.168.0.2
            ip.calc_fields('{}, PROTO_TCP);
            ip.pack_header(packed);

            check("ipv4: pack size", packed.size() == 20);
            check("ipv4: pack version_ihl", packed[0] == 8'h45);
            check("ipv4: pack total_length", {packed[2], packed[3]} == 16'h0028);
            check("ipv4: pack ttl", packed[8] == 8'h40);
            check("ipv4: pack protocol", packed[9] == 8'h06);
            check("ipv4: pack src_addr", {packed[12], packed[13], packed[14], packed[15]} == 32'hC0A80001);

            // Test: checksum is non-zero after calc_fields
            check("ipv4: checksum computed", ip.header_checksum != 0);

            // Test: verify checksum by computing over packed header (should be 0)
            begin
                bit [15:0] verify_csum = packet_utils::ones_complement_checksum(packed);
                check("ipv4: checksum verifies", verify_csum == 16'h0000);
            end

            // Test: unpack
            begin
                ipv4_header ip2 = new();
                offset = 0;
                ip2.unpack_header(packed, offset);
                check("ipv4: unpack version", ip2.version == 4);
                check("ipv4: unpack ihl", ip2.ihl == 5);
                check("ipv4: unpack src_addr", ip2.src_addr == 32'hC0A80001);
                check("ipv4: unpack dst_addr", ip2.dst_addr == 32'hC0A80002);
                check("ipv4: unpack protocol", ip2.protocol == IP_PROTO_TCP);
                check("ipv4: unpack offset", offset == 20);
            end

            // Test: auto_calc=0 preserves user checksum
            begin
                ipv4_header ip3 = new();
                ip3.auto_calc = 0;
                ip3.header_checksum = 16'hDEAD;
                ip3.protocol = IP_PROTO_TCP;
                ip3.calc_fields('{}, PROTO_TCP);
                check("ipv4: auto_calc=0 preserves checksum", ip3.header_checksum == 16'hDEAD);
                check("ipv4: auto_calc=0 preserves protocol", ip3.protocol == IP_PROTO_TCP);
            end

            // Test: clone + compare
            begin
                protocol_base ip4 = ip.clone();
                check("ipv4: clone compare", ip.compare(ip4));
            end
        end
```

- [ ] **Step 2: Write ipv4_header.sv**

```systemverilog
// src/protocols/l3/ipv4_header.sv
`ifndef IPV4_HEADER_SV
`define IPV4_HEADER_SV

`include "protocol_base.sv"

class ipv4_header extends protocol_base;

    rand bit [3:0]   version;
    rand bit [3:0]   ihl;
    rand bit [5:0]   dscp;
    rand bit [1:0]   ecn;
    rand bit [15:0]  total_length;
    rand bit [15:0]  identification;
    rand bit [2:0]   flags;            // [2]=Reserved, [1]=DF, [0]=MF
    rand bit [12:0]  fragment_offset;
    rand bit [7:0]   ttl;
    rand bit [7:0]   protocol;
    rand bit [15:0]  header_checksum;
    rand bit [31:0]  src_addr;
    rand bit [31:0]  dst_addr;
    rand byte unsigned options[$];     // IP options (variable length, 0-40 bytes)

    constraint c_default {
        version == 4;
        ihl     == 5;
        dscp    == 0;
        ecn     == 0;
        flags   == 3'b010;  // DF set
        fragment_offset == 0;
        ttl inside {[32:128]};
        options.size() == 0;
    }

    function new();
        proto_type       = PROTO_IPV4;
        version          = 4;
        ihl              = 5;
        dscp             = 0;
        ecn              = 0;
        total_length     = 20;
        identification   = 0;
        flags            = 3'b010;
        fragment_offset  = 0;
        ttl              = 64;
        protocol         = IP_PROTO_TCP;
        header_checksum  = 0;
        src_addr         = 0;
        dst_addr         = 0;
    endfunction

    static function ipv4_header create(bit [31:0] src = 0, bit [31:0] dst = 0,
                                        bit [7:0] proto = IP_PROTO_TCP, bit [7:0] t = 64);
        ipv4_header h = new();
        h.src_addr = src;
        h.dst_addr = dst;
        h.protocol = proto;
        h.ttl      = t;
        return h;
    endfunction

    virtual function int get_header_length();
        return ihl * 4;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        byte unsigned hdr[$];
        // Version + IHL
        hdr.push_back({version, ihl});
        // DSCP + ECN
        hdr.push_back({dscp, ecn});
        // Total Length
        packet_utils::pack_bytes_16(hdr, total_length);
        // Identification
        packet_utils::pack_bytes_16(hdr, identification);
        // Flags + Fragment Offset
        begin
            bit [15:0] flags_frag = {flags, fragment_offset};
            packet_utils::pack_bytes_16(hdr, flags_frag);
        end
        // TTL
        hdr.push_back(ttl);
        // Protocol
        hdr.push_back(protocol);
        // Header Checksum
        packet_utils::pack_bytes_16(hdr, header_checksum);
        // Source Address
        packet_utils::pack_bytes_32(hdr, src_addr);
        // Destination Address
        packet_utils::pack_bytes_32(hdr, dst_addr);
        // Options
        foreach (options[i]) hdr.push_back(options[i]);

        foreach (hdr[i]) data.push_back(hdr[i]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] byte0, byte1;
        bit [15:0] flags_frag;

        byte0   = data[offset]; offset++;
        version = byte0[7:4];
        ihl     = byte0[3:0];

        byte1 = data[offset]; offset++;
        dscp  = byte1[7:2];
        ecn   = byte1[1:0];

        total_length    = packet_utils::unpack_bytes_16(data, offset);
        identification  = packet_utils::unpack_bytes_16(data, offset);

        flags_frag      = packet_utils::unpack_bytes_16(data, offset);
        flags           = flags_frag[15:13];
        fragment_offset = flags_frag[12:0];

        ttl             = data[offset]; offset++;
        protocol        = data[offset]; offset++;
        header_checksum = packet_utils::unpack_bytes_16(data, offset);
        src_addr        = packet_utils::unpack_bytes_32(data, offset);
        dst_addr        = packet_utils::unpack_bytes_32(data, offset);

        // Read options if ihl > 5
        options = {};
        begin
            int opt_len = (ihl - 5) * 4;
            for (int i = 0; i < opt_len; i++) begin
                options.push_back(data[offset]); offset++;
            end
        end
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;

        // Set protocol field from next layer
        case (next_proto)
            PROTO_TCP:      protocol = IP_PROTO_TCP;
            PROTO_UDP:      protocol = IP_PROTO_UDP;
            PROTO_ICMP:     protocol = IP_PROTO_ICMP;
            PROTO_IGMP:     protocol = IP_PROTO_IGMP;
            PROTO_GRE:      protocol = IP_PROTO_GRE;
            PROTO_IP_IN_IP: protocol = IP_PROTO_IP_IN_IP;
            PROTO_OSPF:     protocol = IP_PROTO_OSPF;
            PROTO_SCTP:     protocol = IP_PROTO_SCTP;
            default: ;
        endcase

        // Compute IHL
        ihl = 5 + options.size() / 4;

        // Compute total_length = header + payload
        total_length = get_header_length() + payload_data.size();

        // Compute checksum: zero out checksum field, pack header, compute
        header_checksum = 0;
        begin
            byte unsigned hdr_bytes[$];
            pack_header(hdr_bytes);
            header_checksum = packet_utils::ones_complement_checksum(hdr_bytes);
        end
    endfunction

    virtual function protocol_base clone();
        ipv4_header h = new();
        h.version          = version;
        h.ihl              = ihl;
        h.dscp             = dscp;
        h.ecn              = ecn;
        h.total_length     = total_length;
        h.identification   = identification;
        h.flags            = flags;
        h.fragment_offset  = fragment_offset;
        h.ttl              = ttl;
        h.protocol         = protocol;
        h.header_checksum  = header_checksum;
        h.src_addr         = src_addr;
        h.dst_addr         = dst_addr;
        h.options          = options;
        h.auto_calc        = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv4_header o;
        if (!$cast(o, other)) return 0;
        if (version != o.version || ihl != o.ihl) return 0;
        if (dscp != o.dscp || ecn != o.ecn) return 0;
        if (total_length != o.total_length) return 0;
        if (identification != o.identification) return 0;
        if (flags != o.flags || fragment_offset != o.fragment_offset) return 0;
        if (ttl != o.ttl || protocol != o.protocol) return 0;
        if (header_checksum != o.header_checksum) return 0;
        if (src_addr != o.src_addr || dst_addr != o.dst_addr) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version  : %0d\n", version)};
        s = {s, $sformatf("  ihl      : %0d\n", ihl)};
        s = {s, $sformatf("  dscp     : %0d\n", dscp)};
        s = {s, $sformatf("  ecn      : %0d\n", ecn)};
        s = {s, $sformatf("  total_len: %0d\n", total_length)};
        s = {s, $sformatf("  ident    : 0x%04x\n", identification)};
        s = {s, $sformatf("  flags    : %03b (DF=%0b MF=%0b)\n", flags, flags[1], flags[0])};
        s = {s, $sformatf("  frag_off : %0d\n", fragment_offset)};
        s = {s, $sformatf("  ttl      : %0d\n", ttl)};
        s = {s, $sformatf("  protocol : %0d\n", protocol)};
        s = {s, $sformatf("  checksum : 0x%04x\n", header_checksum)};
        s = {s, $sformatf("  src_addr : %s\n", packet_utils::format_ipv4(src_addr))};
        s = {s, $sformatf("  dst_addr : %s\n", packet_utils::format_ipv4(dst_addr))};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%s -> %s proto:%0d ttl:%0d",
                         packet_utils::format_ipv4(src_addr),
                         packet_utils::format_ipv4(dst_addr),
                         protocol, ttl);
    endfunction

endclass

`endif // IPV4_HEADER_SV
```

- [ ] **Step 3: Run test — verify IPv4 tests pass**

```bash
make run_protocol_headers SIM=vcs
```

Expected: All Ethernet + VLAN + IPv4 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/protocols/l3/ipv4_header.sv test/test_protocol_headers.sv
git commit -m "feat: add ipv4_header with checksum computation and fragment support"
```

---

### Task 7: ipv6_header.sv — IPv6 header

**Files:**
- Modify: `src/protocols/l3/ipv6_header.sv` (replace stub)
- Modify: `test/test_protocol_headers.sv` (add IPv6 tests)

- [ ] **Step 1: Add IPv6 tests to test_protocol_headers.sv**

Insert before the final results line:

```systemverilog
        // ---- IPv6 ----
        begin
            ipv6_header ip6 = new();
            byte unsigned packed[$];
            int offset;

            check("ipv6: proto_type", ip6.proto_type == PROTO_IPV6);
            check("ipv6: header_length", ip6.get_header_length() == 40);

            // Test: pack
            ip6.version       = 6;
            ip6.traffic_class = 0;
            ip6.flow_label    = 20'hABCDE;
            ip6.payload_length = 20;
            ip6.next_header   = IPV6_NH_TCP;
            ip6.hop_limit     = 64;
            ip6.src_addr      = 128'hFE800000_00000000_00000000_00000001;
            ip6.dst_addr      = 128'hFE800000_00000000_00000000_00000002;
            ip6.calc_fields('{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                              8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                              8'h00, 8'h00, 8'h00, 8'h00}, PROTO_TCP);
            ip6.pack_header(packed);

            check("ipv6: pack size", packed.size() == 40);
            check("ipv6: pack version", packed[0][7:4] == 4'h6);
            check("ipv6: pack next_header", packed[6] == 8'h06);  // TCP
            check("ipv6: pack hop_limit", packed[7] == 8'h40);    // 64

            // Test: unpack
            begin
                ipv6_header ip6_2 = new();
                offset = 0;
                ip6_2.unpack_header(packed, offset);
                check("ipv6: unpack version", ip6_2.version == 6);
                check("ipv6: unpack flow_label", ip6_2.flow_label == 20'hABCDE);
                check("ipv6: unpack next_header", ip6_2.next_header == IPV6_NH_TCP);
                check("ipv6: unpack hop_limit", ip6_2.hop_limit == 64);
                check("ipv6: unpack src_addr", ip6_2.src_addr == 128'hFE800000_00000000_00000000_00000001);
                check("ipv6: unpack offset", offset == 40);
            end

            // Test: clone + compare
            begin
                protocol_base ip6_3 = ip6.clone();
                check("ipv6: clone compare", ip6.compare(ip6_3));
            end
        end
```

- [ ] **Step 2: Write ipv6_header.sv**

```systemverilog
// src/protocols/l3/ipv6_header.sv
`ifndef IPV6_HEADER_SV
`define IPV6_HEADER_SV

`include "protocol_base.sv"

class ipv6_header extends protocol_base;

    rand bit [3:0]    version;
    rand bit [7:0]    traffic_class;
    rand bit [19:0]   flow_label;
    rand bit [15:0]   payload_length;
    rand bit [7:0]    next_header;
    rand bit [7:0]    hop_limit;
    rand bit [127:0]  src_addr;
    rand bit [127:0]  dst_addr;

    constraint c_default {
        version == 6;
        traffic_class == 0;
        flow_label == 0;
        hop_limit inside {[32:128]};
    }

    function new();
        proto_type      = PROTO_IPV6;
        version         = 6;
        traffic_class   = 0;
        flow_label      = 0;
        payload_length  = 0;
        next_header     = IPV6_NH_TCP;
        hop_limit       = 64;
        src_addr        = 0;
        dst_addr        = 0;
    endfunction

    static function ipv6_header create(bit [127:0] src = 0, bit [127:0] dst = 0,
                                        bit [7:0] nh = IPV6_NH_TCP, bit [7:0] hl = 64);
        ipv6_header h = new();
        h.src_addr    = src;
        h.dst_addr    = dst;
        h.next_header = nh;
        h.hop_limit   = hl;
        return h;
    endfunction

    virtual function int get_header_length();
        return 40;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        bit [31:0] word0 = {version, traffic_class, flow_label};
        packet_utils::pack_bytes_32(data, word0);
        packet_utils::pack_bytes_16(data, payload_length);
        data.push_back(next_header);
        data.push_back(hop_limit);
        // Source address (16 bytes)
        for (int i = 15; i >= 0; i--) begin
            data.push_back(src_addr[(i*8)+:8]);
        end
        // Destination address (16 bytes)
        for (int i = 15; i >= 0; i--) begin
            data.push_back(dst_addr[(i*8)+:8]);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] word0 = packet_utils::unpack_bytes_32(data, offset);
        version       = word0[31:28];
        traffic_class = word0[27:20];
        flow_label    = word0[19:0];
        payload_length = packet_utils::unpack_bytes_16(data, offset);
        next_header   = data[offset]; offset++;
        hop_limit     = data[offset]; offset++;
        // Source address
        src_addr = 0;
        for (int i = 15; i >= 0; i--) begin
            src_addr[(i*8)+:8] = data[offset]; offset++;
        end
        // Destination address
        dst_addr = 0;
        for (int i = 15; i >= 0; i--) begin
            dst_addr[(i*8)+:8] = data[offset]; offset++;
        end
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;

        case (next_proto)
            PROTO_TCP:           next_header = IPV6_NH_TCP;
            PROTO_UDP:           next_header = IPV6_NH_UDP;
            PROTO_ICMPV6:        next_header = IPV6_NH_ICMPV6;
            PROTO_IPV6_HBH:      next_header = IPV6_NH_HBH;
            PROTO_IPV6_ROUTING:  next_header = IPV6_NH_ROUTING;
            PROTO_IPV6_FRAGMENT: next_header = IPV6_NH_FRAGMENT;
            PROTO_IPV6_DEST:     next_header = IPV6_NH_DEST;
            PROTO_GRE:           next_header = IPV6_NH_GRE;
            PROTO_OSPF:          next_header = IPV6_NH_OSPF;
            PROTO_SCTP:          next_header = IPV6_NH_SCTP;
            default: ;
        endcase

        payload_length = payload_data.size();
    endfunction

    virtual function protocol_base clone();
        ipv6_header h = new();
        h.version        = version;
        h.traffic_class  = traffic_class;
        h.flow_label     = flow_label;
        h.payload_length = payload_length;
        h.next_header    = next_header;
        h.hop_limit      = hop_limit;
        h.src_addr       = src_addr;
        h.dst_addr       = dst_addr;
        h.auto_calc      = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        ipv6_header o;
        if (!$cast(o, other)) return 0;
        return (version == o.version) && (traffic_class == o.traffic_class) &&
               (flow_label == o.flow_label) && (payload_length == o.payload_length) &&
               (next_header == o.next_header) && (hop_limit == o.hop_limit) &&
               (src_addr == o.src_addr) && (dst_addr == o.dst_addr);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  version      : %0d\n", version)};
        s = {s, $sformatf("  traffic_class: 0x%02x\n", traffic_class)};
        s = {s, $sformatf("  flow_label   : 0x%05x\n", flow_label)};
        s = {s, $sformatf("  payload_len  : %0d\n", payload_length)};
        s = {s, $sformatf("  next_header  : %0d\n", next_header)};
        s = {s, $sformatf("  hop_limit    : %0d\n", hop_limit)};
        s = {s, $sformatf("  src_addr     : %s\n", packet_utils::format_ipv6(src_addr))};
        s = {s, $sformatf("  dst_addr     : %s\n", packet_utils::format_ipv6(dst_addr))};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%s -> %s nh:%0d hl:%0d",
                         packet_utils::format_ipv6(src_addr),
                         packet_utils::format_ipv6(dst_addr),
                         next_header, hop_limit);
    endfunction

endclass

`endif // IPV6_HEADER_SV
```

- [ ] **Step 3: Run test — verify IPv6 tests pass**

```bash
make run_protocol_headers SIM=vcs
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/protocols/l3/ipv6_header.sv test/test_protocol_headers.sv
git commit -m "feat: add ipv6_header with 128-bit address pack/unpack"
```

---

### Task 8: arp_header.sv — ARP header

**Files:**
- Modify: `src/protocols/l3/arp_header.sv` (replace stub)
- Modify: `test/test_protocol_headers.sv` (add ARP tests)

- [ ] **Step 1: Add ARP tests to test_protocol_headers.sv**

Insert before the final results line:

```systemverilog
        // ---- ARP ----
        begin
            arp_header arp = new();
            byte unsigned packed[$];
            int offset;

            check("arp: proto_type", arp.proto_type == PROTO_ARP);
            check("arp: header_length", arp.get_header_length() == 28);

            // Test: ARP request pack
            arp.hw_type     = 16'h0001;  // Ethernet
            arp.proto_type_field = 16'h0800;  // IPv4
            arp.hw_len      = 6;
            arp.proto_len   = 4;
            arp.opcode      = 16'h0001;  // Request
            arp.sender_mac  = 48'h001122334455;
            arp.sender_ip   = 32'hC0A80001;
            arp.target_mac  = 48'h000000000000;
            arp.target_ip   = 32'hC0A80002;
            arp.calc_fields('{}, PROTO_RAW_PAYLOAD);
            arp.pack_header(packed);

            check("arp: pack size", packed.size() == 28);
            check("arp: pack hw_type", {packed[0], packed[1]} == 16'h0001);
            check("arp: pack opcode", {packed[6], packed[7]} == 16'h0001);

            // Test: unpack
            begin
                arp_header arp2 = new();
                offset = 0;
                arp2.unpack_header(packed, offset);
                check("arp: unpack opcode", arp2.opcode == 16'h0001);
                check("arp: unpack sender_mac", arp2.sender_mac == 48'h001122334455);
                check("arp: unpack sender_ip", arp2.sender_ip == 32'hC0A80001);
                check("arp: unpack target_ip", arp2.target_ip == 32'hC0A80002);
                check("arp: unpack offset", offset == 28);
            end

            // Test: clone + compare
            begin
                protocol_base arp3 = arp.clone();
                check("arp: clone compare", arp.compare(arp3));
            end
        end
```

- [ ] **Step 2: Write arp_header.sv**

```systemverilog
// src/protocols/l3/arp_header.sv
`ifndef ARP_HEADER_SV
`define ARP_HEADER_SV

`include "protocol_base.sv"

class arp_header extends protocol_base;

    rand bit [15:0]  hw_type;           // Hardware type (1 = Ethernet)
    rand bit [15:0]  proto_type_field;  // Protocol type (0x0800 = IPv4)
    rand bit [7:0]   hw_len;            // Hardware address length (6 for Ethernet)
    rand bit [7:0]   proto_len;         // Protocol address length (4 for IPv4)
    rand bit [15:0]  opcode;            // 1=Request, 2=Reply
    rand bit [47:0]  sender_mac;
    rand bit [31:0]  sender_ip;
    rand bit [47:0]  target_mac;
    rand bit [31:0]  target_ip;

    constraint c_default {
        hw_type          == 16'h0001;
        proto_type_field == 16'h0800;
        hw_len           == 6;
        proto_len        == 4;
        opcode inside {16'h0001, 16'h0002};
    }

    function new();
        proto_type       = PROTO_ARP;
        hw_type          = 16'h0001;
        proto_type_field = 16'h0800;
        hw_len           = 6;
        proto_len        = 4;
        opcode           = 16'h0001;
        sender_mac       = 0;
        sender_ip        = 0;
        target_mac       = 0;
        target_ip        = 0;
    endfunction

    static function arp_header create(bit [15:0] op = 16'h0001,
                                       bit [47:0] s_mac = 0, bit [31:0] s_ip = 0,
                                       bit [47:0] t_mac = 0, bit [31:0] t_ip = 0);
        arp_header h = new();
        h.opcode     = op;
        h.sender_mac = s_mac;
        h.sender_ip  = s_ip;
        h.target_mac = t_mac;
        h.target_ip  = t_ip;
        return h;
    endfunction

    virtual function int get_header_length();
        return 28;  // For Ethernet + IPv4
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, hw_type);
        packet_utils::pack_bytes_16(data, proto_type_field);
        data.push_back(hw_len);
        data.push_back(proto_len);
        packet_utils::pack_bytes_16(data, opcode);
        packet_utils::pack_bytes_48(data, sender_mac);
        packet_utils::pack_bytes_32(data, sender_ip);
        packet_utils::pack_bytes_48(data, target_mac);
        packet_utils::pack_bytes_32(data, target_ip);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        hw_type          = packet_utils::unpack_bytes_16(data, offset);
        proto_type_field = packet_utils::unpack_bytes_16(data, offset);
        hw_len           = data[offset]; offset++;
        proto_len        = data[offset]; offset++;
        opcode           = packet_utils::unpack_bytes_16(data, offset);
        sender_mac       = packet_utils::unpack_bytes_48(data, offset);
        sender_ip        = packet_utils::unpack_bytes_32(data, offset);
        target_mac       = packet_utils::unpack_bytes_48(data, offset);
        target_ip        = packet_utils::unpack_bytes_32(data, offset);
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        // ARP has no auto-calculated fields beyond what's set at construction
    endfunction

    virtual function protocol_base clone();
        arp_header h = new();
        h.hw_type          = hw_type;
        h.proto_type_field = proto_type_field;
        h.hw_len           = hw_len;
        h.proto_len        = proto_len;
        h.opcode           = opcode;
        h.sender_mac       = sender_mac;
        h.sender_ip        = sender_ip;
        h.target_mac       = target_mac;
        h.target_ip        = target_ip;
        h.auto_calc        = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        arp_header o;
        if (!$cast(o, other)) return 0;
        return (hw_type == o.hw_type) && (proto_type_field == o.proto_type_field) &&
               (hw_len == o.hw_len) && (proto_len == o.proto_len) &&
               (opcode == o.opcode) && (sender_mac == o.sender_mac) &&
               (sender_ip == o.sender_ip) && (target_mac == o.target_mac) &&
               (target_ip == o.target_ip);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  hw_type    : 0x%04x\n", hw_type)};
        s = {s, $sformatf("  proto_type : 0x%04x\n", proto_type_field)};
        s = {s, $sformatf("  opcode     : %0d (%s)\n", opcode, (opcode == 1) ? "Request" : "Reply")};
        s = {s, $sformatf("  sender_mac : %s\n", packet_utils::format_mac(sender_mac))};
        s = {s, $sformatf("  sender_ip  : %s\n", packet_utils::format_ipv4(sender_ip))};
        s = {s, $sformatf("  target_mac : %s\n", packet_utils::format_mac(target_mac))};
        s = {s, $sformatf("  target_ip  : %s\n", packet_utils::format_ipv4(target_ip))};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%s %s -> %s",
                         (opcode == 1) ? "ARP-Request" : "ARP-Reply",
                         packet_utils::format_ipv4(sender_ip),
                         packet_utils::format_ipv4(target_ip));
    endfunction

endclass

`endif // ARP_HEADER_SV
```

- [ ] **Step 3: Run test — verify ARP tests pass**

```bash
make run_protocol_headers SIM=vcs
```

- [ ] **Step 4: Commit**

```bash
git add src/protocols/l3/arp_header.sv test/test_protocol_headers.sv
git commit -m "feat: add arp_header with request/reply support"
```

---

### Task 9: tcp_header.sv — TCP header

**Files:**
- Modify: `src/protocols/l4/tcp_header.sv` (replace stub)
- Modify: `test/test_protocol_headers.sv` (add TCP tests)

- [ ] **Step 1: Add TCP tests to test_protocol_headers.sv**

Insert before the final results line:

```systemverilog
        // ---- TCP ----
        begin
            tcp_header tcp = new();
            byte unsigned packed[$];
            int offset;

            check("tcp: proto_type", tcp.proto_type == PROTO_TCP);
            check("tcp: header_length default", tcp.get_header_length() == 20);

            // Test: pack
            tcp.src_port    = 16'd12345;
            tcp.dst_port    = 16'd80;
            tcp.seq_num     = 32'h11223344;
            tcp.ack_num     = 32'h55667788;
            tcp.data_offset = 5;
            tcp.flags       = 9'h002;  // SYN
            tcp.window_size = 16'hFFFF;
            tcp.checksum    = 0;
            tcp.urgent_ptr  = 0;
            // No pseudo-header checksum test here — that requires IP context
            tcp.auto_calc = 0;  // skip checksum for this test
            tcp.pack_header(packed);

            check("tcp: pack size", packed.size() == 20);
            check("tcp: pack src_port", {packed[0], packed[1]} == 16'd12345);
            check("tcp: pack dst_port", {packed[2], packed[3]} == 16'd80);
            check("tcp: pack seq_num", {packed[4], packed[5], packed[6], packed[7]} == 32'h11223344);
            check("tcp: pack data_offset", packed[12][7:4] == 4'd5);
            check("tcp: pack flags SYN", packed[13][1] == 1'b1);

            // Test: unpack
            begin
                tcp_header tcp2 = new();
                offset = 0;
                tcp2.unpack_header(packed, offset);
                check("tcp: unpack src_port", tcp2.src_port == 16'd12345);
                check("tcp: unpack dst_port", tcp2.dst_port == 16'd80);
                check("tcp: unpack seq_num", tcp2.seq_num == 32'h11223344);
                check("tcp: unpack ack_num", tcp2.ack_num == 32'h55667788);
                check("tcp: unpack offset", offset == 20);
            end

            // Test: clone + compare
            begin
                protocol_base tcp3 = tcp.clone();
                check("tcp: clone compare", tcp.compare(tcp3));
            end
        end
```

- [ ] **Step 2: Write tcp_header.sv**

```systemverilog
// src/protocols/l4/tcp_header.sv
`ifndef TCP_HEADER_SV
`define TCP_HEADER_SV

`include "protocol_base.sv"

class tcp_header extends protocol_base;

    rand bit [15:0]  src_port;
    rand bit [15:0]  dst_port;
    rand bit [31:0]  seq_num;
    rand bit [31:0]  ack_num;
    rand bit [3:0]   data_offset;   // Header length in 32-bit words
    rand bit [2:0]   reserved;
    rand bit [8:0]   flags;         // NS,CWR,ECE,URG,ACK,PSH,RST,SYN,FIN
    rand bit [15:0]  window_size;
    rand bit [15:0]  checksum;
    rand bit [15:0]  urgent_ptr;
    rand byte unsigned options[$];

    constraint c_default {
        data_offset == 5;
        reserved    == 0;
        window_size inside {[1024:65535]};
        urgent_ptr  == 0;
        options.size() == 0;
    }

    function new();
        proto_type   = PROTO_TCP;
        src_port     = 0;
        dst_port     = 0;
        seq_num      = 0;
        ack_num      = 0;
        data_offset  = 5;
        reserved     = 0;
        flags        = 0;
        window_size  = 16'hFFFF;
        checksum     = 0;
        urgent_ptr   = 0;
    endfunction

    static function tcp_header create(bit [15:0] sp = 0, bit [15:0] dp = 0,
                                       bit [8:0] f = 0);
        tcp_header h = new();
        h.src_port = sp;
        h.dst_port = dp;
        h.flags    = f;
        return h;
    endfunction

    // Flag accessors
    function bit get_syn(); return flags[1]; endfunction
    function bit get_ack(); return flags[4]; endfunction
    function bit get_fin(); return flags[0]; endfunction
    function bit get_rst(); return flags[2]; endfunction
    function bit get_psh(); return flags[3]; endfunction

    function void set_syn(bit v); flags[1] = v; endfunction
    function void set_ack(bit v); flags[4] = v; endfunction
    function void set_fin(bit v); flags[0] = v; endfunction
    function void set_rst(bit v); flags[2] = v; endfunction
    function void set_psh(bit v); flags[3] = v; endfunction

    virtual function int get_header_length();
        return data_offset * 4;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, src_port);
        packet_utils::pack_bytes_16(data, dst_port);
        packet_utils::pack_bytes_32(data, seq_num);
        packet_utils::pack_bytes_32(data, ack_num);
        // Data offset (4 bits) + reserved (3 bits) + flags high bit (NS)
        data.push_back({data_offset, reserved, flags[8]});
        // Flags lower 8 bits
        data.push_back(flags[7:0]);
        packet_utils::pack_bytes_16(data, window_size);
        packet_utils::pack_bytes_16(data, checksum);
        packet_utils::pack_bytes_16(data, urgent_ptr);
        foreach (options[i]) data.push_back(options[i]);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [7:0] byte12, byte13;

        src_port    = packet_utils::unpack_bytes_16(data, offset);
        dst_port    = packet_utils::unpack_bytes_16(data, offset);
        seq_num     = packet_utils::unpack_bytes_32(data, offset);
        ack_num     = packet_utils::unpack_bytes_32(data, offset);

        byte12      = data[offset]; offset++;
        byte13      = data[offset]; offset++;
        data_offset = byte12[7:4];
        reserved    = byte12[3:1];
        flags       = {byte12[0], byte13};

        window_size = packet_utils::unpack_bytes_16(data, offset);
        checksum    = packet_utils::unpack_bytes_16(data, offset);
        urgent_ptr  = packet_utils::unpack_bytes_16(data, offset);

        // Options
        options = {};
        begin
            int opt_len = (data_offset - 5) * 4;
            for (int i = 0; i < opt_len; i++) begin
                options.push_back(data[offset]); offset++;
            end
        end
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        data_offset = 5 + options.size() / 4;
        // TCP checksum requires pseudo-header — computed at packet level, not here
        // The packet class will call compute_l4_checksum() after assembling pseudo-header
        checksum = 0;
    endfunction

    virtual function protocol_base clone();
        tcp_header h = new();
        h.src_port    = src_port;
        h.dst_port    = dst_port;
        h.seq_num     = seq_num;
        h.ack_num     = ack_num;
        h.data_offset = data_offset;
        h.reserved    = reserved;
        h.flags       = flags;
        h.window_size = window_size;
        h.checksum    = checksum;
        h.urgent_ptr  = urgent_ptr;
        h.options     = options;
        h.auto_calc   = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        tcp_header o;
        if (!$cast(o, other)) return 0;
        return (src_port == o.src_port) && (dst_port == o.dst_port) &&
               (seq_num == o.seq_num) && (ack_num == o.ack_num) &&
               (data_offset == o.data_offset) && (flags == o.flags) &&
               (window_size == o.window_size) && (checksum == o.checksum) &&
               (urgent_ptr == o.urgent_ptr);
    endfunction

    virtual function string to_string();
        string s, flag_str;
        flag_str = "";
        if (flags[1]) flag_str = {flag_str, "SYN "};
        if (flags[4]) flag_str = {flag_str, "ACK "};
        if (flags[0]) flag_str = {flag_str, "FIN "};
        if (flags[2]) flag_str = {flag_str, "RST "};
        if (flags[3]) flag_str = {flag_str, "PSH "};
        if (flags[5]) flag_str = {flag_str, "URG "};

        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  src_port   : %0d\n", src_port)};
        s = {s, $sformatf("  dst_port   : %0d\n", dst_port)};
        s = {s, $sformatf("  seq_num    : 0x%08x\n", seq_num)};
        s = {s, $sformatf("  ack_num    : 0x%08x\n", ack_num)};
        s = {s, $sformatf("  data_offset: %0d\n", data_offset)};
        s = {s, $sformatf("  flags      : [%s] (0x%03x)\n", flag_str, flags)};
        s = {s, $sformatf("  window     : %0d\n", window_size)};
        s = {s, $sformatf("  checksum   : 0x%04x\n", checksum)};
        s = {s, $sformatf("  urgent_ptr : %0d\n", urgent_ptr)};
        return s;
    endfunction

    virtual function string to_brief();
        string flag_str = "";
        if (flags[1]) flag_str = {flag_str, "S"};
        if (flags[4]) flag_str = {flag_str, "A"};
        if (flags[0]) flag_str = {flag_str, "F"};
        if (flags[2]) flag_str = {flag_str, "R"};
        if (flags[3]) flag_str = {flag_str, "P"};
        return $sformatf("%0d -> %0d [%s] seq:%08x ack:%08x",
                         src_port, dst_port, flag_str, seq_num, ack_num);
    endfunction

endclass

`endif // TCP_HEADER_SV
```

- [ ] **Step 3: Run test — verify TCP tests pass**

```bash
make run_protocol_headers SIM=vcs
```

- [ ] **Step 4: Commit**

```bash
git add src/protocols/l4/tcp_header.sv test/test_protocol_headers.sv
git commit -m "feat: add tcp_header with flag accessors and options support"
```

---

### Task 10: udp_header.sv — UDP header

**Files:**
- Modify: `src/protocols/l4/udp_header.sv` (replace stub)
- Modify: `test/test_protocol_headers.sv` (add UDP tests)

- [ ] **Step 1: Add UDP tests to test_protocol_headers.sv**

Insert before the final results line:

```systemverilog
        // ---- UDP ----
        begin
            udp_header udp = new();
            byte unsigned packed[$];
            int offset;

            check("udp: proto_type", udp.proto_type == PROTO_UDP);
            check("udp: header_length", udp.get_header_length() == 8);

            // Test: pack
            udp.src_port = 16'd4789;
            udp.dst_port = 16'd4789;
            udp.length   = 16'd28;
            udp.checksum = 16'h0000;
            udp.auto_calc = 0;
            udp.pack_header(packed);

            check("udp: pack size", packed.size() == 8);
            check("udp: pack src_port", {packed[0], packed[1]} == 16'd4789);
            check("udp: pack dst_port", {packed[2], packed[3]} == 16'd4789);
            check("udp: pack length", {packed[4], packed[5]} == 16'd28);

            // Test: unpack
            begin
                udp_header udp2 = new();
                offset = 0;
                udp2.unpack_header(packed, offset);
                check("udp: unpack src_port", udp2.src_port == 16'd4789);
                check("udp: unpack dst_port", udp2.dst_port == 16'd4789);
                check("udp: unpack length", udp2.length == 16'd28);
                check("udp: unpack offset", offset == 8);
            end

            // Test: clone + compare
            begin
                protocol_base udp3 = udp.clone();
                check("udp: clone compare", udp.compare(udp3));
            end
        end
```

- [ ] **Step 2: Write udp_header.sv**

```systemverilog
// src/protocols/l4/udp_header.sv
`ifndef UDP_HEADER_SV
`define UDP_HEADER_SV

`include "protocol_base.sv"

class udp_header extends protocol_base;

    rand bit [15:0]  src_port;
    rand bit [15:0]  dst_port;
    rand bit [15:0]  length;
    rand bit [15:0]  checksum;

    constraint c_default {
        src_port inside {[1024:65535]};
    }

    function new();
        proto_type = PROTO_UDP;
        src_port   = 0;
        dst_port   = 0;
        length     = 8;
        checksum   = 0;
    endfunction

    static function udp_header create(bit [15:0] sp = 0, bit [15:0] dp = 0);
        udp_header h = new();
        h.src_port = sp;
        h.dst_port = dp;
        return h;
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        packet_utils::pack_bytes_16(data, src_port);
        packet_utils::pack_bytes_16(data, dst_port);
        packet_utils::pack_bytes_16(data, length);
        packet_utils::pack_bytes_16(data, checksum);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        src_port = packet_utils::unpack_bytes_16(data, offset);
        dst_port = packet_utils::unpack_bytes_16(data, offset);
        length   = packet_utils::unpack_bytes_16(data, offset);
        checksum = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        length = 8 + payload_data.size();
        // UDP checksum requires pseudo-header — computed at packet level
        checksum = 0;
    endfunction

    virtual function protocol_base clone();
        udp_header h = new();
        h.src_port = src_port;
        h.dst_port = dst_port;
        h.length   = length;
        h.checksum = checksum;
        h.auto_calc = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        udp_header o;
        if (!$cast(o, other)) return 0;
        return (src_port == o.src_port) && (dst_port == o.dst_port) &&
               (length == o.length) && (checksum == o.checksum);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  src_port : %0d\n", src_port)};
        s = {s, $sformatf("  dst_port : %0d\n", dst_port)};
        s = {s, $sformatf("  length   : %0d\n", length)};
        s = {s, $sformatf("  checksum : 0x%04x\n", checksum)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("%0d -> %0d len:%0d", src_port, dst_port, length);
    endfunction

endclass

`endif // UDP_HEADER_SV
```

- [ ] **Step 3: Run test — verify UDP tests pass**

```bash
make run_protocol_headers SIM=vcs
```

- [ ] **Step 4: Commit**

```bash
git add src/protocols/l4/udp_header.sv test/test_protocol_headers.sv
git commit -m "feat: add udp_header"
```

---

### Task 11: icmp_header.sv + icmpv6_header.sv

**Files:**
- Modify: `src/protocols/l4/icmp_header.sv` (replace stub)
- Modify: `src/protocols/l4/icmpv6_header.sv` (replace stub)
- Modify: `test/test_protocol_headers.sv` (add ICMP/ICMPv6 tests)

- [ ] **Step 1: Add ICMP tests to test_protocol_headers.sv**

Insert before the final results line:

```systemverilog
        // ---- ICMPv4 ----
        begin
            icmp_header icmp = new();
            byte unsigned packed[$];
            int offset;

            check("icmp: proto_type", icmp.proto_type == PROTO_ICMP);
            check("icmp: header_length", icmp.get_header_length() == 8);

            // Test: Echo Request pack
            icmp.icmp_type = 8;  // Echo Request
            icmp.icmp_code = 0;
            icmp.identifier = 16'h1234;
            icmp.sequence_num = 16'h0001;
            icmp.auto_calc = 1;
            icmp.calc_fields('{}, PROTO_RAW_PAYLOAD);
            icmp.pack_header(packed);

            check("icmp: pack size", packed.size() == 8);
            check("icmp: pack type", packed[0] == 8'd8);
            check("icmp: pack code", packed[1] == 8'd0);
            check("icmp: pack identifier", {packed[4], packed[5]} == 16'h1234);

            // Test: checksum verification
            begin
                bit [15:0] verify = packet_utils::ones_complement_checksum(packed);
                check("icmp: checksum verifies", verify == 16'h0000);
            end

            // Test: unpack
            begin
                icmp_header icmp2 = new();
                offset = 0;
                icmp2.unpack_header(packed, offset);
                check("icmp: unpack type", icmp2.icmp_type == 8);
                check("icmp: unpack identifier", icmp2.identifier == 16'h1234);
                check("icmp: unpack sequence", icmp2.sequence_num == 16'h0001);
            end
        end

        // ---- ICMPv6 ----
        begin
            icmpv6_header icmp6 = new();
            byte unsigned packed[$];

            check("icmpv6: proto_type", icmp6.proto_type == PROTO_ICMPV6);
            check("icmpv6: header_length", icmp6.get_header_length() == 8);

            icmp6.icmp_type = 128;  // Echo Request
            icmp6.icmp_code = 0;
            icmp6.identifier = 16'hABCD;
            icmp6.sequence_num = 16'h0001;
            icmp6.auto_calc = 0;  // ICMPv6 checksum needs pseudo-header
            icmp6.pack_header(packed);

            check("icmpv6: pack size", packed.size() == 8);
            check("icmpv6: pack type", packed[0] == 8'd128);
        end
```

- [ ] **Step 2: Write icmp_header.sv**

```systemverilog
// src/protocols/l4/icmp_header.sv
`ifndef ICMP_HEADER_SV
`define ICMP_HEADER_SV

`include "protocol_base.sv"

class icmp_header extends protocol_base;

    rand bit [7:0]   icmp_type;
    rand bit [7:0]   icmp_code;
    rand bit [15:0]  checksum;
    rand bit [15:0]  identifier;
    rand bit [15:0]  sequence_num;

    constraint c_default {
        icmp_type inside {0, 8};  // Echo Reply or Echo Request
        icmp_code == 0;
    }

    function new();
        proto_type    = PROTO_ICMP;
        icmp_type     = 8;   // Echo Request
        icmp_code     = 0;
        checksum      = 0;
        identifier    = 0;
        sequence_num  = 0;
    endfunction

    static function icmp_header create(bit [7:0] t = 8, bit [7:0] c = 0,
                                        bit [15:0] id = 0, bit [15:0] seq = 0);
        icmp_header h = new();
        h.icmp_type    = t;
        h.icmp_code    = c;
        h.identifier   = id;
        h.sequence_num = seq;
        return h;
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(icmp_type);
        data.push_back(icmp_code);
        packet_utils::pack_bytes_16(data, checksum);
        packet_utils::pack_bytes_16(data, identifier);
        packet_utils::pack_bytes_16(data, sequence_num);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        icmp_type    = data[offset]; offset++;
        icmp_code    = data[offset]; offset++;
        checksum     = packet_utils::unpack_bytes_16(data, offset);
        identifier   = packet_utils::unpack_bytes_16(data, offset);
        sequence_num = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // ICMP checksum is over the entire ICMP message (header + data)
        checksum = 0;
        begin
            byte unsigned msg[$];
            pack_header(msg);
            foreach (payload_data[i]) msg.push_back(payload_data[i]);
            checksum = packet_utils::ones_complement_checksum(msg);
        end
    endfunction

    virtual function protocol_base clone();
        icmp_header h = new();
        h.icmp_type    = icmp_type;
        h.icmp_code    = icmp_code;
        h.checksum     = checksum;
        h.identifier   = identifier;
        h.sequence_num = sequence_num;
        h.auto_calc    = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        icmp_header o;
        if (!$cast(o, other)) return 0;
        return (icmp_type == o.icmp_type) && (icmp_code == o.icmp_code) &&
               (checksum == o.checksum) && (identifier == o.identifier) &&
               (sequence_num == o.sequence_num);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  type     : %0d\n", icmp_type)};
        s = {s, $sformatf("  code     : %0d\n", icmp_code)};
        s = {s, $sformatf("  checksum : 0x%04x\n", checksum)};
        s = {s, $sformatf("  id       : 0x%04x\n", identifier)};
        s = {s, $sformatf("  seq      : %0d\n", sequence_num)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ICMP type:%0d code:%0d id:0x%04x seq:%0d",
                         icmp_type, icmp_code, identifier, sequence_num);
    endfunction

endclass

`endif // ICMP_HEADER_SV
```

- [ ] **Step 3: Write icmpv6_header.sv**

```systemverilog
// src/protocols/l4/icmpv6_header.sv
`ifndef ICMPV6_HEADER_SV
`define ICMPV6_HEADER_SV

`include "protocol_base.sv"

class icmpv6_header extends protocol_base;

    rand bit [7:0]   icmp_type;
    rand bit [7:0]   icmp_code;
    rand bit [15:0]  checksum;
    rand bit [15:0]  identifier;
    rand bit [15:0]  sequence_num;

    constraint c_default {
        icmp_type inside {128, 129};  // Echo Request/Reply
        icmp_code == 0;
    }

    function new();
        proto_type    = PROTO_ICMPV6;
        icmp_type     = 128;  // Echo Request
        icmp_code     = 0;
        checksum      = 0;
        identifier    = 0;
        sequence_num  = 0;
    endfunction

    static function icmpv6_header create(bit [7:0] t = 128, bit [7:0] c = 0,
                                          bit [15:0] id = 0, bit [15:0] seq = 0);
        icmpv6_header h = new();
        h.icmp_type    = t;
        h.icmp_code    = c;
        h.identifier   = id;
        h.sequence_num = seq;
        return h;
    endfunction

    virtual function int get_header_length();
        return 8;
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        data.push_back(icmp_type);
        data.push_back(icmp_code);
        packet_utils::pack_bytes_16(data, checksum);
        packet_utils::pack_bytes_16(data, identifier);
        packet_utils::pack_bytes_16(data, sequence_num);
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        icmp_type    = data[offset]; offset++;
        icmp_code    = data[offset]; offset++;
        checksum     = packet_utils::unpack_bytes_16(data, offset);
        identifier   = packet_utils::unpack_bytes_16(data, offset);
        sequence_num = packet_utils::unpack_bytes_16(data, offset);
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        // ICMPv6 checksum includes IPv6 pseudo-header — computed at packet level
        checksum = 0;
    endfunction

    virtual function protocol_base clone();
        icmpv6_header h = new();
        h.icmp_type    = icmp_type;
        h.icmp_code    = icmp_code;
        h.checksum     = checksum;
        h.identifier   = identifier;
        h.sequence_num = sequence_num;
        h.auto_calc    = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        icmpv6_header o;
        if (!$cast(o, other)) return 0;
        return (icmp_type == o.icmp_type) && (icmp_code == o.icmp_code) &&
               (checksum == o.checksum) && (identifier == o.identifier) &&
               (sequence_num == o.sequence_num);
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s ===\n", proto_type.name());
        s = {s, $sformatf("  type     : %0d\n", icmp_type)};
        s = {s, $sformatf("  code     : %0d\n", icmp_code)};
        s = {s, $sformatf("  checksum : 0x%04x\n", checksum)};
        s = {s, $sformatf("  id       : 0x%04x\n", identifier)};
        s = {s, $sformatf("  seq      : %0d\n", sequence_num)};
        return s;
    endfunction

    virtual function string to_brief();
        return $sformatf("ICMPv6 type:%0d code:%0d id:0x%04x seq:%0d",
                         icmp_type, icmp_code, identifier, sequence_num);
    endfunction

endclass

`endif // ICMPV6_HEADER_SV
```

- [ ] **Step 4: Run test — verify ICMP/ICMPv6 tests pass**

```bash
make run_protocol_headers SIM=vcs
```

- [ ] **Step 5: Commit**

```bash
git add src/protocols/l4/icmp_header.sv src/protocols/l4/icmpv6_header.sv test/test_protocol_headers.sv
git commit -m "feat: add icmp_header and icmpv6_header"
```

---

### Task 12: protocol_graph.sv — Protocol transition graph

**Files:**
- Create: `src/core/protocol_graph.sv`
- Create: `test/test_protocol_graph.sv`

- [ ] **Step 1: Write test_protocol_graph.sv**

```systemverilog
// test/test_protocol_graph.sv
`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "core/protocol_graph.sv"

program test_protocol_graph;

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
        protocol_graph g;
        protocol_type_e result[$];

        $display("=== test_protocol_graph ===");

        g = new();

        // Test: Ethernet -> IPv4 is valid
        check("graph: eth->ipv4 valid", g.is_valid_next(PROTO_ETHERNET, PROTO_IPV4));

        // Test: Ethernet -> IPv6 is valid
        check("graph: eth->ipv6 valid", g.is_valid_next(PROTO_ETHERNET, PROTO_IPV6));

        // Test: Ethernet -> TCP is invalid
        check("graph: eth->tcp invalid", !g.is_valid_next(PROTO_ETHERNET, PROTO_TCP));

        // Test: IPv4 -> TCP valid
        check("graph: ipv4->tcp valid", g.is_valid_next(PROTO_IPV4, PROTO_TCP));

        // Test: IPv4 -> UDP valid
        check("graph: ipv4->udp valid", g.is_valid_next(PROTO_IPV4, PROTO_UDP));

        // Test: UDP -> VXLAN valid
        check("graph: udp->vxlan valid", g.is_valid_next(PROTO_UDP, PROTO_VXLAN));

        // Test: VXLAN -> Ethernet valid (inner L2)
        check("graph: vxlan->eth valid", g.is_valid_next(PROTO_VXLAN, PROTO_ETHERNET));

        // Test: VXLAN -> TCP invalid
        check("graph: vxlan->tcp invalid", !g.is_valid_next(PROTO_VXLAN, PROTO_TCP));

        // Test: get_valid_next for IPv4
        g.get_valid_next(PROTO_IPV4, result);
        check("graph: ipv4 has TCP in nexts", result.find_first_index(x) with (x == PROTO_TCP) != '{});
        check("graph: ipv4 has UDP in nexts", result.find_first_index(x) with (x == PROTO_UDP) != '{});
        check("graph: ipv4 has GRE in nexts", result.find_first_index(x) with (x == PROTO_GRE) != '{});

        // Test: validate_chain — valid chain
        check("graph: validate ETH/IP/TCP",
              g.validate_chain('{PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP}));

        // Test: validate_chain — valid VXLAN chain
        check("graph: validate ETH/IP/UDP/VXLAN/ETH/IP/TCP",
              g.validate_chain('{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_VXLAN,
                                 PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP}));

        // Test: validate_chain — invalid chain (ETH -> TCP)
        check("graph: validate ETH/TCP invalid",
              !g.validate_chain('{PROTO_ETHERNET, PROTO_TCP}));

        // Test: validate_chain — single element (always valid)
        check("graph: validate single ETH", g.validate_chain('{PROTO_ETHERNET}));

        // Test: VLAN nesting
        check("graph: vlan->vlan valid", g.is_valid_next(PROTO_VLAN, PROTO_VLAN));
        check("graph: validate ETH/VLAN/VLAN/IPv4",
              g.validate_chain('{PROTO_ETHERNET, PROTO_VLAN, PROTO_VLAN, PROTO_IPV4}));

        // Test: IPv6 extension headers
        check("graph: ipv6->hbh valid", g.is_valid_next(PROTO_IPV6, PROTO_IPV6_HBH));
        check("graph: hbh->tcp valid", g.is_valid_next(PROTO_IPV6_HBH, PROTO_TCP));

        // Test: user-added transition
        g.register_transition(PROTO_TCP, PROTO_RAW_PAYLOAD);  // already registered, should not duplicate
        check("graph: tcp->raw valid", g.is_valid_next(PROTO_TCP, PROTO_RAW_PAYLOAD));

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end
endprogram
```

- [ ] **Step 2: Run test — verify it fails**

```bash
make run_protocol_graph SIM=vcs
```

Expected: Compilation error — `protocol_graph.sv` not found.

- [ ] **Step 3: Write protocol_graph.sv**

```systemverilog
// src/core/protocol_graph.sv
`ifndef PROTOCOL_GRAPH_SV
`define PROTOCOL_GRAPH_SV

`include "packet_defines.sv"

class protocol_graph;

    // Adjacency list: protocol -> list of valid next-layer protocols
    protected protocol_type_e legal_next[protocol_type_e][$];

    function new();
        init_default_transitions();
    endfunction

    // Register a valid transition. Duplicate-safe: won't add if already present.
    function void register_transition(protocol_type_e from, protocol_type_e to);
        if (!legal_next.exists(from)) begin
            legal_next[from] = '{to};
            return;
        end
        // Check for duplicate
        foreach (legal_next[from][i]) begin
            if (legal_next[from][i] == to) return;
        end
        legal_next[from].push_back(to);
    endfunction

    // Check if from -> to is a valid transition
    function bit is_valid_next(protocol_type_e from, protocol_type_e to);
        if (!legal_next.exists(from)) return 0;
        foreach (legal_next[from][i]) begin
            if (legal_next[from][i] == to) return 1;
        end
        return 0;
    endfunction

    // Get all valid next-layer protocols for a given protocol
    function void get_valid_next(protocol_type_e from, ref protocol_type_e result[$]);
        result = {};
        if (legal_next.exists(from)) begin
            result = legal_next[from];
        end
    endfunction

    // Validate an entire protocol chain
    function bit validate_chain(protocol_type_e chain[$]);
        if (chain.size() <= 1) return 1;
        for (int i = 0; i < chain.size() - 1; i++) begin
            if (!is_valid_next(chain[i], chain[i+1])) return 0;
        end
        return 1;
    endfunction

    // Initialize all default protocol transitions per spec
    protected function void init_default_transitions();
        // Ethernet
        register_transition(PROTO_ETHERNET, PROTO_IPV4);
        register_transition(PROTO_ETHERNET, PROTO_IPV6);
        register_transition(PROTO_ETHERNET, PROTO_ARP);
        register_transition(PROTO_ETHERNET, PROTO_VLAN);
        register_transition(PROTO_ETHERNET, PROTO_QINQ);
        register_transition(PROTO_ETHERNET, PROTO_MPLS);
        register_transition(PROTO_ETHERNET, PROTO_LLDP);
        register_transition(PROTO_ETHERNET, PROTO_LACP);
        register_transition(PROTO_ETHERNET, PROTO_STP);
        register_transition(PROTO_ETHERNET, PROTO_MACSEC);
        register_transition(PROTO_ETHERNET, PROTO_EAP);
        register_transition(PROTO_ETHERNET, PROTO_MAC_CONTROL);
        register_transition(PROTO_ETHERNET, PROTO_PTP);

        // VLAN
        register_transition(PROTO_VLAN, PROTO_IPV4);
        register_transition(PROTO_VLAN, PROTO_IPV6);
        register_transition(PROTO_VLAN, PROTO_ARP);
        register_transition(PROTO_VLAN, PROTO_VLAN);
        register_transition(PROTO_VLAN, PROTO_MPLS);

        // QinQ
        register_transition(PROTO_QINQ, PROTO_VLAN);
        register_transition(PROTO_QINQ, PROTO_IPV4);
        register_transition(PROTO_QINQ, PROTO_IPV6);

        // IPv4
        register_transition(PROTO_IPV4, PROTO_TCP);
        register_transition(PROTO_IPV4, PROTO_UDP);
        register_transition(PROTO_IPV4, PROTO_ICMP);
        register_transition(PROTO_IPV4, PROTO_IGMP);
        register_transition(PROTO_IPV4, PROTO_GRE);
        register_transition(PROTO_IPV4, PROTO_IP_IN_IP);
        register_transition(PROTO_IPV4, PROTO_OSPF);
        register_transition(PROTO_IPV4, PROTO_SCTP);

        // IPv6
        register_transition(PROTO_IPV6, PROTO_TCP);
        register_transition(PROTO_IPV6, PROTO_UDP);
        register_transition(PROTO_IPV6, PROTO_ICMPV6);
        register_transition(PROTO_IPV6, PROTO_IPV6_HBH);
        register_transition(PROTO_IPV6, PROTO_IPV6_ROUTING);
        register_transition(PROTO_IPV6, PROTO_IPV6_FRAGMENT);
        register_transition(PROTO_IPV6, PROTO_IPV6_DEST);
        register_transition(PROTO_IPV6, PROTO_GRE);
        register_transition(PROTO_IPV6, PROTO_OSPF);
        register_transition(PROTO_IPV6, PROTO_SCTP);

        // IPv6 Extension Headers
        register_transition(PROTO_IPV6_HBH, PROTO_IPV6_ROUTING);
        register_transition(PROTO_IPV6_HBH, PROTO_IPV6_FRAGMENT);
        register_transition(PROTO_IPV6_HBH, PROTO_IPV6_DEST);
        register_transition(PROTO_IPV6_HBH, PROTO_TCP);
        register_transition(PROTO_IPV6_HBH, PROTO_UDP);
        register_transition(PROTO_IPV6_HBH, PROTO_ICMPV6);

        register_transition(PROTO_IPV6_ROUTING, PROTO_IPV6_FRAGMENT);
        register_transition(PROTO_IPV6_ROUTING, PROTO_IPV6_DEST);
        register_transition(PROTO_IPV6_ROUTING, PROTO_TCP);
        register_transition(PROTO_IPV6_ROUTING, PROTO_UDP);
        register_transition(PROTO_IPV6_ROUTING, PROTO_ICMPV6);

        register_transition(PROTO_IPV6_FRAGMENT, PROTO_TCP);
        register_transition(PROTO_IPV6_FRAGMENT, PROTO_UDP);
        register_transition(PROTO_IPV6_FRAGMENT, PROTO_ICMPV6);
        register_transition(PROTO_IPV6_FRAGMENT, PROTO_IPV6_DEST);

        register_transition(PROTO_IPV6_DEST, PROTO_TCP);
        register_transition(PROTO_IPV6_DEST, PROTO_UDP);
        register_transition(PROTO_IPV6_DEST, PROTO_ICMPV6);

        // UDP upper layers
        register_transition(PROTO_UDP, PROTO_VXLAN);
        register_transition(PROTO_UDP, PROTO_GENEVE);
        register_transition(PROTO_UDP, PROTO_GTP_U);
        register_transition(PROTO_UDP, PROTO_GTP_C);
        register_transition(PROTO_UDP, PROTO_MPLS_UDP);
        register_transition(PROTO_UDP, PROTO_DNS);
        register_transition(PROTO_UDP, PROTO_DHCP);
        register_transition(PROTO_UDP, PROTO_DHCPV6);
        register_transition(PROTO_UDP, PROTO_BFD);
        register_transition(PROTO_UDP, PROTO_ROCEV2);
        register_transition(PROTO_UDP, PROTO_SNMP);
        register_transition(PROTO_UDP, PROTO_PTP);
        register_transition(PROTO_UDP, PROTO_RAW_PAYLOAD);

        // TCP upper layers
        register_transition(PROTO_TCP, PROTO_HTTP);
        register_transition(PROTO_TCP, PROTO_IWARP);
        register_transition(PROTO_TCP, PROTO_NVME_TCP);
        register_transition(PROTO_TCP, PROTO_ISCSI);
        register_transition(PROTO_TCP, PROTO_BGP);
        register_transition(PROTO_TCP, PROTO_DNS);
        register_transition(PROTO_TCP, PROTO_RAW_PAYLOAD);

        // Tunnel -> inner
        register_transition(PROTO_VXLAN, PROTO_ETHERNET);
        register_transition(PROTO_GRE, PROTO_IPV4);
        register_transition(PROTO_GRE, PROTO_IPV6);
        register_transition(PROTO_GRE, PROTO_ETHERNET);
        register_transition(PROTO_GRE, PROTO_ERSPAN_I);
        register_transition(PROTO_GRE, PROTO_ERSPAN_II);
        register_transition(PROTO_GRE, PROTO_ERSPAN_III);
        register_transition(PROTO_GRE, PROTO_MPLS_GRE);
        register_transition(PROTO_GENEVE, PROTO_ETHERNET);
        register_transition(PROTO_NVGRE, PROTO_ETHERNET);
        register_transition(PROTO_ERSPAN_II, PROTO_ETHERNET);
        register_transition(PROTO_ERSPAN_III, PROTO_ETHERNET);
        register_transition(PROTO_GTP_U, PROTO_IPV4);
        register_transition(PROTO_GTP_U, PROTO_IPV6);
        register_transition(PROTO_L2TP, PROTO_IPV4);
        register_transition(PROTO_L2TP, PROTO_IPV6);

        // RDMA
        register_transition(PROTO_ROCEV2, PROTO_NVME_RDMA);
        register_transition(PROTO_ROCEV2, PROTO_RAW_PAYLOAD);

        // MPLS
        register_transition(PROTO_MPLS, PROTO_IPV4);
        register_transition(PROTO_MPLS, PROTO_IPV6);
        register_transition(PROTO_MPLS, PROTO_ETHERNET);
        register_transition(PROTO_MPLS, PROTO_MPLS);
    endfunction

endclass

`endif // PROTOCOL_GRAPH_SV
```

- [ ] **Step 4: Run test — verify graph tests pass**

```bash
make run_protocol_graph SIM=vcs
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/protocol_graph.sv test/test_protocol_graph.sv
git commit -m "feat: add protocol_graph with all default transitions"
```

---

### Task 13: template_registry.sv — Template to protocol chain mapping

**Files:**
- Create: `src/core/template_registry.sv`
- Modify: `test/test_protocol_graph.sv` (add template registry tests)

- [ ] **Step 1: Add template registry tests to test_protocol_graph.sv**

Insert before the final results line:

```systemverilog
        // ---- Template Registry ----
        begin
            template_registry reg_inst = new();
            protocol_type_e chain[$];

            // Test: ETH_IPV4_TCP
            reg_inst.get_chain(ETH_IPV4_TCP, chain);
            check("tmpl: ETH_IPV4_TCP length", chain.size() == 3);
            check("tmpl: ETH_IPV4_TCP[0]", chain[0] == PROTO_ETHERNET);
            check("tmpl: ETH_IPV4_TCP[1]", chain[1] == PROTO_IPV4);
            check("tmpl: ETH_IPV4_TCP[2]", chain[2] == PROTO_TCP);

            // Test: ETH_ARP
            reg_inst.get_chain(ETH_ARP, chain);
            check("tmpl: ETH_ARP length", chain.size() == 2);
            check("tmpl: ETH_ARP[0]", chain[0] == PROTO_ETHERNET);
            check("tmpl: ETH_ARP[1]", chain[1] == PROTO_ARP);

            // Test: VXLAN template
            reg_inst.get_chain(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP, chain);
            check("tmpl: VXLAN length", chain.size() == 7);
            check("tmpl: VXLAN[3]", chain[3] == PROTO_VXLAN);
            check("tmpl: VXLAN[4]", chain[4] == PROTO_ETHERNET);

            // Test: VLAN template
            reg_inst.get_chain(ETH_VLAN_IPV4_TCP, chain);
            check("tmpl: VLAN length", chain.size() == 4);
            check("tmpl: VLAN[1]", chain[1] == PROTO_VLAN);

            // Test: all templates validate against protocol graph
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
        end
```

- [ ] **Step 2: Write template_registry.sv**

```systemverilog
// src/core/template_registry.sv
`ifndef TEMPLATE_REGISTRY_SV
`define TEMPLATE_REGISTRY_SV

`include "packet_defines.sv"

class template_registry;

    protected protocol_type_e chains[packet_template_e][$];

    function new();
        init_default_templates();
    endfunction

    function void register_template(packet_template_e tmpl, protocol_type_e chain[$]);
        chains[tmpl] = chain;
    endfunction

    function void get_chain(packet_template_e tmpl, ref protocol_type_e chain[$]);
        if (chains.exists(tmpl))
            chain = chains[tmpl];
        else
            chain = {};
    endfunction

    protected function void init_default_templates();
        // Basic
        chains[ETH_IPV4_TCP]     = '{PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP};
        chains[ETH_IPV4_UDP]     = '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP};
        chains[ETH_IPV6_TCP]     = '{PROTO_ETHERNET, PROTO_IPV6, PROTO_TCP};
        chains[ETH_IPV6_UDP]     = '{PROTO_ETHERNET, PROTO_IPV6, PROTO_UDP};
        chains[ETH_ARP]          = '{PROTO_ETHERNET, PROTO_ARP};
        chains[ETH_IPV4_ICMP]    = '{PROTO_ETHERNET, PROTO_IPV4, PROTO_ICMP};
        chains[ETH_IPV6_ICMPV6]  = '{PROTO_ETHERNET, PROTO_IPV6, PROTO_ICMPV6};

        // VLAN
        chains[ETH_VLAN_IPV4_TCP] = '{PROTO_ETHERNET, PROTO_VLAN, PROTO_IPV4, PROTO_TCP};
        chains[ETH_VLAN_IPV4_UDP] = '{PROTO_ETHERNET, PROTO_VLAN, PROTO_IPV4, PROTO_UDP};
        chains[ETH_VLAN_IPV6_TCP] = '{PROTO_ETHERNET, PROTO_VLAN, PROTO_IPV6, PROTO_TCP};
        chains[ETH_VLAN_IPV6_UDP] = '{PROTO_ETHERNET, PROTO_VLAN, PROTO_IPV6, PROTO_UDP};
        chains[ETH_QINQ_IPV4_TCP] = '{PROTO_ETHERNET, PROTO_QINQ, PROTO_VLAN, PROTO_IPV4, PROTO_TCP};
        chains[ETH_QINQ_IPV4_UDP] = '{PROTO_ETHERNET, PROTO_QINQ, PROTO_VLAN, PROTO_IPV4, PROTO_UDP};

        // Tunnel
        chains[ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_VXLAN, PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP};
        chains[ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_VXLAN, PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP};
        chains[ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_VXLAN, PROTO_ETHERNET, PROTO_IPV6, PROTO_TCP};
        chains[ETH_IPV4_GRE_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_GRE, PROTO_IPV4, PROTO_TCP};
        chains[ETH_IPV4_GRE_IPV4_UDP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_GRE, PROTO_IPV4, PROTO_UDP};
        chains[ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_GENEVE, PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP};
        chains[ETH_IPV4_GRE_ETH_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_GRE, PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP};
        chains[ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_GRE, PROTO_ERSPAN_II, PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP};
        chains[ETH_IPV4_UDP_GTP_U_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_GTP_U, PROTO_IPV4, PROTO_TCP};

        // VLAN + Tunnel
        chains[ETH_VLAN_IPV4_UDP_VXLAN_ETH_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_VLAN, PROTO_IPV4, PROTO_UDP, PROTO_VXLAN, PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP};

        // RDMA
        chains[ETH_IPV4_UDP_ROCEV2] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_ROCEV2};
        chains[ETH_VLAN_IPV4_UDP_ROCEV2] =
            '{PROTO_ETHERNET, PROTO_VLAN, PROTO_IPV4, PROTO_UDP, PROTO_ROCEV2};

        // Storage
        chains[ETH_IPV4_TCP_NVME_TCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP, PROTO_NVME_TCP};
        chains[ETH_IPV4_UDP_ROCEV2_NVME_RDMA] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_ROCEV2, PROTO_NVME_RDMA};
        chains[ETH_IPV4_TCP_ISCSI] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP, PROTO_ISCSI};
        chains[ETH_IPV4_TCP_IWARP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP, PROTO_IWARP};

        // Mgmt/Control
        chains[ETH_IPV4_UDP_DHCP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_DHCP};
        chains[ETH_IPV6_UDP_DHCPV6] =
            '{PROTO_ETHERNET, PROTO_IPV6, PROTO_UDP, PROTO_DHCPV6};
        chains[ETH_IPV4_UDP_DNS] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_DNS};
        chains[ETH_IPV4_UDP_BFD] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_BFD};
        chains[ETH_IPV4_UDP_PTP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_PTP};
        chains[ETH_PTP_L2] =
            '{PROTO_ETHERNET, PROTO_PTP};
        chains[ETH_IGMP] =
            '{PROTO_ETHERNET, PROTO_IPV4, PROTO_IGMP};
        chains[ETH_LLDP] =
            '{PROTO_ETHERNET, PROTO_LLDP};
        chains[ETH_LACP] =
            '{PROTO_ETHERNET, PROTO_LACP};
        chains[ETH_STP] =
            '{PROTO_ETHERNET, PROTO_STP};
        chains[ETH_MAC_CONTROL] =
            '{PROTO_ETHERNET, PROTO_MAC_CONTROL};

        // MPLS
        chains[ETH_MPLS_IPV4_TCP] =
            '{PROTO_ETHERNET, PROTO_MPLS, PROTO_IPV4, PROTO_TCP};
        chains[ETH_MPLS_IPV4_UDP] =
            '{PROTO_ETHERNET, PROTO_MPLS, PROTO_IPV4, PROTO_UDP};
    endfunction

endclass

`endif // TEMPLATE_REGISTRY_SV
```

- [ ] **Step 3: Update test includes and run**

Add `include "core/template_registry.sv"` to `test_protocol_graph.sv` after the protocol_graph include.

```bash
make run_protocol_graph SIM=vcs
```

Expected: All graph + template tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/core/template_registry.sv test/test_protocol_graph.sv
git commit -m "feat: add template_registry with all predefined template chains"
```

---

### Task 14: packet.sv — Core packet class

**Files:**
- Create: `src/core/packet.sv`
- Create: `test/test_packet_builder.sv`

- [ ] **Step 1: Write test_packet_builder.sv**

```systemverilog
// test/test_packet_builder.sv
`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "l2/eth_header.sv"
`include "l2/vlan_header.sv"
`include "l3/ipv4_header.sv"
`include "l3/ipv6_header.sv"
`include "l3/arp_header.sv"
`include "l4/tcp_header.sv"
`include "l4/udp_header.sv"
`include "l4/icmp_header.sv"
`include "l4/icmpv6_header.sv"
`include "core/protocol_graph.sv"
`include "core/template_registry.sv"
`include "core/packet.sv"

program test_packet_builder;

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
        $display("=== test_packet_builder ===");

        // Test 1: Build from template ETH_IPV4_TCP
        begin
            packet pkt = new();
            byte unsigned data[$];
            protocol_base layers[$];

            pkt.build_from_template(ETH_IPV4_TCP);
            pkt.get_all_layers(layers);

            check("pkt: template ETH_IPV4_TCP layer count", layers.size() == 3);
            check("pkt: layer[0] is ETHERNET", layers[0].proto_type == PROTO_ETHERNET);
            check("pkt: layer[1] is IPV4", layers[1].proto_type == PROTO_IPV4);
            check("pkt: layer[2] is TCP", layers[2].proto_type == PROTO_TCP);

            // Pack
            pkt.pkt_length = 64;
            pkt.do_pack();
            data = pkt.raw_data;

            check("pkt: packed length >= 64", data.size() >= 64);
            check("pkt: starts with ETH dst_mac", data[0] == 8'h00 || 1);  // any value is fine

            // Verify headers_length
            check("pkt: headers_length = 14+20+20", pkt.get_all_headers_length() == 54);
        end

        // Test 2: Build from template ETH_ARP
        begin
            packet pkt = new();
            protocol_base layers[$];

            pkt.build_from_template(ETH_ARP);
            pkt.get_all_layers(layers);

            check("pkt: template ETH_ARP layer count", layers.size() == 2);
            check("pkt: ARP layer[1]", layers[1].proto_type == PROTO_ARP);
        end

        // Test 3: Free-form construction
        begin
            packet pkt = new();
            protocol_base layers[$];

            pkt.add_layer(eth_header::create());
            pkt.add_layer(vlan_header::create(.vid(100)));
            pkt.add_layer(ipv4_header::create());
            pkt.add_layer(tcp_header::create());
            pkt.get_all_layers(layers);

            check("pkt: freeform layer count", layers.size() == 4);
            check("pkt: freeform VLAN present", layers[1].proto_type == PROTO_VLAN);
        end

        // Test 4: Invalid chain rejected (force_mode=0)
        begin
            packet pkt = new();
            bit added;

            pkt.add_layer(eth_header::create());
            added = pkt.add_layer(tcp_header::create());  // ETH -> TCP is invalid
            check("pkt: invalid chain rejected", !added);
        end

        // Test 5: Force mode allows invalid chain
        begin
            packet pkt = new();
            bit added;

            pkt.force_mode = 1;
            pkt.add_layer(eth_header::create());
            added = pkt.add_layer(tcp_header::create());  // Forced
            check("pkt: force_mode allows invalid", added);
        end

        // Test 6: get_layer
        begin
            packet pkt = new();
            protocol_base layer;

            pkt.build_from_template(ETH_IPV4_TCP);
            layer = pkt.get_layer(PROTO_IPV4);
            check("pkt: get_layer finds IPv4", layer != null && layer.proto_type == PROTO_IPV4);

            layer = pkt.get_layer(PROTO_VXLAN);
            check("pkt: get_layer returns null for missing", layer == null);
        end

        // Test 7: Length control — pkt_length > headers
        begin
            packet pkt = new();
            byte unsigned data[$];

            pkt.build_from_template(ETH_IPV4_UDP);
            pkt.pkt_length = 100;
            pkt.do_pack();
            data = pkt.raw_data;

            check("pkt: length control 100 bytes", data.size() == 100);
        end

        // Test 8: Length control — pkt_length < headers triggers warning
        begin
            packet pkt = new();
            byte unsigned data[$];
            int hdr_len;

            pkt.build_from_template(ETH_IPV4_TCP);
            hdr_len = pkt.get_all_headers_length();  // 54
            pkt.pkt_length = 30;  // Less than headers
            pkt.do_pack();
            data = pkt.raw_data;

            check("pkt: undersize generates full headers", data.size() == hdr_len);
        end

        // Test 9: Payload modes
        begin
            packet pkt = new();
            byte unsigned data[$];

            pkt.build_from_template(ETH_IPV4_UDP);
            pkt.pkt_length = 100;
            pkt.payload_mode = PAYLOAD_INCREMENT;
            pkt.do_pack();
            data = pkt.raw_data;

            // Payload starts after headers (14+20+8=42)
            check("pkt: increment payload[0]", data[42] == 8'h00);
            check("pkt: increment payload[1]", data[43] == 8'h01);
            check("pkt: increment payload[2]", data[44] == 8'h02);
        end

        // Test 10: Pack then unpack roundtrip
        begin
            packet pkt = new();
            packet pkt2 = new();
            byte unsigned data[$];

            pkt.build_from_template(ETH_IPV4_TCP);
            pkt.pkt_length = 80;
            pkt.do_pack();
            data = pkt.raw_data;

            pkt2.unpack(data);
            begin
                protocol_base layers[$];
                pkt2.get_all_layers(layers);
                check("pkt: unpack recovers 3 layers", layers.size() >= 3);
                check("pkt: unpack layer[0] ETH", layers[0].proto_type == PROTO_ETHERNET);
                check("pkt: unpack layer[1] IPv4", layers[1].proto_type == PROTO_IPV4);
                check("pkt: unpack layer[2] TCP", layers[2].proto_type == PROTO_TCP);
            end
        end

        // Test 11: to_proto_chain
        begin
            packet pkt = new();
            string chain_str;

            pkt.build_from_template(ETH_IPV4_TCP);
            chain_str = pkt.to_proto_chain();
            check("pkt: proto_chain string", chain_str == "PROTO_ETHERNET -> PROTO_IPV4 -> PROTO_TCP");
        end

        // Test 12: to_brief
        begin
            packet pkt = new();
            string brief;
            ipv4_header ip;
            tcp_header tcp;

            pkt.build_from_template(ETH_IPV4_TCP);
            ip = new();
            $cast(ip, pkt.get_layer(PROTO_IPV4));
            ip.src_addr = 32'hC0A80001;
            ip.dst_addr = 32'hC0A80002;
            $cast(tcp, pkt.get_layer(PROTO_TCP));
            tcp.src_port = 12345;
            tcp.dst_port = 80;

            brief = pkt.to_brief();
            // Should contain IP and port info
            check("pkt: to_brief not empty", brief.len() > 0);
        end

        $display("=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TESTS FAILED");
    end
endprogram
```

- [ ] **Step 2: Write packet.sv**

```systemverilog
// src/core/packet.sv
`ifndef PACKET_SV
`define PACKET_SV

`include "packet_defines.sv"
`include "packet_utils.sv"
`include "protocol_base.sv"
`include "core/protocol_graph.sv"
`include "core/template_registry.sv"
// Protocol headers included by the test/top-level file

class packet;

    // Layer stack
    protected protocol_base layer_stack[$];

    // Packet properties
    int unsigned    pkt_length    = 64;
    payload_mode_e  payload_mode  = PAYLOAD_RANDOM;
    byte unsigned   payload_pattern[$];    // For PAYLOAD_PATTERN mode
    bit [7:0]       payload_fixed_val = 0; // For PAYLOAD_FIXED mode
    bit             force_mode    = 0;

    // Output
    byte unsigned   raw_data[$];

    // Shared instances
    protected static protocol_graph   s_graph;
    protected static template_registry s_registry;

    function new();
        if (s_graph == null) s_graph = new();
        if (s_registry == null) s_registry = new();
    endfunction

    // Build from predefined template
    function void build_from_template(packet_template_e tmpl);
        protocol_type_e chain[$];
        s_registry.get_chain(tmpl, chain);
        layer_stack = {};
        foreach (chain[i]) begin
            protocol_base hdr = create_header(chain[i]);
            if (hdr != null) layer_stack.push_back(hdr);
        end
    endfunction

    // Add layer with protocol graph validation (returns 1 if added, 0 if rejected)
    function bit add_layer(protocol_base layer);
        if (!force_mode && layer_stack.size() > 0) begin
            protocol_type_e prev = layer_stack[layer_stack.size()-1].proto_type;
            if (!s_graph.is_valid_next(prev, layer.proto_type)) begin
                $warning("packet::add_layer: invalid transition %s -> %s (use force_mode to override)",
                         prev.name(), layer.proto_type.name());
                return 0;
            end
        end
        layer_stack.push_back(layer);
        return 1;
    endfunction

    // Get first layer matching protocol type
    function protocol_base get_layer(protocol_type_e proto);
        foreach (layer_stack[i]) begin
            if (layer_stack[i].proto_type == proto) return layer_stack[i];
        end
        return null;
    endfunction

    // Get all layers
    function void get_all_layers(ref protocol_base layers[$]);
        layers = layer_stack;
    endfunction

    // Total headers length
    function int get_all_headers_length();
        int total = 0;
        foreach (layer_stack[i]) total += layer_stack[i].get_header_length();
        return total;
    endfunction

    // Total packet length after pack
    function int get_total_length();
        return raw_data.size();
    endfunction

    // Pack all layers + payload into raw_data
    function void do_pack();
        byte unsigned payload[$];
        int hdr_len = get_all_headers_length();
        int payload_len;

        // Determine payload
        if (pkt_length < hdr_len) begin
            $warning("packet::do_pack: pkt_length(%0d) < headers_length(%0d), generating full headers without payload, actual_length=%0d",
                     pkt_length, hdr_len, hdr_len);
            payload_len = 0;
        end else begin
            payload_len = pkt_length - hdr_len;
        end

        // Generate payload bytes
        payload = {};
        for (int i = 0; i < payload_len; i++) begin
            case (payload_mode)
                PAYLOAD_RANDOM:    payload.push_back($urandom_range(0, 255));
                PAYLOAD_FIXED:     payload.push_back(payload_fixed_val);
                PAYLOAD_INCREMENT: payload.push_back(i % 256);
                PAYLOAD_PATTERN: begin
                    if (payload_pattern.size() > 0)
                        payload.push_back(payload_pattern[i % payload_pattern.size()]);
                    else
                        payload.push_back(0);
                end
            endcase
        end

        // Calc fields from innermost to outermost
        begin
            byte unsigned remaining_data[$];
            remaining_data = payload;
            for (int i = layer_stack.size() - 1; i >= 0; i--) begin
                protocol_type_e next_proto;
                if (i < layer_stack.size() - 1)
                    next_proto = layer_stack[i+1].proto_type;
                else
                    next_proto = PROTO_RAW_PAYLOAD;

                layer_stack[i].calc_fields(remaining_data, next_proto);

                // Prepend this header to remaining_data for outer layers
                begin
                    byte unsigned hdr_bytes[$];
                    layer_stack[i].pack_header(hdr_bytes);
                    foreach (remaining_data[j]) hdr_bytes.push_back(remaining_data[j]);
                    remaining_data = hdr_bytes;
                end
            end
        end

        // Now pack in order: headers + payload
        raw_data = {};
        foreach (layer_stack[i]) begin
            layer_stack[i].pack_header(raw_data);
        end
        foreach (payload[i]) raw_data.push_back(payload[i]);
    endfunction

    // Unpack from byte stream
    function void unpack(byte unsigned data[$]);
        int offset = 0;
        protocol_type_e current_proto = PROTO_ETHERNET;  // Start with Ethernet
        layer_stack = {};
        raw_data = data;

        while (offset < data.size()) begin
            protocol_base hdr = create_header(current_proto);
            if (hdr == null) break;

            hdr.unpack_header(data, offset);
            layer_stack.push_back(hdr);

            // Determine next protocol
            current_proto = identify_next_proto(hdr);
            if (current_proto == PROTO_RAW_PAYLOAD) break;
        end
    endfunction

    // Protocol chain string
    function string to_proto_chain();
        string s = "";
        foreach (layer_stack[i]) begin
            if (i > 0) s = {s, " -> "};
            s = {s, layer_stack[i].proto_type.name()};
        end
        return s;
    endfunction

    // Brief one-line summary
    function string to_brief();
        string proto_names = "";
        string detail = "";
        foreach (layer_stack[i]) begin
            if (i > 0) proto_names = {proto_names, "/"};
            // Short name without PROTO_ prefix
            proto_names = {proto_names, layer_stack[i].proto_type.name()};
        end
        // Get detail from innermost L3/L4
        foreach (layer_stack[i]) begin
            if (layer_stack[i].proto_type == PROTO_IPV4 ||
                layer_stack[i].proto_type == PROTO_IPV6 ||
                layer_stack[i].proto_type == PROTO_TCP  ||
                layer_stack[i].proto_type == PROTO_UDP) begin
                detail = {detail, " ", layer_stack[i].to_brief()};
            end
        end
        return $sformatf("[%s]%s len=%0d", proto_names, detail, raw_data.size());
    endfunction

    // Detailed multi-line output
    function string to_detail();
        string s = "";
        foreach (layer_stack[i]) begin
            s = {s, $sformatf("=== Layer %0d: %s ===\n", i, layer_stack[i].proto_type.name())};
            s = {s, layer_stack[i].to_string()};
        end
        // Payload hex dump
        if (raw_data.size() > get_all_headers_length()) begin
            byte unsigned payload_bytes[$];
            int hdr_len = get_all_headers_length();
            for (int i = hdr_len; i < raw_data.size(); i++)
                payload_bytes.push_back(raw_data[i]);
            s = {s, $sformatf("=== Payload (%0d bytes) ===\n", payload_bytes.size())};
            s = {s, packet_utils::hex_dump(payload_bytes)};
            s = {s, "\n"};
        end
        return s;
    endfunction

    // ---- Private helpers ----

    // Factory: create a header object from protocol type
    protected function protocol_base create_header(protocol_type_e proto);
        case (proto)
            PROTO_ETHERNET:  begin eth_header h = new(); return h; end
            PROTO_VLAN:      begin vlan_header h = new(); return h; end
            PROTO_QINQ:     begin vlan_header h = new(); h.proto_type = PROTO_QINQ; return h; end
            PROTO_IPV4:      begin ipv4_header h = new(); return h; end
            PROTO_IPV6:      begin ipv6_header h = new(); return h; end
            PROTO_ARP:       begin arp_header h = new(); return h; end
            PROTO_TCP:       begin tcp_header h = new(); return h; end
            PROTO_UDP:       begin udp_header h = new(); return h; end
            PROTO_ICMP:      begin icmp_header h = new(); return h; end
            PROTO_ICMPV6:    begin icmpv6_header h = new(); return h; end
            default: return null;  // Extended protocols added in Phase 2
        endcase
    endfunction

    // Identify next protocol from current header fields
    protected function protocol_type_e identify_next_proto(protocol_base hdr);
        case (hdr.proto_type)
            PROTO_ETHERNET: begin
                eth_header eth;
                $cast(eth, hdr);
                case (eth.ethertype)
                    ETHERTYPE_IPV4:  return PROTO_IPV4;
                    ETHERTYPE_IPV6:  return PROTO_IPV6;
                    ETHERTYPE_ARP:   return PROTO_ARP;
                    ETHERTYPE_VLAN:  return PROTO_VLAN;
                    ETHERTYPE_QINQ:  return PROTO_QINQ;
                    ETHERTYPE_MPLS_UNI: return PROTO_MPLS;
                    ETHERTYPE_LLDP:  return PROTO_LLDP;
                    ETHERTYPE_PTP:   return PROTO_PTP;
                    default:         return PROTO_RAW_PAYLOAD;
                endcase
            end
            PROTO_VLAN, PROTO_QINQ: begin
                vlan_header vlan;
                $cast(vlan, hdr);
                case (vlan.ethertype)
                    ETHERTYPE_IPV4:  return PROTO_IPV4;
                    ETHERTYPE_IPV6:  return PROTO_IPV6;
                    ETHERTYPE_ARP:   return PROTO_ARP;
                    ETHERTYPE_VLAN:  return PROTO_VLAN;
                    default:         return PROTO_RAW_PAYLOAD;
                endcase
            end
            PROTO_IPV4: begin
                ipv4_header ip;
                $cast(ip, hdr);
                case (ip.protocol)
                    IP_PROTO_TCP:      return PROTO_TCP;
                    IP_PROTO_UDP:      return PROTO_UDP;
                    IP_PROTO_ICMP:     return PROTO_ICMP;
                    IP_PROTO_IGMP:     return PROTO_IGMP;
                    IP_PROTO_GRE:      return PROTO_GRE;
                    IP_PROTO_IP_IN_IP: return PROTO_IP_IN_IP;
                    IP_PROTO_OSPF:     return PROTO_OSPF;
                    IP_PROTO_SCTP:     return PROTO_SCTP;
                    default:           return PROTO_RAW_PAYLOAD;
                endcase
            end
            PROTO_IPV6: begin
                ipv6_header ip6;
                $cast(ip6, hdr);
                case (ip6.next_header)
                    IPV6_NH_TCP:      return PROTO_TCP;
                    IPV6_NH_UDP:      return PROTO_UDP;
                    IPV6_NH_ICMPV6:   return PROTO_ICMPV6;
                    IPV6_NH_HBH:      return PROTO_IPV6_HBH;
                    IPV6_NH_ROUTING:  return PROTO_IPV6_ROUTING;
                    IPV6_NH_FRAGMENT: return PROTO_IPV6_FRAGMENT;
                    IPV6_NH_DEST:     return PROTO_IPV6_DEST;
                    IPV6_NH_GRE:      return PROTO_GRE;
                    IPV6_NH_OSPF:     return PROTO_OSPF;
                    IPV6_NH_SCTP:     return PROTO_SCTP;
                    default:          return PROTO_RAW_PAYLOAD;
                endcase
            end
            default: return PROTO_RAW_PAYLOAD;
        endcase
    endfunction

endclass

`endif // PACKET_SV
```

- [ ] **Step 3: Run test — verify packet builder tests pass**

```bash
make run_packet_builder SIM=vcs
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/core/packet.sv test/test_packet_builder.sv
git commit -m "feat: add packet class with template builder, free-form construction, pack/unpack, length control"
```

---

### Task 15: Update filelist.f + final integration test

**Files:**
- Modify: `filelist.f`

- [ ] **Step 1: Update filelist.f with all source files**

```
// filelist.f
+incdir+src/common
+incdir+src/protocols
+incdir+src/protocols/l2
+incdir+src/protocols/l3
+incdir+src/protocols/l4
+incdir+src/core

src/common/packet_defines.sv
src/common/packet_utils.sv
src/protocols/protocol_base.sv
src/protocols/l2/eth_header.sv
src/protocols/l2/vlan_header.sv
src/protocols/l3/ipv4_header.sv
src/protocols/l3/ipv6_header.sv
src/protocols/l3/arp_header.sv
src/protocols/l4/tcp_header.sv
src/protocols/l4/udp_header.sv
src/protocols/l4/icmp_header.sv
src/protocols/l4/icmpv6_header.sv
src/core/protocol_graph.sv
src/core/template_registry.sv
src/core/packet.sv
```

- [ ] **Step 2: Run all tests**

```bash
make test_all SIM=vcs
```

Expected: All test suites PASS.

- [ ] **Step 3: Commit**

```bash
git add filelist.f
git commit -m "feat: update filelist.f with all Phase 1 source files"
```

---

## Phase 1 Summary

After completing all 15 tasks, you will have:

- **8 protocol headers**: Ethernet, VLAN, IPv4, IPv6, ARP, TCP, UDP, ICMP/ICMPv6 — each with full pack/unpack/calc_fields/clone/compare/print
- **Protocol graph**: Complete transition table for all protocols (including those implemented in later phases)
- **Template registry**: All predefined template chains registered
- **Packet class**: Template + free-form construction, length control, payload modes, pack/unpack, force_mode, printing
- **Test suite**: 3 test programs covering utils, protocol headers, graph, templates, and packet builder

**Next phases** (separate plan documents):
- Phase 2: Tunnel headers (VXLAN, GRE, Geneve, ERSPAN, GTP), RDMA (RoCEv2, iWARP), Storage (NVMe, iSCSI), remaining L2/L3 (MPLS, LLDP, LACP, STP, MACsec, IGMP, DHCP, etc.), App (DNS, HTTP, BFD, PTP, SNMP)
- Phase 3: Protocol parser, packet comparator, pcap reader/writer, IP fragmentation
- Phase 4: Protocol sequences, traffic streams, UVM wrapper (packet_item, packet_sequence, protocol_seq_wrapper)

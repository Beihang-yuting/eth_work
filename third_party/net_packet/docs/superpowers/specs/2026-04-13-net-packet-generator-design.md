# Net Packet Generator Design Spec

基于 SystemVerilog + UVM 的网络报文生成器，用于协议一致性测试。核心层为纯 SV class，外层提供 UVM 封装。

## 1. 协议枚举与核心数据模型

### 1.1 协议类型枚举

统一协议标识，发包器和解析器共用：

```systemverilog
typedef enum {
    // L2
    PROTO_ETHERNET, PROTO_VLAN, PROTO_QINQ, PROTO_MPLS,
    PROTO_MAC_CONTROL, PROTO_LLDP, PROTO_LACP, PROTO_STP,
    PROTO_MACSEC, PROTO_EAP,
    // L3
    PROTO_IPV4, PROTO_IPV6, PROTO_ARP, PROTO_IGMP,
    PROTO_IPV6_HBH, PROTO_IPV6_ROUTING, PROTO_IPV6_FRAGMENT, PROTO_IPV6_DEST,
    PROTO_DHCP, PROTO_DHCPV6, PROTO_OSPF, PROTO_BGP, PROTO_ISIS,
    // L4
    PROTO_TCP, PROTO_UDP, PROTO_ICMP, PROTO_ICMPV6, PROTO_SCTP,
    // Tunnel
    PROTO_VXLAN, PROTO_GRE, PROTO_NVGRE, PROTO_GENEVE,
    PROTO_ERSPAN_I, PROTO_ERSPAN_II, PROTO_ERSPAN_III,
    PROTO_IP_IN_IP, PROTO_L2TP, PROTO_GTP_U, PROTO_GTP_C,
    PROTO_MPLS_GRE, PROTO_MPLS_UDP,
    // App/Mgmt
    PROTO_DNS, PROTO_HTTP, PROTO_SNMP, PROTO_BFD, PROTO_PTP,
    // Storage/RDMA
    PROTO_ROCEV2, PROTO_IWARP, PROTO_NVME_TCP, PROTO_NVME_RDMA, PROTO_ISCSI,
    // Special
    PROTO_RAW_PAYLOAD
} protocol_type_e;
```

### 1.2 报文模板枚举

预定义常见协议栈组合，无 `PKT_` 前缀，方便使用：

```systemverilog
typedef enum {
    // 基础
    ETH_IPV4_TCP,
    ETH_IPV4_UDP,
    ETH_IPV6_TCP,
    ETH_IPV6_UDP,
    ETH_ARP,
    ETH_IPV4_ICMP,
    ETH_IPV6_ICMPV6,
    // VLAN
    ETH_VLAN_IPV4_TCP,
    ETH_VLAN_IPV4_UDP,
    ETH_VLAN_IPV6_TCP,
    ETH_VLAN_IPV6_UDP,
    ETH_QINQ_IPV4_TCP,
    ETH_QINQ_IPV4_UDP,
    // 隧道
    ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP,
    ETH_IPV4_UDP_VXLAN_ETH_IPV4_UDP,
    ETH_IPV4_UDP_VXLAN_ETH_IPV6_TCP,
    ETH_IPV4_GRE_IPV4_TCP,
    ETH_IPV4_GRE_IPV4_UDP,
    ETH_IPV4_UDP_GENEVE_ETH_IPV4_TCP,
    ETH_IPV4_GRE_ETH_IPV4_TCP,      // NVGRE
    ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP,
    ETH_IPV4_UDP_GTP_U_IPV4_TCP,
    // VLAN + 隧道
    ETH_VLAN_IPV4_UDP_VXLAN_ETH_IPV4_TCP,
    // RDMA
    ETH_IPV4_UDP_ROCEV2,
    ETH_VLAN_IPV4_UDP_ROCEV2,
    // 存储
    ETH_IPV4_TCP_NVME_TCP,
    ETH_IPV4_UDP_ROCEV2_NVME_RDMA,
    ETH_IPV4_TCP_ISCSI,
    // iWARP
    ETH_IPV4_TCP_IWARP,
    // 管理/控制
    ETH_IPV4_UDP_DHCP,
    ETH_IPV6_UDP_DHCPV6,
    ETH_IPV4_UDP_DNS,
    ETH_IPV4_UDP_BFD,
    ETH_IPV4_UDP_PTP,
    ETH_PTP_L2,
    ETH_IGMP,
    ETH_LLDP,
    ETH_LACP,
    ETH_STP,
    ETH_MAC_CONTROL,
    // MPLS
    ETH_MPLS_IPV4_TCP,
    ETH_MPLS_IPV4_UDP
} packet_template_e;
```

### 1.3 协议头基类

```systemverilog
class protocol_base;
    protocol_type_e  proto_type;
    protocol_base    next_layer;      // 链式嵌套下一层
    bit              auto_calc = 1;   // 自动计算 checksum/length，置 0 可注入异常值

    // 核心虚方法
    virtual function void          pack(ref byte unsigned data[$]);
    virtual function void          unpack(ref byte unsigned data[$], ref int offset);
    virtual function int           get_header_length();
    virtual function void          calc_fields();      // 自动计算 checksum/length 等
    virtual function protocol_base clone();
    virtual function bit           compare(protocol_base other);
    virtual function void          print(int verbosity = 0);
    virtual function string        to_string();
endclass
```

每个协议头继承此基类，字段声明为 `rand`，通过 `constraint` 定义默认合理值。`auto_calc=0` 时跳过自动计算，允许用户注入异常值。

## 2. 协议图（Protocol Graph）

### 2.1 协议图结构

定义合法的协议上下层转换关系，是系统的核心路由表：

```systemverilog
class protocol_graph;
    // 邻接表：当前协议 -> 合法的下一层协议列表
    protocol_type_e legal_next[protocol_type_e][$];

    function void register_transition(protocol_type_e from, protocol_type_e to);
    function bit is_valid_next(protocol_type_e from, protocol_type_e to);
    function void get_valid_next(protocol_type_e from, ref protocol_type_e result[$]);
    function bit validate_chain(protocol_type_e chain[$]);
endclass
```

### 2.2 预置转换规则

```
Ethernet  -> {IPv4, IPv6, ARP, VLAN, QinQ, MPLS, LLDP, LACP, STP, MACsec, EAP, MAC_Control, PTP}
VLAN      -> {IPv4, IPv6, ARP, VLAN, MPLS}
IPv4      -> {TCP, UDP, ICMP, IGMP, GRE, IP_IN_IP, OSPF, SCTP, IPv6_Fragment}
IPv6      -> {TCP, UDP, ICMPv6, HBH, Routing, Fragment, Dest, GRE, OSPF, SCTP}
IPv6_HBH  -> {Routing, Fragment, Dest, TCP, UDP, ICMPv6}
IPv6_Routing -> {Fragment, Dest, TCP, UDP, ICMPv6}
IPv6_Fragment -> {TCP, UDP, ICMPv6, Dest}
IPv6_Dest -> {TCP, UDP, ICMPv6}
UDP       -> {VXLAN, Geneve, GTP_U, GTP_C, MPLS_UDP, DNS, DHCP, DHCPv6, BFD, RoCEv2, SNMP, PTP, RAW_PAYLOAD}
TCP       -> {HTTP, iWARP, NVMe_TCP, iSCSI, BGP, DNS, RAW_PAYLOAD}
VXLAN     -> {Ethernet}
GRE       -> {IPv4, IPv6, Ethernet, ERSPAN_I, ERSPAN_II, ERSPAN_III, MPLS_GRE}
Geneve    -> {Ethernet}
NVGRE     -> {Ethernet}
ERSPAN_II -> {Ethernet}
ERSPAN_III-> {Ethernet}
GTP_U     -> {IPv4, IPv6}
L2TP      -> {IPv4, IPv6}
RoCEv2    -> {NVMe_RDMA, RAW_PAYLOAD}
MPLS      -> {IPv4, IPv6, Ethernet, MPLS}
```

### 2.3 模板注册

```systemverilog
class template_registry;
    protocol_type_e template_chain[packet_template_e][$];

    function void register_template(packet_template_e tmpl, protocol_type_e chain[$]);
    function void get_chain(packet_template_e tmpl, ref protocol_type_e chain[$]);
endclass
```

模板枚举映射为协议图中的固定路径，例如 `ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP` 映射为：
`{PROTO_ETHERNET, PROTO_IPV4, PROTO_UDP, PROTO_VXLAN, PROTO_ETHERNET, PROTO_IPV4, PROTO_TCP}`

### 2.4 Force 模式（实例级）

```systemverilog
class packet;
    bit force_mode = 0;  // 实例级别，仅此报文跳过协议图校验
endclass
```

`force_mode` 下沉到每个 packet 实例。开启后可任意堆叠协议层构造异常报文，关闭时严格按协议图校验。

## 3. 报文构造器

### 3.1 报文类

```systemverilog
class packet;
    rand protocol_base    layer_stack[$];   // 协议层队列
    rand int unsigned     pkt_length;       // 报文总长度
    rand byte unsigned    payload[$];       // payload
    bit                   force_mode = 0;   // 实例级 force
    byte unsigned         raw_data[$];      // pack 后的 byte 流

    // 构造
    function void build_from_template(packet_template_e tmpl);
    function void add_layer(protocol_base layer);

    // 随机化
    function void randomize_all();  // 所有层随机化 + 跨层字段自动关联

    // 打包/解包
    function void pack(ref byte unsigned data[$]);
    function void unpack(byte unsigned data[$]);

    // 查询
    function protocol_base get_layer(protocol_type_e proto);
    function void get_all_layers(ref protocol_base layers[$]);
    function int get_total_length();
    function int get_all_headers_length();

    // IP 分片
    function void fragment(int unsigned mtu, ref packet fragments[$]);
    static function packet reassemble(packet fragments[$]);

    // 长度约束
    constraint c_length_default {
        pkt_length inside {[64:1518]};
    }

    constraint c_payload_size {
        payload.size() == (pkt_length > get_all_headers_length())
                          ? (pkt_length - get_all_headers_length())
                          : 0;
    }
endclass
```

### 3.2 长度控制

| 情况 | 处理 |
|---|---|
| `pkt_length > headers_length` | 正常：自动填充 payload 补齐差值 |
| `pkt_length == headers_length` | 正常：无 payload |
| `pkt_length < headers_length` | 告警 + 生成完整协议头，实际长度 = headers_length，无 payload |

### 3.3 Payload 填充模式

```systemverilog
typedef enum {
    PAYLOAD_RANDOM,       // 随机数据（默认）
    PAYLOAD_FIXED,        // 固定字节填充
    PAYLOAD_INCREMENT,    // 递增填充 0x00,0x01,0x02...
    PAYLOAD_PATTERN       // 用户自定义 pattern 循环填充
} payload_mode_e;
```

### 3.4 使用示例

```systemverilog
// 模板模式 + 随机化
packet pkt = new();
pkt.build_from_template(ETH_IPV4_TCP);
pkt.randomize_all() with {
    ipv4.src_addr == 32'hC0A80001;
    tcp.dst_port  == 16'd80;
    pkt_length    == 256;
};

// 自由组合模式
packet pkt2 = new();
pkt2.add_layer(eth_header::create());
pkt2.add_layer(vlan_header::create());
pkt2.add_layer(ipv4_header::create());
pkt2.add_layer(udp_header::create());
pkt2.add_layer(vxlan_header::create());
pkt2.add_layer(eth_header::create());
pkt2.add_layer(ipv4_header::create());
pkt2.add_layer(tcp_header::create());
pkt2.randomize_all();

// 异常报文
packet bad = new();
bad.force_mode = 1;
bad.add_layer(eth_header::create());
bad.add_layer(tcp_header::create());  // 跳过 IP 层
bad.randomize_all();

// 异常 checksum
pkt.get_layer(PROTO_IPV4).auto_calc = 0;
pkt.get_layer(PROTO_IPV4).header_checksum = 16'hDEAD;
```

## 4. 协议序列（Protocol Sequence）

### 4.1 序列基类

```systemverilog
class protocol_sequence;
    rand packet packets[$];
    protocol_type_e seq_type;

    virtual function void generate();
    function void get_packets(ref packet pkts[$]);
endclass
```

### 4.2 预定义序列

| 序列类 | 报文列表 |
|---|---|
| `tcp_handshake_seq` | SYN -> SYN-ACK -> ACK |
| `tcp_full_session_seq` | 三次握手 + N 个数据包 + 四次挥手 |
| `arp_seq` | ARP Request -> ARP Reply |
| `dhcp_dora_seq` | Discover -> Offer -> Request -> ACK |
| `dhcpv6_sarr_seq` | Solicit -> Advertise -> Request -> Reply |
| `icmp_ping_seq` | Echo Request -> Echo Reply |
| `igmp_join_leave_seq` | Membership Report -> Leave Group |
| `bfd_session_seq` | Init -> Up -> 周期性心跳 |
| `rocev2_conn_seq` | CM 建连 + RDMA Read/Write 操作序列 |
| `ptp_sync_seq` | Sync -> Follow_Up -> Delay_Req -> Delay_Resp |

序列内部通过约束保证关联字段一致性（五元组一致、seq/ack 递进等）。

### 4.3 使用示例

```systemverilog
tcp_full_session_seq tcp_seq = new();
tcp_seq.randomize() with {
    src_ip   == 32'hC0A80001;
    dst_ip   == 32'hC0A80002;
    src_port == 16'd12345;
    dst_port == 16'd80;
    data_pkt_count == 5;
};
tcp_seq.generate();

packet pkts[$];
tcp_seq.get_packets(pkts);  // SYN, SYN-ACK, ACK, 5x DATA, FIN, FIN-ACK, ACK
```

## 5. 流量模板（Traffic Stream）

### 5.1 流量模板类

```systemverilog
class traffic_stream;
    packet          base_pkt;
    int unsigned    pkt_count;        // 发包总数（0=持续）
    field_modifier  modifiers[$];

    function void generate(ref packet pkts[$]);
endclass

class field_modifier;
    string          field_path;       // 如 "ipv4.src_addr"
    modifier_mode_e mode;
    bit [63:0]      step;
    bit [63:0]      min_val;
    bit [63:0]      max_val;
    bit [63:0]      value_list[$];    // LIST 模式的值列表
endclass

typedef enum {
    MOD_INCREMENT,
    MOD_DECREMENT,
    MOD_RANDOM,
    MOD_LIST
} modifier_mode_e;
```

### 5.2 使用示例

```systemverilog
traffic_stream stream = new();
stream.base_pkt = pkt;
stream.pkt_count = 1000;

field_modifier m = new();
m.field_path = "ipv4.src_addr";
m.mode       = MOD_INCREMENT;
m.step       = 1;
m.min_val    = 32'hC0A80001;
m.max_val    = 32'hC0A800FE;
stream.modifiers.push_back(m);

packet stream_pkts[$];
stream.generate(stream_pkts);
```

## 6. 协议解析器（Protocol Parser）

### 6.1 解析器核心

复用协议图逐层识别：

```systemverilog
class protocol_parser;
    protocol_graph  graph;

    function packet parse(byte unsigned data[$]);
    function protocol_type_e identify_protocol(
        protocol_type_e current_proto,
        byte unsigned data[$],
        int offset
    );
    function parse_result_t validate(packet pkt);
endclass
```

### 6.2 解析结果

```systemverilog
typedef struct {
    bit              valid;
    protocol_type_e  proto_chain[$];
    string           errors[$];
    string           warnings[$];
} parse_result_t;
```

### 6.3 协议识别逻辑

| 当前层 | 识别字段 | 示例 |
|---|---|---|
| Ethernet | EtherType | 0x0800->IPv4, 0x86DD->IPv6, 0x0806->ARP, 0x8100->VLAN, 0x88F7->PTP |
| IPv4 | Protocol | 6->TCP, 17->UDP, 1->ICMP, 47->GRE, 4->IP-in-IP |
| IPv6 | Next Header | 同 IPv4 Protocol + 扩展头 (0->HBH, 43->Routing, 44->Fragment, 60->Dest) |
| UDP | dst_port | 4789->VXLAN, 6081->Geneve, 2152->GTP-U, 4791->RoCEv2 |
| TCP | dst_port | 4420->NVMe-TCP, 3260->iSCSI |
| GRE | Protocol Type | 0x88BE->ERSPAN, 0x6558->Transparent Ethernet |

### 6.4 打印输出

三种粒度：

```systemverilog
class packet;
    // 摘要 — 一行概览
    function string to_brief();
    // [Ethernet/IPv4/TCP] 192.168.0.1:12345 -> 192.168.0.2:80, len=128

    // 协议链 — 用枚举名打印
    function string to_proto_chain();
    // PROTO_ETHERNET -> PROTO_IPV4 -> PROTO_TCP

    // 详细 — 逐层展开所有字段 + payload hex dump
    function string to_detail();
    // === Layer 0: PROTO_ETHERNET ===
    //   dst_mac  : 00:11:22:33:44:55
    //   src_mac  : 66:77:88:99:AA:BB
    //   ethertype: 0x0800
    // === Layer 1: PROTO_IPV4 ===
    //   version  : 4
    //   ihl      : 5
    //   src_addr : 192.168.0.1
    //   dst_addr : 192.168.0.2
    //   protocol : 6
    //   checksum : 0xABCD (valid)
    // === Layer 2: PROTO_TCP ===
    //   src_port : 12345
    //   dst_port : 80
    // === Payload (46 bytes) ===
    //   0000: 00 01 02 03 04 05 06 07 08 09 ...
endclass
```

### 6.5 报文对比

```systemverilog
class packet_comparator;
    function void compare(packet a, packet b, ref diff_entry_t diffs[$]);
endclass

typedef struct {
    protocol_type_e layer;
    string          field_name;
    string          val_a;
    string          val_b;
} diff_entry_t;

// DIFF [PROTO_IPV4.ttl] expected: 64, actual: 63
// DIFF [PROTO_TCP.checksum] expected: 0x1234, actual: 0x5678
```

## 7. Pcap 文件读写

### 7.1 写入

```systemverilog
class pcap_writer;
    int     fd;
    string  filename;

    function void open(string path);
    function void write_global_header();
    function void write_packet(packet pkt, int unsigned timestamp_sec = 0,
                               int unsigned timestamp_usec = 0);
    function void write_packets(packet pkts[$]);
    function void close();
endclass
```

### 7.2 读取

```systemverilog
class pcap_reader;
    protocol_parser parser;

    function void open(string path);
    function void read_all(ref packet pkts[$]);
    function packet read_next();
    function bit eof();
    function void close();
endclass
```

### 7.3 格式支持

| 格式 | Magic Number | 说明 |
|---|---|---|
| pcap (little-endian) | 0xD4C3B2A1 | 标准 pcap |
| pcap (big-endian) | 0xA1B2C3D4 | 大端 pcap |

### 7.4 使用示例

```systemverilog
// 写入
pcap_writer pw = new();
pw.open("test_traffic.pcap");
pw.write_packets(pkts);
pw.close();

// 读取并解析
pcap_reader pr = new();
pr.open("captured.pcap");
packet imported[$];
pr.read_all(imported);
pr.close();

// 导入后可修改重用
imported[0].to_detail();
imported[0].get_layer(PROTO_IPV4).src_addr = 32'hAC100001;
```

## 8. UVM 封装层

### 8.1 UVM Sequence Item

```systemverilog
class packet_item extends uvm_sequence_item;
    `uvm_object_utils(packet_item)

    packet pkt;

    function void do_copy(uvm_object rhs);
    function bit  do_compare(uvm_object rhs, uvm_comparer comparer);
    function void do_print(uvm_printer printer);
    function void do_pack(uvm_packer packer);
    function void do_unpack(uvm_packer packer);
endclass
```

### 8.2 UVM Sequence

```systemverilog
// 单包 sequence
class packet_sequence extends uvm_sequence #(packet_item);
    `uvm_object_utils(packet_sequence)

    rand packet_template_e  tmpl;
    rand int unsigned       pkt_length;

    virtual task body();
        packet_item item = packet_item::type_id::create("item");
        item.pkt = new();
        item.pkt.build_from_template(tmpl);
        item.pkt.randomize_all() with { pkt_length == local::pkt_length; };
        `uvm_send(item)
    endtask
endclass

// 协议序列 sequence
class protocol_seq_wrapper extends uvm_sequence #(packet_item);
    protocol_sequence inner_seq;

    virtual task body();
        packet pkts[$];
        inner_seq.generate();
        inner_seq.get_packets(pkts);
        foreach (pkts[i]) begin
            packet_item item = packet_item::type_id::create($sformatf("item_%0d", i));
            item.pkt = pkts[i];
            `uvm_send(item)
        end
    endtask
endclass
```

## 9. IP 分片支持

```systemverilog
class packet;
    // 按 MTU 拆分为多个分片报文
    function void fragment(int unsigned mtu, ref packet fragments[$]);

    // 将分片报文重组为完整报文
    static function packet reassemble(packet fragments[$]);
endclass
```

IPv4 通过 flags(MF) + fragment_offset 字段控制分片；IPv6 通过 Fragment Extension Header 实现。

## 10. 项目结构

```
net_packet/
├── src/
│   ├── common/
│   │   ├── packet_defines.sv            # 协议枚举、模板枚举、类型定义
│   │   └── packet_utils.sv              # 工具函数（字节序转换、checksum 计算等）
│   ├── protocols/
│   │   ├── protocol_base.sv             # 协议头基类
│   │   ├── l2/
│   │   │   ├── eth_header.sv
│   │   │   ├── vlan_header.sv
│   │   │   ├── mpls_header.sv
│   │   │   ├── lldp_header.sv
│   │   │   ├── lacp_header.sv
│   │   │   ├── stp_header.sv
│   │   │   ├── macsec_header.sv
│   │   │   ├── mac_control_header.sv
│   │   │   └── eap_header.sv
│   │   ├── l3/
│   │   │   ├── ipv4_header.sv
│   │   │   ├── ipv6_header.sv
│   │   │   ├── ipv6_ext_header.sv       # HBH, Routing, Fragment, Dest
│   │   │   ├── arp_header.sv
│   │   │   ├── igmp_header.sv
│   │   │   ├── dhcp_header.sv
│   │   │   └── routing_header.sv        # OSPF, BGP, IS-IS
│   │   ├── l4/
│   │   │   ├── tcp_header.sv
│   │   │   ├── udp_header.sv
│   │   │   ├── icmp_header.sv
│   │   │   ├── icmpv6_header.sv
│   │   │   └── sctp_header.sv
│   │   ├── tunnel/
│   │   │   ├── vxlan_header.sv
│   │   │   ├── gre_header.sv
│   │   │   ├── nvgre_header.sv
│   │   │   ├── geneve_header.sv
│   │   │   ├── erspan_header.sv
│   │   │   ├── gtp_header.sv
│   │   │   ├── l2tp_header.sv
│   │   │   └── ip_in_ip_header.sv
│   │   ├── rdma/
│   │   │   ├── rocev2_header.sv         # BTH, RETH, AETH
│   │   │   └── iwarp_header.sv          # MPA, DDP, RDMAP
│   │   ├── storage/
│   │   │   ├── nvme_tcp_header.sv
│   │   │   ├── nvme_rdma_header.sv
│   │   │   └── iscsi_header.sv
│   │   └── app/
│   │       ├── dns_header.sv
│   │       ├── http_header.sv
│   │       ├── snmp_header.sv
│   │       ├── bfd_header.sv
│   │       └── ptp_header.sv
│   ├── core/
│   │   ├── packet.sv                    # 报文类
│   │   ├── packet_builder.sv            # 构造器
│   │   ├── protocol_graph.sv            # 协议图
│   │   └── template_registry.sv         # 模板注册表
│   ├── sequence/
│   │   ├── protocol_sequence.sv         # 序列基类
│   │   ├── tcp_sequences.sv
│   │   ├── arp_sequence.sv
│   │   ├── dhcp_sequence.sv
│   │   ├── icmp_sequence.sv
│   │   ├── igmp_sequence.sv
│   │   ├── bfd_sequence.sv
│   │   ├── ptp_sequence.sv
│   │   └── rocev2_sequence.sv
│   ├── stream/
│   │   ├── traffic_stream.sv
│   │   └── field_modifier.sv
│   ├── parser/
│   │   ├── protocol_parser.sv
│   │   └── packet_comparator.sv
│   ├── pcap/
│   │   ├── pcap_writer.sv
│   │   └── pcap_reader.sv
│   └── uvm_wrapper/
│       ├── packet_item.sv
│       ├── packet_sequence.sv
│       └── protocol_seq_wrapper.sv
├── test/
│   ├── test_basic_packet.sv
│   ├── test_template_packets.sv
│   ├── test_protocol_sequences.sv
│   ├── test_parser.sv
│   ├── test_pcap.sv
│   └── test_abnormal_packets.sv
├── docs/
│   └── superpowers/
│       └── specs/
└── filelist.f
```

# net_packet — SystemVerilog 网络报文生成与解析框架

一个纯 SystemVerilog 实现的网络报文构建、解析、验证与 PCAP 读写框架，适用于 FPGA/ASIC 验证环境中的网络协议仿真与测试。

## 功能概览

- **70+ 种报文模板**：覆盖基本 L2-L4、隧道封装、RDMA、存储、管理协议
- **自动字段计算**：checksum、length、ethertype、protocol 等字段自动填充
- **协议图约束**：基于有向图的协议栈合法性校验，防止非法协议组合
- **PCAP 读写**：支持标准 PCAP 格式的写入与读取，可与 Wireshark 等工具互操作
- **协议解析器**：从原始字节流自动识别并解析协议栈，支持 checksum 验证
- **报文比较器**：逐字段对比两个报文，精确定位差异
- **IP 分片与 TCP 分段**：支持 IPv4 分片重组和 TCP 分段
- **流量流（Traffic Stream）**：支持字段递增/递减/随机修改，生成流量序列
- **协议序列**：预置 TCP 三次握手/四次挥手、ARP 请求/应答、ICMP ping 等序列
- **UVM 封装**：提供 `packet_item` 和 `packet_sequence` 供 UVM 环境集成
- **VCS/Questa 兼容**：经 VCS Q-2020.03-SP2-7 和 Questa 全面测试通过

## 支持的协议

### L2（数据链路层）
| 协议 | 头文件 | 说明 |
|------|--------|------|
| Ethernet | `l2/eth_header.sv` | IEEE 802.3 以太网帧 |
| VLAN/QinQ | `l2/vlan_header.sv` | 802.1Q / 802.1ad 双标签 |
| MPLS | `l2/mpls_header.sv` | 多协议标签交换 |

### L3（网络层）
| 协议 | 头文件 | 说明 |
|------|--------|------|
| IPv4 | `l3/ipv4_header.sv` | 含 header checksum 自动计算 |
| IPv6 | `l3/ipv6_header.sv` | 支持扩展头 |
| IPv6 Ext | `l3/ipv6_ext_header.sv` | Hop-by-Hop / Routing / Destination / Fragment |
| ARP | `l3/arp_header.sv` | 地址解析协议 |

### L4（传输层）
| 协议 | 头文件 | 说明 |
|------|--------|------|
| TCP | `l4/tcp_header.sv` | 含 options（MSS/WScale/SACK/Timestamps）和伪头 checksum |
| UDP | `l4/udp_header.sv` | 含伪头 checksum |
| ICMP | `l4/icmp_header.sv` | ICMPv4 |
| ICMPv6 | `l4/icmpv6_header.sv` | 含伪头 checksum |
| SCTP | `l4/sctp_header.sv` | 流控制传输协议 |

### 隧道协议
| 协议 | 头文件 | 说明 |
|------|--------|------|
| VXLAN | `tunnel/vxlan_header.sv` | Virtual eXtensible LAN (RFC 7348) |
| VXLAN-GPE | `tunnel/vxlan_gpe_header.sv` | VXLAN Generic Protocol Extension |
| Geneve | `tunnel/geneve_header.sv` | Generic Network Virtualization Encapsulation (RFC 8926) |
| GRE | `tunnel/gre_header.sv` | Generic Routing Encapsulation，支持 key/seq/checksum |
| GTP-U | `tunnel/gtp_header.sv` | GPRS Tunnelling Protocol User Plane |
| ERSPAN II/III | `tunnel/erspan_header.sv` | Encapsulated Remote SPAN |
| IP-in-IP | `tunnel/ip_in_ip_header.sv` | IP 隧道 |
| ESP | `tunnel/esp_header.sv` | IPsec 封装安全载荷 |

### RDMA
| 协议 | 头文件 | 说明 |
|------|--------|------|
| RoCEv2 | `rdma/rocev2_header.sv` | RDMA over Converged Ethernet v2，支持 BTH/RETH/AETH |
| iWARP | `rdma/iwarp_header.sv` | Internet Wide Area RDMA Protocol |

### 存储协议
| 协议 | 头文件 | 说明 |
|------|--------|------|
| NVMe-TCP | `storage/nvme_tcp_header.sv` | NVMe over TCP |
| iSCSI | `storage/iscsi_header.sv` | Internet Small Computer Systems Interface |

### 应用层
| 协议 | 头文件 | 说明 |
|------|--------|------|
| PTP | `app/ptp_header.sv` | IEEE 1588 精确时间协议 |

## 项目结构

```
net_packet/
├── src/
│   ├── common/
│   │   ├── packet_defines.sv      # 枚举定义、类型定义、模板枚举
│   │   └── packet_utils.sv        # 字节打包/解包、checksum 计算工具
│   ├── core/
│   │   ├── packet.sv              # 核心报文类（构建、打包、解包、字段计算）
│   │   ├── protocol_graph.sv      # 协议转换有向图（合法性校验）
│   │   ├── template_registry.sv   # 70+ 报文模板注册表
│   │   ├── ip_fragment.sv         # IPv4 分片与重组
│   │   └── tcp_segment.sv         # TCP 分段
│   ├── protocols/
│   │   ├── protocol_base.sv       # 协议头基类（pack/unpack/clone/compare/verify）
│   │   ├── l2/                    # Ethernet, VLAN, MPLS
│   │   ├── l3/                    # IPv4, IPv6, ARP, IPv6 扩展头
│   │   ├── l4/                    # TCP, UDP, ICMP, ICMPv6, SCTP
│   │   ├── tunnel/                # VXLAN, GRE, Geneve, GTP-U, ERSPAN, ESP 等
│   │   ├── rdma/                  # RoCEv2, iWARP
│   │   ├── storage/               # NVMe-TCP, iSCSI
│   │   └── app/                   # PTP
│   ├── parser/
│   │   ├── protocol_parser.sv     # 协议解析器（自动识别协议栈、checksum 验证）
│   │   └── packet_comparator.sv   # 报文比较器（逐字段差异对比）
│   ├── pcap/
│   │   ├── pcap_writer.sv         # PCAP 文件写入
│   │   └── pcap_reader.sv         # PCAP 文件读取
│   ├── sequence/
│   │   ├── protocol_sequence.sv   # 协议序列基类
│   │   ├── tcp_sequences.sv       # TCP 握手/挥手序列
│   │   ├── arp_sequence.sv        # ARP 请求/应答序列
│   │   ├── icmp_sequence.sv       # ICMP ping 序列
│   │   └── ptp_sequence.sv        # PTP 同步序列
│   ├── stream/
│   │   ├── traffic_stream.sv      # 流量流生成器
│   │   └── field_modifier.sv      # 字段修改器（递增/递减/随机/列表）
│   └── uvm_wrapper/
│       ├── packet_item.sv         # UVM sequence_item 封装
│       ├── packet_sequence.sv     # UVM sequence 封装
│       └── protocol_seq_wrapper.sv
├── test/                          # 15 个测试文件，覆盖所有功能模块
├── tools/
│   └── pkt_help.c                 # 独立 CLI 帮助工具
├── Makefile                       # 构建与测试入口
└── filelist.f                     # 仿真器文件列表
```

## 快速开始

### 环境要求

- Synopsys VCS（Q-2020.03 或更高版本）或 Mentor Questa
- GCC（仅编译 CLI 帮助工具时需要）

### 运行测试

```bash
# 运行全部 15 个测试
make test_all

# 运行单个测试
make test_packet_builder       # 报文构建测试
make test_protocol_headers     # 各协议头 pack/unpack 测试
make test_tunnel_headers       # 隧道协议测试
make test_rdma_storage_headers # RDMA/存储协议测试
make test_parser               # 协议解析与验证测试
make test_pcap                 # PCAP 读写测试
make test_pcap_verify          # PCAP 往返综合验证（含 checksum）
make test_ip_fragment          # IP 分片测试
make test_protocol_sequences   # 协议序列测试
make test_traffic_stream       # 流量流测试

# 使用 Questa 仿真器
make test_all SIM=questa
```

### 编译 CLI 帮助工具

```bash
make pkt_help
./pkt_help          # 查看所有协议模板与使用说明
```

## 使用示例

### 1. 构建并发送报文

```systemverilog
// 使用模板快速创建 IPv4 TCP 报文
packet pkt = new();
pkt.build_from_template(ETH_IPV4_TCP);

// 设置字段
ipv4_header ip;
$cast(ip, pkt.get_layer(PROTO_IPV4));
ip.src_addr = 32'hC0A80101;   // 192.168.1.1
ip.dst_addr = 32'hC0A80102;   // 192.168.1.2

tcp_header tcp;
$cast(tcp, pkt.get_layer(PROTO_TCP));
tcp.src_port = 16'd45678;
tcp.dst_port = 16'd443;

// 设置报文长度和载荷模式
pkt.pkt_len = 128;
pkt.payload_mode = PAYLOAD_INCREMENT;

// 打包（自动计算 checksum、length 等）
pkt.do_pack();

// pkt.raw_data 即为完整的报文字节流
```

### 2. 使用快捷访问器

```systemverilog
packet pkt = new();
pkt.build_from_template(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP);

// 快捷访问器，支持索引访问多层同类型头
ipv4_header outer_ip = pkt.get_ipv4(0);  // 外层 IPv4
ipv4_header inner_ip = pkt.get_ipv4(1);  // 内层 IPv4
tcp_header  tcp      = pkt.get_tcp();
vxlan_header vx      = pkt.get_vxlan();

outer_ip.src_addr = 32'hC0A80A01;
inner_ip.src_addr = 32'h0A0A0A01;
vx.vni = 24'd5000;
```

### 3. PCAP 写入与读取

```systemverilog
// 写入 PCAP
pcap_writer pw = new();
pw.open("test_traffic.pcap");
pw.write_packet(pkt, $time / 1000000000, ($time % 1000000000) / 1000);
pw.close();

// 读取 PCAP（自动解析协议栈）
pcap_reader pr = new();
packet pkts[$];
pr.open("test_traffic.pcap");
pr.read_all(pkts);
pr.close();

// pkts[0].layer_stack 即为解析后的协议栈
```

### 4. 协议解析与验证

```systemverilog
protocol_parser parser = new();
parser.verify_en = 1;  // 启用 checksum/length/type 全面验证

parse_result_t result = parser.validate(pkt);
if (result.valid)
    $display("报文验证通过");
else begin
    foreach (result.errors[i])
        $display("错误: %s", result.errors[i]);
end
```

### 5. 报文比较

```systemverilog
packet_comparator cmp = new();
diff_entry_t diffs[$];
cmp.compare(pkt_expected, pkt_actual, diffs);

foreach (diffs[i])
    $display("[%s] %s: 期望=%s 实际=%s",
        diffs[i].layer.name(), diffs[i].field_name,
        diffs[i].val_a, diffs[i].val_b);
```

### 6. 流量流生成

```systemverilog
traffic_stream stream = new();
stream.base_pkt = pkt;
stream.pkt_count = 100;

// 源 IP 递增
field_modifier mod = new();
mod.layer_type = PROTO_IPV4;
mod.field_name = "src_addr";
mod.mode = MOD_INCREMENT;
mod.step = 1;
stream.modifiers.push_back(mod);

// 生成 100 个报文
packet pkts[$];
stream.generate(pkts);
```

### 7. TCP 三次握手序列

```systemverilog
tcp_handshake_sequence seq = new();
seq.src_ip = 32'hC0A80101;
seq.dst_ip = 32'hC0A80102;
seq.src_port = 16'd12345;
seq.dst_port = 16'd80;

packet handshake_pkts[$];
seq.generate(handshake_pkts);
// handshake_pkts: [SYN, SYN-ACK, ACK]
```

### 8. 自由组合协议栈

```systemverilog
packet pkt = new();
eth_header  eth = new();
vlan_header vl  = new();
ipv4_header ip  = new();
tcp_header  tcp = new();

pkt.add_layer(eth);   // 自动校验协议图合法性
pkt.add_layer(vl);
pkt.add_layer(ip);
pkt.add_layer(tcp);

// 强制模式：跳过协议图校验
pkt.force_mode = 1;
```

### 9. aip_core 集成 — TCL 运行时参数传递

当与 [aip_core](https://github.com/Beihang-yuting/aip_core) 一起编译时，所有协议头支持通过 `load_params(path)` 从 TCL/plusargs 动态加载字段值。未设置的字段保持默认值或随机值。

```systemverilog
// 编译时加上 aip_core（自动启用 load_params）
// vcs ... +incdir+<aip_core_path> aip_core_pkg.sv ...

packet pkt = new();
pkt.build_from_template(ETH_IPV4_TCP);
pkt.load_params("eth_tx");   // seq 名作为 path 前缀
pkt.do_pack();
```

TCL 中设置字段（`set_param` 或 plusargs）：

```tcl
# 路径规则：{seq_name}.{outer/inner}_{proto}.{field}
set_param {
    eth_tx.outer_eth.dst_mac     0xAABBCCDDEEFF
    eth_tx.outer_eth.src_mac     0x112233445566
    eth_tx.ipv4.src_addr         0xC0A80001
    eth_tx.ipv4.dst_addr         0xC0A80002
    eth_tx.ipv4.ttl              128
    eth_tx.tcp.src_port          12345
    eth_tx.tcp.dst_port          80
    eth_tx.pkt_len               256
}
eth_tx count=10
```

VXLAN 隧道场景 — outer/inner 自动区分：

```tcl
set_param {
    vxlan_tx.outer_eth.dst_mac       0xAAAAAAAAAAAA
    vxlan_tx.outer_ipv4.src_addr     0x0A000001
    vxlan_tx.outer_udp.dst_port      4789
    vxlan_tx.vxlan.vni               0x123456
    vxlan_tx.inner_eth.dst_mac       0xBBBBBBBBBBBB
    vxlan_tx.inner_ipv4.dst_addr     0xC0A80064
    vxlan_tx.tcp.dst_port            443
}
vxlan_tx count=5
```

**路径命名规则：**

| 路径 | 说明 |
|------|------|
| `seq.outer_eth.dst_mac` | 外层以太网（第一个出现的 eth） |
| `seq.inner_eth.dst_mac` | 内层以太网（第二个出现的 eth） |
| `seq.tcp.dst_port` | 只出现一次的协议，也可省略 outer_ 前缀 |
| `seq.vxlan.vni` | 隧道协议（只有一层） |
| `seq.pkt_len` | 报文总长度 |
| `seq.tmpl` | 模板名（动态切换，如 `ETH_IPV4_TCP`） |

**支持的协议字段：**

| 协议头 | 可配置字段 |
|--------|-----------|
| eth | `dst_mac`, `src_mac` |
| vlan | `vlan_id`, `pcp` |
| mpls | `label`, `tc`, `ttl` |
| arp | `opcode`, `hw_type`, `proto_type_field`, `hw_len`, `proto_len`, `sender_mac`, `sender_ip`, `target_mac`, `target_ip` |
| ipv4 | `src_addr`, `dst_addr`, `ttl`, `dscp`, `identification` |
| ipv6 | `src_addr`, `dst_addr`（128bit，见下「IPv6 地址格式」）, `hop_limit`, `traffic_class`, `flow_label` |
| ipv6_ext (Hop-by-Hop) | `next_header`, `hdr_ext_len`, `opt_router_alert_en`/`opt_router_alert_val`, `opt_jumbo_en`/`opt_jumbo_len` |
| ipv6_ext (Routing) | `next_header`, `hdr_ext_len`, `routing_type`, `segments_left` |
| ipv6_ext (Fragment) | `next_header`, `fragment_offset`, `m_flag`, `identification` |
| ipv6_ext (Destination) | `next_header`, `hdr_ext_len`, `opt_custom_en`/`opt_custom_type`/`opt_custom_data` |
| tcp | `src_port`, `dst_port`, `seq_num`, `ack_num`, `flags`, `window_size` |
| udp | `src_port`, `dst_port` |
| sctp | `src_port`, `dst_port`, `verification_tag` |
| icmp | `icmp_type`, `code` |
| igmp | `igmp_type`, `max_resp_time`, `group_address` |
| icmpv6 | `icmp_type`, `icmp_code`, `identifier`, `sequence_num` |
| vxlan | `vni` |
| vxlan_gpe | `flags`, `next_protocol`, `vni` |
| gre | `key`, `protocol_type` |
| geneve | `vni` |
| gtp | `version`, `message_type`, `teid`, `sequence_number`, `n_pdu_number`, `next_ext_hdr_type`, `ext_hdr_type` |
| esp | `spi`, `sequence_number` |
| erspan (Type II) | `version`, `vlan`, `cos`, `en`, `truncated`, `session_id`, `index` |
| erspan (Type III) | `version`, `vlan`, `cos`, `bso`, `truncated`, `session_id`, `timestamp`, `sgt`, `p_flag`, `ft`, `hw_id`, `direction`, `gra`, `o_flag` |
| nvme_tcp | `pdu_type`, `flags`, `hlen`, `pdo` |
| iscsi | `opcode`, `flags`, `total_ahs_len`, `data_segment_len`, `lun`（64bit）, `initiator_task_tag` |
| iwarp | `mpa_length`, `tagged_bit`, `last`, `ddp_version`, `queue_number`, `msn`, `msg_offset`（48bit）, `rdmap_version`, `rdmap_opcode`, `sink_stag` |
| rocev2 | `opcode`（枚举数值）, `se`, `mig_req`, `pad_count`, `tver`, `pkey`, `dest_qp`, `ack_req`, `psn`, `reth_va`/`reth_r_key`/`reth_dma_len`, `aeth_syndrome`/`aeth_msn`, `imm_data`, `atomic_va`/`atomic_r_key`/`atomic_swap_add`/`atomic_compare`/`atomic_orig_data`, `ieth_r_key`, `deth_q_key`/`deth_src_qp` |
| ptp | `transport_specific`, `message_type`, `version_ptp`, `domain_number`, `flag_field`, `correction_field`（64bit）, `clock_identity`（64bit）, `port_number`, `sequence_id`, `control_field`, `log_message_interval` |
| lldp | `chassis_id`（48bit）, `port_id`（48bit）, `ttl` |
| lacp | `actor_system`（48bit）, `actor_key`, `actor_port`, `partner_system`（48bit） |
| stp | `root_id`（64bit）, `bridge_id`（64bit）, `port_id`, `flags` |
| mac_control | `opcode`, `pause_time` |
| dhcp | `op`, `xid`, `ciaddr`, `yiaddr`, `chaddr`（48bit） |
| dhcpv6 | `msg_type`, `transaction_id`（24bit） |
| dns | `id`, `flags`, `qdcount`, `ancount` |
| bfd | `my_discriminator`, `your_discriminator`, `detect_mult`, `desired_min_tx` |
| nvme_rdma | `opcode`, `command_id`, `nsid`, `prp1`（64bit） |

> **L2 控制 / 管理 / NVMe-RDMA 协议**（lldp/lacp/stp/mac_control/dhcp/dhcpv6/dns/bfd/nvme_rdma/igmp）为**固定头最小实现**（mandatory 字段，无 TLV/option 扩展），用于报文构建与随机覆盖；模板 `ETH_LLDP`/`ETH_LACP`/`ETH_STP`/`ETH_MAC_CONTROL`/`ETH_IPV4_UDP_DHCP`/`ETH_IPV6_UDP_DHCPV6`/`ETH_IPV4_UDP_DNS`/`ETH_IPV4_UDP_BFD`/`ETH_*_ROCEV2_NVME_RDMA` 均可建。

> **IPv6 地址格式**：`src_addr`/`dst_addr` 经 `packet_utils::parse_ipv6` 解析，支持冒号写法（`2001:db8::1`、`::1`、`::`、`fe80::abcd`）或纯十六进制（`0x2001...`，≤32 hex）。非法格式保持默认值。
>
> **宽字段满宽**：MAC 48bit、iSCSI `lun` / PTP `correction_field`·`clock_identity` / RoCEv2 64bit 字段、IPv6 128bit 地址均全宽设置无截断（真机 VCS Q-2020 验证，见 `test/test_load_params_wide.sv`）。

> 自动计算字段（ethertype、checksum、length、protocol 等）不在 load_params 范围内，由 `do_pack()` 中的 `calc_fields()` 自动处理，确保报文正确性。

> 不带 aip_core 编译时，`load_params` 为空函数（`ifdef AIP_CMDLINE_SV` 保护），不影响原有功能。

## 报文模板列表

### 基本报文
| 模板名 | 协议栈 |
|--------|--------|
| `ETH_IPV4_TCP` | Ethernet → IPv4 → TCP |
| `ETH_IPV4_UDP` | Ethernet → IPv4 → UDP |
| `ETH_IPV6_TCP` | Ethernet → IPv6 → TCP |
| `ETH_IPV6_UDP` | Ethernet → IPv6 → UDP |
| `ETH_ARP` | Ethernet → ARP |
| `ETH_IPV4_ICMP` | Ethernet → IPv4 → ICMP |
| `ETH_IPV6_ICMPV6` | Ethernet → IPv6 → ICMPv6 |
| `ETH_IPV4_IGMP` | Ethernet → IPv4 → IGMP (v2) |

### VLAN 报文
| 模板名 | 协议栈 |
|--------|--------|
| `ETH_VLAN_IPV4_TCP` | Ethernet → VLAN → IPv4 → TCP |
| `ETH_VLAN_IPV4_UDP` | Ethernet → VLAN → IPv4 → UDP |
| `ETH_VLAN_IPV6_TCP` | Ethernet → VLAN → IPv6 → TCP |

### 隧道报文
| 模板名 | 协议栈 |
|--------|--------|
| `ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP` | VXLAN 隧道（外IPv4，内IPv4 TCP） |
| `ETH_IPV4_UDP_GENEVE_ETH_IPV4_UDP` | Geneve 隧道 |
| `ETH_IPV4_GRE_IPV4_TCP` | GRE L3 隧道 |
| `ETH_IPV4_GRE_ETH_IPV4_TCP` | NVGRE L2 隧道 |
| `ETH_IPV4_UDP_GTP_U_IPV4_TCP` | GTP-U 隧道 |
| `ETH_IPV4_GRE_ERSPAN_II_ETH_IPV4_TCP` | ERSPAN Type II |
| `ETH_IPV4_GRE_ERSPAN_III_ETH_IPV4_TCP` | ERSPAN Type III |

### RDMA / 存储
| 模板名 | 协议栈 |
|--------|--------|
| `ETH_IPV4_UDP_ROCEV2` | RoCEv2 (RDMA) |
| `ETH_IPV4_TCP_NVME_TCP` | NVMe over TCP |
| `ETH_IPV4_TCP_ISCSI` | iSCSI |
| `ETH_IPV4_TCP_IWARP` | iWARP |

> 完整模板列表见 `src/common/packet_defines.sv` 中的 `packet_template_e` 枚举定义。

## 测试覆盖

| 测试文件 | 测试内容 | 子测试数 |
|---------|---------|---------|
| `test_protocol_headers` | 各协议头 pack/unpack/clone/compare/verify | 多项 |
| `test_protocol_graph` | 协议转换图合法性 | 多项 |
| `test_packet_builder` | 模板构建、自由组合、长度控制、roundtrip | 多项 |
| `test_tunnel_headers` | VXLAN/GRE/Geneve/ERSPAN/GTP-U/IP-in-IP | 121项 |
| `test_tunnel_packet` | 隧道报文整包 pack/unpack | 多项 |
| `test_rdma_storage_headers` | RoCEv2/iWARP/NVMe-TCP/iSCSI 头字段 | 80项 |
| `test_rdma_storage_packet` | RDMA/存储报文整包 roundtrip | 33项 |
| `test_phase2c_headers` | MPLS/IPv6 Ext/SCTP/PTP/VXLAN-GPE/ESP | 多项 |
| `test_phase2c_packet` | Phase2c 报文整包 | 多项 |
| `test_parser` | 协议解析、验证、checksum 校验、隧道验证 | 21项 |
| `test_pcap` | PCAP 读写往返 | 多项 |
| `test_pcap_verify` | 11种协议的 PCAP 综合往返验证 | 72项 |
| `test_ip_fragment` | IPv4 分片与重组 | 多项 |
| `test_protocol_sequences` | TCP 握手/挥手、ARP、ICMP 序列 | 多项 |
| `test_traffic_stream` | 流量流生成、字段修改器 | 多项 |

## 架构设计

### 协议头基类

所有协议头继承自 `protocol_base`，必须实现以下虚方法：

```
protocol_base
  ├── pack_header()      — 序列化为字节流
  ├── unpack_header()    — 从字节流反序列化
  ├── get_header_length()— 返回头长度（字节）
  ├── calc_fields()      — 自动计算 checksum/length/type 等
  ├── clone()            — 深拷贝
  ├── compare()          — 与另一个头比较
  ├── verify()           — 字段正确性验证
  └── to_string()        — 格式化输出
```

### 协议图

`protocol_graph` 维护一张有向图，定义合法的协议转换关系：

```
Ethernet → {IPv4, IPv6, ARP, VLAN, MPLS, ...}
IPv4     → {TCP, UDP, ICMP, GRE, ESP, ...}
UDP      → {VXLAN, Geneve, GTP-U, RoCEv2, DNS, DHCP, ...}
TCP      → {NVMe-TCP, iSCSI, iWARP, HTTP, BGP, ...}
GRE      → {IPv4, IPv6, Ethernet, ERSPAN_II, ERSPAN_III}
VXLAN    → {Ethernet}
...
```

### Checksum 计算

- **IPv4 Header Checksum**：ones' complement 校验和
- **TCP/UDP/ICMPv6 Checksum**：含 IPv4/IPv6 伪头的 ones' complement 校验和
- **隧道场景**：从内到外计算，确保外层 checksum 包含正确的内层 checksum

## 许可证

MIT License

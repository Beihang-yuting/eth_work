# SVT/VIP env 与 net-packet 用户指南

本文说明 `eth_work` 中已经完成交叉验证的 Synopsys SVT Ethernet VIP 模式，
以及如何把这些模式接入自己的 UVM env、选择速率/FEC/自协商、运行普通或复位
交叉测试，并用 `third_party/net_packet` 生成真实的 Ethernet 报文。

代码中的统一实现位于：

- VIP 配置、交叉 env 和测试：[`test/svt/eth_svt_cross_pkg.sv`](../test/svt/eth_svt_cross_pkg.sv)
- VIP 与自研 PHY 的顶层接线：[`test/svt/top_svt.sv`](../test/svt/top_svt.sv)
- 全速率接口宏：[`src/agent/eth_pcs_macros.svh`](../src/agent/eth_pcs_macros.svh)
- net-packet 发包适配：[`test/uvm/eth_tb_pkg.sv`](../test/uvm/eth_tb_pkg.sv)
- VIP/环回 make 目标：[`sim/Makefile`](../sim/Makefile)

## 1. 先理解数据路径

SVT 交叉 env 的两条方向是独立的：

```text
方向 A：SVT VIP transaction
  -> vip_mac driver
  -> top_svt 的 serial/XGMII 线
  -> 自研 eth_pcs_agent RX
  -> cross_scoreboard

方向 B：net_packet::packet
  -> packet.do_pack() 得到 raw_data[]
  -> eth_frame_txn.data
  -> eth_pcs_agent driver
  -> 自研 PCS/FEC/PMA
  -> top_svt 的 serial/XGMII 线
  -> SVT VIP RX monitor/checker
  -> cross_scoreboard
```

`eth_frame_txn.data` 只包含从目的 MAC 开始的 Ethernet 帧字节，不包含
preamble、SFD 和 FCS。自研 driver 负责把帧送进 XGMII/GMII，FCS 由帧发送层
统一追加；因此用户在 net-packet 中不要手工再加 FCS。

普通交叉测试默认同时发送两路流量：VIP 发 500 帧、自研侧发 1000 帧。复位
交叉测试每轮发送 VIP 100 帧、自研侧 200 帧，执行 3 轮我方 PHY 中途复位，
复位后重新等锁再继续发包。

## 2. 在 53/VCS 主机上准备环境

SVT 目标必须在 VCS 主机（`10.11.10.53`）上用登录 shell 执行。DesignWare
路径只在当前编译/运行进程中设置，不写入仓库配置：

```bash
cd /home/ubuntu/ryan/eth_work/sim
export DESIGNWARE_HOME=/home/ubuntu/synopsys/designware_vip_R-2020.12
export ETH_SVT_DESIGN=/home/ubuntu/ryan/eth_svt_design

# 只编译一次 SVT simv；后续各模式复用它
make svt_simv

# 10G 默认模式：VIP -> 自研 500 帧，自研 -> VIP 1000 帧
make svt
```

`ETH_SVT_DESIGN` 必须是 `dw_vip_setup` 生成的 design directory，内部应有
`src/sverilog/vcs`、`include/sverilog` 等目录。`sim/filelist_svt.f` 已经把
这些目录和 net-packet 源码加入编译清单。

如果只想直接运行已经编译好的产物，可以使用同一组 plusarg：

```bash
build/svt/simv +UVM_TESTNAME=eth_svt_cross_test \
  +UVM_MAX_QUIT_COUNT=5 +SPEED=25g \
  -l build/svt/manual_25g.log
```

通过 `+A_FRAMES=<n>` 和 `+B_FRAMES=<n>` 可临时改变两方向帧数，不需要改
SystemVerilog。复位目标使用同样的速率参数，例如：

```bash
make svt_25g svt_25g_reset
build/svt/simv +UVM_TESTNAME=eth_svt_cross_reset_test \
  +SPEED=25g +A_FRAMES=100 +B_FRAMES=200 \
  -l build/svt/manual_25g_reset.log
```

## 3. VIP 模式与 env 配置对照

`eth_svt_cross_test.build_phase()` 根据 `+SPEED` 调用
`cross_svt_cfg` 中对应的 `set_*_cfg()`，再创建 `eth_pcs_cfg`。普通用户优先
使用 make 目标；自己创建 test 时只需复用同样的字段组合。

| `+SPEED` | `cross_svt_cfg` | SVT `interface_select` | 自研 PHY 配置 | 物理串行接口 | VIP 目标 |
|---|---|---|---|---|---|
| 默认 `10g` | `set_kr_cfg()` | `ETH_XSBI_SERIAL` | `num_lanes=1,num_phys=1` | `vif_serial_p`，MAC 侧 `vif_xgmii_p` | `svt` / `svt_reset` |
| `an73` | `set_an73_cfg()` | `ETH_AN_CL73`，HCD=10GBASE-KR | 单 lane，`an_enable=1` | `vif_serial_p` | `svt_an` / `svt_an_reset` |
| `5g` | `set_5g_cfg()` | `ETH_5G_BASER_SERIAL` | 单 lane | `vif_serial_p` | `svt_5g` / `svt_5g_reset` |
| `25g` | `set_25g_cfg()` | `ETH_25G_SERIAL` | 单 lane | `vif_serial_p` | `svt_25g` / `svt_25g_reset` |
| `40g` | `set_40g_cfg()` | `ETH_XLSBI_SERIAL` | 4 PCS / 4 物理 lane | `vif_serial_p_l0..l3` | `svt_40g` / `svt_40g_reset` |
| `50g` | `set_50g_cfg()` | `ETH_50G_SERIAL` | 4 PCS / 2 物理 lane | `vif_serial_p_l0..l1` | `svt_50g` / `svt_50g_reset` |
| `100g` | `set_100g_cfg()` | `ETH_CAUI` | 20 PCS / 10 物理 lane | `vif_serial_p_l0..l9` | `svt_100g` / `svt_100g_reset` |
| `100g4` | `set_100g4_cfg()` | `ETH_CAUI_25X4` | 20 PCS / 4 物理 lane | `vif_serial_p_l0..l3` | `svt_100g4` / `svt_100g4_reset` |
| `100gr` | `set_100gr_cfg()` | `ETH_CSBI_4_LANE` + RS-FEC | 20 PCS / 4 FEC 物理 lane，RS-FEC 内置 | `vif_serial_p_l0..l3` | `svt_100gr` / `svt_100gr_reset` |
| `200g` | `set_200g_cfg()` | `ETH_200G_SERIAL` | Clause 119，8 PCS / 8 物理 lane | `vif_serial_p_l0..l7` | `svt_200g` / `svt_200g_reset` |
| `400g` | `set_400g_cfg()` | `ETH_400G_SERIAL` | Clause 119 CDBI，16 / 16 lane | `vif_serial_p_l0..l15` | `svt_400g` / `svt_400g_reset` |
| `1g` | `set_1g_cfg()` | `ETH_1G_BASEX_1BIT` | `basex=1`，8b/10b | `vif_serial_p`，MAC 侧 `vif_gmii_p` | `svt_1g` / `svt_1g_reset` |
| `2.5g` | `set_2p5g_cfg()` | `ETH_2PT5G_BASEX_SERIAL` | `basex=1`，8b/10b | `vif_serial_p`，MAC 侧 `vif_gmii_p` | `svt_2p5g` / `svt_2p5g_reset` |

这里的“PCS lane / 物理 lane”要区分清楚：100G CAUI-10 是 20 条 PCS lane
按 2:1 bit 交织到 10 条物理 lane；100G CAUI-4 是 20:4；50G 是 4:2。
200G 和 400G 是 Clause 119 路径，分别使用 8 和 16 条物理 lane，不能把
200G 的 lane 排布直接套到 400G。

### FEC、AN 和 lane4 叠加规则

| plusarg | 作用 | 可用模式/目标 |
|---|---|---|
| `+FEC` | Clause 74 BASE-R FEC | 10G、25G、40G、100G CAUI-10；例如 `svt_25g_fec` |
| `+RSFEC` | 单 lane RS(528,514)，25G 时为 Clause 108 | 25G 的 `svt_25g_rsfec*`；10G 线速 RS-FEC 只做自环 |
| `+SPEED=100gr` | Clause 91 100G RS-FEC，4 FEC lane | `svt_100gr*`；不要再加 `+FEC` 或 `+RSFEC` |
| `+SPEED=an73` | Clause 73 AN，协商完成后进入 10G 数据态 | `svt_an` / `svt_an_reset`；与 FEC 不叠加 |
| `+LANE4` | 单 lane 奇数帧从 lane4 起帧（0x33） | 10G/5G 自环和 `svt_lane4`；多 lane/BASE-X 不可用 |

200G 和 400G 已经内置 Clause 119 的 RS(544,514)/KP4，agent 会拒绝再叠加
`+FEC`、`+RSFEC`、AN、LT 或 BASE-X。

400G 必须带行为级仿真开关；它们只影响当前仿真进程，不改变逻辑协议速率：

```bash
make svt_400g svt_400g_reset
# Makefile 内等价于：
# +SPEED=400g +C400_CLK_DIV=100 +C400_DEFER_FEC
```

`+C400_CLK_DIV=100` 按比例降低 400G 行为级时钟，保持 bit/word 比例；
`+C400_DEFER_FEC` 只在空闲建链/AM 去偏斜阶段延迟 RS 检查，首段流量前和每次
复位后会重新打开完整 RS 检查。不要把它理解成关闭 400G FEC。

当前 SVT 版本没有与本项目对接的 `56g` Ethernet PCS 枚举，因此不存在
`+SPEED=56g` 目标；`1g`、`2.5g`、5G、10G、25G、40G、50G、100G、200G、400G
均有对应配置或目标。

## 4. 把 VIP 和自研 agent 接入自己的 env

### 4.1 顶层 interface 和时钟

最省事的方式是沿用现有宏。VIP 全模式的时钟宏必须放在
`svt_ethernet_txrx_if` 实例之后；自研端口在同一个复位域内。下面是核心
接线片段，时钟发生器的具体频率、复位释放和运行时 lane mux 省略，完整可运行
版本见 `test/svt/top_svt.sv`：

```systemverilog
`include "aip_log.sv"
`include "aip_time.sv"
`include "aip_clk.sv"
`timescale 1ps/1fs
`include "agent/eth_pcs_macros.svh"

module my_svt_top;
  import uvm_pkg::*;

  `eth_pcs_svt_clock_gen(v)
  svt_ethernet_txrx_if mac_ethernet_if (v_reference_clk);
  svt_ethernet_xxm_bfm_driver     vip_drv (mac_ethernet_if);
  svt_ethernet_xxm_mon_chk_driver vip_mon (mac_ethernet_if);
  `eth_pcs_svt_clock_wire(v, mac_ethernet_if)

  logic rst_n = 0;
  aip_clk_if word_clk_if();
  aip_clk word_clk_gen;
  wire word_clk = word_clk_if.clk;
  wire bit_clk  = v_serial_baser_clk; // 单 lane 示例

  `eth_pcs_port(p, word_clk, bit_clk, rst_n)
  // 多 lane 时 p_lane_clk 按 SPEED 选择：40G 用 v_serial_baser_clk，
  // 50G/100G4/100gr 用 v_serial_25g_clk，200G/400G 用 v_scd_clk。
  wire p_lane_clk = v_scd_clk; // 此行仅作 200G/400G 示例
  `eth_pcs_mld_lanes(p, 20, p_lane_clk, rst_n)

  // 10G/25G/5G 等单 lane：
  // assign mac_ethernet_if.rx_lane = {'0, p_serial.tx_bit};
  // assign p_serial.rx_bit = mac_ethernet_if.tx_lane[0];

  // 多 lane 接收方向；发送方向按 SPEED 选择物理 lane 数，
  // 现成实现见 test/svt/top_svt.sv。
  `eth_pcs_mld_rx_wire(p, mac_ethernet_if, 20)
  `eth_pcs_mld_vifs(p, 20)

  initial uvm_config_db#(virtual xgmii_if)::set(
    null, "uvm_test_top", "vif_xgmii_p", p_xgmii);
  initial uvm_config_db#(virtual serial_if)::set(
    null, "uvm_test_top", "vif_serial_p", p_serial);

  // 1G/2.5G 还要提供：
  // initial uvm_config_db#(virtual gmii_if)::set(
  //   null, "uvm_test_top", "vif_gmii_p", p_gmii);
endmodule
```

实际使用时不要照抄上面的单 lane mux 到所有速率：

- 单 lane：`mac_ethernet_if.tx_lane[0] <-> p_serial.rx_bit/tx_bit`。
- 40G：使用 `p_l[0]..p_l[3]`。
- 50G：使用 `p_l[0]..p_l[1]`，虽然自研内部是 4 PCS lane。
- 100G CAUI-10：使用 `p_l[0]..p_l[9]`。
- 100G CAUI-4、100G RS-FEC：使用 `p_l[0]..p_l[3]`。
- 200G：使用 `p_l[0]..p_l[7]`。
- 400G：使用 `p_l[0]..p_l[15]`。

现成的完整运行时 mux、400G PMA 时钟和复位握手都在
[`test/svt/top_svt.sv`](../test/svt/top_svt.sv)，建议自有 top 先以该文件为
模板，再替换 DUT 侧连接。

### 4.2 `cross_env` 的配置对象

`cross_env` 内部创建三个组件：

```text
cross_env
├── vip_mac   : svt_ethernet_agent
├── phy_agent : eth_pcs_agent
└── sb        : cross_scoreboard
```

它从 config_db 取得 `vip_cfg` 和 `phy_cfg`，再分别下发到 `vip_mac*` 和
`phy_agent`；四个 analysis port 的连接是：

```text
vip_mac.monitor.item_collected_port_tx -> sb.svt_tx_imp
vip_mac.monitor.item_collected_port_rx -> sb.svt_rx_imp
phy_agent.drv.tx_ap                    -> sb.our_tx_imp
phy_agent.mon.rx_ap                    -> sb.our_rx_imp
```

自己创建 env 时，核心字段组合如下（模式选择仍建议直接调用
`set_*_cfg()`，不要直接猜 SVT enum）：

```systemverilog
cross_svt_cfg vip_cfg;
eth_pcs_cfg   phy_cfg;

vip_cfg = cross_svt_cfg::type_id::create("vip_cfg");
vip_cfg.set_100g4_cfg();                 // 例：100G CAUI-4
vip_cfg.set_fec_overlay(0, 0);           // cl74, 25G RS-FEC
vip_cfg.mac_address[0] = 48'h0000_0000_4455;

phy_cfg = eth_pcs_cfg::type_id::create("phy_cfg");
phy_cfg.is_active = 1;
phy_cfg.vif_xgmii = vxgmii;
phy_cfg.num_lanes = 20;
phy_cfg.num_phys  = 4;
phy_cfg.am_spacing = 64;
phy_cfg.ber_limit = 97;
phy_cfg.ber_window_blocks = 781250;
for (int i = 0; i < 4; i++)
  phy_cfg.vif_serial_lanes[i] = lane_vif[i];

uvm_config_db#(cross_svt_cfg)::set(this, "env", "vip_cfg", vip_cfg);
uvm_config_db#(eth_pcs_cfg)::set(this, "env", "phy_cfg", phy_cfg);
```

不同模式只替换表中的 lane/FEC/`cl119`/`cl400` 字段。`am_spacing` 必须与
VIP 配置一致：40G/100G 系列仿真加速值通常为 64，50G 为 1280，200G VIP
按 16 个 RS 码字对齐，400G 为 16 个 CDBI 码字对齐。完整的模式分支和
`vif_serial_p_l<i>` 获取逻辑在 `eth_svt_cross_test.build_phase()`。

1G/2.5G 不能把 XGMII 句柄当作 MAC 入口，必须改用 `vif_gmii_p`：

```systemverilog
phy_cfg.basex   = 1;
phy_cfg.vif_gmii = gmii_vif;
phy_cfg.vif_serial = serial_vif;
```

## 5. 用 net-packet 生成并发送具体报文

### 5.1 仓库默认发包行为

`eth_loopback_seq` 已经在 `test/uvm/eth_tb_pkg.sv` 中完成适配。每帧流程是：

1. 在 `ETH_IPV4_TCP`、`ETH_IPV4_UDP`、`ETH_ARP` 中随机选择模板。
2. `packet.randomize_all()` 随机化各协议头。
3. `packet.do_pack()` 自动生成 payload、length、EtherType、IP/L4 checksum。
4. 取 `packet.raw_data` 填入 `eth_frame_txn.data`，短帧补到 60 字节。
5. 通过 `env.phy_agent.sqr` 交给自研 driver。

因此下面这些命令已经会真正经过 net-packet，而不是发送固定的空帧：

```bash
cd sim
make stress_25g
make svt_100g
make svt_400g
```

`make stress_*` 是自研 agent 环回；`make svt_*` 是 net-packet -> 自研 TX ->
SVT RX 的方向 B，同时 VIP 方向 A 也并行发包。

### 5.2 用户自定义 sequence：IPv4/UDP、VLAN、VXLAN、RoCEv2

下面的 sequence 可以放在自己的 test package 中（该 package 需要
`import uvm_pkg::*; import eth_pcs_pkg::*; import eth_tb_pkg::*;`）。它直接
产生 `eth_frame_txn`，所以可以替换自研侧默认随机序列；不需要修改 PCS/FEC
代码。

```systemverilog
class user_packet_seq extends uvm_sequence #(eth_frame_txn);
  `uvm_object_utils(user_packet_seq)

  int num_frames = 10;

  function new(string name = "user_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    repeat (num_frames) begin
      packet pkt = new();
      eth_frame_txn tr = eth_frame_txn::type_id::create("tr");
      eth_header eh;
      ipv4_header ip;
      udp_header udp;

      pkt.build_from_template(ETH_IPV4_UDP);
      pkt.randomize_all();

      eh  = pkt.get_eth();
      ip  = pkt.get_ipv4();
      udp = pkt.get_udp();
      eh.dst_mac = 48'h02_00_00_00_00_02;
      eh.src_mac = 48'h02_00_00_00_00_01;
      ip.src_addr = 32'hC0A8_0101;       // 192.168.1.1
      ip.dst_addr = 32'hC0A8_0102;       // 192.168.1.2
      udp.src_port = 16'd40000;
      udp.dst_port = 16'd4791;

      pkt.pkt_len = 256;
      pkt.payload_mode = PAYLOAD_INCREMENT;
      pkt.do_pack();                         // 自动重算长度和 checksum

      tr.data = pkt.raw_data;
      while (tr.data.size() < 60) tr.data.push_back(8'h00);
      start_item(tr);
      finish_item(tr);
    end
  endtask
endclass
```

VLAN、VXLAN 和 RoCEv2 只需换模板并设置对应层。字段访问方式与仓库已有
net-packet 测试一致：

```systemverilog
// VLAN + IPv4 + UDP
packet vlan_pkt = new();
vlan_header vlan;
vlan_pkt.build_from_template(ETH_VLAN_IPV4_UDP);
vlan_pkt.randomize_all();
$cast(vlan, vlan_pkt.get_layer(PROTO_VLAN));
vlan.vlan_id = 12'd100;

// IPv4 + UDP + VXLAN + inner Ethernet + inner IPv4 + TCP
packet vx_pkt = new();
vxlan_header vx;
vx_pkt.build_from_template(ETH_IPV4_UDP_VXLAN_ETH_IPV4_TCP);
vx_pkt.randomize_all();
vx = vx_pkt.get_vxlan();
vx.vni = 24'd5000;
vx_pkt.pkt_len = 300;
vx_pkt.do_pack();

// IPv4 + UDP + RoCEv2
packet roce_pkt = new();
rocev2_bth bth;
roce_pkt.build_from_template(ETH_IPV4_UDP_ROCEV2);
roce_pkt.randomize_all();
$cast(bth, roce_pkt.get_layer(PROTO_ROCEV2));
bth.opcode = 8'h04;                       // SEND Only
bth.dest_qp = 24'h000100;
bth.psn = 24'h000001;
roce_pkt.pkt_len = 100;
roce_pkt.do_pack();
```

常用模板还包括 `ETH_IPV4_TCP`、`ETH_IPV4_UDP`、`ETH_IPV6_TCP`、
`ETH_IPV6_UDP`、`ETH_ARP`、Geneve、GRE、GTP-U、iWARP、NVMe-TCP、iSCSI 和
PTP。完整模板枚举见
[`third_party/net_packet/src/common/packet_defines.sv`](../third_party/net_packet/src/common/packet_defines.sv)。

### 5.3 在交叉 test 中替换自研侧流量

现成 `eth_svt_cross_test` 会在 `run_traffic()` 中创建 `eth_loopback_seq`。
如果用户要保留 VIP 500 帧方向 A，同时让方向 B 使用上面的 sequence，可以在
派生 test 中并行启动两个 sequence：

```systemverilog
class my_svt_packet_test extends eth_svt_cross_test;
  `uvm_component_utils(my_svt_packet_test)

  function new(string name = "my_svt_packet_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    vip_frame_seq   vip_seq = vip_frame_seq::type_id::create("vip_seq");
    user_packet_seq usr_seq = user_packet_seq::type_id::create("usr_seq");

    vip_seq.num_frames = 500;
    usr_seq.num_frames = 1000;
    phase.raise_objection(this);
    wait_lock();
    fork
      vip_seq.start(env.vip_mac.sequencer);
      usr_seq.start(env.phy_agent.sqr);
    join
    // 等 monitor 收齐拖尾帧，再让 scoreboard 在 check_phase 结算
    env.sb.draining = 1;
    #10us;
    phase.drop_objection(this);
  endtask
endclass
```

一个具体用户流程是：把 `user_packet_seq` 和 `my_svt_packet_test` 加入自己的
SVT filelist，在 `sim/Makefile` 的 `svt_simv` 编译命令中追加该源文件，然后：

```bash
export DESIGNWARE_HOME=/home/ubuntu/synopsys/designware_vip_R-2020.12
export ETH_SVT_DESIGN=/home/ubuntu/ryan/eth_svt_design
cd /home/ubuntu/ryan/eth_work/sim
make svt_simv
build/svt/simv +UVM_TESTNAME=my_svt_packet_test +UVM_MAX_QUIT_COUNT=5 \
  +SPEED=25g -l build/svt/my_udp_25g.log
```

如果只需要改变协议字段而不需要改变 test 生命周期，也可以直接把
`eth_loopback_seq.body()` 中的模板和字段替换为上面的 sequence；PCS、FEC、VIP
接线和 scoreboard 都保持不变。

这个派生 test 仍然复用基类 `build_phase()` 的所有模式选择和 lane 接线。
如果启用 `+SPEED=an73`，还要像基类一样等待 VIP 进入 `AN_GOOD`；如果运行
400G，仍须加 `+C400_CLK_DIV=100 +C400_DEFER_FEC`。复位版本可参考
`eth_svt_cross_reset_test`，复位后必须重新 `wait_lock()`，400G 还要重新打开
延迟的 FEC decode。

### 5.4 使用 net-packet UVM wrapper 的边界

`third_party/net_packet/src/uvm_wrapper/packet_item.sv` 和
`packet_sequence.sv` 可供其他 agent 使用，但 `eth_work` 的 PCS agent 事务
类型是 `eth_frame_txn`，不是 `packet_item`。在本项目中应沿用：

```text
packet/packet_item
  -> packet.do_pack()
  -> raw_data[$]
  -> eth_frame_txn.data
```

这样 scoreboard 仍可按 Ethernet 字节逐帧比较，而协议字段的随机化和 checksum
计算留在 net-packet。

## 6. 如何选择测试和判断结果

### 普通交叉

```bash
make svt                    # 10G
make svt_5g svt_25g         # 5G/25G
make svt_40g svt_50g        # 40G/50G
make svt_100g svt_100g4     # CAUI-10/CAUI-4
make svt_100gr              # 100G Clause 91 RS-FEC
make svt_200g svt_400g      # Clause 119 / CDBI
make svt_1g svt_2p5g        # BASE-X + GMII
```

带 FEC 或 lane4 的目标按前文的专用目标运行，例如：

```bash
make svt_fec svt_25g_rsfec svt_100g_fec svt_lane4
```

### 交叉复位

每个支持模式都有对应的 `<target>_reset`。合格日志必须包含：

```text
CROSS_RESET_RECOVERY_PASS rounds=3
A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200
UVM_ERROR : 0
UVM_FATAL : 0
```

普通交叉必须包含：

```text
A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000
UVM_ERROR : 0
UVM_FATAL : 0
```

`A` 是 VIP 发帧到自研 RX，`B` 是自研发帧到 VIP RX。`bad` 是自研 RX 收到的
CRC/preamble 脏帧数。不要只看计数行；`sim/Makefile` 的 `CHECK_CLEAN` 会继续
检查 `UVM_ERROR` 和 `UVM_FATAL`，因为 UVM 的 quit count 允许少量错误时仿真
继续运行。

400G 还应检查 `PCS_STATS` 中 `invalid_block=0`、`fec_uncorr=0`、
`tx_underrun=0`。复位/扰动窗口内由 VIP 产生的预期 `register_fail:*` 会被
测试回调降为 WARNING，窗口外仍必须满足零错误判据。

## 7. 常见配置错误

| 现象 | 原因和处理 |
|---|---|
| `ETH_SVT_DESIGN` 找不到头文件 | 没有在当前进程设置 design directory，或路径不是 `dw_vip_setup` 生成目录；先检查 `sim/filelist_svt.f` 所列子目录。 |
| `未取得 vif_serial_p_l<i>` | 多 lane 模式的物理 lane 数配置错了。按表取 4/2/10/4/4/8/16 条 lane。 |
| 1G/2.5G 无帧 | MAC 侧应取得 `vif_gmii_p`，不能继续把 XGMII 句柄传给 BASE-X。 |
| FEC 初始化 fatal | `+FEC` 与 `+RSFEC` 互斥；100gr/200g/400g 的内置 FEC 也不能再叠加。 |
| 40G/100G 对齐错误 | 两侧 AM 间隔必须一致；现有 SVT 配置使用 40G/100G 的 64，50G 使用 1280。 |
| 400G 建链很慢或不推进 | 使用 `+C400_CLK_DIV=100 +C400_DEFER_FEC`，并确认 16 条 lane 都已接到 `vif_serial_p_l0..l15`。 |
| `+SPEED=56g` 无法选择模式 | 当前 SVT R-2020.12 没有 56G Ethernet PCS enum，本项目没有 56G 目标。 |

更完整的每速率原理、FEC 码流和覆盖矩阵分别见
[`docs/integration_25g_5g.md`](integration_25g_5g.md)、
[`docs/integration_100g_200g.md`](integration_100g_200g.md)、
[`docs/integration_fec.md`](integration_fec.md) 和
[`docs/verification_matrix.md`](verification_matrix.md)。

# 802.3 分层结构与真实 DUT 对接发包指南

本文两部分：① 完整 MAC/PHY 层级关系与各模块功能（对照本仓库覆盖范围）；
② 真实 DUT（带 MAC，或带 MAC+PHY）对接时，如何用本 agent 充当对端发送
真实网络业务报文。

## 1. 完整层级关系

```
        ┌────────────────────────────────────┐
        │   上层协议 (LLC / IP 栈 / 应用)     │
        └────────────────┬───────────────────┘
   ═══════════ MAC 层（数据链路层下半部）═══════════
        ┌────────────────▼───────────────────┐
        │  MAC Client / MAC Control 子层      │  PAUSE/PFC 流控帧生成与终结、
        │  (Clause 31, 802.1Qbb)             │  按优先级反压调度
        ├────────────────────────────────────┤
        │  MAC 子层 (Clause 4)                │  帧封装/解封装：前导码+SFD、
        │                                    │  DA/SA/Type、FCS(CRC32) 生成
        │                                    │  与校验、最小 64B 补齐(pad)、
        │                                    │  IPG 间隔控制、超长/runt 检出
        ├────────────────────────────────────┤
        │  RS 协调子层 (Clause 46/81)         │  MAC 字节流语义 ↔ xMII 并行
        │                                    │  控制字符映射；Local/Remote
        │                                    │  Fault 序集检测与响应状态机
        └────────────────┬───────────────────┘
              XGMII / XLGMII（64bit 数据 + 8bit 控制，逻辑接口）
   ═══════════ PHY 层（物理层）═══════════
        ┌────────────────▼───────────────────┐
        │  PCS (Clause 49/82)                │  64b/66b 编解码、x^58 自同步
        │                                    │  扰码、块同步；40G+ 加 MLD：
        │                                    │  多 lane 分发/AM/BIP/去偏斜
        ├────────────────────────────────────┤
        │  FEC (Clause 74 / 91/108)          │  前向纠错：fire code (BASE-R)
        │                                    │  或 RS-FEC，换开销保误码率
        ├────────────────────────────────────┤
        │  PMA (Clause 51/83)                │  串化/解串（gearbox 位宽转换）、
        │                                    │  时钟恢复(CDR)、弹性缓冲速率
        │                                    │  补偿、环回控制
        ├────────────────────────────────────┤
        │  AN/LT (Clause 73/72，电口 KR)      │  自协商（DME 页交换定速率/FEC
        │                                    │  能力）+ 链路训练（均衡调整）
        ├────────────────────────────────────┤
        │  PMD (Clause 52/…)                 │  物理介质驱动：电气/光收发、
        │                                    │  信号完整性
        └────────────────┬───────────────────┘
                    介质（铜缆 / 光纤 / 背板）
```

### 各模块功能一句话

- **MAC Control**：带内流控。PAUSE 帧（DA=01-80-C2-00-00-01、type 0x8808）
  让对端暂停指定时间；PFC 按 8 个优先级独立反压。
- **MAC**：帧的"信封"。TX 加前导/SFD/FCS/pad、维持 IPG ≥ 96bit；
  RX 剥壳 + CRC 校验 + 长度合法性（64~1518/Jumbo）。
- **RS**：MAC 字节流 ↔ xMII S/D/T/E/idle 控制字符互译；链路故障时发
  LF/RF 序集通知对端并压制数据。
- **PCS**：串行链路的字节边界恢复——66b 块结构供块同步锚定、扰码保证
  跳变密度、MLD 把 4/20 个物理 lane 重组回单一流。
- **FEC**：冗余校验位纠错，链路误码率不达标时必开。
- **PMA**：位宽世界 ↔ 串行世界的桥，含两侧时钟域速率补偿（弹性 idle
  增删）。
- **AN/LT**：KR 电口上电握手，协商共同速率/FEC 后训练均衡器，完成才进
  数据模式。
- **PMD**：模拟域，数字仿真不建模（svt VIP 同样抽象为 bit 流）。

### 本仓库覆盖对照

| 子层 | 状态 |
|---|---|
| MAC Control / MAC / RS | 由 svt VIP 扮演（交叉验证），或由真实 DUT 提供 |
| PCS | 完整自研（10G/25G/5G 单 lane + 40G MLD） |
| FEC | Clause 74 完整；RS-FEC (cl91/108) 待做 |
| PMA | 数字核心行为级（1bit 串化 + 弹性域）；无 gearbox 并口/CDR 建模 |
| AN/LT | 待做（完整形态优先级最高项） |
| PMD | 不建模 |

即：本 agent 等效一颗"PHY 芯片"，上边 XGMII、下边 serdes 串行 lane。

## 2. 真实 DUT 对接与业务报文发送

两种 DUT 形态，对接点不同，发包入口相同（都是 `eth_frame_txn` 序列）。

### 2.1 报文怎么构造（两种形态通用）

激励单位是 `eth_frame_txn.raw_data`：**完整 L2 帧字节流（DA 起，不含
前导/SFD/FCS）**。FCS 由 driver 自动补（CRC32 反射 0xEDB88320），前导/
SFD 由 BFM 编码路径生成。真实网络业务报文直接复用
`third_party/net_packet`（Beihang-yuting/net_packet）构造 L2~L4：

```systemverilog
// 例：构造一个真实 UDP 业务包并发送
class my_traffic_seq extends uvm_sequence #(eth_frame_txn);
  `uvm_object_utils(my_traffic_seq)
  ...
  virtual task body();
    eth_frame_txn t;
    repeat (num_frames) begin
      `uvm_create(t)
      // raw_data = DA(6) SA(6) EthType(2=0800) IP 头(20) UDP 头(8) payload
      // 用 net_packet 的报文生成函数填充，或手工拼字节
      t.raw_data = build_udp_packet(.dst_mac(48'h001122334455),
                                    .src_mac(48'h065544332211),
                                    .dst_ip(32'hC0A80102) /* ... */);
      `uvm_send(t)   // driver 补 FCS -> BFM 编码 -> 串行发出
    end
  endtask
endclass
```

要点：60B 以下自动 pad 到最小帧长；SA bit40 保持 0（单播，组播 SA 会被
对端 MAC checker 报错，见 svt 交叉激励的处理）。

### 2.2 形态 A：DUT 只有 MAC（不带 PHY，暴露 XGMII）

我方充当 DUT 的 PHY + 链路对端，拓扑是"两级 agent 背靠背"：

```
 DUT(MAC) ─XGMII─ agent#1（当 DUT 的 PHY） ─串行─ agent#2（当对端）─XGMII─（对端序列/记分板）
```

- **接线**：DUT 的 XGMII TX/RX ↔ `xgmii_if`（`eth_pcs_port` 宏的
  `<name>_xgmii`）；agent#1 与 agent#2 串行交叉（`eth_pcs_connect`，
  40G 用 `eth_pcs_mld_connect`）。即 test/uvm/top.sv 环回拓扑把一端的
  XGMII 让位给 DUT。
  **agent#2 的 XGMII 悬空即可**（BFM 对未驱动的 XGMII 按全 idle 处理）：
  它不是第二套环境，只是串行侧的"报文打包器"，成本一个实例 + 两根串行线。
- **发包（打向 DUT）**：在 **agent#2** 的 sequencer 上跑 2.1 的序列。
  报文经 agent#2 编码 → 串行 → agent#1 解码 → XGMII → 进 DUT MAC RX。
  DUT MAC 只见标准 XGMII 码流，与接真 PHY 无差别。
- **收包（DUT 发出）**：DUT MAC TX → XGMII → agent#1 编码 → 串行 →
  agent#2 monitor 收帧出 `eth_frame_txn`，接记分板比对。
- **前置**：发流前等两方向 `rx_locked()` + ~1us 解扰自同步（见
  integration_10g_basekr.md 的 link-up 流程）。

### 2.3 形态 B：DUT 带 MAC+PHY（暴露 serdes 串行 lane）

我方充当链路对端（link partner），拓扑与 svt 交叉验证完全同构——把
VIP 的位置换成 DUT：

```
 DUT(MAC+PHY) ─串行 lane─ 本 agent（对端 PHY 等效）─XGMII─（对端序列/记分板）
```

- **接线**：单 lane（10G/25G/5G）：DUT tx/rx ↔ `<name>_serial`；
  40G：DUT 4 lane ↔ `eth_pcs_mld_lanes` 的 `<name>_l[0..3]`
  （test/svt/top_svt.sv 的接线即模板，`mac_ethernet_if` 换成 DUT 端口）。
- **发包（打向 DUT）**：本 agent sequencer 跑 2.1 序列。报文经我方
  PCS 编码成 66b 加扰码流（40G 含 MLD 分发+AM）→ DUT PHY 解码 →
  DUT MAC 收到完整业务帧。
- **收包**：DUT 发出的码流由我方 BFM 块同步/解码，monitor 出帧比对。
- **前置**：
  1. 时钟/AM 参数与 DUT 一致（+SPEED、+AM_SPACING；教训见
     integration_40g.md：AM 间隔两侧必须一致）；
  2. 等锁流程同上；
  3. 若 DUT 的 KR 口不能旁路自协商，需先完成 AN/LT（cl73/72）建链——
     本仓库该项在做，未完成前需 DUT 配成强制速率模式（force mode）。

### 2.4 XGMII 直驱开关（纯 MAC 功能验证提速）

只验 MAC 功能正确性、不关心链路层时序时，开 `cfg.xgmii_direct`（配套
插件参数 `+XGMII_DIRECT`）跳过整条 PCS/串行链路：

- driver 的帧直接展开成 XGMII 拍，经 BFM 驱向 DUT 的 rxd/rxc；DUT TX
  的 XGMII 拍直接采样交 monitor 装配 —— **发包序列零适配**，同一个
  `eth_frame_txn` 序列两种模式通用；
- `rx_locked()` 直驱下恒为 1，既有测试的等锁流程也无需改；
- 位时钟随 `+XGMII_DIRECT` 关闭（提速主要来源：10G+ 位钟事件全免）。
  实测 1000 帧 stress 仿真 CPU 时间 4.59s -> 1.05s（约 4.4x，帧数越大
  差距越大）；
- 自测目标：`make loopback_direct` / `make stress_direct`（lb_env 宏在
  该插件参数下 force 双向 XGMII 交叉环回）。

代价：无锁定过程、弹性 idle 增删、fault 传播。验证复位/反压/fault 等
链路条件行为必须走串行（形态 A 标准拓扑）。

### 2.5 两种形态怎么选

- DUT 交付物只有 MAC RTL（PHY 用行为模型/后续集成）→ 形态 A。
- DUT 是 MAC+PHY 集成（子系统/全芯片）→ 形态 B，最贴近真实链路，
  我方覆盖协议线上格式的每一位。
- 两种形态发包代码零差别：换拓扑不换序列。

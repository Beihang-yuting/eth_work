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
  跳变密度、MLD 把 4/20 条 PCS lane 重组回单一流。
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
| PCS | 完整自研：BASE-R 64b/66b（10G/25G/5G 单 lane；40G/100G MLD，100G 含 PMA 2:1/5:1 复用）；200G Clause 119（257b + RS(544,514)）；BASE-X 8b/10b（1G/2.5G，Clause 36，MAC 侧 GMII）。64b/66b 块型：单 lane 按 Clause 49（含 lane4 起始与序集块），多 lane 按 Clause 82（限制见 integration_10g_basekr.md §8）；64b/66b 模式另有 BER 监视（hi_ber），RX 链路未起或 hi_ber 时向 MAC 输出 Local Fault（BASE-X 无此信令） |
| FEC | Clause 74（10G/25G 单 lane；40G/100G 每 PCS lane 一套）；RS-FEC RS(528,514)：25G Clause 108、100G Clause 91（20 PCS lane → 4 FEC lane）。VIP 交叉覆盖 cl74 10G/25G/40G/100G（CAUI-10）与 RS-FEC 25G/100G，详见 integration_fec.md |
| PMA | 数字核心行为级（1bit 串化 + 弹性域）；无 gearbox 并口/CDR 建模 |
| AN/LT | Clause 73 自协商（仅 10G 单 lane，已与 VIP 交叉：`svt_an` / `svt_an_reset`）；Clause 72 链路训练（训练帧为自定简化格式、非 802.3 帧，VIP 不支持 cl72，仅自环验证）；KR 完整建链 AN→LT→数据见 §2.5；Clause 37（BASE-X AN）未做 |
| PMD | 不建模 |

即：本 agent 等效一颗"PHY 芯片"，上边 XGMII、下边 serdes 串行 lane。

## 2. 真实 DUT 对接与业务报文发送

两种 DUT 形态，对接点不同，发包入口相同（都是 `eth_frame_txn` 序列）。

### 2.1 报文怎么构造（两种形态通用）

激励单位是 `eth_frame_txn.data`：**完整 L2 帧字节流（DA 起，不含
前导/SFD/FCS）**。前导/SFD/FCS 都由 driver 生成（`eth_frame_to_words` /
`eth_frame_to_gmii`，FCS 为 CRC32 反射 0xEDB88320），BFM 只做 PCS 编码。
真实网络业务报文直接复用 `third_party/net_packet`（Beihang-yuting/net_packet）
构造 L2~L4（其 `packet.raw_data` 即这段字节流，直接赋给 `data`）：

```systemverilog
// 例：构造一个真实 UDP 业务包并发送
class my_traffic_seq extends uvm_sequence #(eth_frame_txn);
  `uvm_object_utils(my_traffic_seq)
  ...
  virtual task body();
    eth_frame_txn t;
    repeat (num_frames) begin
      `uvm_create(t)
      // data = DA(6) SA(6) EthType(2=0800) IP 头(20) UDP 头(8) payload
      // 用 net_packet 的报文生成函数填充，或手工拼字节
      t.data = build_udp_packet(.dst_mac(48'h001122334455),
                                .src_mac(48'h065544332211),
                                .dst_ip(32'hC0A80102) /* ... */);
      `uvm_send(t)   // driver 加前导/SFD/FCS -> BFM 编码 -> 串行发出
    end
  endtask
endclass
```

要点：driver 不 pad 也不查帧长 —— 不足 60B 须由序列自己补齐到最小帧长
（否则发出的是 runt 帧；参考序列 `eth_loopback_seq` 补零到 60B）；SA bit40
保持 0（单播，组播 SA 会被对端 MAC checker 报错，`eth_loopback_seq` 同样
强制清零）。

### 2.2 形态 A：DUT 只有 MAC（不带 PHY，暴露 XGMII）

我方充当 DUT 的 PHY + 链路对端，拓扑是"两级 agent 背靠背"：

```
 DUT(MAC) ─XGMII─ agent#1（当 DUT 的 PHY） ─串行─ agent#2（当对端）─XGMII─（对端序列/记分板）
```

- **接线**：DUT 的 XGMII TX/RX ↔ `xgmii_if`（`eth_pcs_port` 宏的
  `<name>_xgmii`）；agent#1 与 agent#2 串行交叉（`eth_pcs_connect`，
  多 lane 用 `eth_pcs_mld_connect`）。即 test/uvm/top.sv 环回拓扑把一端的
  XGMII 让位给 DUT。`xgmii_if` 是 64bit SDR 展平形式（每字钟一拍 64bit
  数据 + 8bit 控制），DUT 若是 32bit DDR 的 XGMII 引脚，需自加一层
  DDR↔SDR 适配（相邻两个 32bit 拍拼成 lane0~3 / lane4~7）。
  **agent#2 的 XGMII 悬空即可**（BFM 对未驱动的 XGMII 按全 idle 处理）：
  它不是第二套环境，只是串行侧的"报文打包器"，成本一个实例 + 两根串行线。
- **帧起点**：32bit 内核的 MAC 展平后帧起始会交替落在 lane0 / lane4。
  单 lane（Clause 49，10G/5G）编码器两种起点都支持（0x78；0x33、0x66），
  适配层不必重排；多 lane（Clause 82，40G/100G/200G）无 lane4 起点，S 落
  lane4 的拍编码为 ERROR 块 —— XLGMII/CGMII/200GMII 的 MAC 按规范只在
  lane0 起帧。DUT RS 发出的序集（如 Remote Fault）编成序集块（单 lane
  0x4B/0x55/0x2D，多 lane 0x4B 且只有 /Q/）照常过链路。
- **发包（打向 DUT）**：在 **agent#2** 的 sequencer 上跑 2.1 的序列。
  报文经 agent#2 编码 → 串行 → agent#1 解码 → XGMII → 进 DUT MAC RX。
  DUT MAC 只见标准 XGMII 码流，与接真 PHY 无差别。
- **收包（DUT 发出）**：DUT MAC TX → XGMII → agent#1 编码 → 串行 →
  agent#2 monitor 收帧出 `eth_frame_txn`，接记分板比对。
- **DUT 看到的 RX 引脚**（agent#1 驱出）：
  - 链路未起（上电建链前、断线失锁、hi_ber、开 AN/LT 时的建链阶段）
    持续为 Local Fault（单 lane `rxc=8'h11 rxd=64'h0100009C_0100009C`，
    lane0/lane4 各一个 LF 序集；多 lane `rxc=8'h01 rxd=64'h00000000_0100009C`），
    DUT RS 应据此进入故障态（发 Remote Fault、停发数据），链路起来后 LF
    消失；
  - 链路起来后只在帧间补/删 idle，吸收时钟差与 FEC 解码的突发交付，
    帧内不插拍；环回/交叉测试以 `rxpin_midframe_underrun == 0` 断言；
  - 覆盖目标 `make link_fault` / `make link_fault_40g`。机制与 LF 拍格式
    见 integration_10g_basekr.md §6.1~6.2。
- **前置**：发流前等两方向 `rx_link_up()`（锁定且非 hi_ber）+ ~1us
  解扰自同步（见 integration_10g_basekr.md 的 link-up 流程）。

### 2.3 形态 B：DUT 带 MAC+PHY（暴露 serdes 串行 lane）

我方充当链路对端（link partner），拓扑与 svt 交叉验证完全同构——把
VIP 的位置换成 DUT：

```
 DUT(MAC+PHY) ─串行 lane─ 本 agent（对端 PHY 等效）─XGMII─（对端序列/记分板）
```

- **接线**：单 lane（10G/25G/5G）：DUT tx/rx ↔ `<name>_serial`；
  多 lane：DUT 各物理 lane ↔ `eth_pcs_mld_lanes` 的 `<name>_l[i]`（40G 4 条、
  100G CAUI-10 10 条、CAUI-4/100gr 4 条、200G 8 条）
  （test/svt/top_svt.sv 的接线即模板，`mac_ethernet_if` 换成 DUT 端口）。
- **发包（打向 DUT）**：本 agent sequencer 跑 2.1 序列。报文经我方
  PCS 编码成 66b 加扰码流（40G 含 MLD 分发+AM）→ DUT PHY 解码 →
  DUT MAC 收到完整业务帧。
- **收包**：DUT 发出的码流由我方 BFM 块同步/解码，monitor 出帧比对。
- **前置**：
  1. 时钟/AM 参数与 DUT 一致：`+SPEED` 选速率；MLD 模式（40g/100g/100g4）
     的 AM 间隔要同时改 `cfg.am_spacing`（BFM 按它插 AM）和时钟宏的
     `+AM_SPACING`（只用于字钟扣 AM 开销），两者取同一值 —— 单传
     `+AM_SPACING` 不改 AM 间隔（教训见 integration_40g.md：AM 间隔两侧
     必须一致）；
  2. 等锁流程同上；
  3. 若 DUT 的 KR 口不能旁路自协商，开 `cfg.an_enable`（`+AN`）走
     Clause 73 建链（仅 10G），见 §2.5。按与 VIP 交叉时 VIP 侧必须改的
     两项核对 DUT：AN link_fail_inhibit 须长于我方 PCS 锁定时间与两端
     切数据模式的时间差（VIP 默认 505ns 不够，交叉放宽到 10us）；我方
     复位后改发 DME，DUT 须在 AN_GOOD 下识别链路失效并重新协商（VIP 需
     开 `enable_an73_internal_restart`）。DUT 若还要求 Clause 72 链路
     训练，当前仍需配成训练旁路 —— 本 agent 的 LT（`+LT`）只经自环验证，
     训练帧格式未与 802.3 对齐（见 §2.5 限制）。

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
- 自测目标：`make loopback_direct` / `make stress_direct` /
  `make multi_reset_direct`（lb_env 宏在该插件参数下 force 双向 XGMII
  交叉环回）。

代价：无锁定过程、弹性 idle 增删、fault 传播（RX 引脚不插删、不发
Local Fault）。验证复位/反压/fault 等链路条件行为必须走串行（形态 A
标准拓扑）。

### 2.5 Clause 73 自协商 / Clause 72 链路训练（KR 电口建链）

真实 KR 口上电不是直接进数据模式，而是先自协商。开关：

```systemverilog
cfg.an_enable  = 1;          // 或插件参数 +AN
cfg.an_ability = 25'h4;      // A2 = 10GBASE-KR（advertise 的技术能力）
cfg.an_nonce   = 5'h05;      // 与对端取不同值；相同则检出碰撞、随机换 nonce 重协商
cfg.an_link_fail_inhibit = 20us;  // 数据模式链路失效门限（见下）
```

行为：上电后串行线由 AN 引擎驱动 DME 页波形（不是 PCS 码流），基页
交换完成（能力检测 → Ack 回显对端 nonce → 双向确认，完成应答发满 6 个
完整 Ack 页）后自动切回 PCS 数据通路（开了 LT 则先进 Clause 72 训练，
见下）。`rx_locked()` 内含"AN 完成"条件，**既有测试流程零改动**：
`wait_link_up()` 会自动等到协商完成。建链阶段 RX 引脚向 MAC 输出 Local
Fault。

重新协商的触发：
- 复位；
- 能力检测中对端稳定页的 nonce 与本端相同（碰撞）：随机换 nonce 重来；
- 应答检测中对端稳定页内容变了（忽略 Ack 与回显 nonce，即对端已重启）；
- 数据模式下 RX 链路持续不可用（失锁或 hi_ber）超过 `cfg.an_link_fail_inhibit`（默认 20us，
  IEEE 500ms 按仿真缩放；IEEE AN_GOOD 下链路失效的行为），LT 与 RX 对齐
  器一并复位。门限须长于本端锁定时间与两端切数据模式的时间差。

观测接口：`bfm.an_done()` / `bfm.an_state()` / `bfm.an_pages()` /
`bfm.an_restarts()`（重新协商次数）。

自测：`make loopback_an`（AN 完成 + 100 帧）、`make stress_an`（1000
帧）、`make multi_reset_an`（5 轮复位重协商）、`make disturb_an`（扰动
恢复，断线 10us 不触发链路失效）、`make disturb_an_relink`（断线 30us
超过门限，两端经链路失效重新协商后流量恢复，判两端重协商次数均 ≥ 1）。

与 VIP 交叉：`make svt_an`（VIP `ETH_AN_CL73`，双方协商 HCD=10GBASE-KR
后切 10G 数据模式跑双向流量）、`make svt_an_reset`（3 轮我方复位 → VIP
重新协商 → 流量恢复，逐段计数核对）。VIP 侧须开
`enable_an73_internal_restart=1`，并经链路事务回调（`an73_link_cb`）把
`an73_link_fail_inhibit_timer` 放宽到 10us（默认 505ns 短于我方锁定
时间）、nonce 取 9（我方 5）；测试等 VIP 仲裁状态到
`AN_GOOD_CHECK_TO_AN_GOOD_ON_LINK_OK` 再发流，复位轮先等它离开 AN_GOOD。

DME 时序（胞宽 66 bit tick = 6.4ns、半胞 33 tick、页 49 胞 + 双段
132 tick 静默定界、页周期 3498 tick = 339.2ns）由 svt VIP
`ETH_AN_CL73` 真实波形逆向标定，非凭规范推断。

Clause 72 链路训练：开 `cfg.lt_enable`（`+LT`）后，AN 完成后（未开 AN
则上电即）先跑训练帧握手 —— 本端依次请求对端 C(-1)/C(0)/C(+1) 三抽头
更新，收到 updated 回执后置 receiver ready，双方就绪才切数据模式；
`rx_locked()` 同样内含"LT 完成"条件。均衡器本身不建模，只走"请求-执行-
回执"协议。观测：`bfm.lt_done()` / `bfm.lt_state()` / `bfm.lt_taps()` /
`bfm.lt_frames()`。自测：`make loopback_lt`（单独 LT + 100 帧）、
`make stress_lt` / `make multi_reset_lt` / `make disturb_lt`；
`make loopback_kr`（AN→LT→数据，另校验双端 AN 完成 + 三抽头收敛）、
`make stress_kr`（1000 帧）、`make multi_reset_kr`（5 轮复位重新建链）、
`make disturb_kr`。

限制（TODO）：Next Page 未实现（NP=0）；无 break_link 静默期；优先级
解析按本端单能力位；基页 FEC 能力位恒 0（不协商 FEC）；不开 LT 时 AN
后直接进数据模式（与 VIP ETH_AN_CL73 流程对齐）。AN 仅 10G 单 lane：
DME 按 10.3125G 位钟 tick 计时，其它速率时序不符，多 lane 由 test 拦截；
LT 仅单 lane，目标均为 10G。LT：svt VIP 不支持 Clause 72，只做了两端
自环对训；训练帧为本实现自定格式（4096bit 帧，系数更新/状态字段未做
DME），未对齐 802.3 72.6.10 的 548 octet 训练帧，对接真实 DUT 的 cl72
前须先按规范补齐帧格式。

### 2.6 两种形态怎么选

- DUT 交付物只有 MAC RTL（PHY 用行为模型/后续集成）→ 形态 A。
- DUT 是 MAC+PHY 集成（子系统/全芯片）→ 形态 B，最贴近真实链路，
  我方覆盖协议线上格式的每一位。
- 两种形态发包代码零差别：换拓扑不换序列。

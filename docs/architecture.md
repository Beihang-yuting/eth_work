# eth_work — MAC 对接用 PCS/SerDes 专用 UVM Agent 架构设计

## 1. 目标

实现一个"等效 svtVIP PHY 侧"的自研 UVM agent：

- 对上通过 **XGMII**（64bit 数据 + 8bit 控制，单时钟展平）对接真实 MAC；
- 对下实现 **10GBASE-R PCS**（IEEE 802.3 Clause 49：64b/66b 编解码、
  自同步扰码 x^58+x^39+1、块同步锁定）；
- 可选 **BASE-R FEC**（Clause 74：(2112,2080) fire code，含 PN-2112 扰码与
  burst 纠错）；
- 串行侧以 **1bit 串行**建模（`serial_if`，位时钟每拍 1bit，等效 SerDes
  已完成时钟恢复后的抽象；块边界由 block_sync 从 bit 流搜索锁定，
  任意相位/bit-slip/失锁行为真实可测）；
- 报文生成/解析复用 `third_party/net_packet`（70+ 协议模板、CRC 自动计算）；
- 最终与 Synopsys svt ethernet VIP（R-2020.12，10G XSBI 示例配置）背靠背
  对接，交叉检查协议完整性。

## 2. 分层结构

（本节为 agent 内部模块分层；完整 802.3 MAC/PHY 层级、各子层功能与
真实 DUT 对接发包方法见 `layering_and_dut_modes.md`。）

```
          sequencer (eth_frame_txn；参考序列用 net_packet 生成报文)
              |
        eth_pcs_driver ──── 帧 -> XGMII 时序（IPG/preamble/SFD/CRC）
              |
   xgmii_if (64b data + 8b ctl)          <== 真实 MAC 从这里接入
              |
        eth_pcs_phy_bfm
          ├─ pcs_codec encode/decode     (64b/66b，块型集合见 §2.2)
          ├─ scrambler / descrambler     (x^58 + x^39 + 1)
          ├─ fec_cl74_encoder/decoder    (可选, Clause 74)
          ├─ block_sync                  (锁定 FSM + bit-slip)
          └─ ber_mon_c                   (BER 监视 / hi_ber，见 §2.1)
              |
   serial_if (1bit 串行；多 lane 为数组)  <== 与 svtVIP / 对端 BFM 相连
```

- TX 路径：XGMII → 66b 编码 → 扰码 →（FEC 编码）→ serial_if 逐 bit 发送。
- RX 路径：serial_if →（FEC 码字对齐/纠错 | 块同步，二选一）→ 解扰 →
  66b 解码 → XGMII；链路未起时 XGMII RX 输出 Local Fault（见 §2.1）。
- 其它速率/模式由 BFM 按 cfg 换入对应引擎：`mld_tx_c/mld_rx_c`（Clause 82
  MLD，40G/100G）、`rs91_tx_c/rs91_rx_c`（RS-FEC，Clause 108/91）、
  `c119_tx_c/c119_rx_c`（200G Clause 119）、`basex_tx_c/basex_rx_c`
  （1G/2.5G 8b/10b，MAC 侧 GMII）、`an73_engine_c/lt72_engine_c`（AN/LT
  建链阶段占用串行线，完成后切回数据通路）；细节见各 `integration_*.md`。

### 2.1 RX 链路层行为（形态 A：驱真实 MAC 的 RX 引脚）

- **链路状态与 Local Fault**：`rx_link_up() = rx_locked() && !hi_ber`。
  链路未起（块/码字/多 lane 未锁定对齐、hi_ber、AN/LT 阶段）时，XGMII RX
  引脚持续输出 Local Fault 序集拍 —— 单 lane（Clause 49）`rxc=11
  rxd=0100009C_0100009C`（lane0/lane4 各一个 LF 序集，0x55 块），多 lane
  （Clause 82）`rxc=01 rxd=00000000_0100009C`；驱动队列里残留的拍作废，
  此期间交付的块丢弃（解扰照常推进）。直驱模式恒视为链路已起；BASE-X
  （GMII）不适用。
- **BER 监视**（`ber_mon_c`，block_sync.sv）：在交付点按块统计非法同步头，
  一个窗口内达到 `cfg.ber_limit` 即 hi_ber，此后首个坏头数低于上限的完整
  窗口结束时清除；RX 失锁时复位。默认 10GBASE-R 值 16 个 / 19531 块（10G
  下 125us；5G 沿用同一块数）；25G/40G/100G 按 IEEE 取 97 个 / 781250 块，
  200G 沿用同值（环回与交叉 tb 按 `+SPEED` 设置）。cl74 下同步头由译码
  重建，hi_ber 不会触发（FEC 错误指示未建模）。
- **RX 引脚弹性**：恢复出的拍按线速成突发产出（cl74 每码字 32 块、RS-FEC
  80 块、200G 每码字对 160 块、MLD+cl74 可达 32×lane 数），按字时钟（约定
  +100ppm）驱出。插/删只在帧间：深度低于低水位时补 idle，高于高水位时删
  一拍全 idle；水位按实测最大突发自适应（低 = 最大突发 + 4，高 = 2×低 + 16）。
  帧内见底计入 `rxpin_midframe_underrun`，非复位/扰动类测试断言为 0。直驱
  模式不插不删；BASE-X 的 GMII RX 引脚按同一约定（帧 = rx_dv 连续为 1）。
- **失锁判据**：BASE-R 块同步 64 块窗内 16 个非法头即失锁；cl74 锁定后连续
  8 个不可纠码字失锁、回搜索态；RS-FEC（Clause 91/108）与 Clause 119 周期
  起点 AM 单次不符按误码容忍，连续 2 次重锁（Clause 119 在 RS 纠错前比对，
  每 lane 另容忍至多 12 个比特差）。
- **多 lane（MLD）**：任一 PCS lane 由锁定转失锁即整体重对齐（IEEE
  align_status 要求全部 lane 锁定），RX 引脚随即转为 Local Fault。对齐后
  每 lane 期望 AM 的位置收到非 AM 时按 AM 占位跳过，连续 3 个以内容忍，
  第 4 个才重对齐（IEEE Clause 82 AM 锁定状态机的 am_invld_cnt）。
- **AN 重新协商**：数据模式下 RX 链路持续不可用（失锁或 hi_ber）超过 `cfg.an_link_fail_inhibit`
  （默认 20us；IEEE 为 500ms 实时，按仿真缩放）即回到 AN，同时复位 LT 与
  RX 对齐器。AN 期间 nonce 碰撞（随机换 nonce）、应答检测中对端稳定页内容
  变化（对端已重启）也重新协商；完成应答发满 6 个完整 Ack 页后才结束 AN
  （转 LT 或数据模式）。

### 2.2 64b/66b 块型集合

| 集合 | 模式 | 块型 |
|------|------|------|
| Clause 49 | 单 lane（10G/5G/25G） | 图 49-7 全部 15 种：0x1E（全 IDLE）、0x78（S0）、0x33（S4）、0x66（O0+S4）、0x55（O0+O4）、0x2D（O4）、0x4B（O0，lane4~7 为 IDLE）、0x87~0xFF（T0~T7） |
| Clause 82 | 多 lane（40G/100G/200G） | 0x1E、0x78、0x4B（lane4~7 为 4 个零数据字节）、0x87~0xFF；Clause 49 专有的 0x33/0x2D/0x55/0x66 编码为 ERROR 块、解码判非法 |

- 序集 O 码：0 ↔ /Q/（0x9C），F ↔ /Fsig/（0x5C），其余保留值解码判非法；
  Clause 82 只接受 0（/Q/），F 同样判非法。
- 全控制块 0x1E 只接受全 IDLE，含 /E/ 等其它 C 码的块解码判非法；编码侧
  无法归类的拍（如 S 不在 lane0/4、T 后非 IDLE）编码为全 ERROR 控制块。
- lane4 起帧：`eth_frame_to_words(..., lane4)` 首拍 lane0~3 为 IDLE、S 落
  lane4；`cfg.lane4_start=1`（`+LANE4`）时 driver 奇数帧从 lane4 起，多 lane
  与 BASE-X 由 agent 拦截（fatal）。
- 已知限制：25G 单 lane 沿用 Clause 49 集合与 Clause 49 Local Fault 拍，
  lane4 起始/0x55 等块在 25GBASE-R 下的格式未与规范核对；lane4 起帧只用于
  10G/5G。

## 3. 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 速率/编码 | 10GBASE-R 单 lane 起步（后续扩展见 §7） | VIP 10G 示例现成，最简完整路径 |
| 串行抽象 | 1bit 串行（位时钟每拍 1bit） | 避免真实 16bit XSBI 时钟域细节，协议内容完全等价；块边界物理上不存在，由 block_sync 从 bit 流搜索锁定，失锁/slip 行为真实可测 |
| S 位置 | 编解码均支持 lane0（0x78）与 lane4（0x33，仅 Clause 49 单 lane）；driver 默认 lane0，`cfg.lane4_start` 时奇数帧 lane4 | 32bit XGMII 内核的 MAC 在 lane0/lane4 间交替起帧（见 §8），形态 A 两个方向都要接受；Clause 82 多 lane 只有 lane0 起点（见 §2.2） |
| FEC | Clause 74 (2112,2080) | 与 VIP 10G FEC 测试同款，可交叉验证（PN 种子/T 位按 VIP 码流标定）；逐位置 GF(2) 线性求解纠错（非传统 error-trapping），可纠 ≤11bit 单突发 |
| 帧模型 | agent 事务 `eth_frame_txn`（DA 起字节流，不含 FCS）；参考序列用 net_packet `packet` 类生成报文 | agent 只认字节流，报文结构知识（含 L4 校验和）留在 net_packet 生成端；FCS 由 eth_frame_utils 统一追加/校验，记分板逐字节比对 |
| 时钟 | aip_clk（third_party/aip_core，vendored 1fs 精度）独立产生字/位时钟 | 高精度 + ppm/抖动/占空比可配；字/位时钟速率差由 BFM 弹性 idle 插入/删除吸收（真实 PHY 弹性缓冲行为） |
| 校验策略 | 双侧 monitor + scoreboard 逐字节比帧；PCS 层校验非法块型/失锁/CRC | "协议完整性检查"落在块层 + 帧层两级 |

## 4. 目录约定

```
docs/           设计文档
src/pkg/        eth_pcs_pkg.sv 顶层 package（编译单元入口）
src/pcs/        Clause 49 编解码、扰码、块同步，及 MLD(cl82)、cl119、8b/10b+cl36、
                AN(cl73)/LT(cl72)（纯函数/类，便于单测）
src/fec/        Clause 74 FEC、RS-FEC 编解码（RS(528,514) 用于 Clause 91/108；
                RS(544,514) 供 cl119）
src/agent/      UVM agent：cfg/driver/monitor/bfm/接口/集成宏
test/unit/      非 UVM 自校验单元测试（编码/扰码/块同步/FEC/帧工具闭环，及
                MLD、AN/LT、RS-FEC、8b/10b、cl119 等）
test/uvm/       UVM 环回环境与测试（双 agent 背靠背）
test/svt/       与 svt VIP 交叉验证（top_svt + 交叉 env/测试）
sim/            filelist 与 Makefile（VCS，10.11.10.53 执行）
examples/       各模式可跑示例导读
third_party/    net_packet（来自 10.11.10.59 ~/workspace/ryan/net_packet）、
                aip_core（aip_clk 高精度时钟）
```

## 5. 与 svtVIP 对接计划（阶段 2）

1. 阶段 1（已完成）：双自研 agent 串行环回，net_packet 发包，
   scoreboard 比帧 —— 证明自身 PCS/FEC 正确闭环。
2. 阶段 2（已完成，`test/svt/`）：以 VIP 示例 `tb_ethernet_svt_uvm_10g_intermediate_sys`
   为基础，本 agent 的 1bit 串行侧直连 VIP `ETH_XSBI_SERIAL` 的
   `tx_lane[0]/rx_lane[0]`（无需适配层；多 lane 模式接 `tx_lane/rx_lane`
   低位各 lane），VIP monitor/协议检查器检查我方发出码流的协议合法性；
   反向用我方 monitor 检查 VIP 码流 —— 双向交叉验证环境准确性。
3. 阶段 3：接真实 MAC RTL：MAC XGMII 直连 xgmii_if，本 agent 充当 PHY。

## 6. 验证清单

各模式的完整覆盖（环回 / 1000 帧 / 多次复位 / 扰动 / VIP 交叉 / 交叉复位
6 列、专项目标、判据与 N/A 原因）见 `verification_matrix.md`，全量回归
`make -k all`。下列为 10G 基线清单。

- [x] 单测：66b 编码→解码环回（随机帧、随机 IPG、各 T 位置）
- [x] 单测：扰码→解扰环回
- [x] 单测：FEC 编码→注错（burst ≤11bit）→解码纠正；>11bit 报不可纠
- [x] 单测：块同步在任意相位/bit-slip 后锁定
- [x] UVM：环回 FEC 开/关零丢失零错帧
- [x] UVM：大流量 1000 帧背靠背（stress / stress_fec）
- [x] UVM：中途复位 → 重新 link-up → 复位后 500 帧全净（reset_recovery）
- [x] UVM：多次中途复位（5 轮流量中复位，每轮复位后严格段 500 帧）（multi_reset）
- [x] UVM：链路扰动（反压等效；整位翻转 + 断线）→ 失锁重锁 → 恢复后 500 帧全净（disturb）
- [x] 阶段 2：svtVIP 双向交叉验证（XSBI_SERIAL，VIP 检查器通过；交叉复位 svt_reset）
- [x] FEC 与 VIP 互通（PN-2112 种子与 T 位按 VIP 码流标定；svt_fec / svt_fec_reset）
- [x] 链路层专项：Local Fault/hi_ber（link_fault）、lane4 起帧（stress_lane4 / svt_lane4）、
      AN 链路失效重协商（disturb_an_relink），内容见 `verification_matrix.md` 专项目标

## 7. 向 VIP 全能力对齐的扩展路线（已确认）

方法与流程复用 10G 打通路径（loopback → 1000 帧 stress → 复位/扰动
恢复 → svtVIP 交叉验证 → 交叉复位，各模式结果见 `verification_matrix.md`），
按增量成本排序：

1. **25G 单 lane**：同 64b/66b，换 25.78125G 时钟即可（近乎免费）；
   5G（ETH_5G_BASER_*）同理。—— 已完成（25G、5G 均环回 + VIP 交叉）。
2. **40G/100G 多 lane**：新增 Clause 82 MLD 层（块轮转分发、对齐标记
   插入/检出、每 lane 去偏），编解码/扰码层复用。—— 已完成（40G MLD、
   100G CAUI-10/CAUI-4，环回 + VIP 交叉）。
3. **RS-FEC（Clause 91/108）**：GF(2^10) RS(528,514)，独立模块，
   与 cl74 并列由 cfg 选择。—— 已完成（25G Clause 108、100G Clause 91，
   环回 + VIP 交叉）。
4. **1G 及以下（GMII/SGMII）+ 2.5G（ETH_2PT5G_BASEX_*）**：8b/10b
   独立编码栈，不与 64b/66b 共享。—— 1G/2.5G BASE-X（GMII）已完成
   （环回 + VIP 交叉）；SGMII 及 1G 以下未做。
5. **AN/LT（Clause 73/72）**：真实 KR 建链流程，可选替代直接进
   数据模式的捷径。—— 已完成（`+AN`/`+LT`，默认关闭）。AN 仅 10G 单
   lane（无 Next Page、FEC 能力位恒 0），与 VIP 交叉含交叉复位；LT 训练帧
   为简化格式（不是 802.3 72.6.10 帧），VIP 不支持 cl72，仅自环验证。

另已完成：200GBASE-R（Clause 119，8 lane，256B/257B + RS(544,514)），
环回 + VIP 交叉；400GBASE-R（Clause 119 CDBI，16 lane，KP4
RS(544,514)）已完成 SVT 普通交叉与交叉复位，目标清单和判据说明见
`verification_matrix.md` 与 `integration_100g_200g.md`。

速率族核查备忘：VIP 覆盖 10M~800G 标准速率 + FlexE/USXGMII/MACsec/PTP；
**80G 不存在**（非 IEEE 标准速率），仅可经 2×40G 聚合或 FlexE 绑定实现。

## 8. 对接 svtVIP 过程中修正的协议细节（重要备忘）

1. **同步头发送顺序**：数据块 "01" 先发 0、控制块 "10" 先发 1
   （即先发 sync[1]）。最初实现反了 —— 现象是两端各自环回都通、
   idle 互通、帧全灭（数据块被对端当控制块，BTF 呈随机值）。
2. **lane4 帧起始（块型 0x33）**：VIP 是 32bit XGMII 内核，帧起点在
   lane0/lane4 间交替；只认 0x78 会按概率丢一半帧。
3. **序集块（0x4b/0x55）**：VIP 在链路建立初期发 Remote Fault 序集，
   不识别会计为非法块；解码为 SEQ(0x9c) 字符即可被帧装配器自然忽略。
4. **源 MAC 单播**：随机 SA 置组播位会触发 VIP framing 检查器报错，
   激励侧必须清 SA bit0。

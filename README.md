# eth_work — MAC 对接用 PCS/SerDes 专用 UVM Agent

自研"等效 svtVIP PHY 侧"agent：上边界 XGMII 对接真实 MAC，内部实现
10GBASE-R PCS（Clause 49 64b/66b + 扰码 + 块同步）与 BASE-R FEC
（Clause 74，可纠 ≤11bit 突发），下边界 1bit 串行（SerDes 抽象）。
报文生成复用 [net_packet](https://github.com/Beihang-yuting/net_packet)；
高精度时钟复用 [aip_core](https://github.com/Beihang-yuting/aip_core) 的
aip_clk（vendored 于 third_party/aip_core，精度提到 1fs），字/位时钟独立
生成（含 ppm 偏差），速率差由 BFM 弹性 idle 插入/删除吸收。

文档索引：
- 设计：`docs/architecture.md`（含 RX 链路层行为、64b/66b 块型集合、扩展
  路线图与 VIP 对接备忘）
- 验证覆盖矩阵：`docs/verification_matrix.md`（每种模式 × 环回/1000 帧/
  多次复位/扰动/VIP 交叉/交叉复位 的 make 目标、判据与 N/A 原因）
- 分层与真实 DUT 对接发包：`docs/layering_and_dut_modes.md`（802.3 完整
  层级图 + MAC-only/MAC+PHY 两形态业务报文发送方法）
- 集成/使用（每模式一份）：`docs/integration_10g_basekr.md`、
  `docs/integration_25g_5g.md`、`docs/integration_40g.md`、
  `docs/integration_1g_2p5g.md`（1G/2.5G BASE-X，8b/10b + GMII）、
  `docs/integration_100g_200g.md`（100G CAUI-10/CAUI-4、200G Clause 119）、
  `docs/integration_fec.md`（FEC 叠加：Clause 74 单 lane/每 PCS lane、
  25G RS-FEC Clause 108、100G RS-FEC Clause 91）
- 可跑示例（每模式一份）：`examples/10g_basekr_loopback/`、
  `examples/25g_loopback/`、`examples/40g_loopback/`、
  `examples/1g_2p5g_loopback/`、`examples/100g_200g_loopback/`、
  `examples/fec_overlay/`

## 运行（10.11.10.53，需 VCS 环境）

```bash
cd sim
make -k all          # 全量回归：unit + 全部环回目标 + 全部 VIP 交叉目标（-k：个别失败不中断其余）
make unit            # 单元测试：编码/扰码/块同步/FEC/帧 闭环，判 UNIT_TEST_PASS
make loopback        # UVM 环回冒烟（FEC 关）：20 帧零丢失零错帧
make fec             # UVM 环回冒烟（FEC 开）
make stress          # 大流量：1000 帧背靠背随机报文（FEC 关）
make stress_fec      # 大流量（FEC 开）
make reset_recovery  # 中途复位：复位后重新 link-up，每段 500 帧
make disturb         # 链路扰动（反压等效）：整位翻转 + 断线各 10us，扰动段毁帧可容忍，恢复后 500 帧全净
make multi_reset     # 多次复位：5 轮"流量中复位 + 复位后严格段 500 帧"
make svt             # 阶段 2：svt VIP 交叉验证（VIP 500 帧 + 我方 1000 帧）
make svt_reset       # 与 VIP 交叉中途复位：3 轮复位，每段 VIP 100 帧 + 我方 200 帧
make link_fault      # 链路故障信令：建链前/断线/hi_ber 期间 RX 引脚为 Local Fault（40G 为 link_fault_40g）
make stress_lane4    # lane4 起帧大流量（奇数帧 S 落 lane4，0x33 块）；VIP 接收检查为 svt_lane4
make svt_an          # Clause 73 AN 与 VIP 交叉；svt_an_reset 为交叉复位（每轮重新协商）
make disturb_an_relink  # AN 链路失效：断线 30us（> 门限 20us），两端重新协商后流量恢复
make loopback_40g    # 40G（4 lane MLD）环回/大流量/多次复位：
make stress_40g multi_reset_40g
# 全部目标按"模式 × 环回/1000 帧/多次复位/扰动/VIP 交叉/交叉复位"列于
# docs/verification_matrix.md；各模式集成与用法见对应的 docs/integration_*.md
```

测试硬性要求（所有新场景默认遵守）：大流量（1000 帧标准）、错误即停（+UVM_MAX_QUIT_COUNT=5）
且日志 `UVM_ERROR`/`UVM_FATAL` 计数须为 0、反压/扰动后可恢复、中途复位后流量完全正常。

## 当前状态

- 阶段 1 完成：双 agent 串行环回，net_packet 发包，字节级记分板 +
  CRC/preamble/块合法性检查全部通过。
- 阶段 2 完成：与 Synopsys svt ethernet VIP（R-2020.12，
  ETH_XSBI_SERIAL / 10G BASE-KR）双向对接 —— VIP 发帧我方全收（CRC 干净），
  我方发帧 VIP 全收（VIP 内建协议检查器通过）。对接中修正：同步头线上
  发送顺序、lane4 帧起始（0x33）与序集块（0x4b/0x55）解码支持。
- 验证覆盖：每种模式按环回 / 1000 帧 / 多次复位 / 扰动 / VIP 交叉 / 交叉复位
  6 列验证，不适用的列标 N/A 并注明原因（10G 线速 RS-FEC、LT/KR 在 VIP 中
  无对应模式；XGMII 直驱无串行线）；所有 UVM 目标另判 `UVM_ERROR`/`UVM_FATAL`
  为 0。见 `docs/verification_matrix.md`。
- 速率覆盖（环回 + 与 VIP 交叉）：5G/10G/25G 单 lane、40G MLD、50GBASE-R、
  100G CAUI-10/CAUI-4、200G Clause 119、400G Clause 119 CDBI、1G/2.5G
  BASE-X。
- FEC 叠加：Clause 74（10G/25G 单 lane、40G/100G CAUI-10 每 PCS lane）、
  25G RS-FEC（Clause 108）、100G RS-FEC（Clause 91，4 FEC lane）—— 均环回 +
  VIP 交叉；200G/400G Clause 119 内置 KP4 RS(544,514)，200G 有环回与 SVT
  交叉、400G 有 SVT 交叉覆盖；另有 10G 线速单 lane RS-FEC（非 IEEE 形态，仅环回）。FEC 码流
  格式（PN 种子、T 位、转码、AM）全部由 VIP 实抓码流标定，见
  `docs/integration_fec.md`。
- 64b/66b 块型：单 lane 覆盖 Clause 49 全部块型（含 lane4 起始 0x33/0x66、
  序集 0x2D/0x55），多 lane 按 Clause 82 集合；driver 可 lane0/lane4 交替起帧
  （`+LANE4`，用于 10G/5G），并由 VIP 10G 接收检查（`svt_lane4`）。
- RX 链路层（形态 A 对接真实 MAC）：链路未起（未锁定/未对齐、hi_ber、AN/LT
  阶段）时 XGMII RX 引脚持续输出 Local Fault；BER 监视判 hi_ber；MLD 多 lane
  （40G/100G CAUI）任一 lane 失锁即整体重对齐，AM 误码连续 3 个以内容忍
  （RS-FEC/200G 为周期起点 AM 单次容忍、连续 2 次重锁）；RX 引脚只在帧间
  插/删 idle，帧内见底次数由非复位/扰动类测试断言为 0。见
  `docs/architecture.md` §2.1。
- KR 建链：Clause 73 AN（10G 单 lane；与 VIP 交叉含交叉复位，数据态链路失效
  后自动重新协商）、Clause 72 LT（训练帧为简化格式，不是 802.3 72.6.10 帧；
  VIP 不支持 cl72，仅自环验证）；另有 XGMII 直驱开关（跳过 PCS/串行，纯 MAC
  功能验证提速），见 `docs/layering_and_dut_modes.md` §2.4~2.5。

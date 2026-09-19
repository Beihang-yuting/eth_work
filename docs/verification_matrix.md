# 验证覆盖矩阵（模式 × 环回 / 1000 帧 / 多次复位 / 扰动 / VIP 交叉 / 交叉复位）

每种 agent 模式都按这 6 列验证；不适用的列注明原因（见第 3 节）。所有目标在
`sim/Makefile`，全量 PHY 回归一条命令：

```bash
cd sim
make -k all      # unit + LOOPBACK_TARGETS（87）+ SVT_TARGETS（33）
```

## 1. 各列含义与判据

| 列 | 测试类 | 内容 | 判据（grep 行 + 下方通用判据） |
|---|---|---|---|
| 环回 | `eth_loopback_test`（AN/KR 为 `eth_an_loopback_test` / `eth_kr_linkup_test`） | 双 agent 串行背靠背，冒烟 20 帧（AN/KR 100 帧，另判建链完成） | `match=20 mismatch=0` 等 |
| 1000 帧 | `eth_stress_test` | 1000 帧背靠背随机模板/长度 | `match=1000 mismatch=0`；另判 `tx_underrun==0` |
| 多次复位 | `eth_multi_reset_test` | 5 轮：流量进行中随机时刻复位（宽松结算）→ 重新 link-up → 500 帧严格段 | `多次复位覆盖完成: 5 轮`；每轮严格段逐段判全净 |
| 扰动 | `eth_disturb_recovery_test` | 500 帧宽松段中注入 20us 扰动：前半整位翻转、后半断线（全 0）→ 恢复后 500 帧严格段 | `段2(恢复后) 完成 match=500` |
| VIP 交叉 | `eth_svt_cross_test` | 与 svt VIP 双向：VIP 发 500 帧我方收，我方发 1000 帧 VIP 收，VIP 全套 checker/覆盖率开 | `A: vip_tx=500 our_rx=500 bad=0 \| B: our_tx=1000 vip_rx=1000` |
| 交叉复位 | `eth_svt_cross_reset_test` | 3 轮我方中途复位（VIP 在线），每段 VIP 100 帧 + 我方 200 帧，逐段计数核对 | `CROSS_RESET_RECOVERY_PASS rounds=3` + 末段计数行 |

通用判据（所有 UVM 目标）：

- 日志 `UVM_ERROR : 0` 且 `UVM_FATAL : 0`（Makefile `CHECK_CLEAN`）—— 只 grep
  汇总行会漏掉 `+UVM_MAX_QUIT_COUNT=5` 下未中止的 1~4 个错误（曾因此漏过
  cl74 启动断流）。
- 严格段（`check_strict`）：该段帧必须全部匹配、零错配、零丢失，逐段判定。
- RX 引脚帧内见底 `rxpin_midframe_underrun == 0`（复位/扰动类测试除外 ——
  它们本就会斩断在途帧）：环回/交叉的 monitor 读 mailbox 看不到引脚，这条
  断言保证形态 A 真实 MAC 看到的 RX 引脚流没有被弹性插拍毁帧。

## 2. 矩阵

| 模式 | 环回 | 1000 帧 | 多次复位 | 扰动 | VIP 交叉 | 交叉复位 |
|---|---|---|---|---|---|---|
| 10G BASE-R | `loopback` | `stress` | `multi_reset`（+`reset_recovery`） | `disturb` | `svt` | `svt_reset` |
| 10G + Clause 74 | `fec` | `stress_fec` | `multi_reset_fec` | `disturb_fec` | `svt_fec` | `svt_fec_reset` |
| 10G 线速 RS-FEC（`+RSFEC`） | `loopback_rsfec` | `stress_rsfec` | `multi_reset_rsfec` | `disturb_rsfec` | N/A ① | N/A ① |
| XGMII 直驱 | `loopback_direct` | `stress_direct` | `multi_reset_direct` | N/A ② | N/A ② | N/A ② |
| AN（Clause 73） | `loopback_an` | `stress_an` | `multi_reset_an` | `disturb_an`（+`disturb_an_relink`） | `svt_an` | `svt_an_reset` |
| LT（Clause 72） | `loopback_lt` | `stress_lt` | `multi_reset_lt` | `disturb_lt` | N/A ③ | N/A ③ |
| KR（AN + LT） | `loopback_kr` | `stress_kr` | `multi_reset_kr` | `disturb_kr` | N/A ③ | N/A ③ |
| 5GBASE-R | `loopback_5g` | `stress_5g` | `multi_reset_5g` | `disturb_5g` | `svt_5g` | `svt_5g_reset` |
| 25GBASE-R | `loopback_25g` | `stress_25g` | `multi_reset_25g` | `disturb_25g` | `svt_25g` | `svt_25g_reset` |
| 25G + Clause 74 | `loopback_25g_fec` | `stress_25g_fec` | `multi_reset_25g_fec` | `disturb_25g_fec` | `svt_25g_fec` | `svt_25g_fec_reset` |
| 25G + RS-FEC（Clause 108） | `loopback_25g_rsfec` | `stress_25g_rsfec` | `multi_reset_25g_rsfec` | `disturb_25g_rsfec` | `svt_25g_rsfec` | `svt_25g_rsfec_reset` |
| 40GBASE-R（MLD 4 lane） | `loopback_40g` | `stress_40g` | `multi_reset_40g` | `disturb_40g` | `svt_40g` | `svt_40g_reset` |
| 40G + Clause 74 | `loopback_40g_fec` | `stress_40g_fec` | `multi_reset_40g_fec` | `disturb_40g_fec` | `svt_40g_fec` | `svt_40g_fec_reset` |
| 100G CAUI-10 | `loopback_100g` | `stress_100g` | `multi_reset_100g` | `disturb_100g` | `svt_100g` | `svt_100g_reset` |
| 100G CAUI-10 + Clause 74 | `loopback_100g_fec` | `stress_100g_fec` | `multi_reset_100g_fec` | `disturb_100g_fec` | `svt_100g_fec` | `svt_100g_fec_reset` |
| 100G CAUI-4 | `loopback_100g4` | `stress_100g4` | `multi_reset_100g4` | `disturb_100g4` | `svt_100g4` | `svt_100g4_reset` |
| 100G RS-FEC（Clause 91，`100gr`） | `loopback_100gr` | `stress_100gr` | `multi_reset_100gr` | `disturb_100gr` | `svt_100gr` | `svt_100gr_reset` |
| 200G（Clause 119） | `loopback_200g` | `stress_200g` | `multi_reset_200g` | `disturb_200g` | `svt_200g` | `svt_200g_reset` |
| 50GBASE-R（SVT 交叉扩展） | — | — | — | — | `svt_50g`（已执行通过） | `svt_50g_reset`（已执行通过） |
| 400GBASE-R（Clause 119，SVT 交叉扩展） | — | — | — | — | `svt_400g`（已执行但失败） | `svt_400g_reset`（尚未执行） |
| 1000BASE-X | `loopback_1g` | `stress_1g` | `multi_reset_1g` | `disturb_1g` | `svt_1g` | `svt_1g_reset` |
| 2.5GBASE-X | `loopback_2p5g` | `stress_2p5g` | `multi_reset_2p5g` | `disturb_2p5g` | `svt_2p5g` | `svt_2p5g_reset` |

专项目标（不属于上面 6 列，覆盖形态 A 的链路层行为）：

| 目标 | 内容 |
|---|---|
| `link_fault` / `link_fault_40g` | RX 引脚在建链前、断线期间（40G 另测仅 lane0 断线）、hi_ber 期间持续为 Local Fault；hi_ber 由稀疏单 bit 误码触发（块锁不丢）、撤扰后一个干净窗口清除；前后各 500 帧严格段 |
| `stress_lane4` / `stress_lane4_fec` / `stress_lane4_rsfec` / `stress_lane4_5g` | driver 奇数帧从 lane4 起帧（0x33 块），1000 帧 |
| `svt_lane4` | 我方 lane4 起帧由 VIP 10G 接收检查 |
| `disturb_an_relink` | 断线 30us（超过 AN 链路失效门限 20us），两端经链路失效重新协商后流量恢复（判两端重协商次数均 ≥ 1） |
| `unit` | 编解码（含 IEEE 图 49-7 黄金值、Clause 82 块型集合）、扰码、块同步、BER 监视、Clause 74、MLD（含 AM 误码容忍）、RS-FEC（含 VIP 黄金码字与定向去偏斜）、Clause 119、AN（含 nonce 碰撞）、LT、8b/10b |

## 3. 不适用（N/A）说明

1. **10G 线速 RS-FEC**：IEEE 没有"10GBASE-R + RS(528,514)"这一形态，svt VIP 也
   没有对应接口模式；码流格式与 25G Clause 108 相同，25G RS-FEC 已与 VIP 交叉
   （`svt_25g_rsfec*`）。
2. **XGMII 直驱**：跳过 PCS 与串行链路，没有线路可扰动、也没有 PHY 码流可与
   VIP 对接（纯 MAC 功能验证提速用）。
3. **LT / KR**：svt VIP R-2020.12 不支持 Clause 72（无 LT 接口模式、配置项与
   示例），只能双 agent 自环对训；KR 的 AN 部分已单独与 VIP 交叉（`svt_an*`）。
4. **100G CAUI-4 + Clause 74**：不是标准组合（100GBASE-KR4/CR4 用 RS-FEC），无目标。

## 4. 扰动与复位的设计要点

- **扰动两段**：整位翻转对 64b/66b 同步头仍合法（01↔10），BASE-R 不会失锁，
  只损伤码字/AM/码组；断线（全 0）保证每种模式都经历"失锁 → 重锁"。
- **AN 模式**：数据态下 RX 链路持续不可用（失锁或 hi_ber）超过 `cfg.an_link_fail_inhibit`（默认 20us）
  即回到 AN 重新协商（IEEE AN_GOOD 下链路失效的行为）；`disturb_an` 的断线
  10us 不触发，`disturb_an_relink` 的 30us 触发。
- **交叉复位 AN**：VIP 开 `enable_an73_internal_restart`（我方复位后改发 DME，
  VIP 发现链路失效自行重协商），测试先等 VIP 离开 AN_GOOD 再等其回到 AN_GOOD。
- **复位/扰动窗内 VIP 报错**：`register_fail:*` 仅在复位窗内降为 WARNING，窗外
  原样报错。

## 5. 待办项（不纳入当前 `make all`）

当前已完成并核对：`make -k all` 在 53 上退出码为 0；`make unit` 的 78697 项检查通过，87 个环回目标和 35 个 SVT 目标通过，均为 `UVM_ERROR=0`、`UVM_FATAL=0`。其中新增的 50G 普通 SVT 交叉和交叉复位已纳入默认回归并通过；普通交叉日志判据为 `A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000`，复位日志判据为 `CROSS_RESET_RECOVERY_PASS rounds=3` 和 `A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200`，两者均满足 `invalid_block=0`、`fec_uncorr=0`、`tx_underrun=0`、`UVM_ERROR : 0`、`UVM_FATAL : 0`。400G 普通 SVT 交叉已执行但失败（RS 解码未通过并出现 VIP PCS 错误），因此不能计入通过数；400G 交叉复位尚未执行。

| 项 | 当前状态 | 计划交付 | 前置确认 |
|---|---|---|---|
| 50G SVT 交叉 | 普通交叉和交叉复位均已执行通过。VIP `ETH_50G_1_LANE` 的 4-lane AM/deskew、PMA 时钟和双向计数判据已接通 | 保持回归覆盖；若修改 50G PMA/MLD，再重跑普通与复位交叉 | 正式流程使用 `v_serial_25g_clk`；不再添加 `+PMA_RX_DIV2`。复位判据：`CROSS_RESET_RECOVERY_PASS rounds=3` 及 `A: vip_tx=100 our_rx=100 bad=0 \| B: our_tx=200 vip_rx=200` |
| 400G SVT 交叉 | 普通交叉已执行但失败：当前 16-lane Clause 119 实现的 RS 解码未通过，并触发 VIP PCS checksum/block 错误；交叉复位尚未执行 | 按现有流程继续确认真实 CDBI lane/codeword 映射；映射稳定且普通交叉通过后再执行 `svt_400g_reset`，并覆盖链路复位和 RS-FEC 判据 | 明确 SVT `ETH_400G_SERIAL` 双 8-lane PCS 的 AM/对齐、四码字交织和 lane 映射；诊断日志不能替代 `UVM_ERROR/FATAL=0` 及双方计数判据 |

DesignWare SVT R-2020.12 还提供 800G 接口枚举，但当前 DUT 和本项目回归范围未覆盖，暂不纳入本次代办。56G 在该 SVT 版本中没有对应的以太网 PCS 接口枚举，不能直接按 `+SPEED=56g` 增加目标。

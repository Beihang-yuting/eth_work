# 示例：FEC 叠加（Clause 74 / 25G RS-FEC / 100G RS-FEC）

展示 FEC 叠加：**同一编译产物**，`+FEC` / `+RSFEC` 开关与 `+SPEED` 组合（可用
组合见下表），100G RS-FEC 用 `+SPEED=100gr`。top 零改动（`eth_pcs_lb_env`
已含单 lane 口与 10 条 lane 组）。

## 组合一览

| 命令行 | 效果 |
|--------|------|
| `+FEC` | 10G BASE-KR + Clause 74 |
| `+SPEED=25g +FEC` | 25GBASE-R + Clause 74 |
| `+SPEED=40g +FEC` | 40GBASE-KR4：MLD 4 lane，每 PCS lane 一套 Clause 74 |
| `+SPEED=100g +FEC` | 100G CAUI-10：20 PCS lane 各一套 Clause 74，再 2:1 bit 复用 |
| `+RSFEC` | 10G 线速 + 单 lane RS-FEC（码流格式同 Clause 108；只有自环目标，IEEE 与 VIP 都没有这一形态） |
| `+SPEED=25g +RSFEC` | 25GBASE-R + Clause 108 RS-FEC |
| `+SPEED=100gr` | 100GBASE-R + Clause 91 RS-FEC（20 PCS lane → 4 FEC lane × 25.78G） |

## 运行

```bash
cd sim
make fec stress_fec multi_reset_fec disturb_fec      # 10G + Clause 74：环回 / 1000 帧 / 多次复位 / 扰动
make stress_25g_fec stress_40g_fec stress_100g_fec   # 25G / 40G / 100G CAUI-10 + Clause 74，1000 帧
make stress_rsfec stress_25g_rsfec stress_100gr      # 10G 线速 / 25G / 100G RS-FEC，1000 帧
make stress_lane4_fec stress_lane4_rsfec             # lane4 起帧经 cl74 / RS-FEC
make svt_fec svt_25g_fec svt_40g_fec svt_100g_fec svt_25g_rsfec svt_100gr   # 与 VIP 交叉
make svt_fec_reset svt_25g_fec_reset svt_40g_fec_reset svt_100g_fec_reset \
     svt_25g_rsfec_reset svt_100gr_reset                                    # 交叉复位
```

每种组合的全部 6 列目标（含各速率的环回、多次复位、扰动）见
`docs/integration_fec.md` 第 2 节，全模式矩阵见 `docs/verification_matrix.md`。

## 预期结果判读

make 目标的 PASS = Makefile 里 grep 的行（下文标"判据行"）+ 日志
`UVM_ERROR : 0` 且 `UVM_FATAL : 0`（`CHECK_CLEAN`）。测试自带的检查 ——
严格段逐段全净、1000 帧 `tx_underrun==0`、非复位/扰动类 RX 引脚帧内见底
为 0、交叉复位逐段计数 —— 都以 UVM_ERROR 上报，由后者兜住。PCS_STATS 计数
monitor 只打印、不判失败。

- 冒烟 / 1000 帧：判据行 `[SB] match=N mismatch=0`；PCS_STATS 两端
  `crc_err=0 invalid_block=0`；
- 多次复位：判据行 `多次复位覆盖完成: 5 轮`；扰动：判据行
  `段2(恢复后) 完成 match=500`。复位/扰动段内被斩断的帧按宽松比对结算，
  之后的严格段须全净；
- 交叉：判据行 `A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000`，
  另应 UVM_WARNING=0（VIP 全套 checker 开启，含 FEC 覆盖率与协议检查）；
- 交叉复位（`svt_*_reset`）：判据行 `CROSS_RESET_RECOVERY_PASS rounds=3` 与末段
  `A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200`（复位窗内 VIP 的
  register_fail 报错按预期降为 WARNING）。

## 自己写发包序列

与 10G 完全一样 —— `eth_frame_txn` 序列零适配。FEC 编码、转码、AM、符号
分发全部在 BFM 内部完成。

集成细节与码流格式：`docs/integration_fec.md`。

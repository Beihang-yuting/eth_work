# 示例：FEC 叠加（Clause 74 / 25G RS-FEC / 100G RS-FEC）

展示 FEC 叠加：**同一编译产物**，`+FEC` / `+RSFEC` 开关与 `+SPEED` 任意组合，
100G RS-FEC 用 `+SPEED=100gr`。top 零改动（`eth_pcs_lb_env` 已含单 lane 口与
10 条 lane 组）。

## 组合一览

| 命令行 | 效果 |
|--------|------|
| `+FEC` | 10G BASE-KR + Clause 74 |
| `+SPEED=25g +FEC` | 25GBASE-R + Clause 74 |
| `+SPEED=40g +FEC` | 40GBASE-KR4：MLD 4 lane，每 PCS lane 一套 Clause 74 |
| `+SPEED=100g +FEC` | 100G CAUI-10：20 PCS lane 各一套 Clause 74，再 2:1 bit 复用 |
| `+SPEED=25g +RSFEC` | 25GBASE-R + Clause 108 RS-FEC |
| `+SPEED=100gr` | 100GBASE-R + Clause 91 RS-FEC（20 PCS lane → 4 FEC lane × 25.78G） |

## 运行

```bash
cd sim
make loopback_40g_fec stress_40g_fec multi_reset_40g_fec
make loopback_25g_rsfec stress_25g_rsfec multi_reset_25g_rsfec
make loopback_100gr stress_100gr multi_reset_100gr
make svt_fec svt_25g_fec svt_40g_fec svt_25g_rsfec svt_100gr      # 与 VIP 交叉
make svt_fec_reset svt_40g_fec_reset svt_25g_rsfec_reset svt_100gr_reset
```

## 预期结果判读

- 环回：`[SB] match=N mismatch=0`；PCS_STATS 两端 `crc_err=0 invalid_block=0`；
- 交叉：`A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000`，
  UVM_ERROR=0、UVM_WARNING=0（VIP 全套 checker 开启，含 FEC 覆盖率与协议检查）。

## 自己写发包序列

与 10G 完全一样 —— `eth_frame_txn` 序列零适配。FEC 编码、转码、AM、符号
分发全部在 BFM 内部完成。

集成细节与码流格式：`docs/integration_fec.md`。

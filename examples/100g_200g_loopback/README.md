# 示例：100G / 200G 多 lane 环回

展示多 lane 高速模式：**同一编译产物**，`+SPEED=100g` / `100g4` / `200g`
切换，top 零改动（`eth_pcs_lb_env` 已含 10 条物理 lane 组）。

## 与 40G 示例的差异点

| 项 | 40G | 100G CAUI-10 | 100G CAUI-4 | 200G |
|----|-----|--------------|-------------|------|
| PCS lane | 4 | 20 | 20 | 8 |
| 物理 lane | 4 × 10.3125G | 10 × 10.3125G | 4 × 25.78125G | 8 × 26.5625G |
| PMA 复用 | 1:1 | 2:1 | 5:1 | 1:1 |
| 编码/FEC | 64b/66b + MLD（`+FEC` 可叠加 cl74） | 64b/66b + MLD（`+FEC` 可叠加 cl74） | 64b/66b + MLD | 257b + RS(544,514) |
| AM | 每 lane 512 块（svt 交叉 64） | 每 lane 64 块 | 每 lane 64 块 | 每 16 码字 120bit |
| svt VIP 模式 | ETH_XLSBI_SERIAL | ETH_CAUI | ETH_CAUI_25X4 | ETH_200G_SERIAL |

## 运行

```bash
cd sim
# 每模式 6 列：环回 / 1000 帧 / 多次复位 / 扰动 / VIP 交叉 / 交叉复位
make loopback_100g stress_100g multi_reset_100g disturb_100g svt_100g svt_100g_reset
make loopback_100g_fec stress_100g_fec multi_reset_100g_fec disturb_100g_fec   # CAUI-10 + cl74
make svt_100g_fec svt_100g_fec_reset
make loopback_100g4 stress_100g4 multi_reset_100g4 disturb_100g4 svt_100g4 svt_100g4_reset
make loopback_200g stress_200g multi_reset_200g disturb_200g svt_200g svt_200g_reset
```

## 预期结果判读

- 通过判据：各目标 grep 的汇总行，且日志 `UVM_ERROR : 0`、`UVM_FATAL : 0`
  （Makefile `CHECK_CLEAN`）；各列 grep 行见 `docs/verification_matrix.md`。
- 环回：`[SB] match=N mismatch=0`；PCS_STATS 两端 `crc_err=0 invalid_block=0
  tx_underrun=0`。PCS_STATS 由 monitor 打印；其中 `stress_*` 另判 A 端
  `tx_underrun == 0`，非复位/扰动类测试另判 RX 引脚帧内见底
  `rxpin_midframe == 0`，违例以 UVM_ERROR 上报。
- 多次复位 / 扰动：`多次复位覆盖完成: 5 轮` / `段2(恢复后) 完成 match=500`，
  每个严格段逐段判全净。
- 交叉：`svt_100g` / `svt_100g_fec` / `svt_100g4` / `svt_200g` 为
  `A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000`（VIP 全套
  checker 开启，含每 lane AM/BIP；200G 的 AM 不含 BIP）；`*_reset` 为
  `CROSS_RESET_RECOVERY_PASS rounds=3`，每段 VIP 100 帧 + 我方 200 帧逐段核对计数。
- UVM_WARNING 不在判据内（交叉复位窗内 VIP 的 `register_fail` 降为 WARNING）。

## 自己写发包序列

与 10G 完全一样 —— `eth_frame_txn` 序列零适配。多 lane 分发、AM、PMA
复用、200G 的转码/RS 编码全部在 BFM 内部完成。

集成细节：`docs/integration_100g_200g.md`。

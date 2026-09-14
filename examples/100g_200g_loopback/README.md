# 示例：100G / 200G 多 lane 环回

展示多 lane 高速模式：**同一编译产物**，`+SPEED=100g` / `100g4` / `200g`
切换，top 零改动（`eth_pcs_lb_env` 已含 10 条物理 lane 组）。

## 与 40G 示例的差异点

| 项 | 40G | 100G CAUI-10 | 100G CAUI-4 | 200G |
|----|-----|--------------|-------------|------|
| PCS lane | 4 | 20 | 20 | 8 |
| 物理 lane | 4 × 10.3125G | 10 × 10.3125G | 4 × 25.78125G | 8 × 26.5625G |
| PMA 复用 | 1:1 | 2:1 | 5:1 | 1:1 |
| 编码/FEC | 64b/66b + MLD | 64b/66b + MLD | 64b/66b + MLD | 257b + RS(544,514) |
| AM | 每 lane 64 块 | 每 lane 64 块 | 每 lane 64 块 | 每 16 码字 120bit |
| svt VIP 模式 | ETH_XLSBI_SERIAL | ETH_CAUI | ETH_CAUI_25X4 | ETH_200G_SERIAL |

## 运行

```bash
cd sim
make loopback_100g stress_100g multi_reset_100g
make loopback_100g4 stress_100g4
make loopback_200g stress_200g multi_reset_200g
make svt_100g svt_100g4 svt_200g                      # 与 VIP 交叉
make svt_100g_reset svt_100g4_reset svt_200g_reset    # 交叉中途复位恢复
```

## 预期结果判读

- 环回：`[SB] match=N mismatch=0`；PCS_STATS 两端 `crc_err=0 invalid_block=0
  tx_underrun=0`；
- 交叉：`A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000`，
  UVM_ERROR=0、UVM_WARNING=0（VIP 全套 checker 开启，含每 lane AM/BIP）。

## 自己写发包序列

与 10G 完全一样 —— `eth_frame_txn` 序列零适配。多 lane 分发、AM、PMA
复用、200G 的转码/RS 编码全部在 BFM 内部完成。

集成细节：`docs/integration_100g_200g.md`。

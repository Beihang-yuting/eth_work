# 示例：25G 单 lane 环回（速率切换模式示例）

展示 `+SPEED` 参数化速率：**同一编译产物**跑 10G/25G/5G，agent 零改动。
文件复用 10G 示例（`examples/10g_basekr_loopback/README.md` 的导读全部
适用），本 README 只列 25G/5G 差异。

## 差异点

| 项 | 10G | 25G | 5G |
|----|-----|-----|----|
| 位时钟 | 10.3125 GHz | 25.78125 GHz | 5.15625 GHz |
| 字时钟（位钟/66） | 156.25 MHz | 390.625 MHz | 78.125 MHz |
| BER 监视（ber_limit / ber_window_blocks） | 16 / 19531 | 97 / 781250 | 16 / 19531（暂同 10G） |
| svt VIP 模式 | ETH_XSBI_SERIAL | ETH_25G_SERIAL（时钟 serial_caui_25g_clk_*） | ETH_5G_BASER_SERIAL（serial_*_baser_clk / xsbi / xgmii 时钟减半） |

时钟由 top.sv 按 `+SPEED` 选（字时钟 top 自动推导），BER 参数由
`eth_loopback_test` / `eth_svt_cross_test` 按 `+SPEED` 设置。

## 运行

```bash
cd sim
make loopback_25g stress_25g multi_reset_25g disturb_25g   # 25G 环回/1000 帧/多次复位/扰动
make svt_25g svt_25g_reset                                 # 25G 与 VIP 交叉 / 交叉复位
make loopback_5g stress_5g multi_reset_5g disturb_5g       # 5G 同上
make svt_5g svt_5g_reset                                   # 5G 与 VIP 交叉 / 交叉复位
```

## 预期结果

- 环回系判读与 10G 示例相同（`[SB] match=N mismatch=0`，PCS_STATS 判读
  见 10G 示例）；
- VIP 交叉 `svt_25g` / `svt_5g`：`A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000`；
  交叉复位 `svt_25g_reset` / `svt_5g_reset`：`CROSS_RESET_RECOVERY_PASS rounds=3`
  与末段 `A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200`；
- 上述目标另要求日志 `UVM_ERROR : 0` 且 `UVM_FATAL : 0`。

各列判据与 25G FEC 变体目标见 `docs/verification_matrix.md`；集成细节：
`docs/integration_25g_5g.md`。

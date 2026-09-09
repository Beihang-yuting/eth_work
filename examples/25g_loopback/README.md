# 示例：25G 单 lane 环回（速率切换模式示例）

展示 `+SPEED` 参数化速率：**同一编译产物**跑 10G/25G/5G，agent 零改动。
文件复用 10G 示例（`examples/10g_basekr_loopback/README.md` 的导读全部
适用），本 README 只列 25G 差异。

## 差异点

| 项 | 10G | 25G |
|----|-----|-----|
| 位时钟 | 10.3125 GHz | 25.78125 GHz（top.sv 按 `+SPEED=25g` 选） |
| 字时钟 | 156.25 MHz | 390.625 MHz（恒为位钟/66，top 自动推导） |
| svt VIP 模式 | ETH_XSBI_SERIAL | ETH_25G_SERIAL（时钟 serial_caui_25g_clk_*） |

## 运行

```bash
cd sim
make loopback_25g stress_25g multi_reset_25g   # 环回/大流量/多次复位
make svt_25g                                    # 与 VIP 25G 交叉验证
make stress_5g                                  # 5G 同理（环回系）
```

预期结果判读与 10G 示例相同（`[SB] match=N mismatch=0`、PCS_STATS 干净）。

集成细节：`docs/integration_25g_5g.md`。

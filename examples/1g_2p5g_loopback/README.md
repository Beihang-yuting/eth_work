# 示例：1G / 2.5G BASE-X 环回（8b/10b 编码栈示例）

展示 BASE-X 模式：**同一编译产物**，`+SPEED=1g` / `+SPEED=2.5g` 切到
8b/10b + Clause 36 有序集，MAC 侧自动从 XGMII 换成 GMII。top 零改动
（`eth_pcs_lb_env` 已含 GMII 口）。

## 与 10G 示例的差异点

| 项 | 10G | 1G | 2.5G |
|----|-----|----|------|
| 位时钟 | 10.3125 GHz | 1.25 Gbaud | 3.125 Gbaud |
| MAC 侧时钟 | XGMII 156.25 MHz | GMII 125 MHz | GMII 312.5 MHz |
| MAC 侧接口 | xgmii_if（64bit） | gmii_if（8bit + tx_en/tx_er） | 同 1G |
| 线路编码 | 64b/66b | 8b/10b | 8b/10b |
| svt VIP 模式 | ETH_XSBI_SERIAL | ETH_1G_BASEX_1BIT | ETH_2PT5G_BASEX_SERIAL |

## 运行

```bash
cd sim
make loopback_1g stress_1g multi_reset_1g disturb_1g         # 1G 环回系全档
make loopback_2p5g stress_2p5g multi_reset_2p5g disturb_2p5g # 2.5G 环回系全档
make svt_1g svt_2p5g                                         # 1G/2.5G 与 VIP 交叉
make svt_1g_reset svt_2p5g_reset                             # 交叉中途复位恢复
```

## 预期结果判读

- 环回系：`[SB] match=N mismatch=0`；
- 交叉 `svt_1g` / `svt_2p5g`：`A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000`；
  交叉复位 `svt_1g_reset` / `svt_2p5g_reset`：`CROSS_RESET_RECOVERY_PASS rounds=3`
  与末段 `A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200`；
- 上述目标另要求日志 `UVM_ERROR : 0` 且 `UVM_FATAL : 0`；各列判据见
  `docs/verification_matrix.md`；
- BASE-X 同步很快（数个 idle 有序集内即得同步）；若交叉时等锁或流量
  超时，先查 VIP 侧 `enable_an37_mode` 是否为 0（我方未实现 Clause 37 AN）。

## 自己写发包序列

与 10G 完全一样 —— 仍然是 `eth_frame_txn` 序列，driver 在 BASE-X 模式下
自动把帧展开成 GMII 字节（7×0x55 前导 + SFD + 帧 + FCS，帧间 12 字节
IPG），序列代码零适配。

集成细节：`docs/integration_1g_2p5g.md`。

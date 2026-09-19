# 25G / 5G 单 lane 模式 —— 环境集成与使用说明

适用：eth_pcs_agent 的 25GBASE-R（`ETH_25G_SERIAL`）与 5GBASE-R
（`ETH_5G_BASER_SERIAL`）单 lane 模式。可跑示例见 `examples/25g_loopback/`。

## 1. 与 10G 的关系（先读 `integration_10g_basekr.md`）

agent 是 **bit 级建模、速率无关**：64b/66b 编解码、扰码、块同步、弹性
idle 机制与 10G 完全共用，无新增代码。25G/5G 只是时钟频率不同（25G 另需
改 BER 监视参数，见第 3 节）：

| 模式 | 位时钟 | 字时钟（位钟/66） |
|------|--------|-------------------|
| 10G  | 10.3125 GHz | 156.25 MHz |
| 25G  | 25.78125 GHz | 390.625 MHz |
| 5G   | 5.15625 GHz | 78.125 MHz |

## 2. 使用方式

TB 层通过 `+SPEED` 插件参数选速率（默认 10g），无需重新编译：

```bash
cd sim
# 25G（VIP ETH_25G_SERIAL）
make loopback_25g stress_25g multi_reset_25g disturb_25g   # 环回/1000 帧/多次复位/扰动
make svt_25g svt_25g_reset     # VIP 交叉 / 交叉复位（3 轮我方复位，VIP 持续在线）
# 5G（VIP ETH_5G_BASER_SERIAL）
make loopback_5g stress_5g multi_reset_5g disturb_5g
make svt_5g svt_5g_reset
make stress_lane4_5g           # 5G 奇数帧从 lane4 起帧，1000 帧

# 任意测试换速率：
build/loopback/simv +UVM_TESTNAME=eth_stress_test +SPEED=25g +NUM_FRAMES=5000
```

25G/5G 的 6 列（环回 / 1000 帧 / 多次复位 / 扰动 / VIP 交叉 / 交叉复位）
齐全；25G 叠加 `+FEC` / `+RSFEC` 的两组 6 列目标、各列内容与判据（grep
汇总行 + 日志 `UVM_ERROR : 0`、`UVM_FATAL : 0`）见 `verification_matrix.md`。

## 3. 集成到自有 TB 的差异点

时钟与 BER 监视参数（其余与 10G 集成说明相同）：

```systemverilog
// aip_clk 设频（top 层）：
bit_clk_gen.set_freq(25.78125e9);          // 25G；5G 用 5.15625e9
word_clk_gen.set_freq(25.78125e9 / 66.0);  // 字钟 = 位钟/66（+RSFEC 另 ×319/320）
word_clk_gen.set_ppm(100);                 // 删除主导域约定不变

// cfg（仅 25G）：BER 监视按 IEEE 25G 窗口；cfg 默认是 10GBASE-R 的 16 / 19531
cfg.ber_limit         = 97;
cfg.ber_window_blocks = 781250;
// 5G 暂沿用默认的 10G 值
```

仓库 TB（`eth_loopback_test` 与 `eth_svt_cross_test` 的 build_phase）已按
`+SPEED` 自动设置这两项，自有 TB 须自己设。

对接 svt VIP（25G）：
- cfg：`interface_select = ETH_25G_SERIAL;`
- 串行时钟：VIP 侧 `serial_caui_25g_clk_tx/rx`（周期 38.788ps），
  数据仍在 `tx_lane[0]/rx_lane[0]`；接线与 10G KR 完全同构，见
  `test/svt/top_svt.sv` 的 `+SPEED=25g` 分支。

对接 svt VIP（5G）：
- cfg：`interface_select = ETH_5G_BASER_SERIAL;`
- 时钟：以下三路为 10G 频率减半 —— `serial_tx/rx_baser_clk` 5.15625GHz、
  `xsbi_tx/rx_clk` = 位钟/16（≈322.27MHz）、`xgmii_tx/rx_clk` 78.125MHz；
  `eth_pcs_svt_clock_gen` 按 `+SPEED=5g` 自动切换。我方位钟接同一根
  `v_serial_baser_clk`，字钟 5.15625G/66 +100ppm，数据在
  `tx_lane[0]/rx_lane[0]`，见 `test/svt/top_svt.sv`。

## 4. 检查点与已知限制

PCS_STATS 检查点与 10G 一致（见 `integration_10g_basekr.md` 第 7 节）。
FEC 叠加：25G 可开 `+FEC`（Clause 74）或 `+RSFEC`（Clause 108），含 VIP
交叉，见 `integration_fec.md`。

- **块型集合**：单 lane（10G/5G/25G）统一按 Clause 49 块型编解码，25G 同样
  支持 lane4 起帧（0x33）与序集块（0x55 等）；这些块在 IEEE 25GBASE-R 下
  的格式未核实。`cfg.lane4_start` 只建议 10G/5G 使用（5G 回归
  `stress_lane4_5g`）。
- **Local Fault**：RX 链路未起（未锁定或 hi_ber）时 RX 引脚持续输出
  Local Fault，25G 同样用 Clause 49 字（`rxc=8'h11`、
  `rxd=64'h0100009C_0100009C`，lane0 与 lane4 各一个 LF 序集）。
  `link_fault` 回归只覆盖 10G 与 40G。
- **BER 监视**：25G 取 97 / 781250（IEEE 2ms 窗口），hi_ber 要等到某个
  完整窗口内坏同步头少于 97 个才清除（一个窗口约 2ms 仿真时间）；5G 暂
  沿用 10G 的 16 / 19531。
- AN(cl73)/LT(cl72) 的实现与自测目标都以 10GBASE-KR 为准（AN 的 DME 时序
  按 10.3125G 位钟 tick 计数），25G/5G 下未验证。

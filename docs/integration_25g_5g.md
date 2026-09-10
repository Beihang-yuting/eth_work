# 25G / 5G 单 lane 模式 —— 环境集成与使用说明

适用：eth_pcs_agent 的 25GBASE-R（`ETH_25G_SERIAL`）与 5GBASE-R
（`ETH_5G_BASER_SERIAL`）单 lane 模式。可跑示例见 `examples/25g_loopback/`。

## 1. 与 10G 的关系（先读 `integration_10g_basekr.md`）

agent 是 **bit 级建模、速率无关**：64b/66b 编解码、扰码、块同步、弹性
idle 机制与 10G 完全共用，无新增代码。25G/5G 只是时钟频率不同：

| 模式 | 位时钟 | 字时钟（位钟/66） |
|------|--------|-------------------|
| 10G  | 10.3125 GHz | 156.25 MHz |
| 25G  | 25.78125 GHz | 390.625 MHz |
| 5G   | 5.15625 GHz | 78.125 MHz |

## 2. 使用方式

TB 层通过 `+SPEED` 插件参数选速率（默认 10g），无需重新编译：

```bash
cd sim
make loopback_25g      # 25G 环回冒烟
make stress_25g        # 25G 大流量 1000 帧
make multi_reset_25g   # 25G 多次复位覆盖
make stress_5g         # 5G 大流量 1000 帧
make svt_25g           # 25G 与 svt VIP（ETH_25G_SERIAL）交叉验证
make svt_25g_reset     # 25G 交叉中途复位恢复（3 轮复位，VIP 持续在线）
make multi_reset_5g    # 5G 环回多次复位覆盖

# 任意测试换速率：
build/loopback/simv +UVM_TESTNAME=eth_stress_test +SPEED=25g +NUM_FRAMES=5000
```

## 3. 集成到自有 TB 的差异点

仅时钟（其余与 10G 集成说明相同）：

```systemverilog
// aip_clk 设频（top 层）：
bit_clk_gen.set_freq(25.78125e9);          // 25G；5G 用 5.15625e9
word_clk_gen.set_freq(25.78125e9 / 66.0);  // 字钟恒为位钟/66
word_clk_gen.set_ppm(100);                 // 删除主导域约定不变
```

对接 svt VIP（25G）：
- cfg：`interface_select = ETH_25G_SERIAL;`
- 串行时钟：VIP 侧 `serial_caui_25g_clk_tx/rx`（周期 38.788ps），
  数据仍在 `tx_lane[0]/rx_lane[0]`；接线与 10G KR 完全同构，见
  `test/svt/top_svt.sv` 的 `+SPEED=25g` 分支。

## 4. 检查点与已知限制

与 10G 完全一致（PCS_STATS 表、FEC 限制、AN/LT 未实现——见
`integration_10g_basekr.md` 第 7/8 节）。5G 的 svt 交叉验证待做
（VIP `ETH_5G_BASER_SERIAL` 时钟信号待接，环回系全部可用）。

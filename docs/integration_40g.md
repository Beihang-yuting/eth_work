# 40G（4 lane，Clause 82 MLD）模式 —— 环境集成与使用说明

适用：eth_pcs_agent 多 lane 模式（40GBASE-R，4×10.3125G）。
可跑示例见 `examples/40g_loopback/`。先读 `integration_10g_basekr.md`
（公共部分），本文只讲多 lane 差异。

## 1. 架构差异

单 66b 块流在加扰后经 **MLD 层**（`src/pcs/mld.sv`）轮转分发到 4 条
串行 lane，每 lane 每 `am_spacing` 块插入一个对齐标记 AM（IEEE 表 82-2
图案，不加扰）。接收端每 lane 独立块同步 → AM 识别 lane 号（**容忍
物理 lane 乱接**）→ 以 AM 去偏斜 → 重组单流 → 解扰解码。

## 2. cfg 与接口

```systemverilog
cfg.num_lanes  = 4;      // >1 启用 MLD
cfg.am_spacing = 512;    // 标准 16384；仿真提速可调小，两端一致即可
cfg.fec_enable = 0;      // MLD 暂不支持叠加 FEC（TODO）
foreach (cfg.vif_serial_lanes[i]) cfg.vif_serial_lanes[i] = <lane i 接口>;
// 单 lane 的 cfg.vif_serial 不使用
```

## 3. top 层要点（参考 test/uvm/top_40g.sv）

- 每端 4 个 `serial_if`（位钟 10.3125G），交叉连线按 lane 对接；
  vif 下发键名 `vif_serial_<port>_l<i>`。
- **字时钟必须扣除 AM 带宽开销**：
  `word_hz = 4×10.3125e9/66 × (am_spacing-1)/am_spacing × (1+100ppm)`
  —— AM 占线上带宽，不扣除会打破删除主导域导致断流。

## 4. 运行

```bash
cd sim
make loopback_40g      # 40G 环回冒烟
make stress_40g        # 1000 帧大流量
make multi_reset_40g   # 5 轮中途复位恢复
make svt_40g           # svt VIP 双向交叉（A: VIP->我方 500 帧，B: 我方->VIP 1000 帧）
```

判读同 10G；`rx_locked()` 在多 lane 模式表示 MLD 全 lane 对齐完成。

## 5. svt VIP 交叉要点（40G XLSBI）

- **AM 间隔必须两侧一致，且受 VIP 能力约束**：VIP `xlsbi_40g_align_timer`
  默认 64，合理约束仅 {64,128,256} —— 标准 16384 超出 VIP 支持范围。
  交叉环境两侧统一 64（`set_40g_cfg` 显式配 VIP，phy `am_spacing=64`，
  top_svt 字钟扣减 63/64）。
- 不一致的后果（曾踩坑）：VIP RX 每周期报 invalid_align/bip，累计 ~21
  周期后 VIP 内部复位并扰乱其 TX，方向 A 出现固定时刻的 76 块乱码与
  len=0 脏帧；report catcher 降级只能压报告压不住 VIP 内部状态。
- BIP-8 按 IEEE 表 82-4 实现（TX 生成 + RX 校验），与 VIP checker 互通。
- mld_rx 对齐后 AM 间隔自检为学习式（首个完整间隔作基准），兼容对端对
  spacing 是否含 AM 的不同计数约定；偏离即整体重对齐。

## 6. 已知限制（TODO）

- MLD 与 Clause 74 FEC 叠加未实现。
- 100G（20 逻辑 lane）待参数化扩展。

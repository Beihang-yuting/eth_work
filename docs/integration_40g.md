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
cfg.fec_enable = 0;      // 1 = 每 PCS lane 叠加 Clause 74（见 integration_fec.md）
cfg.ber_limit         = 97;      // hi_ber：IEEE 40G 窗口 1.25ms = 781250 块 / 97 个
cfg.ber_window_blocks = 781250;  //（cfg 默认是 10G 的 16 / 19531，见第 5 节）
foreach (cfg.vif_serial_lanes[i]) cfg.vif_serial_lanes[i] = <lane i 接口>;
// 单 lane 的 cfg.vif_serial 不使用
```

## 3. top 层要点（参考 test/uvm/top.sv，`eth_pcs_lb_env 一键展开）

- 每端 4 个 `serial_if`（位钟 10.3125G；`eth_pcs_lb_env` 每端实例化 10
  条，40G 用前 4 条），交叉连线按 lane 对接；
  vif 下发键名 `vif_serial_<port>_l<i>`。
- **字时钟必须扣除 AM 带宽开销**：
  `word_hz = 4×10.3125e9/66 × (am_spacing-1)/am_spacing × (1+100ppm)`
  —— AM 占线上带宽，不扣除会打破删除主导域导致断流。
- 扰动注入（`eth_pcs_mld_connect`）：`tb_ctrl_if.err_inject` 只翻转 A→B
  的 lane0，`los` 断 A→B 全部 lane（强制 0），`los_lane0` 只断 lane0。

## 4. 运行

```bash
cd sim
make loopback_40g      # 40G 环回冒烟
make stress_40g        # 1000 帧大流量
make multi_reset_40g   # 5 轮中途复位恢复
make disturb_40g       # 扰动恢复（lane0 整位翻转 + 全 lane 断线）
make svt_40g           # svt VIP 双向交叉（A: VIP->我方 500 帧，B: 我方->VIP 1000 帧）
make svt_40g_reset     # 交叉中途复位恢复（3 轮复位，VIP 持续在线）
make link_fault_40g    # RX 引脚 Local Fault 信令（见第 5 节）
# +FEC：每 PCS lane 叠加 Clause 74，同样 6 列
make loopback_40g_fec stress_40g_fec multi_reset_40g_fec disturb_40g_fec
make svt_40g_fec svt_40g_fec_reset
```

判据：各目标 grep 的汇总行，且日志 `UVM_ERROR : 0`、`UVM_FATAL : 0`；
各列内容与全模式覆盖见 `docs/verification_matrix.md`。测试等 link-up 用
`rx_link_up()`：多 lane 模式 = MLD 全 lane 对齐且非 hi_ber（`rx_locked()`
只表示对齐完成）。

## 5. 失锁、AM 误码与 Local Fault

- **逐 PCS lane 失锁即整体重对齐**：任一 PCS lane 由锁定转失锁（块同步
  失锁；+FEC 时为 cl74 码字失锁，锁定后连续 8 个不可纠码字判失锁），MLD
  立即整体重对齐 —— IEEE align_status 要求全部 lane 锁定。MAC 侧 RX 引脚
  随即转为 Local Fault，待该 lane 重锁、全部 lane 重新以 AM 去偏斜后恢复。
- **AM 误码容忍**：对齐且学得 AM 间隔后（见第 6 节），某 lane 在期望 AM
  的位置收到非 AM，按 AM 占位跳过（不重对齐、数据块不丢）；同一 lane 连续
  4 个坏 AM 才整体重对齐（IEEE Clause 82 AM 锁定状态机的 am_invld_cnt）。
  学得间隔之前（对齐后首个 AM 周期）某 lane 的 AM 误码会被当数据入队，
  学得间隔时检出该 lane 已越过 AM 位置、立即整体重对齐。单测
  `test_mld_am_err`。
- **Local Fault 格式**：链路未起（未对齐、hi_ber）时 RX 引脚持续驱 Local
  Fault，队列中残留拍作废。多 lane 按 Clause 82，只含一个 LF 序集：
  `rxc = 8'h01`、`rxd = 64'h00000000_0100009C`（lane0 /Q/ 0x9C、lane1~3
  为 00 00 01、lane4~7 为 4 个零数据字节，即 0x4B 块）；单 lane（Clause 49）
  为两个 LF 序集：`8'h11` / `64'h0100009C_0100009C`（lane0、lane4 各一个，
  0x55 块）。
- **块型集合按 Clause 82**：序集块 0x4B 的 lane4~7 为零数据（ctl 01），且
  只有 /Q/（0x9C）序集，/Fsig/ 编码为 ERROR 块、解码判非法；Clause 49 专有
  的 lane4 起始/序集块（0x33/0x2D/0x55/0x66）同样编码为 ERROR 块、解码判
  非法。所以 MAC 发来的序集拍须为 /Q/ + ctl 01 + lane4~7 零数据；`+LANE4`
  （lane4 起帧）只适用单 lane，多 lane 下 agent 报 fatal。
- **hi_ber**：环回与 VIP 交叉按 IEEE 取 781250 块窗 / 97 个坏同步头（40G
  窗口 1.25ms；cfg `ber_limit` / `ber_window_blocks`，默认是 10G 的 16 /
  19531）。`link_fault_40g` 为在仿真时间内置位并清除 hi_ber，改用 10G 值。
- **`link_fault_40g`**：建链前、全 lane 断线、仅 lane0 断线、hi_ber（lane0
  稀疏单 bit 误码，块锁不丢）期间 B 端 RX 引脚必须全为 Local Fault；撤扰
  后一个干净窗口清除 hi_ber、链路恢复；前后各 500 帧严格段。判据行
  `链路故障信令覆盖完成`。

## 6. svt VIP 交叉要点（40G XLSBI）

- **AM 间隔必须两侧一致，且受 VIP 能力约束**：VIP `xlsbi_40g_align_timer`
  默认 64，合理约束仅 {64,128,256} —— 标准 16384 超出 VIP 支持范围。
  交叉环境两侧统一 64（`set_40g_cfg` 显式配 VIP，phy `am_spacing=64`，
  top_svt 字钟扣减 63/64）。
- 不一致的后果（曾踩坑）：VIP RX 每周期报 invalid_align/bip，累计 ~21
  周期后 VIP 内部复位并扰乱其 TX，方向 A 出现固定时刻的 76 块乱码与
  len=0 脏帧；report catcher 降级只能压报告压不住 VIP 内部状态。
- BIP-8 按 IEEE 表 82-4 实现（TX 生成 + RX 校验），与 VIP checker 互通。
- mld_rx 对齐后 AM 间隔自检为学习式（首个完整间隔作基准），兼容对端对
  spacing 是否含 AM 的不同计数约定；AM 出现在偏离该间隔的位置即整体重
  对齐（期望位置上的 AM 误码按第 5 节容忍）。
- 去偏斜锚点同周期校验：对端不断流而本端复位重锁时，各 lane 重锁时刻
  可分散超过一个 AM 周期，锚点 tick 跨度超半周期窗则继续等下一轮 AM
  收敛 —— 否则会把相差整周期的块交织重组（持久乱码且周期自检无法发现）。
  svt_40g_reset 覆盖此场景。

## 7. 已知限制（TODO）

- AN(cl73) / LT(cl72) 只走单 lane 路径，`+SPEED=40g` 下不可叠加
  （`eth_loopback_test` 装配时报 fatal）。
- 多 lane RS-FEC 只支持 100GBASE-R 形态（`+SPEED=100gr`），40G 不能开
  `+RSFEC`（agent 配置校验拦截）。
- +FEC 时译出块的同步头由 cl74 码字重建，hi_ber 不会触发（FEC 错误指示
  未建模）。

（MLD 叠加 Clause 74 FEC 已支持，见 `integration_fec.md`；100G 的 20 条
PCS lane 见 `integration_100g_200g.md`。）

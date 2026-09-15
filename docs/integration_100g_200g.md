# 100G / 200G 模式 —— 环境集成与使用说明

适用：eth_pcs_agent 的 100GBASE-R（CAUI-10 / CAUI-4）与 200GBASE-R 多 lane
模式。可跑示例见 `examples/100g_200g_loopback/`。

## 1. 三种模式一览

| `+SPEED` | 规范 | PCS lane | 物理 lane × 线速 | PMA 复用 | FEC | svt VIP 模式 |
|---|---|---|---|---|---|---|
| `100g`  | Clause 82 | 20 | 10 × 10.3125G | 2:1 bit 交织 | 无 | `ETH_CAUI` |
| `100g4` | Clause 82 | 20 | 4 × 25.78125G | 5:1 bit 交织 | 无 | `ETH_CAUI_25X4` |
| `200g`  | Clause 119 | 8 | 8 × 26.5625G | 1:1 | RS(544,514) 内置 | `ETH_200G_SERIAL` |

100G 与 40G 同属 Clause 82（64b/66b + MLD 轮转分发 + 每 lane AM），只是
PCS lane 从 4 扩到 20、多了 PMA bit 复用；200G 是另一套结构（Clause 119），
不走 MLD。

## 2. 使用方式

```bash
cd sim
make loopback_100g stress_100g multi_reset_100g     # 100G CAUI-10 环回族
make loopback_100g4 stress_100g4                    # 100G CAUI-4 环回族
make loopback_200g stress_200g multi_reset_200g     # 200G 环回族
make svt_100g svt_100g4 svt_200g                    # 与 VIP 交叉
make svt_100g_reset svt_100g4_reset svt_200g_reset  # 交叉中途复位恢复
```

同一个 simv，`+SPEED` 切换；top 用 `eth_pcs_lb_env(a, b)` 即可（宏已含 10
条物理 lane 组：100G CAUI-10 用满 10 条，CAUI-4 用前 4 条，200G 用前 8 条）。

## 3. 100G：PMA bit 复用与 AM

- **复用**：cfg `num_lanes = 20`、`num_phys = 10`（或 4）。TX 物理 lane p 逐
  bit 轮转发送 PCS lane `p*m .. p*m+m-1`（m = 20/num_phys）；RX 逐 bit 轮转
  解复用到各 PCS 流、各自块同步，**哪条流是哪条 PCS lane 由 AM 自识别**，
  所以接收端对对端的复用映射/相位不敏感。
- **AM 图案**：20 组（IEEE 表 82-3），已用波形探针从 VIP `ETH_CAUI` 码流
  逐 lane 实测印证；AM 间隔每 lane 64 块（含 AM），与 VIP
  `csbi_100g_align_timer` 默认一致（与 40G 同款坑：两侧必须一致，约束
  {64,128,256}）。
- 字时钟 = 物理 lane 数 × 线速 / 66 × 63/64（扣 AM 开销）+100ppm。

## 4. 200G：Clause 119 结构（全部由 VIP 实抓码流逐层标定）

```
66b 块 ──4 块──► 256B/257B 转码（首个控制块类型压 4bit、原位替换）
      ──► x^58+x^39+1 自同步加扰（覆盖全部 257bit、跨块连续、跳过 AM/填充）
      ──► 每 16 码字一个 AM 周期：首对码字信息区 = 8×120bit AM + 68bit
          PRBS9 填充 + 36 组；其余每对 40 组（=160 块）
      ──► RS(544,514) 码字 A/B（信息符号逐个交替）
      ──► 10bit 符号 LSB 先发；lane l 第 k 符号属 A 当且仅当 (k+l) 为偶；
          A/B 内按"轮次优先、lane 次之"排序（idx = 4k + (l>>1)）
```

标定依据：RS 伴随式全零、**VIP 码字 30 个校验符号被我方编码器逐个复现**、
解扰后 idle 257bit 周期 100% 重复、填充 PRBS9 递推全吻合；与 VIP 交叉
500 个随机长度帧无损接收（证实转码细节）。

实现要点：
- 66b 级**不加扰**（加扰在 257b 层），与 RS-FEC cl91 同理；
- 200G 字时钟 = 3.125G 块/s × 316/320（每 AM 周期 320 组中 4 组让给
  AM+填充）+100ppm；
- TX 以码字对为粒度突发产出（每 lane 1360bit），**首对只装 144 块、后续
  每对 160 块**：启动须预灌 3 个完整码字对垫底（否则首对放完后生产下一对
  慢于 lane 排空，断流插 0 毁掉码字，已实测踩坑）；弹性删除阈值 3 对；
- RX：各 lane 逐 bit 精确匹配 120bit AM 锁定并识别 lane → 去偏斜（队列
  长度差超半周期的 lane 丢整周期）→ 每周期起点核对 AM、不符即整体重锁 →
  RS 纠错 → 解扰 → 反转码；对齐后首个 257b 组只喂解扰器不交付（热身）。
- VIP 侧 AM 周期 `ccbi_rs_fec_mode_align_timer = 16`（按 RS 码字计）。

## 5. 顺带发现

- **VIP 实现了链路故障信令**：我方未发有效 200G 码流时，VIP 持续发
  Remote Fault 有序集（0x4B，D3=0x02）——将来做 MAC 层 fault 语义验证
  可直接利用。
- 100G RS-FEC（Clause 91）已按 VIP 实抓码流重做，见
  `docs/integration_fec.md`（`+SPEED=100gr`）。注意它的加扰位置与 200G 不同：
  RS-FEC 转码的是 66b 层已加扰的块，200G 是先转码再在 257b 层加扰。

## 6. 已知限制（TODO）

- 200G 的 `_2_LANE` / `_4_LANE`（并行块口）、PAM4 未做。
- 200G AM 周期取 VIP 默认 16 码字；标准值（81920 块）未参数化。

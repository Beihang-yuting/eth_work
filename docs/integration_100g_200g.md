# 100G / 200G / 400G 模式 —— 环境集成与使用说明

适用：eth_pcs_agent 的 100GBASE-R（CAUI-10 / CAUI-4）、200GBASE-R 和
400GBASE-R CDBI 多 lane 模式。可跑示例见 `examples/100g_200g_loopback/`。

## 1. 四种模式一览

| `+SPEED` | 规范 | PCS lane | 物理 lane × 线速 | PMA 复用 | FEC | svt VIP 模式 |
|---|---|---|---|---|---|---|
| `100g`  | Clause 82 | 20 | 10 × 10.3125G | 2:1 bit 交织 | 无；`+FEC` 叠加 Clause 74（每 PCS lane） | `ETH_CAUI`（+FEC 时 `enable_fec = 1`） |
| `100g4` | Clause 82 | 20 | 4 × 25.78125G | 5:1 bit 交织 | 无 | `ETH_CAUI_25X4` |
| `200g`  | Clause 119 | 8 | 8 × 26.5625G | 1:1 | RS(544,514) 内置 | `ETH_200G_SERIAL` |
| `400g`  | Clause 119 CDBI | 16 | 16 × 26.5625G | 1:1 | KP4 RS(544,514) 内置 | `ETH_400G_SERIAL` |

100G 与 40G 同属 Clause 82（64b/66b + MLD 轮转分发 + 每 lane AM），只是
PCS lane 从 4 扩到 20、多了 PMA bit 复用；200G 和 400G 都采用 Clause 119，
但 400G 使用 16-lane CDBI 四码字交织布局，不能直接复用 200G 的 8-lane 排布。

## 2. 使用方式

```bash
cd sim
# 每模式 6 列：环回 / 1000 帧 / 多次复位 / 扰动 / VIP 交叉 / 交叉复位
make loopback_100g stress_100g multi_reset_100g disturb_100g                  # 100G CAUI-10
make svt_100g svt_100g_reset
make loopback_100g_fec stress_100g_fec multi_reset_100g_fec disturb_100g_fec  # CAUI-10 + cl74
make svt_100g_fec svt_100g_fec_reset
make loopback_100g4 stress_100g4 multi_reset_100g4 disturb_100g4              # 100G CAUI-4
make svt_100g4 svt_100g4_reset
make loopback_200g stress_200g multi_reset_200g disturb_200g                  # 200G
make svt_200g svt_200g_reset
# 400G CDBI（已纳入正式 SVT 目标）
make svt_400g svt_400g_reset
```

判据：各目标 grep 的汇总行，且日志 `UVM_ERROR : 0`、`UVM_FATAL : 0`；
各列内容与全模式覆盖见 `docs/verification_matrix.md`。100G RS-FEC
（`+SPEED=100gr`，Clause 91）的同类目标 `*_100gr` 见 `integration_fec.md`。

同一个 simv，`+SPEED` 切换；top 用 `eth_pcs_lb_env(a, b)` 即可（宏已含 10
条物理 lane 组：100G CAUI-10 用满 10 条，CAUI-4 用前 4 条，200G 用前 8 条；
400G 交叉由 `top_svt` 的 16 条 CDBI lane 专用接线承载）。
扰动注入与 40G 相同（`eth_pcs_mld_connect`）：整位翻转只打 A→B 物理
lane0，断线为 A→B 全部物理 lane。

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
- `+FEC`（CAUI-10）：20 条 PCS lane 各一套 Clause 74，路径同 40G + FEC，
  VIP 侧 `ETH_CAUI` + `enable_fec = 1`（`svt_100g_fec*`）；码流格式见
  `integration_fec.md`。CAUI-4 + Clause 74 不是标准组合，没有目标。

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
- 66b 级**不加扰**（加扰在 257b 层），这点与 RS-FEC（cl91/cl108）不同：
  后者转码的是 66b 层已加扰的块（见第 6 节）；
- 200G 字时钟 = 3.125G 块/s × 316/320（每 AM 周期 320 组中 4 组让给
  AM+填充）+100ppm；
- TX 以码字对为粒度突发产出（每 lane 1360bit），**首对只装 144 块、后续
  每对 160 块**：启动须预灌 3 个完整码字对垫底（否则首对放完后生产下一对
  慢于 lane 排空，断流插 0 毁掉码字，已实测踩坑）；弹性删除阈值 3 对；
- RX：各 lane 逐 bit 精确匹配 120bit AM 锁定并识别 lane → 去偏斜（队列
  比最短者长出半周期及以上的 lane 锚在了更早的 AM，丢整周期；该 lane 若
  偏斜又更大、队列不足一整周期，差额记为待丢弃，由后续到达的比特抵扣）→
  每周期起点核对各 lane 队首 120bit AM（RS 纠错前，每 lane 容忍至多 12
  个比特差；真实滑位约一半比特不符）：超差的单个周期按误码容忍（AM 在
  码字内，随后由 RS 纠正），连续 2 个周期超差判滑位、整体重锁
  → RS 纠错（不可纠码字对译出的块同步头标 2'b11，PCS 解码计错、帧判损伤）
  → 解扰 → 反转码；对齐后首个 257b 组只喂解扰器不交付（热身）。单测
  `test_cl119(1)` 定向覆盖首 AM 误码下的去偏斜与周期起点 AM 单 bit 误码。
- VIP 侧 AM 周期 `ccbi_rs_fec_mode_align_timer = 16`（按 RS 码字计）。

### 4.1 400G：CDBI 与 `ETH_400G_SERIAL`

400G 使用 16 条 26.5625G NRZ lane。每个对齐周期包含 4 个 136-symbol
group（每 lane 共 5440 bit），周期起始为 16 条 lane 各自的 120-bit AM，随后
为 136 bit 的 PRBS9 填充；每个 group 以 4 个交织的 KP4 RS(544,514) 码字承载，
一个 AM 周期共 16 个码字。发送
与接收端都按物理 lane 的 AM 识别逻辑 lane，再按 CDBI 的半周期 codeword
选择和 8-lane 行索引重组码字；AM、去偏斜和码字重组全部在 RS 纠错前完成。
VIP 侧配置固定为 `ETH_400G_SERIAL` 与
`cdbi_rs_fec_mode_align_timer = 16`，对应代码中的 `set_400g_cfg()`。

400G 的行为级空闲建链边沿很多，SVT 目标使用以下仅作用于该进程的开关：

```bash
export DESIGNWARE_HOME=/home/ubuntu/synopsys/designware_vip_R-2020.12
export ETH_SVT_DESIGN=/home/ubuntu/ryan/eth_svt_design
make svt_400g svt_400g_reset
```

`+C400_CLK_DIV=100` 按比例降低仿真时钟，保持 bit/word 比例不变；
`+C400_DEFER_FEC` 只在空闲建链期间延迟 RS 解码检查，首段流量前以及每次
复位后由测试重新打开完整 RS(544,514) 检查，不会放宽帧数据判据。

截至当前 53/VCS 回归，普通交叉已完成 VIP→我方 500 帧、我方→VIP 1000 帧，
交叉复位已完成 3 轮（每段 100/200 帧）；两者均满足双方计数、
`invalid_block=0`、`fec_uncorr=0`、`tx_underrun=0` 以及
`UVM_ERROR : 0`、`UVM_FATAL : 0`。复位窗口内 VIP checker 为恢复链路而产生的
预期 warning 由测试 demoter 降级，窗口外仍按零错误判定。两个目标当前均在
正式 `SVT_TARGETS`，会随默认 `make all` 执行。2026-09-19 的 53/VCS 完整回归
已实际启动两个目标并通过；完整回归日志中的其他目标状态与一次 40G FEC
初始化停滞重试记录见 `verification_matrix.md` §5。400G 两个目标的本轮
`PCS_STATS` 分别为 `frames=500` 和 `frames=400`，且 `invalid_block`、
`fec_uncorr`、`tx_underrun` 均为 0。

## 5. 失锁、Local Fault 与 hi_ber

- **100G（MLD）同 40G**（见 `integration_40g.md` 第 5 节）：任一 PCS lane
  失锁即整体重对齐，MAC 侧 RX 引脚随即转为 Local Fault；对齐且学得 AM
  间隔后单个 AM 误码按占位跳过，同一 lane 连续 4 个坏 AM 才重对齐（IEEE
  Clause 82 AM 锁定状态机的 am_invld_cnt）。
- **200G**：lane 靠 AM 匹配锁定，没有逐 lane 块同步；周期起点 AM 连续 2 次
  不符即整体重锁（见第 4 节），未对齐期间 RX 引脚为 Local Fault。
- **Local Fault 与序集格式**：这些模式都按 Clause 82 —— LF 为
  `rxc = 8'h01`、`rxd = 64'h00000000_0100009C`（lane4~7 为 4 个零数据字节）；
  序集拍（0x4B 块）须为 ctl 01 + lane4~7 零数据，且只有 /Q/（0x9C），
  /Fsig/ 与 Clause 49 专有的 lane4 起始/序集块都编码为 ERROR 块、解码判
  非法，`+LANE4` 不可用。
- **hi_ber**：环回与 VIP 交叉取 781250 块窗 / 97 个坏同步头（IEEE 100G
  窗口 500us；cfg 默认是 10G 的 19531 / 16）。100G + FEC、200G 和 400G
  的块都由 FEC 译码重建同步头：+FEC 下 hi_ber 不会触发；Clause 119 模式
  只有不可纠码字对（同步头标 2'b11）计入坏头。

## 6. 顺带发现

- **VIP 实现了链路故障信令**：我方未发有效 200G 码流时，VIP 持续发
  Remote Fault 有序集（0x4B，D3=0x02）——将来做 MAC 层 fault 语义验证
  可直接利用。
- 100G RS-FEC（Clause 91）已按 VIP 实抓码流重做，见
  `docs/integration_fec.md`（`+SPEED=100gr`）。注意它的加扰位置与 200G 不同：
  RS-FEC 转码的是 66b 层已加扰的块，200G 是先转码再在 257b 层加扰。

## 7. 已知限制（TODO）

- 200G 的 `_2_LANE` / `_4_LANE`（并行块口）、PAM4 未做。
- 200G AM 周期取 VIP 默认 16 码字；标准值（81920 块）未参数化。

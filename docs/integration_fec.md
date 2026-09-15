# FEC 叠加（Clause 74 / Clause 108 / Clause 91）—— 环境集成与使用说明

适用：eth_pcs_agent 的 FEC 叠加模式——单 lane 与多 lane（MLD）上的
BASE-R FEC（Clause 74），25G RS-FEC（Clause 108），100G RS-FEC（Clause 91，
20 条 PCS lane 映射到 4 条 FEC lane）。可跑示例见 `examples/fec_overlay/`。

## 1. 模式一览

| 开关 | 规范 | 可叠加的速率 | 码 | lane 结构 | svt VIP 配置 |
|---|---|---|---|---|---|
| `+FEC` | Clause 74 | 10g / 25g（单 lane）、40g / 100g（每 PCS lane 一套） | (2112,2080) fire code，纠 ≤11bit 突发 | 不变 | `enable_fec = 1` |
| `+RSFEC` | Clause 108（25g） | 10g / 25g 单 lane | RS(528,514)，纠 7 个 10bit 符号 | 1 条 FEC lane | `ETH_25G_SERIAL` + `enable_xxvsbi_lsbi_rs_fec = 1` + `enable_xxvsbi_lsbi_consortium_mode = 0` |
| `+SPEED=100gr` | Clause 91 | 100G | RS(528,514) | 20 PCS lane → 4 FEC lane × 25.78125G | `ETH_CSBI_4_LANE` + `enable_rs_fec = 1` + `rs_fec_width = ETH_RS_FEC_1B_WIDTH` |

`+FEC` / `+RSFEC` 与 `+SPEED` 正交，环回和 VIP 交叉测试都用同一组开关
（交叉测试里 VIP 侧配置由 `cross_svt_cfg::set_fec_overlay()` 同步打开）。
200G（Clause 119）自带 RS(544,514)，不能再叠加这两个开关。

注意：VIP 的"100G RS-FEC"并不只有并行口。`ETH_CSBI_4_LANE` 配上
`enable_rs_fec` 和 1bit 宽度后，VIP 自己把它当作 4 条串行 lane
（`serial_skew_on_lane` 约束、`number_of_lanes = 4`），线速 25.78125G，
位钟是 `serial_caui_25g_clk`。

## 2. 使用方式

```bash
cd sim
# Clause 74
make fec stress_fec                          # 10G（原有）
make stress_25g_fec                          # 25G
make loopback_40g_fec stress_40g_fec multi_reset_40g_fec   # 40G 每 lane
make stress_100g_fec                         # 100G CAUI-10 每 lane
# 单 lane RS-FEC
make loopback_rsfec stress_rsfec             # 10G 线速（原有）
make loopback_25g_rsfec stress_25g_rsfec multi_reset_25g_rsfec
# 100G RS-FEC（Clause 91，4 FEC lane）
make loopback_100gr stress_100gr multi_reset_100gr
# 与 VIP 交叉（同一 simv，svt_simv 只编一次）
make svt_fec svt_25g_fec svt_40g_fec svt_25g_rsfec svt_100gr
make svt_fec_reset svt_40g_fec_reset svt_25g_rsfec_reset svt_100gr_reset
```

top 不用改：`eth_pcs_lb_env(a, b)` 已经包含单 lane 口和 10 条 lane 组；
100gr 用前 4 条。字钟由 `eth_pcs_clk_gen` 按开关自动算好（见第 5 节）。

## 3. Clause 74 码流（VIP 实抓标定）

```
32 个 66b 块 ─► 66b→65b：T = sync[0] ^ payload[8]（sync[0] 为第二个上线的同步头位）
            ─► 2080bit 信息 + 32bit 校验（g(x)=x^32+x^23+x^21+x^11+x^2+1，MSB 先）
            ─► 异或 PN-2112：x^58+x^39+1，每码字重启，种子 58'h2AA_AAAA_AAAA_AAAA
```

- 多 lane（40G/100G）：每条 PCS lane 各一套 FEC，AM 也当普通 66b 块编进
  本 lane 的码字；RX 用 FEC 码字对齐代替块同步，译出的块交 MLD 去偏斜。
- 标定方法：在码字边界上 c⊕p 的伴随式等于 syn(p)，PN 每码字重启时它跨码字
  恒定，所以不用先知道 PN 就能定出边界；再拿这个恒定值去匹配候选 PN
  种子。T 位规则来自"所有控制块的 T ^ payload[8] 恒为 0"。
- 此前的实现（全 1 种子、T = sync[1]）只能自环，和 VIP 不互通，已修正。
  单测 `test_fec` 里有 VIP 黄金码字：编码器逐位复现 2112/2112，译码器
  32/32 块还原。

## 4. RS-FEC 码流（Clause 91 / 108，VIP 实抓标定）

```
66b 块（照常经 PCS 加扰）
  ─► 4 块 → 256B/257B 转码：t[0]=全数据标志；t[4:1]=各块标志（1=数据）；
     首个控制块只保留"加扰后"的低 4 位（放在 t[8:5]），其余照搬；
     然后 t[4:0] ^= t[12:8]
  ─► 20 组 = 514 个 10bit 符号（LSB 先）─► RS(528,514) ─► 无码字级 PN
  ─► 25G：1 条 lane 顺序上线；100G：码字第 i 个符号 → FEC lane i%4
  ─► 每 16 码字一个 AM 周期，周期首码字的信息区以 AM 开头
```

| 项 | 25G（Clause 108） | 100G（Clause 91） |
|---|---|---|
| AM 区 | 1 个 257b 常量组：100G lane0 与 40G lane1~3 的 AM，BIP3/BIP7 固定 0x33/0xCC，末位填 0 | 20 个 PCS lane AM 按 FEC lane 重排：lane l 依次承载 PCS lane l、4+l、8+l、12+l、16+l；lane 1~3 / 17~19 的固定字节换成 lane 0 / 16 的（BIP 保留）；按 10bit 符号交织成 1280bit + 5 位填充（00101 / 11010 交替） |
| 每周期数据块 | 319 × 4 = 1276 | 1260（与 MLD 周期一致） |
| BIP | 固定值 | 按 PCS lane 计算，算法同 MLD（`mld_tx_c`），已用 VIP 码流核对 20/20 |
| RX 锁定 | 搜 128bit 常量 AM | 各 lane 搜首个 AM（lane 0 固定字节）+ 第二个 AM 识别 FEC lane，去偏斜后对齐 |

要点：
- **加扰位置和 200G 不同**：Clause 119 是先转码再在 257b 层加扰；RS-FEC
  是 PCS 先在 66b 层加扰，FEC 子层直接转码加扰后的块。所以被丢掉的是
  "加扰后"的类型高 4 位，接收端要带 58bit 加扰历史：先解扰低 4 位 → 查
  块类型 → 再按同一加扰关系生成高 4 位（`rs91_xdec_c`）。
- 头部异或 `t[4:0] ^= t[12:8]` 让头部随数据跳变；异或源不被修改，接收端
  总能先去异或再解析。
- 不可纠码字：译出的块同步头标成 2'b11，PCS 解码计错，帧被判损伤
  （等效 802.3 的错误标记）。
- 单测：`test_rs_stream(1/4)`（乱接 + 偏斜 + 注错全对）、
  `test_rs25_golden`（VIP 25G 实抓码字 5280/5280 bit 复现）。

## 5. 时钟与弹性

- 单 lane RS-FEC：每 AM 周期 320 个 257b 组里有 1 组让给 AM，字钟乘
  319/320（`eth_pcs_clk_gen` 与 top_svt 读 `+RSFEC` 自动处理）。
- 100gr：转码省出的带宽正好抵掉校验位，AM 开销与 MLD 一致，字钟公式同
  100g4（4 × 25.78125G / 66 × 63/64）。
- Clause 74：66b→65b 压缩换出校验位，线速不变，字钟不变。
- 删除阈值按码字粒度：cl74 每 lane 2 码字；单 lane RS 2 码字；100gr 每
  lane 4 码字（5280bit）。启动预灌整码字垫，避免码字间断流插 0。

## 6. 与 DUT 对接的注意事项

- **AM 周期**：VIP 默认 16 码字（`xxvsbi_rs_fec_mode_align_timer`；100G
  等效 `csbi_100g_align_timer = 64`），不是标准的 1024 / 4096 码字。DUT 用
  标准值时，我方和 VIP 都要改成一致——和 40G `align_timer` 是同一类坑。
  目前我方 AM 周期固定为 16，未参数化。
- **25G 联盟模式**：VIP 默认 `enable_xxvsbi_lsbi_consortium_mode = 1`。
  我方按 IEEE Clause 108 实现，交叉时显式关掉；对接 IEEE DUT 同理。
- VIP 在 RS-FEC 模式下约束 lane 偏斜为 0；我方 RX 容忍任意 lane 乱接，
  以及半个 AM 周期（每 lane 10560bit ≈ 410ns）以内的偏斜，远大于 802.3
  允许值（单测覆盖乱接 + 0~700bit 偏斜）。更大的偏斜与"锁在相邻一次 AM
  上"本质上无法区分。
- **VIP 时钟必须同源**：100G RS-FEC 模式下 VIP 的并行域时钟（caui_64b、
  40T、66T）必须与 `serial_caui_25g_clk` 严格同频。VIP 示例 top 的固定
  周期值彼此差约 3ppm，约 30us 后 VIP 监视器缓冲下溢（自身 TX 码字读出 X，
  两向报 RS 校验和错；线上码字经伴随式核对全部正确）。
  `eth_pcs_svt_clock_gen` 已改为由 25G 串行钟同步分频生成这几路。

## 7. 已知限制（TODO）

- 标准 AM 周期（1024 / 4096 码字）未参数化。
- 50G / 400G RS-FEC、KP4 以外的 200G 变体未做。
- Clause 74 的 `enable_fec_error`（FEC 向 PCS 报不可纠）未对接；我方不可纠
  码字照常透传，由 PCS 解码与 CRC 暴露。

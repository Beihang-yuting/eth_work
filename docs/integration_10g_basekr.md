# 10G BASE-KR 模式 —— 环境集成与使用说明

适用：将 eth_pcs_agent（10GBASE-R/KR，Clause 49 PCS + 可选 Clause 74 FEC）
集成进任意 UVM 验证环境。可跑示例见 `examples/10g_basekr_loopback/`；
各模式验证覆盖（环回/1000 帧/多次复位/扰动/VIP 交叉/交叉复位）与判据见
`verification_matrix.md`。

## 1. 交付物

| 文件 | 内容 |
|------|------|
| `src/agent/eth_pcs_if.sv` | `xgmii_if`（上边界，接 MAC）+ `serial_if`（下边界，1bit 串行） |
| `src/pkg/eth_pcs_pkg.sv` | 全部类：`eth_pcs_agent/cfg/driver/monitor/phy_bfm`、PCS/FEC 内核 |
| `third_party/aip_core/` | 高精度时钟生成（aip_clk，1fs 精度 vendored 版） |
| `third_party/net_packet/` | 报文生成（发包器复用） |

## 2. 编译集成

filelist 关键片段（完整见 `sim/filelist.f`）：

```
+incdir+<eth_work>/src
+incdir+<eth_work>/third_party/aip_core
+incdir+<eth_work>/third_party/net_packet/src        // 及其各子目录
<eth_work>/src/agent/eth_pcs_if.sv
<eth_work>/src/pkg/eth_pcs_pkg.sv
```

VCS 选项：`-full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ps/1ps`（或更细精度）。

## 3. top 层集成

```systemverilog
`include "aip_log.sv"          // aip 时钟三件套，须在本文件 timescale 前
`include "aip_time.sv"
`include "aip_clk.sv"
`timescale 1ps/1ps

module my_top;
  import uvm_pkg::*;
  import eth_pcs_pkg::*;

  // 时钟：字时钟 156.25MHz、位时钟 10.3125GHz，aip_clk 独立产生。
  // 约定：字时钟频率 >= 位时钟/66（弹性删除主导域，见第 6 节）
  aip_clk_if word_clk_if();  aip_clk word_clk_gen;
  aip_clk_if bit_clk_if();   aip_clk bit_clk_gen;
  wire word_clk = word_clk_if.clk, bit_clk = bit_clk_if.clk;
  logic rst_n = 0;

  initial begin
    word_clk_gen = new("word_clk", word_clk_if);
    word_clk_gen.set_freq(156.25e6);       // 可 set_ppm/set_jitter
    bit_clk_gen  = new("bit_clk", bit_clk_if);
    bit_clk_gen.set_freq(10.3125e9);
    word_clk_gen.start();  bit_clk_gen.start();
  end

  initial begin repeat (10) @(posedge word_clk); rst_n = 1; end

  // 接口：XGMII 接真实 MAC（或由 agent driver 充当 MAC），串行接对端
  xgmii_if  xgmii_p  (word_clk, rst_n);
  serial_if serial_p (bit_clk,  rst_n);

  // 串行连线（对接对端 PHY/VIP 的 1bit 串行；接 VIP 时对 tx_lane[0]）
  // assign peer_rx = serial_p.tx_bit;  assign serial_p.rx_bit = peer_tx;

  initial begin
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top", "vif_xgmii_p", xgmii_p);
    uvm_config_db#(virtual serial_if)::set(null, "uvm_test_top", "vif_serial_p", serial_p);
    run_test();
  end
endmodule
```

### 3.1 宏捷径（推荐）

`src/agent/eth_pcs_macros.svh` 封装了上述全部样板。

**宏 <-> 速率对照**（速率由 `+SPEED` 运行时选择，不换宏不换 top）：

| 宏 | 适用速率 | 说明 |
|---|---|---|
| `` `eth_pcs_lb_env(a, b) `` | 全速率 | 一键环回环境（时钟/复位/接口/接线/vif 全包，见 test/uvm/top.sv） |
| `` `eth_pcs_clk_gen `` | 全速率 | +SPEED 频率表（10g/25g/5g/40g/100g/100g4/100gr/200g/1g/2.5g）；40g/100g 系另读 +AM_SPACING 扣 AM 开销（默认 40g 512、100g 系 64；40g/100g/100g4 须与 cfg.am_spacing 一致，100gr 的 AM 周期固定 64、不读 cfg.am_spacing，+AM_SPACING 须保持 64）；+RSFEC 单 lane 扣 AM 开销 |
| `` `eth_pcs_ctrl_reset `` | 全速率 | 复位 + TB 控制接口 tb_ctrl_if（vif_ctrl：reset_req 复位握手；err_inject 整位翻转、los 全 lane 断线、los_lane0 仅 lane0 断线，由 lb_env 接到 A→B 串行线） |
| `` `eth_pcs_port/vifs/connect `` | 10g/25g/5g | 单 lane 接口对/下发/环回接线 |
| `` `eth_pcs_mld_lanes/connect/vifs `` | 40g/100g/100g4/100gr/200g | 多 lane 组声明/环回接线（可选 err/los/los0 注入）/下发 |
| `` `eth_pcs_connect_svt `` | 10g/25g/5g | 接 svt VIP 单 lane |
| `` `eth_pcs_mld_rx_wire `` | 40g/100g/100g4/100gr/200g | 接 svt VIP 多 lane 接收向 |
| `` `eth_pcs_svt_clock_gen/wire `` | VIP 全模式 | VIP 全套接口时钟（覆盖 txrx_if 全部时钟端口） |

另有 `+XGMII_DIRECT` 直驱开关（纯 MAC 功能验证提速 ~4x，跳过 PCS/串行，
发包序列零适配），见 layering_and_dut_modes.md §2.4。

### 3.2 建链与 FEC 开关一览

| 插件参数 | 作用 | 自测目标 |
|---|---|---|
| `+AN` | Clause 73 自协商（DME 页交换） | `loopback_an` `stress_an` `multi_reset_an` `disturb_an` `disturb_an_relink`（VIP 交叉：`svt_an` `svt_an_reset`，svt 侧以 `+SPEED=an73` 选 VIP AN 模式） |
| `+LT` | Clause 72 链路训练握手（自定简化训练帧，仅自环验证，见 §8） | `loopback_lt` `stress_lt` `multi_reset_lt` `disturb_lt` |
| `+AN +LT` | KR 完整建链 AN→LT→数据 | `loopback_kr` `stress_kr` `multi_reset_kr` `disturb_kr` |
| `+FEC`（或 cl74 变体测试类） | Clause 74 BASE-R FEC | `fec` `stress_fec` `multi_reset_fec` `disturb_fec`（VIP 交叉：`svt_fec` `svt_fec_reset`） |
| `+RSFEC` | 单 lane RS-FEC RS(528,514)（码流格式同 Clause 108；配 `+SPEED=25g` 即 25GBASE-R + Clause 108） | `loopback_rsfec` `stress_rsfec` `multi_reset_rsfec` `disturb_rsfec` |
| `+LANE4` | A 端 `cfg.lane4_start=1`：奇数帧从 lane4 起帧（0x33 块） | `stress_lane4` `stress_lane4_fec` `stress_lane4_rsfec` `stress_lane4_5g`（VIP 交叉：`svt_lane4`） |
| `+XGMII_DIRECT` | 跳过 PCS/串行直驱 XGMII | `loopback_direct` `stress_direct` `multi_reset_direct` |
| `+DISTURB_US=<n>` | 改扰动窗时长（前半整位翻转、后半断线） | `disturb_an_relink`（60us：断线 30us 超过 AN 链路失效门限） |

无 FEC 的 BASE-R 另有链路故障信令目标 `link_fault`（见 §6.2）。

要点：
- 两种 FEC 互斥（不同的码，不叠加），agent build 阶段校验；
- `lane4_start` 仅 Clause 49 单 lane 合法，多 lane / BASE-X 置位时 agent
  build 阶段报 fatal；
- RS-FEC 模式**照常做 66b 级加扰** —— PCS 先在 66b 层加扰，FEC 子层直接
  对加扰后的块做 256B/257B 转码（首个控制块只保留加扰后的类型低 4 位，
  接收端带 58bit 加扰历史复原，见 `rs91_xdec_c`），无码字级 PN，跳变
  密度由 66b 层加扰保证（VIP 实抓码流标定）。66b 级不加扰的只有 200G
  （Clause 119，加扰在 257b 层）；
- RS-FEC 与 MLD 叠加即 100GBASE-R + Clause 91（`+SPEED=100gr`，20 PCS
  lane → 4 FEC lane）；与 VIP 交叉见 `svt_25g_rsfec`（Clause 108）、
  `svt_100gr`（Clause 91），10G 线速的 `+RSFEC` 仅自环。详见
  `integration_fec.md`。

**全速率环回 top 只需一个宏**：

```systemverilog
module top;
  import uvm_pkg::*;  import eth_tb_pkg::*;
  `eth_pcs_lb_env(a, b)     // +SPEED 运行时选速率（10g/25g/5g/40g/100g/100g4/100gr/200g/1g/2.5g）
  initial run_test();
endmodule
```

分立宏手动集成（对接 VIP 等自定义拓扑）：

```systemverilog
`include "aip_log.sv"
`include "aip_time.sv"
`include "aip_clk.sv"
`timescale 1ps/1ps
`include "agent/eth_pcs_macros.svh"

module my_top;
  import uvm_pkg::*;  import eth_pcs_pkg::*;

  `eth_pcs_clk_gen(sys)                       // sys_word_clk/sys_bit_clk，
                                              // 本单 lane 拓扑用 +SPEED=10g|25g|5g
                                              //（宏支持的全部速率见上表）
  `eth_pcs_reset_gen(rst_n, sys_word_clk)     // 上电复位
  `eth_pcs_port(p, sys_word_clk, sys_bit_clk, rst_n)  // p_xgmii + p_serial

  `eth_pcs_connect_svt(p, mac_ethernet_if)    // 对接 svt VIP（serial 系）
  // 或双 agent 环回：`eth_pcs_port(q, ...) + `eth_pcs_connect(p, q)

  `eth_pcs_vifs(p)                            // config_db 下发
                                              // （键 vif_xgmii_p/vif_serial_p）
  initial run_test();
endmodule
```

参考实现：`test/svt/top_svt.sv`（port/vifs、mld_lanes/mld_rx_wire/mld_vifs、
svt_clock_gen/wire；因需按模式 mux `rx_lane`，单 lane 接线在 top 手写，
未用 connect_svt）、`test/uvm/top.sv`（lb_env，内含 clk_gen）。

## 4. UVM 侧集成

```systemverilog
eth_pcs_cfg cfg = eth_pcs_cfg::type_id::create("cfg");
cfg.is_active  = 1;      // 1: 例化 sequencer/driver 充当 MAC 发流
                         // 0: 被动（接真实 MAC RTL 时用，XGMII 由 MAC 驱动）
cfg.fec_enable = 0;      // 1: Clause 74 BASE-R FEC（已与 svt VIP 互通，见 integration_fec.md）
cfg.idle_words_per_gap = 2;   // 帧间空闲拍数（2 拍=16B >= 最小 IPG 12B）
cfg.lane4_start = 0;     // 1: driver 奇数帧从 lane4 起帧（S 落 lane4，0x33 块），
                         //    模拟 32bit XGMII 内核 MAC；仅 Clause 49 单 lane
cfg.ber_limit         = 16;     // hi_ber 门限：一个窗口内非法同步头达此数即 hi_ber
cfg.ber_window_blocks = 19531;  // hi_ber 窗口块数（默认 10GBASE-R 125us；
                                // 25G 及以上置 97 / 781250，见 §6.2）
cfg.an_link_fail_inhibit = 20us;  // 开 AN 时：数据模式 RX 链路持续不可用（失锁/hi_ber）超过此时长
                                  // 即回 AN 重新协商（IEEE 500ms 按仿真缩放）
cfg.vif_xgmii  = vx;  cfg.vif_serial = vs;
uvm_config_db#(eth_pcs_cfg)::set(this, "agent", "cfg", cfg);

agent = eth_pcs_agent::type_id::create("agent", this);
// 记分板接口：agent.drv.tx_ap（发送记录）/ agent.mon.rx_ap（接收观测）
// 事务类型 eth_frame_txn：data[$]（DA 起、不含 FCS）+ crc_ok/preamble_ok
```

发流：对 `agent.sqr` 起任意 `uvm_sequence#(eth_frame_txn)`；参考
`eth_loopback_seq`（net_packet 随机报文 + SA 单播修正 + 60B 补齐）。
60B 补齐在该序列里做，driver 只加前导/SFD/FCS、不补齐也不查帧长 ——
自写序列须自行保证帧长 ≥ 60B，否则线上是 runt 帧。

## 5. link-up 流程（必须遵守）

发流前必须等链路可用，否则链路未起期间的帧必丢：

```systemverilog
while (!agent.bfm.rx_link_up()) #100ns;  // 锁定/对齐完成且非 hi_ber（开 AN/LT 时含建链完成）
#1us;                                    // 解扰器自同步 + 流水线冲净裕量
```

`rx_locked()` 只表示块同步/FEC 码字/多 lane 对齐完成（开 AN/LT 时另含
建链完成）；`rx_link_up()` =
`rx_locked()` 且非 hi_ber，是 RX 停发 Local Fault、开始交付数据的条件
（见 §6.2）。中途复位后同样先等 `rx_link_up()` 再发流（参考
`eth_reset_recovery_test`）。

## 6. 时钟与弹性说明

- 字/位时钟允许独立有 ppm 偏差；TX 侧速率差由 BFM 弹性 idle 插入/删除
  吸收（统计见 `idle_ins/idle_del`）。
- **约定字时钟 ≥ 位时钟/66**（删除主导域）：删除只发生在帧间 idle，
  永不伤帧；启动时预灌弹性垫防队列见底：无 FEC 预灌 8 个 idle 块，FEC
  模式经编码器按整码字预灌（cl74 与单 lane RS-FEC 均为 2 个码字）。
- FEC 模式无法按 bit 插补，队列空计入 `tx_underrun`（应为 0，大流量测试
  在 check 阶段断言 A 端为 0）。

### 6.1 RX 引脚弹性（形态 A 驱真实 MAC）

- RX 恢复出的拍按线速突发产出（cl74 每码字 32 块、RS-FEC 每码字 80 块），
  按字时钟驱出 XGMII RX 引脚；突发与两域 ppm 差由 RX 引脚队列吸收。
- 插/删只在帧间：帧间队列低于低水位时补 idle 拍（`rxpin_ins`），高于
  高水位时删一拍全 idle（`rxpin_del`）。水位按实测最大突发自适应：
  低 = 最大突发 + 4，高 = 2×低 + 16。
- 帧内见底（填充拍插进帧中间，真实 MAC 会判帧损）计入
  `rxpin_midframe_underrun`。环回/交叉的 monitor 读 mailbox、看不到
  引脚，故测试在 check 阶段断言其为 0（环回查两端，VIP 交叉查我方）；
  复位/扰动/link_fault 类测试
  本就会斩断在途帧，不做此断言。
- 直驱模式（`+XGMII_DIRECT`）不插不删。

### 6.2 链路故障信令（Local Fault / hi_ber）

- RX 链路未起（未锁定/未对齐、hi_ber、开 AN/LT 时的建链阶段）时，RX
  引脚持续输出 Local Fault，队列中残留拍作废；链路起来后恢复交付。LF
  拍（`xgmii_local_fault()`）：单 lane（Clause 49 LBLOCK_R）
  `rxc=8'h11`、`rxd=64'h0100009C_0100009C`，lane0 与 lane4 各一个 LF
  序集（0x55 块）；多 lane（Clause 82）`rxc=8'h01`、
  `rxd=64'h00000000_0100009C`，一个 LF 序集 + 4 个零数据字节（0x4B 块）。
- hi_ber 期间、以及 cl74 锁定判据期间的干净码字，其中的块照常解扰但不
  交付（mailbox 与引脚都不送），链路起来后首块即可正确解出。
- BER 监视：按块统计非法同步头，`ber_window_blocks` 窗口内达到
  `ber_limit` 即 hi_ber；此后首个坏头数 < `ber_limit` 的完整窗口结束时
  清除；失锁时复位。默认 16 / 19531 为 10GBASE-R 值（125us）；25G 及以上
  应置 97 / 781250（环回与交叉 tb 按 `+SPEED` 已置）。
- cl74 模式同步头由 FEC 解码重建，hi_ber 不会触发。
- 覆盖：`make link_fault`（仅无 FEC 的 BASE-R）—— 建链前、断线期间、
  hi_ber 期间（稀疏单 bit 误码触发，块锁不丢）B 端 RX 引脚全为 LF，撤扰后
  一个干净窗口清除 hi_ber；前后各 500 帧严格段。`make link_fault_40g`
  同测多 lane（Clause 82 LF），另测仅 lane0 断线。该测试把 BER 窗口
  统一取 10G 值，只验证机制。

## 7. 检查点（monitor `PCS_STATS`）

| 计数 | 含义 | 正常值 |
|------|------|--------|
| frames / crc_err / preamble_err | 帧级完整性 | err 恒 0 |
| invalid_block | 非法 66b 块（坏头/未知块型） | 启动瞬态 ≤1 |
| slip | 对齐滑动次数 | 仅启动搜索期增长 |
| fec_corr / fec_uncorr | FEC 纠错/不可纠 | 注错测试外为 0 |
| idle_ins / idle_del | TX 弹性活动 | 有 ppm 偏差时非 0，正常 |
| tx_underrun | FEC 模式 TX 断流 | 0（大流量测试断言 A 端） |
| rxpin_ins / rxpin_del | RX 引脚帧间补/删 idle 拍（§6.1） | 非 0 属正常 |
| rxpin_midframe | RX 引脚帧内见底（§6.1） | 0（复位/扰动/link_fault 以外的测试断言） |
| hi_ber | 进入 hi_ber 的次数（§6.2） | 注错测试外为 0 |

上表"正常值"指无注错的冒烟/大流量场景。monitor 只打印统计、不据此判
失败；复位/扰动测试里被打断或被扰动毁掉的帧可能让 err 类与 invalid_block
计数非零，属预期。通过判据 = `sim/Makefile` 各 UVM 目标 grep 的汇总行 + 日志
`UVM_ERROR : 0` 且 `UVM_FATAL : 0`（`CHECK_CLEAN`）；tx_underrun、
rxpin_midframe 与分段测试的逐段全净由测试 check/run 阶段以 UVM_ERROR
上报，故也由 `CHECK_CLEAN` 把关。各列判据见 `verification_matrix.md` §1。

## 8. 已知限制

- FEC（cl74）PN-2112 种子与 T 位约定已按 VIP 实抓码流标定，与 svt VIP
  互通（`svt_fec` / `svt_fec_reset`）；不可纠码字照常透传，由 PCS 解码
  与 CRC 暴露；锁定后连续 8 个不可纠码字判失锁、回搜索态（断线后能重锁）。
  FEC 错误指示未建模，cl74 下 hi_ber 不触发（§6.2）。
- 块型：单 lane 编解码按 Clause 49（IEEE 图 49-7）—— S 在 lane0（0x78）
  或 lane4（0x33、0x66），序集 0x4B/0x55/0x2D，O 码 0 = /Q/（0x9C）、
  F = /Fsig/（0x5C），保留 O 码解码判非法（单测 `test_codec_ext` 校黄金
  值）。多 lane 按 Clause 82：无 lane4 起始/序集，序集只有 /Q/（0x4B，
  lane4~7 为零数据，/Fsig/ 编码为 ERROR 块、收到判非法）；Clause 49 专有
  块型的 XGMII 拍同样编码为 ERROR 块、收到判非法。全控制块（0x1E）只
  支持全 /I/：混有 /E/ 等字符的拍整拍编为 ERROR 块，收到非全 /I/ 的
  0x1E 块判非法。
- 25G 单 lane 目前沿用 Clause 49 块型集合与 LF 拍格式，IEEE 25GBASE-R
  对 lane4 起始等块型的格式未核对；`lane4_start` 按 10G/5G 使用。
- AN（cl73）/LT（cl72）默认关闭（复位后直接进数据模式），`+AN`/`+LT`
  开启。AN 仅 10G 单 lane（DME 按 10.3125G 位钟计时；多 lane 由 test
  拦截），无 Next Page、无 break_link 静默期，基页 FEC 能力位恒 0（不
  协商 FEC）。LT 仅单 lane，目标均为 10G。
- LT 只能自环对训（svt VIP 不支持 cl72，无第三方参照）。训练帧为 4096bit
  自定结构（标记 32bit + 系数更新/状态报告各 16bit 原始位、未做 DME +
  PRBS11 4032bit），不是 802.3 72.6.10 的 548 octet 帧格式，对接真实
  DUT 前须核对。

## 9. 可跑示例与回归入口

见 `examples/10g_basekr_loopback/README.md` 与 `sim/Makefile`；全部模式的
目标矩阵见 `verification_matrix.md`，全量回归 `make -k all`。10G 相关：

- 10G BASE-R：`loopback` `stress` `multi_reset` `reset_recovery` `disturb`
  `svt` `svt_reset`，另 `link_fault` `stress_lane4` `svt_lane4`；
- 10G + cl74：`fec` `stress_fec` `multi_reset_fec` `disturb_fec` `svt_fec`
  `svt_fec_reset` `stress_lane4_fec`；
- AN/LT/KR、单 lane RS-FEC、直驱：见 §3.2；
- `unit`：编解码（含块型黄金值）、扰码、块同步、BER 监视、cl74、AN（含
  nonce 碰撞）、LT 等单元测试。

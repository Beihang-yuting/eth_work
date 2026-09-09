# 10G BASE-KR 模式 —— 环境集成与使用说明

适用：将 eth_pcs_agent（10GBASE-R/KR，Clause 49 PCS + 可选 Clause 74 FEC）
集成进任意 UVM 验证环境。可跑示例见 `examples/10g_basekr_loopback/`。

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

## 4. UVM 侧集成

```systemverilog
eth_pcs_cfg cfg = eth_pcs_cfg::type_id::create("cfg");
cfg.is_active  = 1;      // 1: 例化 sequencer/driver 充当 MAC 发流
                         // 0: 被动（接真实 MAC RTL 时用，XGMII 由 MAC 驱动）
cfg.fec_enable = 0;      // 1: Clause 74 BASE-R FEC（仅限与本 agent 对端互通）
cfg.idle_words_per_gap = 2;   // 帧间空闲拍数（2 拍=16B >= 最小 IPG 12B）
cfg.vif_xgmii  = vx;  cfg.vif_serial = vs;
uvm_config_db#(eth_pcs_cfg)::set(this, "env", "cfg", cfg);

agent = eth_pcs_agent::type_id::create("agent", this);
// 记分板接口：agent.drv.tx_ap（发送记录）/ agent.mon.rx_ap（接收观测）
// 事务类型 eth_frame_txn：data[$]（DA 起、不含 FCS）+ crc_ok/preamble_ok
```

发流：对 `agent.sqr` 起任意 `uvm_sequence#(eth_frame_txn)`；参考
`eth_loopback_seq`（net_packet 随机报文 + SA 单播修正 + 60B 补齐）。

## 5. link-up 流程（必须遵守）

发流前必须等链路锁定，否则锁定期内帧必丢：

```systemverilog
while (!agent.bfm.rx_locked()) #100ns;   // 块同步/FEC 码字对齐完成
#1us;                                    // 解扰器自同步 + 流水线冲净裕量
```

中途复位后同样先 `rx_locked()` 再发流（参考 `eth_reset_recovery_test`）。

## 6. 时钟与弹性说明

- 字/位时钟允许独立有 ppm 偏差；速率差由 BFM 弹性 idle 插入/删除吸收
  （统计见 `idle_ins/idle_del`）。
- **约定字时钟 ≥ 位时钟/66**（删除主导域）：删除只发生在帧间 idle，
  永不伤帧；启动时自动预灌 4 块弹性垫防队列见底。
- FEC 模式无法按 bit 插补，underrun 计入 `tx_underrun`（正常应为 0）。

## 7. 检查点（monitor `PCS_STATS`）

| 计数 | 含义 | 正常值 |
|------|------|--------|
| frames / crc_err / preamble_err | 帧级完整性 | err 恒 0 |
| invalid_block | 非法 66b 块（坏头/未知块型） | 启动瞬态 ≤1 |
| slip | 对齐滑动次数 | 仅启动搜索期增长 |
| fec_corr / fec_uncorr | FEC 纠错/不可纠 | 注错测试外为 0 |
| idle_ins / idle_del | 弹性活动 | 有 ppm 偏差时非 0，正常 |
| tx_underrun | FEC 模式断流 | 恒 0 |

## 8. 已知限制

- FEC（cl74）PN-2112 种子为简化约定，仅本 agent 两端互通，与 svt VIP
  的 FEC 未对齐。
- 编码侧 S 仅置 lane0；解码侧兼容 lane0/lane4 起始与序集块（0x4b/0x55）。
- AN/LT（cl73/72）未实现，复位后直接进数据模式。

## 9. 可跑示例与回归入口

见 `examples/10g_basekr_loopback/README.md` 与 `sim/Makefile`
（unit/loopback/fec/stress/stress_fec/reset_recovery/disturb/svt 目标）。

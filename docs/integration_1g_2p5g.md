# 1G / 2.5G BASE-X 模式 —— 环境集成与使用说明

适用：eth_pcs_agent 的 1000BASE-X（`ETH_1G_BASEX_1BIT`）与 2.5GBASE-X
（`ETH_2PT5G_BASEX_SERIAL`）单 lane 模式。可跑示例见
`examples/1g_2p5g_loopback/`。

## 1. 与 10G/25G 的根本区别

BASE-X 是**另一套编码栈**，与 64b/66b 不共享：

| 项 | 10G/25G BASE-R | 1G/2.5G BASE-X |
|---|---|---|
| 线路编码 | 64b/66b + 自同步扰码 | 8b/10b（运行不均等性保证直流平衡） |
| 边界恢复 | 同步头块同步 | 逗号 K28.5（0011111/1100000）对齐 |
| 帧定界 | 块类型字段 | 有序集 /S/ /T/ /R/，idle 为 /I/ |
| MAC 侧接口 | XGMII（64bit+8bit 控制） | **GMII（8bit + tx_en/tx_er）** |
| 规范 | Clause 49 | Clause 36 |

所以 agent 在 BASE-X 模式下 MAC 侧换成 `gmii_if`，driver/monitor 走
GMII 分支（帧由 tx_en/rx_dv 定界，而不是 XGMII 的 S/T 控制字符）。

时钟：

| 模式 | 位时钟（线路） | 字节时钟（GMII，= 位钟/10） |
|---|---|---|
| 1G | 1.25 Gbaud | 125 MHz |
| 2.5G | 3.125 Gbaud | 312.5 MHz |

## 2. 使用方式

```bash
cd sim
make loopback_1g        # 1G 环回冒烟（20 帧）
make stress_1g          # 1G 大流量 1000 帧
make multi_reset_1g     # 1G 5 轮中途复位恢复
make disturb_1g         # 1G 链路扰动恢复
make loopback_2p5g      # 2.5G 环回冒烟
make stress_2p5g        # 2.5G 大流量 1000 帧
make multi_reset_2p5g   # 2.5G 5 轮中途复位恢复
make disturb_2p5g       # 2.5G 链路扰动恢复
make svt_1g             # 1G 与 svt VIP 交叉
make svt_2p5g           # 2.5G 与 svt VIP 交叉
make svt_1g_reset       # 1G 交叉中途复位恢复（3 轮复位，VIP 持续在线）
make svt_2p5g_reset     # 2.5G 交叉中途复位恢复
```

同一个 simv，`+SPEED=1g` / `+SPEED=2.5g` 切换，无需重编译。两种速率的
6 列（环回 / 1000 帧 / 多次复位 / 扰动 / VIP 交叉 / 交叉复位）齐全；各列
内容与判据（grep 汇总行 + 日志 `UVM_ERROR : 0`、`UVM_FATAL : 0`）见
`verification_matrix.md`。

## 3. top 层集成

`eth_pcs_lb_env(a, b)` 一个宏已包含 BASE-X 所需的全部接口（`a_gmii` /
`b_gmii`，vif 键 `vif_gmii_a` / `vif_gmii_b`），top 不用改：

```systemverilog
module top;
  import uvm_pkg::*;  import eth_tb_pkg::*;
  `eth_pcs_lb_env(a, b)     // +SPEED=1g|2.5g 即进入 BASE-X
  initial run_test();
endmodule
```

手工集成（接真实 1G MAC DUT，形态 A）时：

```systemverilog
gmii_if dut_gmii (gmii_clk, rst_n);   // DUT 的 GMII 接这里
// DUT.txd/tx_en/tx_er -> dut_gmii.txd/tx_en/tx_er
// dut_gmii.rxd/rx_dv/rx_er -> DUT.rxd/rx_dv/rx_er
initial uvm_config_db#(virtual gmii_if)::set(null, "uvm_test_top",
                                             "vif_gmii_a", dut_gmii);
// test 里：cfg.basex = 1; cfg.vif_gmii = <上面的句柄>;
// 注：agent build 仍校验 cfg.vif_xgmii 非空（BASE-X 下不使用），挂任一
// xgmii_if 实例即可
```

## 4. 行为要点

- **/S/ 与 /I/ 必须落偶数码组位**：tx_en 恰在奇数位拉起时，PCS 先补完
  idle 的第二个码组，首个前导字节顺延一拍（内部小队列承接，帧后 IPG
  的 idle 字节吸收掉）。/T//R/ 之后若下一位为奇数再补一个 /R/。
- **运行不均等性**：idle 选 /I1/（K28.5 D5.6）还是 /I2/（K28.5 D16.2）
  由当前 RD 决定，保证 idle 期间 RD 回到负。
- **弹性**：GMII 时钟 +100ppm（删除主导域），TX 码组队列超 12 个即删
  一整个 /I/（20bit），只删帧间 idle、永不伤帧。RX 引脚侧同样只在帧间
  （rx_dv=0）补拍或删一个 idle 字节，水位按实测突发自适应；帧内见底计入
  `rxpin_midframe_underrun`，非复位/扰动测试断言为 0。
- **同步**：3 个无错逗号码组得同步，4 个连续无效码组失同步；逗号出现
  在当前对齐相位之外即重新对齐。
- `rx_locked()` 在 BASE-X 下表示同步已得，既有 `wait_link_up()` 流程不改。
- **无 Local Fault / hi_ber**：GMII 没有序集，失同步期间 RX 引脚只是
  rx_dv=0；BASE-R 模式下 XGMII RX 引脚持续输出 Local Fault 的信令不适用
  （`link_fault` 测试也不适用）。BER 监视只在 64b/66b 模式，BASE-X 下
  `rx_link_up()` 与 `rx_locked()` 等价。
- 8b/10b 解码表由编码器反推生成（遍历 256 D + 5 K × 两种 RD），保证
  解码是编码的严格逆。
- **接收端容忍前导收缩**：对端 PCS 在 tx_en 落奇数位时可能丢掉一个前导
  字节来对齐 /S/（svt VIP 即如此，实测约一半帧前导只有 6 字节）。monitor
  按 SFD 定位帧起点，前导 0x55 有 1~7 个都算合法（802.3 对 MAC 的要求）。
  若自己写 GMII 侧 checker，切勿写死"7×0x55 + SFD"。
- 与 VIP 交叉（VIP 全套协议 checker 开启）：`make svt_1g` / `make svt_2p5g`
  判 A 500/500 bad=0、B 1000/1000；交叉复位 `svt_1g_reset` /
  `svt_2p5g_reset` 判 3 轮复位全过、末段 A 100/100 bad=0、B 200/200；
  两者都要求日志 `UVM_ERROR : 0`、`UVM_FATAL : 0`。
- **VIP 2.5G 的位钟就是我们供给的 `serial_basex_clk`**（波形探针实测：
  默认 1.25GHz 下 VIP 2.5G 码流位周期为 800ps）。所以 +SPEED=2.5g 时
  时钟宏把 basex 串行钟改为 3.125GHz、GMII 312.5MHz、XGMII 39.0625MHz
  （VIP 文档值），其余时钟不变。

## 5. 已知限制（TODO）

- Clause 37 自协商（/C/ 配置有序集交换）未实现，上电直接进数据态；与
  VIP 交叉时 VIP 侧须 `enable_an37_mode = 0`。
- 同步 FSM 为简化版（未实现 good_cgs 回升计数细节）。
- 不与 FEC / MLD / AN(cl73) / LT / 直驱 / lane4 起帧叠加（agent build
  阶段校验拦截）。
- SGMII / 100M / 10M（同属 8b/10b 族，速率适配靠字节复制）未做。

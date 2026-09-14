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
make svt_1g             # 1G 与 svt VIP 交叉
```

同一个 simv，`+SPEED=1g` / `+SPEED=2.5g` 切换，无需重编译。

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
```

## 4. 行为要点

- **/S/ 与 /I/ 必须落偶数码组位**：tx_en 恰在奇数位拉起时，PCS 先补完
  idle 的第二个码组，首个前导字节顺延一拍（内部小队列承接，帧后 IPG
  的 idle 字节吸收掉）。/T//R/ 之后若下一位为奇数再补一个 /R/。
- **运行不均等性**：idle 选 /I1/（K28.5 D5.6）还是 /I2/（K28.5 D16.2）
  由当前 RD 决定，保证 idle 期间 RD 回到负。
- **弹性**：GMII 时钟 +100ppm（删除主导域），TX 码组队列超 12 个即删
  一整个 /I/（20bit），只删帧间 idle、永不伤帧。
- **同步**：3 个无错逗号码组得同步，4 个连续无效码组失同步；逗号出现
  在当前对齐相位之外即重新对齐。
- `rx_locked()` 在 BASE-X 下表示同步已得，既有 `wait_link_up()` 流程不改。
- 8b/10b 解码表由编码器反推生成（遍历 256 D + 5 K × 两种 RD），保证
  解码是编码的严格逆。
- **接收端容忍前导收缩**：对端 PCS 在 tx_en 落奇数位时可能丢掉一个前导
  字节来对齐 /S/（svt VIP 即如此，实测约一半帧前导只有 6 字节）。monitor
  按 SFD 定位帧起点，前导 0x55 有 1~7 个都算合法（802.3 对 MAC 的要求）。
  若自己写 GMII 侧 checker，切勿写死"7×0x55 + SFD"。
- 与 VIP 交叉：`make svt_1g` 实测 A 500/500 bad=0、B 1000/1000，
  UVM_ERROR=0、UVM_WARNING=0（VIP 全套协议 checker 开启）。

## 5. 已知限制（TODO）

- Clause 37 自协商（/C/ 配置有序集交换）未实现，上电直接进数据态；与
  VIP 交叉时 VIP 侧须 `enable_an37_mode = 0`。
- 同步 FSM 为简化版（未实现 good_cgs 回升计数细节）。
- 不与 FEC / MLD / AN(cl73) / LT / 直驱叠加（agent build 阶段校验拦截）。
- 2.5G 与 VIP 的交叉验证待做（VIP `ETH_2PT5G_BASEX_SERIAL` 的串行时钟
  来源需先用波形探针标定）。

# 示例：10G BASE-KR 双 agent 环回（首个模式示例，后续模式照此模板）

本示例展示 eth_pcs_agent 的完整集成方式与运行方法。示例**直接复用仓库
现有 TB 源码**（不复制一份，防止漂移），本 README 负责导读。

## 组成文件（导读顺序）

| 文件 | 角色 | 看什么 |
|------|------|--------|
| `test/uvm/top.sv` | 仿真顶层 | `eth_pcs_lb_env` 一键展开：aip_clk 时钟实例化、双 agent 接口交叉连线、复位/扰动钩子（tb_ctrl_if）；宏定义见 `src/agent/eth_pcs_macros.svh` |
| `test/uvm/eth_tb_pkg.sv` | env/测试 | cfg 装配（`eth_loopback_test::build_phase`）、link-up 等待、net_packet 发包序列、字节级记分板 |
| `src/agent/eth_pcs_agent.sv` | agent 本体 | 组件装配参考 |
| `sim/filelist.f` | 编译清单 | incdir 与文件顺序 |
| `sim/Makefile` | 运行入口 | 各测试目标与通过判据 |

集成到自有环境的逐步说明见 `docs/integration_10g_basekr.md`。

## 运行（10.11.10.53，VCS 环境）

```bash
export VCS_HOME=/home/ubuntu/synopsys/vcs/W-2024.09-SP1
export SCL_HOME=/home/ubuntu/synopsys/scl/2024.06
export LM_LICENSE_FILE=27000@simv-ai
export PATH=$VCS_HOME/bin:$SCL_HOME/linux64/bin:$PATH

cd sim
make loopback        # 冒烟：20 帧环回
make fec             # 冒烟（Clause 74 FEC 开）
make stress          # 大流量：1000 帧背靠背
make stress_fec      # 大流量（FEC 开）
make reset_recovery  # 中途复位恢复（每段 500 帧）
make multi_reset     # 多次复位（5 轮，每段 500 帧）
make disturb         # 链路扰动恢复（整位翻转 + 断线，每段 500 帧）
make link_fault      # 建链前/断线/hi_ber 期间 RX 引脚为 Local Fault
make stress_lane4    # 大流量，奇数帧从 lane4 起帧（0x33 块）
```

AN/LT/KR、RS-FEC、XGMII 直驱等 10G 变体目标见
`docs/integration_10g_basekr.md` §3.2；全部模式的目标矩阵见
`docs/verification_matrix.md`。

## 预期结果

通过判据以 `sim/Makefile` 各 UVM 目标为准：grep 的汇总行 + 日志
`UVM_ERROR : 0` 且 `UVM_FATAL : 0`（`CHECK_CLEAN`）。测试内的断言都以
UVM_ERROR 上报，因此一并由 `CHECK_CLEAN` 把关：

- 冒烟/大流量：日志末尾 `[SB] match=<N> mismatch=0`；大流量测试另断言
  A 端 `tx_underrun == 0`；复位/扰动/link_fault 以外的测试断言两端 RX
  引脚帧内见底 `rxpin_midframe_underrun == 0`；
- 复位/扰动：段 2 结束打印 `段2(复位后) 完成 match=500` /
  `段2(恢复后) 完成 match=500`，多次复位末尾打印 `多次复位覆盖完成: 5 轮`；
  各严格段逐段判全净（全部匹配、零错配、零丢失）；
- link_fault：末尾打印 `链路故障信令覆盖完成`；
- `[PCS_STATS]`（monitor 只打印、不据此判失败）：冒烟/大流量下
  crc_err/preamble_err/hi_ber 为 0，invalid_block ≤ 1（启动瞬态），
  idle_ins/idle_del、rxpin_ins/rxpin_del 非零属正常；复位/扰动测试中被
  打断或被扰动毁掉的帧可能计入 crc_err/preamble_err/invalid_block，属
  预期。各计数含义见 `docs/integration_10g_basekr.md` §7。

## 与 svt VIP 对接示例

`test/svt/top_svt.sv` + `test/svt/eth_svt_cross_pkg.sv`：本 agent 串行侧
直连 VIP `ETH_XSBI_SERIAL` 的 `tx_lane[0]/rx_lane[0]`。接线见 `top_svt.sv`
串行链路交叉连接段，VIP 配置见 `eth_svt_cross_pkg.sv` 的 `cross_svt_cfg`。

- `make svt` / `make svt_fec`（叠加 cl74）/ `make svt_lane4`（我方 lane4
  起帧）：双向大流量交叉校验，VIP 发 500 帧我方收、我方发 1000 帧 VIP 收；
- `make svt_reset` / `make svt_fec_reset`：3 轮我方中途复位（VIP 在线），
  每段 VIP 100 帧 + 我方 200 帧，逐段计数核对，判
  `CROSS_RESET_RECOVERY_PASS rounds=3`；
- `make svt_an` / `make svt_an_reset`：VIP 切 `ETH_AN_CL73`，双方先
  Clause 73 协商再进 10G 数据模式，流量规模分别同 `svt` / `svt_reset`
  （`svt_an` 另判 `AN 双方完成: VIP AN_GOOD`）。VIP 侧所需配置见
  `docs/layering_and_dut_modes.md` §2.5。

# 示例：10G BASE-KR 双 agent 环回（首个模式示例，后续模式照此模板）

本示例展示 eth_pcs_agent 的完整集成方式与运行方法。示例**直接复用仓库
现有 TB 源码**（不复制一份，防止漂移），本 README 负责导读。

## 组成文件（导读顺序）

| 文件 | 角色 | 看什么 |
|------|------|--------|
| `test/uvm/top.sv` | 仿真顶层 | aip_clk 时钟实例化、双 agent 接口交叉连线、复位/扰动钩子（tb_ctrl_if） |
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
make stress          # 大流量：20000 帧背靠背
make reset_recovery  # 中途复位恢复（每段 10000 帧）
make disturb         # 链路扰动恢复（每段 10000 帧）
```

## 预期结果

- 日志末尾 `[SB] match=<N> mismatch=0`；
- `[PCS_STATS]` 中 crc_err/preamble_err/tx_underrun 为 0，
  invalid_block ≤ 1（启动瞬态），idle_ins/idle_del 随 ppm 配置非零属正常；
- 复位/扰动测试各段结束打印 `段2(...) 完成 match=<N>`。

## 与 svt VIP 对接示例

`test/svt/top_svt.sv` + `test/svt/eth_svt_cross_pkg.sv`（`make svt`）：
本 agent 串行侧直连 VIP `ETH_XSBI_SERIAL` 的 `tx_lane[0]/rx_lane[0]`，
双向大流量交叉校验。接线与 VIP 配置细节见文件头注释。

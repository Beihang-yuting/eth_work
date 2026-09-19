# 示例：40G（4 lane MLD）双 agent 环回

多 lane 模式示例。导读：

| 文件 | 看什么 |
|------|--------|
| `test/uvm/top.sv` | `` `eth_pcs_lb_env `` 一键展开（10 条 lane 接口组，40G 用前 4 条/交叉连线/字时钟 AM 开销/每 lane vif 下发全在宏内） |
| `src/pcs/mld.sv` | MLD 分发/AM/lane 自识别/去偏斜/重组/AM 误码容忍 |
| `test/uvm/eth_tb_pkg.sv` | `+SPEED=40g` 装配分支（4 lane vif + am_spacing + BER 参数）；`eth_link_fault_test`（RX 引脚 Local Fault） |
| `test/unit/tb_pcs_unit.sv` `test_mld` / `test_mld_am_err` | 乱接+偏斜下的重组闭环单测 / 对齐后 AM 误码容忍 |

## 运行

```bash
cd sim
make loopback_40g stress_40g multi_reset_40g disturb_40g   # 环回/1000 帧/多次复位/扰动
make svt_40g svt_40g_reset                                 # VIP 交叉/交叉复位
make link_fault_40g                                        # Local Fault（含仅 lane0 断线）
make loopback_40g_fec stress_40g_fec multi_reset_40g_fec disturb_40g_fec   # +FEC（每 PCS lane cl74）
make svt_40g_fec svt_40g_fec_reset
```

预期：`[SB] match=N mismatch=0` 等汇总行（各列 grep 行见
`docs/verification_matrix.md`；`link_fault_40g` 为 `链路故障信令覆盖完成`），
且日志 `UVM_ERROR : 0`、`UVM_FATAL : 0`。
集成细节：`docs/integration_40g.md`。

# 示例：40G（4 lane MLD）双 agent 环回

多 lane 模式示例。导读：

| 文件 | 看什么 |
|------|--------|
| `test/uvm/top_40g.sv` | 4 lane 接口/交叉连线（generate）、字时钟 AM 开销公式、每 lane vif 下发 |
| `src/pcs/mld.sv` | MLD 分发/AM/lane 自识别/去偏斜/重组 |
| `test/uvm/eth_tb_pkg.sv` | `+SPEED=40g` 装配分支（4 lane vif + am_spacing） |
| `test/unit/tb_pcs_unit.sv` `test_mld` | 乱接+偏斜下的重组闭环单测 |

## 运行

```bash
cd sim
make loopback_40g stress_40g multi_reset_40g
```

预期同 10G 示例（`[SB] match=N mismatch=0`）。集成细节：
`docs/integration_40g.md`。

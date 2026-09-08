# eth_work — MAC 对接用 PCS/SerDes 专用 UVM Agent

自研"等效 svtVIP PHY 侧"agent：上边界 XGMII 对接真实 MAC，内部实现
10GBASE-R PCS（Clause 49 64b/66b + 扰码 + 块同步）与 BASE-R FEC
（Clause 74，可纠 ≤11bit 突发），下边界 1bit 串行（SerDes 抽象）。
报文生成复用 [net_packet](https://github.com/Beihang-yuting/net_packet)。

设计文档：`docs/architecture.md`。

## 运行（10.11.10.53，需 VCS 环境）

```bash
cd sim
make unit       # 单元测试：编码/扰码/块同步/FEC/帧 闭环，判 UNIT_TEST_PASS
make loopback   # UVM 环回冒烟（FEC 关）：20 帧零丢失零错帧
make fec        # UVM 环回冒烟（FEC 开）
```

## 当前状态

- 阶段 1 完成：双 agent 串行环回，net_packet 发包，字节级记分板 +
  CRC/preamble/块合法性检查全部通过。
- 阶段 2 待做：与 Synopsys svt ethernet VIP（R-2020.12，10G XSBI 示例）
  背靠背交叉验证，见 `docs/architecture.md` 第 5 节。

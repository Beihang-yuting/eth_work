# eth_work — MAC 对接用 PCS/SerDes 专用 UVM Agent

自研"等效 svtVIP PHY 侧"agent：上边界 XGMII 对接真实 MAC，内部实现
10GBASE-R PCS（Clause 49 64b/66b + 扰码 + 块同步）与 BASE-R FEC
（Clause 74，可纠 ≤11bit 突发），下边界 1bit 串行（SerDes 抽象）。
报文生成复用 [net_packet](https://github.com/Beihang-yuting/net_packet)；
高精度时钟复用 [aip_core](https://github.com/Beihang-yuting/aip_core) 的
aip_clk（vendored 于 third_party/aip_core，精度提到 1fs），字/位时钟独立
生成（含 ppm 偏差），速率差由 BFM 弹性 idle 插入/删除吸收。

文档索引：
- 设计：`docs/architecture.md`（含扩展路线图与 VIP 对接备忘）
- 集成/使用（每模式一份）：`docs/integration_10g_basekr.md`、
  `docs/integration_25g_5g.md`、`docs/integration_40g.md`
- 可跑示例（每模式一份）：`examples/10g_basekr_loopback/`、
  `examples/25g_loopback/`、`examples/40g_loopback/`

## 运行（10.11.10.53，需 VCS 环境）

```bash
cd sim
make unit            # 单元测试：编码/扰码/块同步/FEC/帧 闭环，判 UNIT_TEST_PASS
make loopback        # UVM 环回冒烟（FEC 关）：20 帧零丢失零错帧
make fec             # UVM 环回冒烟（FEC 开）
make stress          # 大流量：1000 帧背靠背随机报文（FEC 关）
make stress_fec      # 大流量（FEC 开）
make reset_recovery  # 中途复位：复位后重新 link-up，每段 500 帧
make disturb         # 链路扰动（反压等效）：扰动毁帧可容忍，撤扰后 500 帧全净
make svt             # 阶段 2：svt VIP 交叉验证（VIP 500 帧 + 我方 1000 帧）
make loopback_40g    # 40G（4 lane MLD）环回/大流量/多次复位：
make stress_40g multi_reset_40g
```

测试硬性要求（所有新场景默认遵守）：大流量（1000 帧标准）、错误即停（+UVM_MAX_QUIT_COUNT=5）、反压/扰动后可恢复、
中途复位后流量完全正常。

## 当前状态

- 阶段 1 完成：双 agent 串行环回，net_packet 发包，字节级记分板 +
  CRC/preamble/块合法性检查全部通过。
- 阶段 2 完成（冒烟）：与 Synopsys svt ethernet VIP（R-2020.12，
  ETH_XSBI_SERIAL / 10G BASE-KR）双向对接 —— VIP 发帧我方全收（CRC 干净），
  我方发帧 VIP 全收（VIP 内建协议检查器通过）。对接中修正：同步头线上
  发送顺序、lane4 帧起始（0x33）与序集块（0x4b/0x55）解码支持。
- FEC 互通（我方 Clause 74 vs VIP FEC）未做：PN-2112 种子约定为简化实现，
  互通需按 VIP 行为对齐后另行验证。

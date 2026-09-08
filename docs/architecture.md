# eth_work — MAC 对接用 PCS/SerDes 专用 UVM Agent 架构设计

## 1. 目标

实现一个"等效 svtVIP PHY 侧"的自研 UVM agent：

- 对上通过 **XGMII**（64bit 数据 + 8bit 控制，单时钟展平）对接真实 MAC；
- 对下实现 **10GBASE-R PCS**（IEEE 802.3 Clause 49：64b/66b 编解码、
  自同步扰码 x^58+x^39+1、块同步锁定）；
- 可选 **BASE-R FEC**（Clause 74：(2112,2080) fire code，含 PN-2112 扰码与
  burst 纠错）；
- 串行侧以 **66bit 块粒度**建模（等效 SerDes 已完成 bit 对齐后的抽象，
  保留 bit-slip 行为由 block_sync 模拟）；
- 报文生成/解析复用 `third_party/net_packet`（70+ 协议模板、CRC 自动计算）；
- 最终与 Synopsys svt ethernet VIP（R-2020.12，10G XSBI 示例配置）背靠背
  对接，交叉检查协议完整性。

## 2. 分层结构

```
          sequencer (net_packet packet_item)
              |
        eth_pcs_driver ──── 帧 -> XGMII 时序（IPG/preamble/SFD/CRC）
              |
   xgmii_if (64b data + 8b ctl)          <== 真实 MAC 从这里接入
              |
        eth_pcs_phy_bfm
          ├─ pcs_encoder / pcs_decoder   (Clause 49 64b/66b)
          ├─ scrambler / descrambler     (x^58 + x^39 + 1)
          ├─ fec_cl74_encoder/decoder    (可选, Clause 74)
          └─ block_sync                  (锁定 FSM + bit-slip)
              |
   serial66_if (66b 块 + valid)          <== 与 svtVIP / 对端 BFM 相连
```

- TX 路径：XGMII → 66b 编码 → 扰码 →（FEC 编码）→ serial66_if。
- RX 路径：serial66_if →（FEC 解码/纠错）→ 块同步 → 解扰 → 66b 解码 → XGMII。

## 3. 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 速率/编码 | 10GBASE-R 单 lane | VIP 10G 示例现成，最简完整路径 |
| 串行抽象 | 66b 块 + valid 握手 | 避免真实 16bit XSBI 时钟域细节，协议内容完全等价；块边界失锁由 bit-slip 激励模拟 |
| S 位置 | 仅 lane0（块型 0x78） | 64bit XGMII 下标准仅允许 lane0 起始 |
| FEC | Clause 74 (2112,2080) | 与 VIP 10G FEC 测试同款，可交叉验证；error-trapping 解码可纠 ≤11bit burst |
| 帧模型 | net_packet `packet` 类 | 复用 CRC/checksum/解析器/比较器 |
| 校验策略 | 双侧 monitor + scoreboard 逐字节比帧；PCS 层校验非法块型/失锁/CRC | "协议完整性检查"落在块层 + 帧层两级 |

## 4. 目录约定

```
docs/           设计文档
src/pkg/        eth_pcs_pkg.sv 顶层 package（编译单元入口）
src/pcs/        Clause 49 编解码、扰码、块同步（纯函数/类，便于单测）
src/fec/        Clause 74 FEC 编解码
src/agent/      UVM agent：cfg/driver/monitor/bfm/接口
test/unit/      非 UVM 自校验单元测试（编码环回、FEC 纠错、扰码环回）
test/uvm/       UVM 环回环境与测试（双 agent 背靠背）
sim/            filelist 与 Makefile（VCS，10.11.10.53 执行）
third_party/    net_packet（来自 10.11.10.59 ~/workspace/ryan/net_packet）
```

## 5. 与 svtVIP 对接计划（阶段 2）

1. 阶段 1（本仓库当前）：双自研 agent 串行环回，net_packet 发包，
   scoreboard 比帧 —— 证明自身 PCS/FEC 正确闭环。
2. 阶段 2：以 VIP 示例 `tb_ethernet_svt_uvm_10g_intermediate_sys` 为基础，
   用本 agent 的 serial66 侧替换示例中一端（经 66b↔XSBI 适配层），
   VIP monitor/scoreboard 检查我方发出码流的协议合法性；反向用我方
   monitor 检查 VIP 码流 —— 双向交叉验证环境准确性。
3. 阶段 3：接真实 MAC RTL：MAC XGMII 直连 xgmii_if，本 agent 充当 PHY。

## 6. 验证清单

- [ ] 单测：66b 编码→解码环回（随机帧、随机 IPG、各 T 位置）
- [ ] 单测：扰码→解扰环回、种子无关性
- [ ] 单测：FEC 编码→注错（burst ≤11bit）→解码纠正；>11bit 报不可纠
- [ ] 单测：块同步在 bit-slip 后重新锁定
- [ ] UVM：环回测试 N 帧零丢失零错帧（净荷 46B~9000B 扫描）
- [ ] UVM：FEC 开/关两种模式环回
- [ ] 阶段 2：svtVIP 交叉验证

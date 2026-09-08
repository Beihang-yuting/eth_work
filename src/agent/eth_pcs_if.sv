// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— agent 的两个物理边界接口
// 职责：定义 XGMII 接口（对接真实 MAC 的上边界）与 1bit 串行接口
//       （SerDes 抽象的下边界）。两个接口共同构成 PCS/SerDes agent 的
//       全部信号面，故集中在一个文件便于对照维护。
// 依赖：无（纯 interface 定义）。
// 所有权：top 模块实例化并持有；agent 经 virtual interface 引用，不负责
//         接口生命周期。
// -----------------------------------------------------------------------------

// 为什么 XGMII 用 64bit 单时钟展平：真实 XGMII 是 32bit DDR，验证环境
// 常规做法是展平为 64bit SDR 以简化时序；帧起始仍约束在 lane0，协议
// 语义与 32bit DDR 完全等价。
interface xgmii_if (input logic clk, input logic rst_n);

  // TX 方向：MAC -> PHY(agent)
  logic [63:0] txd;
  logic [7:0]  txc;

  // RX 方向：PHY(agent) -> MAC
  logic [63:0] rxd;
  logic [7:0]  rxc;

  // BFM 侧时序视图：驱动 RX、采样 TX
  clocking phy_cb @(posedge clk);
    input  txd, txc;
    output rxd, rxc;
  endclocking

  // MAC 侧时序视图（阶段 1 环回测试中由 driver 充当 MAC 使用）
  clocking mac_cb @(posedge clk);
    output txd, txc;
    input  rxd, rxc;
  endclocking

endinterface

// 串行接口：每拍 1bit，SerDes 已完成时钟恢复后的抽象视图。
// 为什么每拍 1bit 而不是 66b 块：块边界物理上不存在，保留 bit 粒度才能
// 真实验证块同步/FEC 对齐的锁定与 slip 行为（见 block_sync.sv 头注）。
interface serial_if (input logic clk, input logic rst_n);

  // 单向数据：本端发送 / 本端接收（双工链路由 top 交叉两个实例连接）
  logic tx_bit;
  logic rx_bit;

  clocking tx_cb @(posedge clk);
    output tx_bit;
  endclocking

  clocking rx_cb @(posedge clk);
    input rx_bit;
  endclocking

endinterface

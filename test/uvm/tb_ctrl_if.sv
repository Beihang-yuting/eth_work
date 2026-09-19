// -----------------------------------------------------------------------------
// 所属：eth_work/test/uvm —— TB 控制接口（复位/链路扰动注入钩子）
// 职责：让 UVM test 能触发 top 层动作：
//   reset_req  —— 置 1 请求一次复位脉冲（top 检测后拉低两侧 rst_n 数拍，
//                  完成后 top 将其清零作为完成握手）；
//   err_inject —— 置 1 期间 top 在 A->B 串行线上异或翻转 bit（模拟链路
//                  误码/瞬断，即本层"反压/链路不可用"扰动源）；
//   los        —— 置 1 期间 A->B 全部 lane 强制为 0（线路断开 / 信号丢失）。
//                  整位翻转对 64b/66b 同步头仍合法（01<->10）不会失锁，
//                  断线则保证各模式都经历失锁 -> 重锁。
//   los_lane0  —— 置 1 期间仅多 lane 的 lane0 断线（其余 lane 照常）：验证
//                  单 lane 失锁即整体失去对齐、MAC 侧见 Local Fault。
// 依赖：无。top 实例化并经 config_db 下发 virtual 句柄。
// 所有权：top 持有实例；test 只读写控制位。
// -----------------------------------------------------------------------------

interface tb_ctrl_if ();

  logic reset_req  = 0;
  logic err_inject = 0;
  logic los        = 0;
  logic los_lane0  = 0;

endinterface

// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 49 自同步扰码器 / 解扰器
// 职责：对 66b 块的 64bit payload 做 x^58 + x^39 + 1 自同步扰码与解扰
//       （同步头 2bit 不参与扰码）。扰码消除线路长 0/1 串，保证 DC 平衡
//       与时钟恢复；自同步结构使解扰端无需已知种子，错误传播有限（每个
//       线路误码在解扰后最多扩散为 3 个 bit 错）。
// 依赖：pcs_types.sv（block66_t）。
// 所有权：scrambler_c / descrambler_c 为有状态对象，一条链路方向各持一个
//         实例，由 phy_bfm 在构造时创建、随 BFM 生命周期存续；复位时调用
//         reset() 恢复初始移位寄存器状态。
// -----------------------------------------------------------------------------

// 为什么单独建模而不并入编码器：扰码状态跨块连续（58bit LFSR 不随块边界
// 复位），与逐块无状态的 64b/66b 编码属于不同性质的层；分离后单元测试
// 可独立验证"任意种子下扰码->解扰恒等"与"错误传播 ≤3bit"两条性质。

// 扰码器：out = in ^ S[38] ^ S[57]，移位后 out 进入 S[0]（自同步：寄存器
// 保存的是历史输出 bit）。bit 处理顺序与线路发送顺序一致（payload LSB 先）。
class scrambler_c;

  // 58bit 移位寄存器；S[0] 为最新 bit。上电全 1，避免全 0 死锁状态
  protected logic [57:0] state;

  function new();
    reset();
  endfunction

  // 恢复初始状态（复位或重新建链时由 BFM 调用）
  function void reset();
    state = '1;
  endfunction

  // 扰码一个 64bit payload；bit0 在时间上最先处理
  function logic [63:0] scramble(logic [63:0] din);
    logic [63:0] dout;
    for (int i = 0; i < 64; i++) begin
      logic b = din[i] ^ state[38] ^ state[57];
      dout[i] = b;
      state   = {state[56:0], b};
    end
    return dout;
  endfunction

endclass

// 解扰器：out = in ^ S[38] ^ S[57]，移位后收到的 in（而非 out）进入 S[0]。
// 寄存器保存历史"线路 bit"，因此与扰码端自动对齐，无需传递种子。
class descrambler_c;

  protected logic [57:0] state;

  function new();
    reset();
  endfunction

  // 恢复初始状态；解扰端复位后经过 58 个线路 bit 即重新自同步
  function void reset();
    state = '1;
  endfunction

  // 解扰一个 64bit payload；bit0 在时间上最先处理
  function logic [63:0] descramble(logic [63:0] din);
    logic [63:0] dout;
    for (int i = 0; i < 64; i++) begin
      dout[i] = din[i] ^ state[38] ^ state[57];
      state   = {state[56:0], din[i]};
    end
    return dout;
  endfunction

endclass

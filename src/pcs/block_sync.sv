// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 49 块同步（bit 流 -> 66b 块对齐）
// 职责：从串行 bit 流中搜索并锁定 66b 块边界。模拟 SerDes 之后 PCS 的
//       lock 状态机：候选对齐位置连续收到 64 个合法同步头（01/10）即锁定；
//       锁定后在 64 块滑动窗口内累计 16 个非法同步头则失锁并 slip 1 bit
//       重新搜索。该行为覆盖真实链路上"任意起始相位 + 中途插拔"场景。
// 依赖：pcs_types.sv（block66_t、SYNC_*）。
// 所有权：每条 RX 方向一个实例，由 phy_bfm 创建并随其存续；reset() 用于
//         链路复位后重新搜索。
// -----------------------------------------------------------------------------

// 为什么以 bit 为输入粒度：上游 serial_if 每拍 1 bit（SerDes 抽象），块
// 边界信息物理上不存在，必须由本层通过同步头统计恢复；以 bit 为粒度才能
// 真实模拟 slip 与任意相位锁定，这是"专用 SerDes/PCS agent"区别于简单
// 块搬运的关键行为。
class block_sync_c;

  // 锁定判定参数（Clause 49 49.2.13.2.2 数值）
  localparam int GOOD_TO_LOCK   = 64;   // 连续合法头数 -> 锁定
  localparam int WINDOW_BLOCKS  = 64;   // 失锁统计窗口（块数）
  localparam int BAD_TO_UNLOCK  = 16;   // 窗口内非法头数 -> 失锁

  // 对齐状态
  protected bit          locked;
  protected logic [65:0] shift;        // bit 收集器；bit0 最先到达
  protected int          nbits;        // shift 中已收集的 bit 数

  // 锁定/失锁统计
  protected int good_cnt;              // 未锁定时的连续合法头计数
  protected int window_cnt;            // 已锁定时窗口内块计数
  protected int bad_cnt;               // 已锁定时窗口内非法头计数

  // 对外可读统计：slip 次数（单测/记分板检查重锁行为用）
  int slip_count;

  function new();
    reset();
    slip_count = 0;
  endfunction

  // 复位对齐状态，重新从零搜索边界（不清 slip_count，便于跨复位统计）
  function void reset();
    locked     = 0;
    shift      = '0;
    nbits      = 0;
    good_cnt   = 0;
    window_cnt = 0;
    bad_cnt    = 0;
  endfunction

  // 当前是否已锁定（BFM 决定是否向上递交块）
  function bit is_locked();
    return locked;
  endfunction

  // 推入一个线路 bit。集满 66bit 判定同步头：
  // 返回 1 表示 blk_out 携带一个完整块（无论头合法与否都递交，由上层
  // 解码路径决定丢弃）；返回 0 表示尚未集满或发生了 slip。
  //
  // 失败/边界路径：非法头在未锁定态触发立即 slip（丢 1 bit 重排）；在
  // 锁定态计入窗口统计，达到阈值才失锁 + slip，避免单个误码破坏对齐。
  function bit push_bit(logic b, output block66_t blk_out);
    logic [1:0] sync;
    bit         head_ok;

    shift[nbits] = b;
    nbits++;
    if (nbits < 66) return 0;

    // 集满一个候选块：线路顺序 bit0/bit1 为同步头
    sync    = {shift[1], shift[0]};
    head_ok = (sync == SYNC_DATA) || (sync == SYNC_CTRL);

    if (!locked) begin
      if (head_ok) begin
        good_cnt++;
        if (good_cnt >= GOOD_TO_LOCK) begin
          locked     = 1;
          window_cnt = 0;
          bad_cnt    = 0;
        end
      end
      else begin
        // 候选位置错误：slip 1 bit —— 保留 shift[1..65] 作为新前 65 bit
        good_cnt = 0;
        slip_count++;
        shift = shift >> 1;
        nbits = 65;
        return 0;
      end
    end
    else begin
      window_cnt++;
      if (!head_ok) bad_cnt++;

      if (bad_cnt >= BAD_TO_UNLOCK) begin
        // 窗口内错误过多：失锁并 slip，重新搜索
        locked   = 0;
        good_cnt = 0;
        slip_count++;
        shift = shift >> 1;
        nbits = 65;
        return 0;
      end

      if (window_cnt >= WINDOW_BLOCKS) begin
        window_cnt = 0;
        bad_cnt    = 0;
      end
    end

    // 递交完整块（sync + 64bit payload），复位收集器
    blk_out.sync    = sync;
    for (int i = 0; i < 64; i++) blk_out.payload[i] = shift[2 + i];
    nbits = 0;
    return 1;
  endfunction

endclass

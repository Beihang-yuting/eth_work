// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 82 多 lane 分发 MLD（40G/100G）
// 职责：
//   TX（mld_tx_c）：把加扰后的 66b 块流按轮转分发到 N 个 PCS lane，
//     每 lane 每 am_spacing 块插入一个对齐标记 AM（AM 不加扰）。
//   RX（mld_rx_c）：各 lane 已完成块对齐（复用 block_sync_c 在 BFM 层），
//     本类接收各 lane 块流：按 AM 图案识别 lane 号（容忍物理乱接）、
//     以 AM 位置对齐去偏斜、移除 AM 后轮转重组回单一块流。
// 依赖：pcs_types.sv（block66_t、SYNC_CTRL）。
// 所有权：BFM 每方向各持一个实例（num_lanes>1 时启用）；reset() 清对齐。
// 简化说明（记 TODO）：Clause 74 FEC 与 MLD 叠加未实现（MLD 模式
//   FEC 须关）。BIP-8 已按表 82-4 实现（TX 生成 + RX 校验计数）。
// -----------------------------------------------------------------------------

// 支持的最大 lane 数（40G=4；100G 逻辑 20 lane 后续参数化启用）
localparam int MLD_MAX_LANES = 4;

// AM 图案（IEEE 802.3 表 82-2，40GBASE-R）：payload 字节序
// {M0,M1,M2,BIP3,M4,M5,M6,BIP7}，M4..M6 = ~M0..~M2，BIP7 = ~BIP3。
// bip3 为上一 AM 周期的 BIP-8 累计值（Clause 82.2.9）。
function automatic logic [63:0] mld_am_payload(int lane, logic [7:0] bip3);
  logic [7:0] m0, m1, m2;
  case (lane)
    0: begin m0 = 8'h90; m1 = 8'h76; m2 = 8'h47; end
    1: begin m0 = 8'hF0; m1 = 8'hC4; m2 = 8'hE6; end
    2: begin m0 = 8'hC5; m1 = 8'h65; m2 = 8'h9B; end
    default: begin m0 = 8'hA2; m1 = 8'h79; m2 = 8'h3D; end
  endcase
  return {~bip3, ~m2, ~m1, ~m0, bip3, m2, m1, m0};
endfunction

// BIP-8 累计（IEEE 表 82-4）：66 位块按传输序 bit k 归入
// BIP[(k-2) mod 8]（k>=2），k=0 归 BIP[3]、k=1 归 BIP[4]。
// 传输序：bit0=sync[1]（先发）、bit1=sync[0]、bit2+i=payload[i]。
function automatic logic [7:0] mld_bip_acc(logic [7:0] bip, block66_t b);
  logic tx_bit;
  for (int k = 0; k < 66; k++) begin
    if (k == 0)      tx_bit = b.sync[1];
    else if (k == 1) tx_bit = b.sync[0];
    else             tx_bit = b.payload[k-2];
    if (k == 0)      bip[3] ^= tx_bit;
    else if (k == 1) bip[4] ^= tx_bit;
    else             bip[(k-2) % 8] ^= tx_bit;
  end
  return bip;
endfunction

// 按 M0..M2（payload 低 24bit）匹配 AM 归属 lane；非 AM 返回 -1
function automatic int mld_am_lane(block66_t b);
  logic [63:0] am;
  if (b.sync != SYNC_CTRL) return -1;
  for (int l = 0; l < MLD_MAX_LANES; l++) begin
    am = mld_am_payload(l, 8'h00);
    if (b.payload[23:0] == am[23:0]) return l;
  end
  return -1;
endfunction

// ---------------- TX：分发 + AM 插入 ----------------

class mld_tx_c;

  protected int num_lanes;
  protected int am_spacing;        // 每 lane 两个 AM 之间的块数（含 AM）
  protected int cur_lane;          // 轮转指针
  protected int blk_cnt[MLD_MAX_LANES];   // 各 lane 周期内块计数（含 AM）
  protected logic [7:0] bip[MLD_MAX_LANES];   // 各 lane BIP-8 累计器

  function new(int lanes, int spacing);
    num_lanes  = lanes;
    am_spacing = spacing;
    reset();
  endfunction

  function void reset();
    cur_lane = 0;
    foreach (blk_cnt[i]) blk_cnt[i] = 0;
    foreach (bip[i]) bip[i] = '0;
  endfunction

  // 输入一个（已加扰的）66b 块，输出它应去的 lane 及需要先行插入的
  // AM 块。调用方按 out_am_valid 先送 AM 再送数据块到同一 lane。
  // 周期定义（与 802.3/VIP 定时器一致）：每 am_spacing 个线上块
  //（含 AM 本身）一个 AM；AM 携带上一周期 BIP-8，自身计入新周期。
  function void push_block(block66_t b, output int lane,
                           output bit out_am_valid, output block66_t am_blk);
    lane = cur_lane;
    out_am_valid = 0;

    if (blk_cnt[lane] == 0) begin
      out_am_valid   = 1;
      am_blk.sync    = SYNC_CTRL;
      am_blk.payload = mld_am_payload(lane, bip[lane]);
      bip[lane]      = '0;
      bip[lane]      = mld_bip_acc(bip[lane], am_blk);
      blk_cnt[lane]  = 1;   // AM 占本周期第 1 块
    end

    bip[lane]     = mld_bip_acc(bip[lane], b);
    blk_cnt[lane] = (blk_cnt[lane] + 1) % am_spacing;
    cur_lane = (cur_lane + 1) % num_lanes;
  endfunction

endclass

// ---------------- RX：lane 识别 + 去偏斜 + 重组 ----------------

// 为什么在块粒度做去偏斜：各 lane 经 block_sync 已恢复块边界，AM 在
// 块流中的位置差即偏斜量；以"各 lane 最近一次 AM"对齐后按轮转序取块
// 即可重组。物理 lane 到逻辑 lane 的映射由 AM 图案自识别。
class mld_rx_c;

  protected int num_lanes;
  protected int am_spacing;

  // 每物理 lane 的接收块队列（对齐锚之后的数据块）
  protected block66_t lane_q[MLD_MAX_LANES][$];

  // phys_of_logical[l] = 逻辑 lane l 来自哪个物理 lane；-1 未识别
  protected int phys_of_logical[MLD_MAX_LANES];
  protected bit aligned;
  protected int rr;                 // 重组轮转指针

  // 统计：单测/记分板用
  int am_seen[MLD_MAX_LANES];
  int realign_count;
  int bip_err_count;

  // 各物理 lane 的 BIP-8 累计（含上一 AM 起的全部块）
  protected logic [7:0] bip_rx[MLD_MAX_LANES];

  // 各物理 lane 距上个 AM 的数据块计数（对齐态周期自检用）。
  // 期望间隔在对齐后从首个完整间隔学习（learned_gap）：不同实现对
  // am_spacing 的计数约定不同（是否含 AM 本身），学习式两者都兼容。
  protected int since_am[MLD_MAX_LANES];
  protected int learned_gap;

  function new(int lanes, int spacing);
    num_lanes  = lanes;
    am_spacing = spacing;
    reset();
  endfunction

  function void reset();
    foreach (lane_q[i]) lane_q[i].delete();
    foreach (phys_of_logical[i]) phys_of_logical[i] = -1;
    foreach (bip_rx[i]) bip_rx[i] = '0;
    foreach (am_seen[i]) am_seen[i] = 0;
    foreach (since_am[i]) since_am[i] = 0;
    learned_gap = -1;
    aligned = 0;
    rr      = 0;
  endfunction

  function bit is_aligned();
    return aligned;
  endfunction

  // 输入某物理 lane 的一个块（须已过 block_sync）。
  // AM 块：登记逻辑 lane 映射并把该 lane 队列清到 AM 对齐点（AM 本身
  // 不入队，即去偏斜锚）；数据块：入该 lane 队列。
  // 失败路径：AM 图案与既有映射冲突（线缆中途换接）→ 整体重对齐。
  function void push_block(int phys, block66_t b);
    int l = mld_am_lane(b);

    if (l >= 0) begin
      am_seen[phys]++;

      // BIP 校验：AM 携带的 BIP3 应等于本 lane 上一周期累计值。
      // 首个 AM（累计器刚起）不校验。
      if (am_seen[phys] > 1 && b.payload[31:24] !== bip_rx[phys])
        bip_err_count++;
      bip_rx[phys] = '0;
      bip_rx[phys] = mld_bip_acc(bip_rx[phys], b);

      if (phys_of_logical[l] != phys) begin
        if (phys_of_logical[l] != -1 || lane_map_of(phys) != -1) begin
          realign_count++;
          $display("[MLD_REALIGN] @%0t lane-conflict phys=%0d logical=%0d",
                   $time, phys, l);
          reset();
        end
        phys_of_logical[l] = phys;
      end

      // 对齐态周期自检：两 AM 间数据块数应恒定（首个完整间隔学得基
      // 准）；偏离说明该 lane 曾滑块，重组已错位且无法自愈 —— 整体
      // 重对齐（在途块丢弃，由上层 lenient/计数暴露）。
      if (aligned) begin
        if (learned_gap < 0) begin
          learned_gap = since_am[phys];
        end else if (since_am[phys] != learned_gap) begin
          realign_count++;
          $display("[MLD_REALIGN] @%0t gap-mismatch phys=%0d gap=%0d learned=%0d",
                   $time, phys, since_am[phys], learned_gap);
          reset();
          phys_of_logical[l] = phys;
          bip_rx[phys] = mld_bip_acc('0, b);
          am_seen[phys] = 1;
          return;
        end
      end
      since_am[phys] = 0;

      // 以 AM 为对齐锚：仅初对齐阶段清残余（去偏斜）。对齐后 AM 只
      // 跳过不入队 —— 此时清队会丢弃尚未消费的数据块。
      if (!aligned) lane_q[phys].delete();

      // 全部逻辑 lane 已识别即进入对齐态，重组从逻辑 lane0 开始
      if (!aligned) begin
        bit all = 1;
        for (int i = 0; i < num_lanes; i++)
          if (phys_of_logical[i] == -1) all = 0;
        if (all) begin
          aligned = 1;
          rr      = 0;
        end
      end
      return;
    end

    bip_rx[phys] = mld_bip_acc(bip_rx[phys], b);
    since_am[phys]++;
    lane_q[phys].push_back(b);
  endfunction

  // 取重组后的下一个块。按轮转序从对应物理 lane 队列头部取；该 lane
  // 队列空则返回 0（等待偏斜较大的 lane 到齐）。
  function bit pop_block(output block66_t b);
    int phys;
    if (!aligned) return 0;
    phys = phys_of_logical[rr];
    if (lane_q[phys].size() == 0) return 0;
    b  = lane_q[phys].pop_front();
    rr = (rr + 1) % num_lanes;
    return 1;
  endfunction

  // 物理 lane 当前映射到的逻辑 lane；未映射返回 -1
  protected function int lane_map_of(int phys);
    foreach (phys_of_logical[i])
      if (phys_of_logical[i] == phys) return i;
    return -1;
  endfunction

endclass

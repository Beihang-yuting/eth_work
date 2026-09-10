// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 72 链路训练（LT，KR 电口建链第二步）
// 职责：
//   训练帧层（lt72_frame_tx_c / lt72_frame_rx_c）：4096 bit 训练帧
//     <-> 线上比特流。帧结构（IEEE 802.3 72.6.10）：
//       [0..15]    帧标记前半 = 16 个 1
//       [16..31]   帧标记后半 = 16 个 0
//       [32..47]   系数更新 Coefficient Update（本端对"对端发射均衡"的
//                  调整请求）
//       [48..63]   状态报告 Status Report（本端对"收到的对端调整"的
//                  执行回执 + receiver ready）
//       [64..4095] 训练码型 PRBS11（x^11+x^9+1），供对端调均衡用
//     为什么标记取 16 个 1 + 16 个 0（32 bit）而不是单纯 16 个 1：
//     PRBS11 最长游程 11，若只用 16 连 1 作锚，PRBS 尾部的连 1 会与
//     标记连成最长 27 连 1，RX 在"第 16 个 1"处触发同步会早锚最多
//     11 位、字段整体解错（两端对称即死锁，已实测）。改为"ones 结束
//     后再数 16 个 0"作锚点，与前置 PRBS 尾长度无关，唯一确定。
//     注：VIP 不支持 cl72，此为本实现的确定性选择，对接真实 DUT 前
//     需按对端实际帧标记定义核对（TODO）。
//   训练握手层（lt72_engine_c）：本端把对端发射均衡三抽头依次拉到
//     "已更新"，并回执对端对我方的调整请求；双方 receiver ready 置位
//     即训练完成。
// 依赖：无（纯行为级，BFM 每 bit 时钟调用 tx_tick/rx_tick）。
// 所有权：BFM 在 lt_enable 时持有一个实例；reset() 重新训练。
// 验证说明：svt VIP **不支持 Clause 72**（无 LT 接口模式/配置项/示例），
//   故本模块只能自环对训验证（我方两端引擎互训）+ 单测，无第三方参照。
//   线上格式严格按规范实现，以便将来对接真实 DUT。
// 简化说明（记 TODO）：均衡器本身不建模（无抽头/眼图），系数更新按
//   "请求-执行-回执"协议语义走完状态机即视为收敛；PRESET/INITIALIZE
//   按规范位定义保留但不改变信号质量。
// -----------------------------------------------------------------------------

localparam int LT72_FRAME_BITS   = 4096;
localparam int LT72_MARKER_ONES  = 16;   // 标记前半：全 1
localparam int LT72_MARKER_ZEROS = 16;   // 标记后半：全 0（唯一锚点）
localparam int LT72_MARKER_BITS  = LT72_MARKER_ONES + LT72_MARKER_ZEROS;
localparam int LT72_STATUS_START = LT72_MARKER_BITS + 16;   // 48
localparam int LT72_PRBS_START   = LT72_STATUS_START + 16;  // 64

// 系数更新字段（IEEE 表 72-4）：
//   [1:0] C(-1) 预加重  [3:2] C(0) 主抽头  [5:4] C(+1) 后加重
//   编码：00 hold、01 increment、10 decrement
//   [12] Initialize  [13] Preset
// 状态报告字段（IEEE 表 72-5）：
//   [1:0] C(-1) 状态 [3:2] C(0) 状态 [5:4] C(+1) 状态
//   编码：00 not_updated、01 updated、10 minimum、11 maximum
//   [15] Receiver Ready
localparam logic [1:0] LT72_UPD_HOLD = 2'b00;
localparam logic [1:0] LT72_UPD_INC  = 2'b01;
localparam logic [1:0] LT72_UPD_DEC  = 2'b10;

localparam logic [1:0] LT72_ST_NOT_UPDATED = 2'b00;
localparam logic [1:0] LT72_ST_UPDATED     = 2'b01;
localparam logic [1:0] LT72_ST_MAXIMUM     = 2'b11;

// PRBS11：x^11 + x^9 + 1，每拍出 1 bit（种子非零）
class lt72_prbs11_c;

  protected logic [10:0] lfsr;

  function new();
    reset();
  endfunction

  function void reset();
    lfsr = 11'h7FF;
  endfunction

  function logic next();
    logic fb;
    fb   = lfsr[10] ^ lfsr[8];
    lfsr = {lfsr[9:0], fb};
    return fb;
  endfunction

endclass

// ---------------- 训练帧 TX ----------------

class lt72_frame_tx_c;

  // 待发字段（帧边界锁存，可随时更新）
  logic [15:0] coeff_update;
  logic [15:0] status_report;

  bit                     frame_start;   // 本拍是帧首（供引擎计时）
  protected int           bitpos;
  protected logic [15:0]  cur_upd, cur_sts;
  protected lt72_prbs11_c prbs;

  function new();
    prbs          = new();
    coeff_update  = '0;
    status_report = '0;
    reset();
  endfunction

  function void reset();
    bitpos      = 0;
    cur_upd     = '0;
    cur_sts     = '0;
    frame_start = 0;
    prbs.reset();
  endfunction

  // 每 bit 时钟一拍。帧边界锁存字段，保证一帧内字段恒定（对端按帧解析）
  function logic tx_tick();
    logic b;
    frame_start = (bitpos == 0);
    if (bitpos == 0) begin
      cur_upd = coeff_update;
      cur_sts = status_report;
      prbs.reset();          // 每帧重启码型，便于对端逐帧独立判定
    end

    if (bitpos < LT72_MARKER_ONES)
      b = 1'b1;                                       // 标记前半
    else if (bitpos < LT72_MARKER_BITS)
      b = 1'b0;                                       // 标记后半（锚）
    else if (bitpos < LT72_STATUS_START)
      b = cur_upd[bitpos - LT72_MARKER_BITS];
    else if (bitpos < LT72_PRBS_START)
      b = cur_sts[bitpos - LT72_STATUS_START];
    else
      b = prbs.next();                                // 训练码型

    bitpos = (bitpos + 1) % LT72_FRAME_BITS;
    return b;
  endfunction

endclass

// ---------------- 训练帧 RX ----------------

// 帧同步（两段式，见文件头"为什么标记取 32 bit"）：
//   ① 搜 >=16 连 1（PRBS11 游程上限 11，不会自误触发）；
//   ② 该 ones 串结束后的第一个 0 即标记后半起点，从它数满 16 个 0
//      即锚定 —— 中途出现 1 说明是伪锚，退回 ①。
// 之后按位计数解析字段；帧尾回搜索态重锚，任何滑位都能自愈。
class lt72_frame_rx_c;

  logic [15:0] coeff_update;    // 最近一帧解出的字段
  logic [15:0] status_report;
  int          frames_rx;

  protected bit          synced;
  protected bit          in_zeros;    // 已见 >=16 连 1，正在数标记的 0
  protected int          bitpos;
  protected int          ones_run;
  protected int          zeros_run;
  protected logic [15:0] acc_upd, acc_sts;

  function new();
    reset();
  endfunction

  function void reset();
    synced        = 0;
    in_zeros      = 0;
    bitpos        = 0;
    ones_run      = 0;
    zeros_run     = 0;
    acc_upd       = '0;
    acc_sts       = '0;
    coeff_update  = '0;
    status_report = '0;
    frames_rx     = 0;
  endfunction

  function bit is_synced();
    return synced;
  endfunction

  // 每 bit 时钟喂一个采样；字段区解完返回 1
  function bit rx_tick(logic b);
    bit got = 0;

    if (!synced) begin
      if (!in_zeros) begin
        // ① 搜 >=16 连 1
        if (b === 1'b1) ones_run++;
        else begin
          if (ones_run >= LT72_MARKER_ONES) begin
            in_zeros  = 1;      // 本 0 即标记后半第 1 位
            zeros_run = 1;
          end
          ones_run = 0;
        end
      end
      else begin
        // ② 数满 16 个 0 即锚定；中途出现 1 = 伪锚，退回 ①
        if (b === 1'b0) begin
          zeros_run++;
          if (zeros_run >= LT72_MARKER_ZEROS) begin
            synced   = 1;
            in_zeros = 0;
            bitpos   = LT72_MARKER_BITS;   // 标记已消费
            acc_upd  = '0;
            acc_sts  = '0;
          end
        end
        else begin
          in_zeros  = 0;
          zeros_run = 0;
          ones_run  = 1;
        end
      end
      return 0;
    end

    if (bitpos < LT72_STATUS_START)
      acc_upd[bitpos - LT72_MARKER_BITS] = b;
    else if (bitpos < LT72_PRBS_START)
      acc_sts[bitpos - LT72_STATUS_START] = b;
    // 训练码型区不解析（均衡器不建模）

    bitpos++;
    if (bitpos == LT72_PRBS_START) begin
      coeff_update  = acc_upd;
      status_report = acc_sts;
      frames_rx++;
      got = 1;
    end
    else if (bitpos == LT72_FRAME_BITS) begin
      synced    = 0;
      in_zeros  = 0;
      bitpos    = 0;
      ones_run  = 0;
      zeros_run = 0;
    end

    return got;
  endfunction

endclass

// ---------------- 训练握手 FSM ----------------

// 协议语义（不建模真实均衡器）：本端作为发起方对对端发射均衡依次发
// increment 请求（C(-1) -> C(0) -> C(+1)），对端回 updated 即认为该
// 抽头收敛；三抽头走完置本端 receiver ready。同时作为响应方对收到的
// update 请求回执 updated，并在对端 ready 后进入完成态。
class lt72_engine_c;

  typedef enum { LT_TRAIN_CM1, LT_TRAIN_C0, LT_TRAIN_CP1,
                 LT_LOCAL_RDY, LT_DONE } lt72_state_e;

  lt72_frame_tx_c ftx;
  lt72_frame_rx_c frx;

  // 观测
  int frames_seen;
  int tap_done;          // 已收敛抽头数

  protected lt72_state_e state;
  protected bit          peer_ready;
  protected int          hold_frames;

  function new();
    ftx = new();
    frx = new();
    reset();
  endfunction

  function void reset();
    state       = LT_TRAIN_CM1;
    peer_ready  = 0;
    hold_frames = 0;
    frames_seen = 0;
    tap_done    = 0;
    ftx.reset();
    frx.reset();
    ftx.coeff_update  = {10'b0, LT72_UPD_HOLD, LT72_UPD_HOLD, LT72_UPD_INC};
    ftx.status_report = '0;
  endfunction

  function bit is_done();
    return state == LT_DONE;
  endfunction

  function string state_name();
    return state.name();
  endfunction

  // 每 bit 时钟一拍。LT_LOCAL_RDY 的保持窗按"本端已发出帧数"推进 ——
  // 同 AN：先完成的一方会切数据模式而停发训练帧，按收到帧数计时会让
  // 后完成的一方卡死。
  function logic tx_tick();
    logic b = ftx.tx_tick();
    if (state == LT_LOCAL_RDY && peer_ready && ftx.frame_start) begin
      hold_frames++;
      if (hold_frames >= 3) state = LT_DONE;
    end
    return b;
  endfunction

  // 每 bit 时钟喂线采样；整帧字段解出后推进握手
  function void rx_tick(logic b);
    logic [1:0]  req_cm1, req_c0, req_cp1;
    logic [15:0] sts, upd;

    if (!frx.rx_tick(b)) return;

    frames_seen++;

    // --- 响应方：对收到的调整请求回执 ---
    req_cm1  = frx.coeff_update[1:0];
    req_c0   = frx.coeff_update[3:2];
    req_cp1  = frx.coeff_update[5:4];
    sts      = ftx.status_report;
    sts[1:0] = (req_cm1 == LT72_UPD_HOLD) ? LT72_ST_NOT_UPDATED
                                          : LT72_ST_UPDATED;
    sts[3:2] = (req_c0  == LT72_UPD_HOLD) ? LT72_ST_NOT_UPDATED
                                          : LT72_ST_UPDATED;
    sts[5:4] = (req_cp1 == LT72_UPD_HOLD) ? LT72_ST_NOT_UPDATED
                                          : LT72_ST_UPDATED;

    // --- 发起方：按对端回执推进本端训练轮次 ---
    peer_ready = frx.status_report[15];
    upd        = '0;
    case (state)
      LT_TRAIN_CM1: begin
        if (frx.status_report[1:0] == LT72_ST_UPDATED) begin
          tap_done = 1;
          state    = LT_TRAIN_C0;
          upd      = {10'b0, LT72_UPD_HOLD, LT72_UPD_INC, LT72_UPD_HOLD};
        end
        else upd = {10'b0, LT72_UPD_HOLD, LT72_UPD_HOLD, LT72_UPD_INC};
      end
      LT_TRAIN_C0: begin
        if (frx.status_report[3:2] == LT72_ST_UPDATED) begin
          tap_done = 2;
          state    = LT_TRAIN_CP1;
          upd      = {10'b0, LT72_UPD_INC, LT72_UPD_HOLD, LT72_UPD_HOLD};
        end
        else upd = {10'b0, LT72_UPD_HOLD, LT72_UPD_INC, LT72_UPD_HOLD};
      end
      LT_TRAIN_CP1: begin
        if (frx.status_report[5:4] == LT72_ST_UPDATED) begin
          tap_done = 3;
          state    = LT_LOCAL_RDY;
          sts[15]  = 1'b1;            // 本端接收就绪
          upd      = '0;              // 训练请求归 hold
        end
        else upd = {10'b0, LT72_UPD_INC, LT72_UPD_HOLD, LT72_UPD_HOLD};
      end
      LT_LOCAL_RDY: begin
        sts[15] = 1'b1;
        upd     = '0;
        // 保持窗由 tx_tick 按本端发帧数推进（见其注释）
      end
      default: begin
        sts[15] = 1'b1;
        upd     = '0;
      end
    endcase

    ftx.coeff_update  = upd;
    ftx.status_report = sts;
  endfunction

endclass

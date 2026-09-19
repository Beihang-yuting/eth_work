// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 73 自协商（AN，KR 电口建链第一步）
// 职责：
//   DME 层（an73_dme_tx_c / an73_dme_rx_c）：48bit 页 <-> 线上电平序列。
//     时序按 10.3125G bit tick 整数计数（由 svt VIP ETH_AN_CL73 波形
//     逆向标定，与 IEEE 802.3 73.5.1 一致）：
//       位胞 66 tick(6.4ns)，胞界跳变，bit=1 加 33 tick(3.2ns) 中点跳变；
//       页 = 48 数据胞 + 1 填充胞 + 尾部定界（静默-跳变-静默）；
//       页周期 3498 tick(339.2ns)。
//   仲裁层（an73_engine_c）：基页交换 FSM（能力检测 -> 应答检测 ->
//     完成应答 -> AN 完成）。完成后 is_done() 置位，BFM 切数据模式。
//     重新协商（restart()）：nonce 碰撞、应答检测中对端页不一致（对端
//     已重启）时引擎自调；数据模式下链路失效由 BFM 调（IEEE AN_GOOD 下
//     link_status 失效即回 TRANSMIT_DISABLE）。
// 依赖：无（纯行为级，BFM 每 bit 时钟调用 tx_tick/rx_tick）。
// 所有权：BFM 在 an_enable 时持有一个实例；reset() 清状态重新协商。
// 简化说明（记 TODO）：Next Page 交换未实现（NP=0）；优先级解析只按
//   本端单能力位（配置哪个速率就 advertise 哪个）；无 break_link 静默期；
//   Clause 72 链路训练在 lt_cl72（cfg.lt_enable，VIP 无 cl72）。
// -----------------------------------------------------------------------------

// 基页字段布局（IEEE 73.6，D0 先发）：
//   D[4:0]   Selector = 5'b00001（802.3）
//   D[9:5]   Echoed Nonce（应答对端的 Transmit Nonce）
//   D[12:10] C[2:0] Pause 能力
//   D13      RF（Remote Fault）
//   D14      Ack
//   D15      NP（Next Page）
//   D[20:16] Transmit Nonce
//   D[45:21] 技术能力 A[24:0]（A0=1000BASE-KX A1=10GBASE-KX4
//            A2=10GBASE-KR A3=40GBASE-KR4 ...）
//   D[47:46] FEC 能力 F0/F1
typedef struct packed {
  logic [1:0]  fec;          // D[47:46]
  logic [24:0] ability;      // D[45:21]
  logic [4:0]  tx_nonce;     // D[20:16]
  logic        np;           // D15
  logic        ack;          // D14
  logic        rf;           // D13
  logic [2:0]  pause;        // D[12:10]
  logic [4:0]  echoed_nonce; // D[9:5]
  logic [4:0]  selector;     // D[4:0]
} an73_page_t;

// AN 时序常量（bit tick；10.3125G 下 1 tick = 96.9697ps，实测 VIP
// 胞宽 6.4ns = 66 tick、半胞 3.2ns = 33 tick）
localparam int AN73_HALF_CELL  = 33;
localparam int AN73_CELL       = 66;
localparam int AN73_DATA_CELLS = 48;
localparam int AN73_PAGE_TICKS = 3498;   // 339.2ns（实测页周期）

function automatic logic [47:0] an73_pack(an73_page_t p);
  return p;   // packed struct：字段拼成 D47..D0
endfunction

function automatic an73_page_t an73_unpack(logic [47:0] d);
  an73_page_t p;
  p = d;
  return p;
endfunction

// ---------------- DME TX：页 -> 每 tick 线电平 ----------------

class an73_dme_tx_c;

  logic [47:0] page;            // 待发页（页边界锁存，可随时更新）
  bit          page_start;      // 本拍是页首（供引擎按"本端已发页数"计时）
  protected int          tick;
  protected logic        level;
  protected logic [47:0] cur;

  function new();
    reset();
  endfunction

  function void reset();
    tick       = 0;
    level      = 0;
    cur        = '0;
    page_start = 0;
  endfunction

  // 每 bit 时钟调用一次，返回线电平。
  // 页模板（tick 相对页首）：0/66/.../49*66 每胞界跳变；bit k=1 时
  // 66k+33 处加中点跳变；49*66+132 处尾定界跳变；PAGE_TICKS 回卷。
  function logic tx_tick();
    int k;
    page_start = (tick == 0);
    if (tick == 0) cur = page;

    // 胞界跳变覆盖 48 数据胞 + 1 填充胞（实测 VIP 末胞界 = 49*66=3234）
    if (tick <= (AN73_DATA_CELLS + 1) * AN73_CELL && tick % AN73_CELL == 0)
      level = ~level;
    else if (tick < AN73_DATA_CELLS * AN73_CELL &&
             tick % AN73_CELL == AN73_HALF_CELL) begin
      k = tick / AN73_CELL;
      if (cur[k]) level = ~level;
    end
    else if (tick == (AN73_DATA_CELLS + 1) * AN73_CELL + 4 * AN73_HALF_CELL)
      level = ~level;

    tick = (tick + 1) % AN73_PAGE_TICKS;
    return level;
  endfunction

endclass

// ---------------- DME RX：每 tick 线电平 -> 页 ----------------

// 解码策略：页间定界是两段静默（每段 132 tick）；连续两次"长静默后
// 跳变"即锁定页首胞界，其后按 tick 网格归类跳变（胞界/中点），中点
// 跳变置该位为 1。容差 ±8 tick 吸收对端时钟偏差。
class an73_dme_rx_c;

  localparam int GAP_MIN = 100;   // > 1.5 胞视为定界静默
  localparam int TOL     = 8;

  protected logic        prev;
  protected int          since_edge;
  protected int          in_page;    // -1 页外；>=0 页内 tick 计数
  protected logic [47:0] shift;
  protected int          gap_cnt;

  int pages_rx;

  function new();
    reset();
  endfunction

  function void reset();
    prev       = 0;
    since_edge = 0;
    in_page    = -1;
    gap_cnt    = 0;
    shift      = '0;
    pages_rx   = 0;
  endfunction

  // 每 bit 时钟喂一个采样；页解出时返回 1 并输出该页
  function bit rx_tick(logic b, output logic [47:0] page);
    bit got = 0;
    bit edge_now = (b !== prev);
    int pos, cell, frac;
    prev = b;

    if (in_page >= 0) begin
      if (edge_now) begin
        pos  = in_page;
        cell = pos / AN73_CELL;
        frac = pos % AN73_CELL;
        if (cell < AN73_DATA_CELLS &&
            frac >= AN73_HALF_CELL - TOL && frac <= AN73_HALF_CELL + TOL)
          shift[cell] = 1'b1;
        since_edge = 0;
      end
      in_page++;
      if (in_page == (AN73_DATA_CELLS + 1) * AN73_CELL) begin
        page     = shift;
        got      = 1;
        pages_rx++;
        in_page  = -1;
        gap_cnt  = 0;
        shift    = '0;
      end
    end
    else begin
      if (edge_now) begin
        if (since_edge >= GAP_MIN) gap_cnt++;
        else                       gap_cnt = 0;
        if (gap_cnt >= 2) begin
          in_page = 1;     // 本跳变 = 页首胞界（tick 0）
          gap_cnt = 0;
          shift   = '0;
        end
        since_edge = 0;
      end
    end

    since_edge++;
    return got;
  endfunction

endclass

// ---------------- 仲裁 FSM ----------------

class an73_engine_c;

  typedef enum { AN_ABILITY, AN_ACK, AN_COMPLETE, AN_DONE } an73_state_e;

  an73_dme_tx_c dme_tx;
  an73_dme_rx_c dme_rx;

  // 本端能力（BFM 按 cfg 配置；默认 A2 = 10GBASE-KR）
  logic [24:0] ability   = 25'h4;
  logic [4:0]  nonce     = 5'h05;   // 非零，避免与对端 nonce 碰撞
  logic [2:0]  pause_cap = 3'b011;

  // 观测
  int pages_seen;
  int restarts;             // 重新协商次数（nonce 碰撞/对端重启/链路失效）

  // COMPLETE_ACKNOWLEDGE 保持页数：进入时正在发的页不完整，须再发满 6 个
  // 完整 Ack 页（IEEE 73.10.4 要求 6~8 页；VIP svt_err_an73_ack_finished
  // 检查不足），故按页首计 7 次
  localparam int ACK_HOLD_PAGES = 7;

  // 一致性比较忽略 Ack（D14）与 Echoed Nonce（D[9:5]）：对端进入应答态
  // 时两者一起变化
  localparam logic [47:0] CMP_MASK = ~((48'h1 << 14) | (48'h1f << 5));

  protected an73_state_e   state;
  protected an73_page_t    tx_page;
  protected logic [47:0]   last_rx;
  protected logic [47:0]   ack_ref;     // 触发 ABILITY->ACK 的对端页（掩码后）
  protected int            match_cnt;
  protected int            hold_pages;

  function new();
    dme_tx = new();
    dme_rx = new();
    reset();
  endfunction

  function void reset();
    pages_seen = 0;
    tx_page          = '0;
    tx_page.selector = 5'b00001;
    tx_page.pause    = pause_cap;
    tx_page.ability  = ability;
    restart();
    restarts = 0;
  endfunction

  // 重新协商（IEEE TRANSMIT_DISABLE -> ABILITY_DETECT）：清仲裁状态、撤
  // Ack 与回显 nonce，DME 收发从页首重新开始。BFM 在数据模式链路失效时
  // 调用（AN_GOOD 下 link_status 失效即重协商）；nonce 碰撞与对端页不
  // 一致时引擎自调
  function void restart();
    state      = AN_ABILITY;
    match_cnt  = 0;
    hold_pages = 0;
    last_rx    = '0;
    ack_ref    = '0;
    tx_page.ack          = 1'b0;
    tx_page.echoed_nonce = '0;
    tx_page.tx_nonce     = nonce;
    dme_tx.reset();
    dme_rx.reset();
    dme_tx.page = an73_pack(tx_page);
    restarts++;
  endfunction

  function bit is_done();
    return state == AN_DONE;
  endfunction

  function string state_name();
    return state.name();
  endfunction

  // 每 bit 时钟：本 tick 应驱动的线电平
  // 每 bit 时钟：本 tick 应驱动的线电平。
  // AN_COMPLETE 的保持窗按"本端已发出页数"推进 —— 不能依赖对端继续
  // 发页：先完成的一方会切到下一阶段（LT/数据）而停发 DME，若按收到
  // 页数计时，后完成的一方将永久卡死（曾实测死锁）。
  function logic tx_tick();
    logic b = dme_tx.tx_tick();
    if (state == AN_COMPLETE && dme_tx.page_start) begin
      hold_pages++;
      if (hold_pages >= ACK_HOLD_PAGES) state = AN_DONE;
    end
    return b;
  endfunction

  // 每 bit 时钟：喂线采样，页完成时推进仲裁
  function void rx_tick(logic b);
    logic [47:0] pg;
    an73_page_t  rp;
    logic [47:0] cmp_new, cmp_old;

    if (!dme_rx.rx_tick(b, pg)) return;

    pages_seen++;
    rp = an73_unpack(pg);

    // 一致性判定忽略 Ack 位（cl73 匹配规则）
    cmp_new = pg      & ~(48'h1 << 14);
    cmp_old = last_rx & ~(48'h1 << 14);
    if (cmp_new == cmp_old) match_cnt++;
    else                    match_cnt = 1;
    last_rx = pg;

    case (state)
      AN_ABILITY: begin
        // nonce 碰撞（对端 Transmit Nonce 与本端相同，如环回到自身）：
        // 换 nonce 重新协商（IEEE nonce_match -> TRANSMIT_DISABLE）。
        // 与 ability_match 同样只认连续 3 页一致的稳定页（单页解码错不算）
        if (match_cnt >= 3 && rp.tx_nonce == nonce) begin
          // 随机换新 nonce（IEEE 为随机数）：固定递增会让同 nonce 的两端
          // 同步换值、永远碰撞
          logic [4:0] old = nonce;
          do nonce = $urandom_range(1, 31); while (nonce == old);
          restart();
          return;
        end
        // 连续 3 页一致且 selector 合法 = 能力检测通过，转应答
        if (match_cnt >= 3 && rp.selector == 5'b00001) begin
          tx_page.echoed_nonce = rp.tx_nonce;
          tx_page.ack          = 1'b1;
          dme_tx.page          = an73_pack(tx_page);
          ack_ref   = pg & CMP_MASK;
          state     = AN_ACK;
          match_cnt = 0;
        end
      end
      AN_ACK: begin
        // 对端稳定页内容变了（忽略 Ack/回显 nonce）= 对端已重启协商：本端
        // 随之重启（IEEE ACKNOWLEDGE_DETECT 的 consistency_match 失败）
        if (match_cnt >= 3 && (pg & CMP_MASK) != ack_ref) begin
          restart();
          return;
        end
        // 对端也置 Ack 且回显了我方 nonce = 双向确认
        if (rp.ack && rp.echoed_nonce == nonce && match_cnt >= 3) begin
          state      = AN_COMPLETE;
          hold_pages = 0;
        end
      end
      AN_COMPLETE: ;   // 保持窗由 tx_tick 按本端发页数推进（见其注释）
      default: ;
    endcase
  endfunction

endclass

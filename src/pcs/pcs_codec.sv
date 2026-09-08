// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— Clause 49 64b/66b 编码器与解码器
// 职责：在一拍 XGMII（xgmii64_t）与一个 66b 块（block66_t）之间做无状态
//       双向转换。编码侧限定生成本环境实际使用的块型集合
//       （全数据 / 全控制 / S0 起始 / T0..T7 终止），解码侧接受同一集合，
//       其余块型一律解码为 XGMII 错误字符并返回失败，供协议完整性检查。
// 依赖：pcs_types.sv（块类型码与数据结构）。
// 所有权：纯静态函数类，无实例状态；调用方无需管理生命周期。
// -----------------------------------------------------------------------------

// 为什么用无状态静态函数而不是 module：编码规则本身逐块独立，做成纯函数
// 后单元测试可以直接枚举/随机打（XGMII 拍 -> 块 -> XGMII 拍）闭环比对，
// 不需要时钟与复位；时序行为统一放在 phy_bfm 中处理。
class pcs_codec;

  // ---------------- 编码：XGMII 一拍 -> 66b 块 ----------------
  //
  // 输入：w        —— 一拍 64bit XGMII（data + ctl）
  // 输出：返回值   —— 对应的 66b 块
  // 失败路径：无法归入合法模式的组合（如 S 不在 lane0、T 后出现数据）
  //           编码为全 ERROR 控制块，不抛断言 —— 保持 BFM 在异常激励下
  //           仍能持续输出码流，错误交由对端解码/记分板暴露。
  static function block66_t encode(xgmii64_t w);
    block66_t b;
    int t_lane;

    // 全数据块：8 字节均无控制位
    if (w.ctl == 8'h00) begin
      b.sync    = SYNC_DATA;
      b.payload = w.data;
      return b;
    end

    // 全控制块：8 字节全为控制字符且均为 IDLE
    if (w.ctl == 8'hff) begin
      bit all_idle = 1;
      for (int i = 0; i < 8; i++)
        if (w.data[i*8 +: 8] != XGMII_IDLE) all_idle = 0;
      if (all_idle) begin
        b.sync    = SYNC_CTRL;
        b.payload = {56'h0, BT_CTRL};   // 8 个 CC_IDLE(0) 已隐含为 0
        return b;
      end
    end

    // 帧起始块：lane0 为 START，其余 7 字节为数据
    if (w.ctl == 8'h01 && w.data[7:0] == XGMII_START) begin
      b.sync    = SYNC_CTRL;
      b.payload = {w.data[63:8], BT_START0};
      return b;
    end

    // 帧终止块：lane t 为 TERM，之前全数据、之后全 IDLE
    t_lane = -1;
    for (int i = 0; i < 8; i++)
      if (w.ctl[i] && w.data[i*8 +: 8] == XGMII_TERM) begin t_lane = i; break; end

    if (t_lane >= 0) begin
      bit shape_ok = 1;

      // T 之前必须是数据、之后必须是 IDLE 控制字符
      for (int i = 0; i < t_lane; i++)
        if (w.ctl[i]) shape_ok = 0;
      for (int i = t_lane + 1; i < 8; i++)
        if (!w.ctl[i] || w.data[i*8 +: 8] != XGMII_IDLE) shape_ok = 0;

      if (shape_ok) begin
        b.sync    = SYNC_CTRL;
        b.payload = '0;
        b.payload[7:0] = term_bt(t_lane);

        // T 前的数据字节紧跟块类型码放置；T 后 C 码全 0（IDLE），无需填充
        for (int i = 0; i < t_lane; i++)
          b.payload[8 + i*8 +: 8] = w.data[i*8 +: 8];
        return b;
      end
    end

    // 兜底：非法组合编码为全 ERROR 控制块
    return error_block();
  endfunction

  // ---------------- 解码：66b 块 -> XGMII 一拍 ----------------
  //
  // 输入：b         —— 66b 块
  // 输出：w_out     —— 解码出的 XGMII 拍
  // 返回：1 = 块合法；0 = 同步头或块型非法（w_out 置为全 ERROR）。
  //       返回值供 monitor 做协议完整性统计，解码本身不中断。
  static function bit decode(block66_t b, output xgmii64_t w_out);
    byte unsigned bt;
    int t_lane;

    if (b.sync == SYNC_DATA) begin
      w_out.ctl  = 8'h00;
      w_out.data = b.payload;
      return 1;
    end

    if (b.sync != SYNC_CTRL) begin
      w_out = xgmii_all_error();
      return 0;
    end

    bt = b.payload[7:0];

    // 全控制块：仅接受全 IDLE（C 码非 0，含 ERROR C 码，一律按非法块处理）
    if (bt == BT_CTRL) begin
      if (b.payload[63:8] != 56'h0) begin
        w_out = xgmii_all_error();
        return 0;
      end
      w_out = xgmii_all_idle();
      return 1;
    end

    if (bt == BT_START0) begin
      w_out.ctl        = 8'h01;
      w_out.data[7:0]  = XGMII_START;
      w_out.data[63:8] = b.payload[63:8];
      return 1;
    end

    t_lane = term_lane(bt);
    if (t_lane >= 0) begin
      w_out = xgmii_all_idle();
      for (int i = 0; i < t_lane; i++) begin
        w_out.ctl[i]          = 1'b0;
        w_out.data[i*8 +: 8]  = b.payload[8 + i*8 +: 8];
      end
      w_out.data[t_lane*8 +: 8] = XGMII_TERM;
      return 1;
    end

    // 未支持/非法块型
    w_out = xgmii_all_error();
    return 0;
  endfunction

  // ---------------- 内部辅助 ----------------

  // T 所在 lane -> 块类型码。调用方保证 lane 在 0..7 内。
  static function byte unsigned term_bt(int lane);
    case (lane)
      0: return BT_TERM0;  1: return BT_TERM1;
      2: return BT_TERM2;  3: return BT_TERM3;
      4: return BT_TERM4;  5: return BT_TERM5;
      6: return BT_TERM6;  default: return BT_TERM7;
    endcase
  endfunction

  // 块类型码 -> T 所在 lane；非终止块型返回 -1
  static function int term_lane(byte unsigned bt);
    case (bt)
      BT_TERM0: return 0;  BT_TERM1: return 1;
      BT_TERM2: return 2;  BT_TERM3: return 3;
      BT_TERM4: return 4;  BT_TERM5: return 5;
      BT_TERM6: return 6;  BT_TERM7: return 7;
      default:  return -1;
    endcase
  endfunction

  // 全 ERROR 控制块（编码侧兜底输出；解码侧会将其判为非法块并计数）
  static function block66_t error_block();
    block66_t b;
    b.sync    = SYNC_CTRL;
    b.payload = {56'h0, BT_CTRL};
    for (int i = 0; i < 8; i++)
      b.payload[8 + i*7 +: 7] = CC_ERROR;
    return b;
  endfunction

  // 全 ERROR XGMII 拍（解码侧兜底输出）
  static function xgmii64_t xgmii_all_error();
    xgmii64_t w;
    w.ctl = 8'hff;
    for (int i = 0; i < 8; i++) w.data[i*8 +: 8] = XGMII_ERROR;
    return w;
  endfunction

endclass

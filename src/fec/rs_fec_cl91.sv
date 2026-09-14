// -----------------------------------------------------------------------------
// 所属：eth_work/src/fec —— Clause 91 RS-FEC：RS(528,514) over GF(2^10)
// 职责：
//   GF(2^10) 域运算（本原多项式 x^10+x^3+1 = 0x409）的 exp/log 表；
//   rs91_encoder_c：514 个 10bit 信息符号 -> 528 符号码字（系统码，
//     14 个校验符号在尾部），纠错能力 t = 7 个符号；
//   rs91_decoder_c：伴随式 -> Berlekamp-Massey 求错误定位多项式 ->
//     Chien 搜索定根 -> Forney 求错值；超能力标记不可纠。
// 依赖：无（纯行为级，供 BFM/单测调用）。
// 所有权：BFM 每方向各持一个实例（RS-FEC 模式）；单测直接构造。
// 与 Clause 74（fec_cl74.sv）的关系：不同的码，互不替代 —— cl74 是
//   二元 fire code (2112,2080) 纠突发；cl91 是符号级 RS 码，纠 7 个
//   10bit 符号（覆盖 ~70bit 突发），100G/200G 用。
//   256B/257B 转码（91.5.2.5）见本文件末 rs91_transcoder_*；lane 分发/
//   交织随 100G 多 lane 一并做。VIP 的 RS-FEC 只绑定 100G CSBI 接口
//   （enable_rs_fec + CSBI 2/4 lane），故交叉验证也随 100G 一并做。
// -----------------------------------------------------------------------------

localparam int RS91_M      = 10;                 // 符号位宽
localparam int RS91_N      = 528;                // 码字符号数
localparam int RS91_K      = 514;                // 信息符号数
localparam int RS91_PARITY = RS91_N - RS91_K;    // 14
localparam int RS91_T      = RS91_PARITY / 2;    // 7 符号纠错能力
localparam int RS91_FIELD  = 1 << RS91_M;        // 1024
localparam int RS91_PRIM   = 'h409;              // x^10 + x^3 + 1

typedef logic [RS91_M-1:0] rs91_sym_t;

// GF(2^10) 表：exp_t[i] = α^i（周期 1023，尾部复制一段免取模），
// log_t[x] = 使 α^i = x 的 i。静态构造一次。
class rs91_gf_c;

  static rs91_sym_t exp_t[2046];
  static int        log_t[1024];
  static bit        built = 0;

  static function void build();
    int x;
    if (built) return;
    x = 1;
    for (int i = 0; i < 1023; i++) begin
      exp_t[i] = x[RS91_M-1:0];
      log_t[x] = i;
      x = x << 1;
      if (x & RS91_FIELD) x = x ^ RS91_PRIM;   // 越界即模本原多项式
    end
    for (int i = 1023; i < 2046; i++) exp_t[i] = exp_t[i-1023];
    log_t[0] = -1;                              // 0 无对数
    built    = 1;
  endfunction

  static function rs91_sym_t mul(rs91_sym_t a, rs91_sym_t b);
    build();
    if (a == 0 || b == 0) return '0;
    return exp_t[log_t[a] + log_t[b]];
  endfunction

  static function rs91_sym_t div(rs91_sym_t a, rs91_sym_t b);
    build();
    if (a == 0) return '0;
    return exp_t[(log_t[a] - log_t[b] + 1023) % 1023];
  endfunction

  // α^p（p 可为负）
  static function rs91_sym_t alpha_pow(int p);
    build();
    return exp_t[((p % 1023) + 1023) % 1023];
  endfunction

endclass

// ---------------- 参数化 RS(N,K) over GF(2^10) ----------------
//
// cl91 用 RS(528,514)（t=7），200GBASE-R（Clause 119）用 RS(544,514)
//（KP4，t=15）。生成多项式 g(x) = Π_{i=0..P-1} (x - α^i)，P = N-K；
// 系统码：cw[0..K-1] = 信息符号，cw[K..N-1] = 校验符号（余数高位在前）。

class rs10_encoder_c #(int N = 528, int K = 514);

  localparam int P = N - K;

  protected rs91_sym_t g[P+1];

  function new();
    rs91_sym_t tmp[P+1];
    rs91_gf_c::build();
    foreach (g[i]) g[i] = '0;
    g[0] = 1;
    for (int i = 0; i < P; i++) begin
      foreach (tmp[j]) tmp[j] = '0;
      for (int j = 0; j <= i; j++) begin
        tmp[j+1] = tmp[j+1] ^ g[j];                                    // *x
        tmp[j]   = tmp[j]   ^ rs91_gf_c::mul(g[j],
                                             rs91_gf_c::alpha_pow(i)); // *α^i
      end
      foreach (g[j]) g[j] = tmp[j];
    end
  endfunction

  function void encode(input rs91_sym_t data[K], output rs91_sym_t cw[N]);
    rs91_sym_t par[P];
    rs91_sym_t fb;

    foreach (par[i]) par[i] = '0;
    // LFSR 除法：逐个信息符号移入，par 保持余数
    for (int i = 0; i < K; i++) begin
      fb = data[i] ^ par[P-1];
      for (int j = P-1; j > 0; j--)
        par[j] = par[j-1] ^ rs91_gf_c::mul(fb, g[j]);
      par[0] = rs91_gf_c::mul(fb, g[0]);
    end

    for (int i = 0; i < K; i++) cw[i] = data[i];
    for (int i = 0; i < P; i++) cw[K + i] = par[P-1-i];   // 余数高位在前
  endfunction

endclass

class rs10_decoder_c #(int N = 528, int K = 514);

  localparam int P = N - K;
  localparam int T = P / 2;

  // 统计
  int corrected_count;      // 成功纠正的码字数
  int uncorrectable_count;  // 判定不可纠的码字数
  int sym_err_corrected;    // 累计纠正的符号数

  function new();
    rs91_gf_c::build();
    reset();
  endfunction

  function void reset();
    corrected_count     = 0;
    uncorrectable_count = 0;
    sym_err_corrected   = 0;
  endfunction

  // 就地纠正 cw；返回 1 = 码字有效（无错或已纠正），
  // 0 = 超出纠错能力（cw 不保证正确，上层按不可纠处理）
  function bit decode(ref rs91_sym_t cw[N]);
    rs91_sym_t synd[P];
    rs91_sym_t lambda[T+1];
    rs91_sym_t bpoly[T+1];
    rs91_sym_t tpoly[T+1];
    rs91_sym_t omega[P];
    int        err_pos[T];
    rs91_sym_t err_val, delta, d, dinv, xi, num, den, tmp;
    int        L, m, nerr, pw;
    bit        has_err;

    // --- 伴随式 S_i = cw(α^i)，i = 0..P-1 ---
    has_err = 0;
    for (int i = 0; i < P; i++) begin
      tmp = '0;
      for (int j = 0; j < N; j++)
        tmp = tmp ^ rs91_gf_c::mul(cw[j], rs91_gf_c::alpha_pow(i * (N-1-j)));
      synd[i] = tmp;
      if (tmp != 0) has_err = 1;
    end
    if (!has_err) return 1;

    // --- Berlekamp-Massey ---
    foreach (lambda[i]) lambda[i] = '0;
    foreach (bpoly[i])  bpoly[i]  = '0;
    lambda[0] = 1;
    bpoly[0]  = 1;
    L = 0;
    m = 1;
    d = 1;

    for (int n = 0; n < P; n++) begin
      delta = synd[n];
      for (int i = 1; i <= L; i++)
        delta = delta ^ rs91_gf_c::mul(lambda[i], synd[n-i]);

      if (delta == 0) begin
        m++;
      end
      else if (2*L <= n) begin
        foreach (tpoly[i]) tpoly[i] = lambda[i];
        dinv = rs91_gf_c::div(delta, d);
        for (int i = 0; i + m <= T; i++)
          lambda[i+m] = lambda[i+m] ^ rs91_gf_c::mul(dinv, bpoly[i]);
        L = n + 1 - L;
        foreach (bpoly[i]) bpoly[i] = tpoly[i];
        d = delta;
        m = 1;
      end
      else begin
        dinv = rs91_gf_c::div(delta, d);
        for (int i = 0; i + m <= T; i++)
          lambda[i+m] = lambda[i+m] ^ rs91_gf_c::mul(dinv, bpoly[i]);
        m++;
      end
    end

    if (L > T) begin
      uncorrectable_count++;
      return 0;
    end

    // --- Chien 搜索：lambda(α^-pw) == 0 的位置即错误位置 ---
    nerr = 0;
    for (int j = 0; j < N; j++) begin
      pw  = N - 1 - j;
      tmp = lambda[0];
      for (int i = 1; i <= L; i++)
        tmp = tmp ^ rs91_gf_c::mul(lambda[i], rs91_gf_c::alpha_pow(-i * pw));
      if (tmp == 0) begin
        if (nerr >= T) begin
          uncorrectable_count++;
          return 0;
        end
        err_pos[nerr] = j;
        nerr++;
      end
    end

    // 根数与 lambda 次数不符 = 超出纠错能力（漏根/伪根）
    if (nerr != L) begin
      uncorrectable_count++;
      return 0;
    end

    // --- omega(x) = S(x)·lambda(x) mod x^P ---
    foreach (omega[i]) omega[i] = '0;
    for (int i = 0; i < P; i++)
      for (int j = 0; j <= L; j++)
        if (i + j < P)
          omega[i+j] = omega[i+j] ^ rs91_gf_c::mul(synd[i], lambda[j]);

    // --- Forney：e = X·omega(X^-1) / lambda'(X^-1)（根从 α^0 起，b0=0）---
    for (int k = 0; k < nerr; k++) begin
      pw  = N - 1 - err_pos[k];
      xi  = rs91_gf_c::alpha_pow(pw);
      num = '0;
      for (int i = 0; i < P; i++)
        num = num ^ rs91_gf_c::mul(omega[i], rs91_gf_c::alpha_pow(-i * pw));
      // GF(2) 上导数只保留奇次项
      den = '0;
      for (int i = 1; i <= L; i += 2)
        den = den ^ rs91_gf_c::mul(lambda[i], rs91_gf_c::alpha_pow(-(i-1) * pw));
      if (den == 0) begin
        uncorrectable_count++;
        return 0;
      end
      // X_k 因子不可省（漏乘会得到错误的错值，纠错后码字仍不对）
      err_val        = rs91_gf_c::mul(xi, rs91_gf_c::div(num, den));
      cw[err_pos[k]] = cw[err_pos[k]] ^ err_val;
    end

    corrected_count++;
    sym_err_corrected += nerr;
    return 1;
  endfunction

endclass

// cl91 RS(528,514) 与 200G KP4 RS(544,514) 的特化名
typedef rs10_encoder_c #(528, 514) rs91_encoder_c;
typedef rs10_decoder_c #(528, 514) rs91_decoder_c;
typedef rs10_encoder_c #(544, 514) rs544_encoder_c;
typedef rs10_decoder_c #(544, 514) rs544_decoder_c;

// ---------------- 256B/257B 转码（Clause 91.5.2.5）----------------
//
// 目的：RS-FEC 承载 257bit 块而非 66bit 块 —— 4 个 66b 块 (264 bit)
// 压成 257 bit，省下的 7 bit 给 RS 校验开销腾带宽。
// 位预算（无损的关键）：
//   · 4 块全数据：4 个同步头(8bit) 压成 1 个标志位 -> 正好省 7 bit，
//     净荷 4×64 原样保留 = 1 + 256 = 257。
//   · 含控制块：标志位 + 4 个"数据/控制"指示位（共 5bit，替代 8bit
//     同步头，省 3）；每个控制块的 8bit 块类型字段用 4bit 码表示
//     （Clause 49 合法块类型仅 13 种），每块再省 4 bit。最坏情形
//     （1 控制块）总省 3+4 = 7 bit 正好够，其余情形有富余（补零）。
// 与规范的差异（记 TODO）：规范对控制块字段有更细的重排位序，本实现
//   只保证"4 块 <-> 257bit 双向唯一且无损"，与真实 DUT/VIP 对接前须
//   按 91.5.2.5 精确位序核对。

// 块类型 <-> 4bit 码映射（Clause 49 合法块类型 13 种）
function automatic logic [3:0] rs91_bt_encode(byte unsigned bt);
  case (bt)
    BT_CTRL:   return 4'd0;
    BT_START0: return 4'd1;
    BT_START4: return 4'd2;
    BT_OSET0:  return 4'd3;
    BT_OSET2:  return 4'd4;
    BT_TERM0:  return 4'd5;
    BT_TERM1:  return 4'd6;
    BT_TERM2:  return 4'd7;
    BT_TERM3:  return 4'd8;
    BT_TERM4:  return 4'd9;
    BT_TERM5:  return 4'd10;
    BT_TERM6:  return 4'd11;
    BT_TERM7:  return 4'd12;
    default:   return 4'd15;   // 非法块类型（透传失败，由上层计数）
  endcase
endfunction

function automatic byte unsigned rs91_bt_decode(logic [3:0] c);
  case (c)
    4'd0:  return BT_CTRL;
    4'd1:  return BT_START0;
    4'd2:  return BT_START4;
    4'd3:  return BT_OSET0;
    4'd4:  return BT_OSET2;
    4'd5:  return BT_TERM0;
    4'd6:  return BT_TERM1;
    4'd7:  return BT_TERM2;
    4'd8:  return BT_TERM3;
    4'd9:  return BT_TERM4;
    4'd10: return BT_TERM5;
    4'd11: return BT_TERM6;
    4'd12: return BT_TERM7;
    default: return 8'h00;     // 非法码
  endcase
endfunction

// 4 个 66b 块 -> 257 bit（[0] = 全数据标志）
function automatic void rs91_transcode_enc(input block66_t b[4],
                                           output logic [256:0] t);
  logic [3:0] is_data;
  int         pos;
  t = '0;
  for (int i = 0; i < 4; i++) is_data[i] = (b[i].sync == SYNC_DATA);

  if (&is_data) begin
    t[0] = 1'b1;
    for (int i = 0; i < 4; i++) t[1 + i*64 +: 64] = b[i].payload;
  end
  else begin
    t[0]     = 1'b0;
    t[4:1]   = is_data;
    pos      = 5;
    for (int i = 0; i < 4; i++) begin
      if (is_data[i]) begin
        t[pos +: 64] = b[i].payload;      // 数据块原样 64 bit
        pos += 64;
      end
      else begin
        t[pos +: 4]  = rs91_bt_encode(b[i].payload[7:0]);   // 类型压 4bit
        t[pos+4 +: 56] = b[i].payload[63:8];                // 其余 56 bit
        pos += 60;
      end
    end
  end
endfunction

// 257 bit -> 4 个 66b 块
function automatic void rs91_transcode_dec(input logic [256:0] t,
                                           output block66_t b[4]);
  logic [3:0] is_data;
  int         pos;
  if (t[0]) begin
    for (int i = 0; i < 4; i++) begin
      b[i].sync    = SYNC_DATA;
      b[i].payload = t[1 + i*64 +: 64];
    end
  end
  else begin
    is_data = t[4:1];
    pos     = 5;
    for (int i = 0; i < 4; i++) begin
      if (is_data[i]) begin
        b[i].sync    = SYNC_DATA;
        b[i].payload = t[pos +: 64];
        pos += 64;
      end
      else begin
        b[i].sync    = SYNC_CTRL;
        b[i].payload = {t[pos+4 +: 56], rs91_bt_decode(t[pos +: 4])};
        pos += 60;
      end
    end
  end
endfunction

// ---------------- 码流封装：66b 块 <-> RS 码字比特流 ----------------
//
// 组织方式（与 cl74 的做法同构，便于 BFM 复用同一套弹性/对齐骨架）：
//   20 个 257bit 转码块 = 5140 bit = 514 个 10bit 符号，正好填满
//   RS(528,514) 的信息区；编码后 528 符号 = 5280 bit 上线。
//   即每 80 个 66b 块（20 组 × 4 块）产出一个 5280bit 码字。
// 对齐：码字级 PN 加扰（复用 cl74 的思路：消除码字周期性图案），
//   解码侧按"连续 N 个可纠码字"判锁，滑位重试。
localparam int RS91_GROUPS   = 20;                     // 每码字的 257b 组数
localparam int RS91_BLOCKS   = RS91_GROUPS * 4;        // 80 个 66b 块
localparam int RS91_CW_BITS  = RS91_N * RS91_M;        // 5280 bit

// 码字级 PN 加扰（与 cl74 同构：x^11+x^9+1，每码字重启）
function automatic void rs91_pn_xor(ref logic cw[RS91_CW_BITS]);
  logic [10:0] lfsr = 11'h7FF;
  for (int i = 0; i < RS91_CW_BITS; i++) begin
    logic fb = lfsr[10] ^ lfsr[8];
    cw[i] = cw[i] ^ fb;
    lfsr  = {lfsr[9:0], fb};
  end
endfunction

class rs91_fec_encoder_c;

  protected block66_t     blk_q[$];
  protected rs91_encoder_c enc;

  function new();
    enc = new();
  endfunction

  function void reset();
    blk_q.delete();
  endfunction

  // 输入一个 66b 块；集满 80 块产出一个 5280bit 码字并返回 1
  function bit push_block(block66_t b, output logic cw_out[RS91_CW_BITS]);
    blk_q.push_back(b);
    if (blk_q.size() < RS91_BLOCKS) return 0;

    begin
      block66_t    grp[4];
      logic [256:0] t257;
      logic        msg[RS91_K * RS91_M];
      rs91_sym_t   data[RS91_K];
      rs91_sym_t   cw[RS91_N];
      int          idx = 0;

      // 80 块 -> 20 组 257bit -> 5140 bit 信息位流
      for (int g = 0; g < RS91_GROUPS; g++) begin
        for (int i = 0; i < 4; i++) grp[i] = blk_q[g*4 + i];
        rs91_transcode_enc(grp, t257);
        for (int i = 0; i < 257; i++) msg[idx++] = t257[i];
      end
      blk_q.delete();

      // 比特流 -> 10bit 符号（MSB 先，与上线顺序一致）
      for (int i = 0; i < RS91_K; i++) begin
        rs91_sym_t sym = '0;
        for (int j = 0; j < RS91_M; j++)
          sym[RS91_M-1-j] = msg[i*RS91_M + j];
        data[i] = sym;
      end

      enc.encode(data, cw);

      for (int i = 0; i < RS91_N; i++)
        for (int j = 0; j < RS91_M; j++)
          cw_out[i*RS91_M + j] = cw[i][RS91_M-1-j];

      rs91_pn_xor(cw_out);
    end
    return 1;
  endfunction

endclass

class rs91_fec_decoder_c;

  localparam int LOCK_CLEAN = 2;    // 连续干净码字数判锁

  protected logic          bitbuf[$];
  protected bit            locked;
  protected int            clean_cnt;
  protected rs91_decoder_c dec;

  // 统计
  int slip_count;
  int corrected_count;
  int uncorrectable_count;

  function new();
    dec = new();
    reset();
  endfunction

  function void reset();
    bitbuf.delete();
    locked              = 0;
    clean_cnt           = 0;
    slip_count          = 0;
    corrected_count     = 0;
    uncorrectable_count = 0;
    dec.reset();
  endfunction

  function bit is_locked();
    return locked;
  endfunction

  // 喂一个线路 bit；凑满一个码字即尝试译码。
  // 成功（无错或已纠）则输出 80 个 66b 块并返回 1；未锁定时失败即
  // 滑一位重试（与 cl74 同构）。
  function bit push_bit(logic b, output block66_t blks[RS91_BLOCKS]);
    logic      cw_bits[RS91_CW_BITS];
    rs91_sym_t cw[RS91_N];
    logic      msg[RS91_K * RS91_M];
    block66_t  grp[4];
    logic [256:0] t257;
    bit        ok;
    int        idx;

    bitbuf.push_back(b);
    if (bitbuf.size() < RS91_CW_BITS) return 0;

    for (int i = 0; i < RS91_CW_BITS; i++) cw_bits[i] = bitbuf[i];
    rs91_pn_xor(cw_bits);

    for (int i = 0; i < RS91_N; i++) begin
      rs91_sym_t sym = '0;
      for (int j = 0; j < RS91_M; j++)
        sym[RS91_M-1-j] = cw_bits[i*RS91_M + j];
      cw[i] = sym;
    end

    ok = dec.decode(cw);

    if (!ok) begin
      uncorrectable_count++;
      if (!locked) begin
        // 未锁定：候选位置错，滑一位重试
        void'(bitbuf.pop_front());
        slip_count++;
        clean_cnt = 0;
        return 0;
      end
      // 已锁定：整码字丢弃（上层按丢块处理），保持码字边界
      bitbuf.delete();
      return 0;
    end

    corrected_count++;
    if (!locked) begin
      clean_cnt++;
      if (clean_cnt >= LOCK_CLEAN) locked = 1;
      bitbuf.delete();
      return 0;             // 锁定过程中的码字不向上交付
    end
    bitbuf.delete();

    // 符号 -> 信息比特 -> 20 组 257bit -> 80 个 66b 块
    idx = 0;
    for (int i = 0; i < RS91_K; i++)
      for (int j = 0; j < RS91_M; j++)
        msg[idx++] = cw[i][RS91_M-1-j];

    for (int g = 0; g < RS91_GROUPS; g++) begin
      for (int i = 0; i < 257; i++) t257[i] = msg[g*257 + i];
      rs91_transcode_dec(t257, grp);
      for (int i = 0; i < 4; i++) blks[g*4 + i] = grp[i];
    end
    return 1;
  endfunction

endclass

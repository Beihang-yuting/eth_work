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
//   码流层（本文件后半）：256B/257B 转码 + AM + 符号分发，1 条 FEC lane
//   （25GBASE-R，Clause 108；VIP ETH_25G_SERIAL + enable_xxvsbi_lsbi_rs_fec）
//   或 4 条（100GBASE-R，Clause 91；VIP ETH_CSBI_4_LANE + enable_rs_fec +
//   1bit 宽度 = 4 条串行 lane）。布局全部由 VIP 实抓码流标定，见各段注释。
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

// ---------------- 256B/257B 转码（RS-FEC 形态）----------------
//
// 布局与 Clause 119（pcs_cl119.sv）相同：t[0]=1 表示 4 块全数据；否则
// t[4:1] 为各块标志（1=数据、0=控制），仅首个控制块的 8bit 类型压成低 4 位
// 原位替换。与 200G 的差异两处，均由 svt VIP（ETH_25G_SERIAL + RS-FEC、
// ETH_CSBI_4_LANE + RS-FEC）实抓码流标定：
//   1. 输入是 PCS 已加扰的 66b 块（加扰在 66b 层；AM 不加扰、不推进加扰器），
//      首个控制块保留的是"加扰后"的低 4 位。接收端须按加扰历史解出低半字节
//      -> 查表得块类型 -> 再加扰复原被丢弃的高 4 位（见 rs91_xdec_c）。
//      实测：25G 996/996 组、100G 1674/1674 组吻合，全流解扰后块全部正确。
//   2. 头部 5 位再与 t[12:8] 异或（t[4:0] ^= t[12:8]），使头部随加扰数据
//      跳变。实测：全控制组去异或后头部恒为 0_0000（25G 220 组、100G 300 组）。
//      异或源 t[12:8] 自身不变，任何标志组合下接收端都可先去异或再解析。
function automatic void rs91_transcode_enc(input block66_t b[4],
                                           output logic [256:0] t);
  logic [3:0] is_data;
  int pos, first_c;
  t = '0;
  for (int i = 0; i < 4; i++) is_data[i] = (b[i].sync == SYNC_DATA);
  if (&is_data) begin
    t[0] = 1'b1;
    for (int i = 0; i < 4; i++) t[1 + 64*i +: 64] = b[i].payload;
  end
  else begin
    t[0]    = 1'b0;
    t[4:1]  = is_data;
    first_c = -1;
    for (int i = 0; i < 4; i++) if (!is_data[i] && first_c < 0) first_c = i;
    pos = 5;
    for (int i = 0; i < 4; i++) begin
      if (i == first_c) begin
        t[pos +: 4]    = b[i].payload[3:0];     // 加扰后的低 4 位
        t[pos+4 +: 56] = b[i].payload[63:8];
        pos += 60;
      end
      else begin
        t[pos +: 64] = b[i].payload;
        pos += 64;
      end
    end
  end
  t[4:0] = t[4:0] ^ t[12:8];
endfunction

// 257b -> 4 个（已加扰）66b 块。有状态：保存最近 58 个加扰 payload 位，
// 用于复原首个控制块被丢弃的类型高 4 位；跨组、跨码字连续（AM 区不经过
// 这里）。对齐/重锁后须 reset()，其后首个控制块可能复原错（历史不足），
// 由 BFM 的解扰热身块机制吸收。
class rs91_xdec_c;

  protected logic [57:0] h;      // h[0] = 最近一个加扰位

  function new();
    h = '0;
  endfunction

  function void reset();
    h = '0;
  endfunction

  protected function void take(logic y);
    h = {h[56:0], y};
  endfunction

  function void decode(input logic [256:0] tin, output block66_t b[4]);
    logic [256:0] t;
    logic [3:0]   is_data;
    int           pos, first_c;
    t      = tin;
    t[4:0] = t[4:0] ^ t[12:8];
    if (t[0]) begin
      for (int i = 0; i < 4; i++) begin
        b[i].sync    = SYNC_DATA;
        b[i].payload = t[1 + 64*i +: 64];
        for (int k = 0; k < 64; k++) take(b[i].payload[k]);
      end
      return;
    end
    is_data = t[4:1];
    first_c = -1;
    for (int i = 0; i < 4; i++) if (!is_data[i] && first_c < 0) first_c = i;
    pos = 5;
    for (int i = 0; i < 4; i++) begin
      b[i].sync = is_data[i] ? SYNC_DATA : SYNC_CTRL;
      if (i == first_c) begin
        logic [63:0]  y;
        logic [3:0]   dn;
        byte unsigned bt;
        y       = '0;
        y[3:0]  = t[pos +: 4];
        y[63:8] = t[pos+4 +: 56];
        // 低 4 位解扰 -> 块类型 -> 高 4 位按同一加扰关系重新生成
        for (int k = 0; k < 4; k++) begin
          dn[k] = y[k] ^ h[38] ^ h[57];
          take(y[k]);
        end
        bt = bt_from_low_nibble(dn);
        for (int k = 4; k < 8; k++) begin
          y[k] = bt[k] ^ h[38] ^ h[57];
          take(y[k]);
        end
        for (int k = 8; k < 64; k++) take(y[k]);
        b[i].payload = y;
        pos += 60;
      end
      else begin
        b[i].payload = t[pos +: 64];
        for (int k = 0; k < 64; k++) take(b[i].payload[k]);
        pos += 64;
      end
    end
  endfunction

endclass

// ---------------- RS-FEC 码流（Clause 91 / Clause 108）----------------
//
// 布局（VIP 实抓标定，伴随式全零 + 转码/AM/BIP 逐项吻合）：
//   · 每码字信息区 20 个 257b 组 = 514 符号；10bit 符号 LSB 先上线；无码字
//     级加扰（跳变密度由 66b 层加扰保证）；
//   · FEC lane：1 条（25GBASE-R，Clause 108）或 4 条（100GBASE-R，
//     Clause 91；码字第 i 个符号 -> lane i%4）；
//   · AM 周期 16 码字（VIP xxvsbi_rs_fec_mode_align_timer 默认 16；100G 等效
//     每 PCS lane 64 块 = csbi_100g_align_timer 默认 64）；周期首码字信息区
//     以 AM 开头：
//       25G：1 个 257b 常量组（RS108_AM）；
//       100G：20 个 PCS lane AM（BIP 由 mld_tx_c 按 PCS lane 计算，已用 VIP
//         码流验证 20/20）按 FEC lane 重排 —— lane l 依次承载 PCS lane l、
//         4+l、8+l、12+l、16+l 的 AM；PCS lane 1~3 / 17~19 的固定字节换成
//         lane 0 / 16 的（BIP 保留）；4 条 320bit 子流按 10bit 符号交织成
//         1280bit，再加 5 位填充（00101 与 11010 逐 AM 交替）= 1285bit；
//   · 每周期数据块：25G 319×4 = 1276 块；100G 1260 块（与 MLD 周期一致）。
// 标准 AM 周期（1024/4096 码字）未参数化，取 VIP 默认。
localparam int RS91_GROUPS   = 20;                     // 每码字的 257b 组数
localparam int RS91_BLOCKS   = RS91_GROUPS * 4;        // 80 个 66b 块
localparam int RS91_CW_BITS  = RS91_N * RS91_M;        // 5280 bit
localparam int RS91_MSG_BITS = RS91_K * RS91_M;        // 5140 bit
localparam int RS91_AM_CWS   = 16;                     // AM 周期（码字）
localparam int RS91_AM4_BITS = 1285;                   // 100G AM 区（5 组）
localparam logic [4:0] RS91_PAD = 5'b00101;            // 100G AM 填充（偶数次）

// 25G AM 组（bit i = 第 i 个上线位）：100G PCS lane0 与 40G lane1~3 的 AM，
// BIP3/BIP7 固定 0x33/0xCC，末位填充 0
localparam logic [256:0] RS108_AM = {1'b0,
  64'hCCC2865D333D79A2, 64'hCC649A3A339B65C5,
  64'hCC193B0F33E6C4F0, 64'hCCDE973E332168C1};

// AM 64bit 中的固定字节（M0..M2、M4..M6）掩码；其余为 BIP3/BIP7
localparam logic [63:0] RS91_AM_FIXED = 64'h00FFFFFF_00FFFFFF;

class rs91_tx_c;

  // 各 FEC lane 本次产出的比特（BFM 取走入串行队列）
  logic out_bits[4][$];

  protected int            nfl;           // FEC lane 数：1 或 4
  protected mld_tx_c       amgen;         // 100G：20 条 PCS lane 的 AM/BIP
  protected rs91_encoder_c enc;
  protected logic          msg[$];        // 当前码字信息位
  protected block66_t      grp[$];        // 待转码的块（凑满 4 块）
  protected block66_t      row_hold[$];   // 100G：AM 行期间暂存的数据块
  protected logic [63:0]   am_row[20];
  protected int            cw_in_period;  // 当前码字在 AM 周期中的序号
  protected bit            pad_odd;

  function new(int nfl);
    this.nfl = nfl;
    enc = new();
    if (nfl == 4) amgen = new(20, 64);
    reset();
  endfunction

  function void reset();
    foreach (out_bits[l]) out_bits[l].delete();
    msg.delete();
    grp.delete();
    row_hold.delete();
    cw_in_period = 0;
    pad_odd      = 0;
    if (nfl == 4) amgen.reset();
  endfunction

  // 输入一个已加扰的 66b 块；本次若产出码字返回 1（比特在 out_bits）
  function bit push_block(block66_t b);
    int n0 = out_bits[0].size();
    if (nfl == 4) begin
      int       lane;
      bit       amv;
      block66_t amb;
      // mld_tx_c 按 PCS lane 轮转计 BIP；周期起点 20 条 lane 依次给出 AM，
      // 凑齐一行后先放 AM 区，再放这 20 个数据块（即 de-MLD 次序）
      amgen.push_block(b, lane, amv, amb);
      if (amv) begin
        am_row[lane] = amb.payload;
        row_hold.push_back(b);
        if (lane == 19) begin
          put_am100();
          foreach (row_hold[i]) put_block(row_hold[i]);
          row_hold.delete();
        end
        return out_bits[0].size() != n0;
      end
    end
    else if (cw_in_period == 0 && msg.size() == 0) begin
      for (int i = 0; i < 257; i++) msg.push_back(RS108_AM[i]);
    end
    put_block(b);
    return out_bits[0].size() != n0;
  endfunction

  protected function void put_block(block66_t b);
    grp.push_back(b);
    if (grp.size() < 4) return;
    begin
      block66_t     g4[4];
      logic [256:0] t;
      foreach (g4[i]) g4[i] = grp[i];
      grp.delete();
      rs91_transcode_enc(g4, t);
      for (int i = 0; i < 257; i++) msg.push_back(t[i]);
    end
    if (msg.size() == RS91_MSG_BITS) emit();
  endfunction

  // 100G AM 区：20 个 AM 固定字节替换 -> 按 FEC lane 重排 -> 符号交织 + 填充
  protected function void put_am100();
    logic [63:0]  am_m[20];
    logic [319:0] sub[4];
    if (msg.size() != 0 || grp.size() != 0)
      $error("rs91_tx: AM 行未落在码字边界（msg=%0d grp=%0d）",
             msg.size(), grp.size());
    for (int x = 0; x < 20; x++) begin
      int src;
      src     = (x >= 1 && x <= 3) ? 0 : ((x >= 17) ? 16 : x);
      am_m[x] = (am_row[x] & ~RS91_AM_FIXED) |
                (mld_am_payload(20, src, 8'h00) & RS91_AM_FIXED);
    end
    for (int l = 0; l < 4; l++)
      for (int k = 0; k < 5; k++) sub[l][64*k +: 64] = am_m[4*k + l];
    for (int i = 0; i < 128; i++)
      for (int j = 0; j < RS91_M; j++) msg.push_back(sub[i % 4][RS91_M*(i/4) + j]);
    for (int j = 0; j < 5; j++) msg.push_back(RS91_PAD[j] ^ pad_odd);
    pad_odd = !pad_odd;
  endfunction

  protected function void emit();
    rs91_sym_t data[RS91_K];
    rs91_sym_t cw[RS91_N];
    for (int i = 0; i < RS91_K; i++)
      for (int j = 0; j < RS91_M; j++) data[i][j] = msg[i*RS91_M + j];   // LSB 先
    msg.delete();
    enc.encode(data, cw);
    for (int i = 0; i < RS91_N; i++)
      for (int j = 0; j < RS91_M; j++) out_bits[i % nfl].push_back(cw[i][j]);
    cw_in_period = (cw_in_period + 1) % RS91_AM_CWS;
  endfunction

endclass

class rs91_rx_c;

  // 统计（BFM/单测读取）
  int slip_count;          // 失锁重锁次数
  int am_locks;            // 对齐完成次数
  int am_miss_total;       // 周期起点 AM 不符次数
  int rs_uncorrectable;    // 不可纠码字数（其块同步头标坏向上交付）

  protected int            nfl;
  protected int            per;            // 每 lane 每码字 bit 数
  protected logic [127:0]  sr[4];          // 各物理 lane 搜索窗（[0] 最早）
  protected int            nseen[4];
  protected int            fl_of[4];       // 物理 lane -> FEC lane（-1 未锁）
  protected logic          q[4][$];        // 按 FEC lane 的对齐后比特
  protected bit            aligned;
  protected int            cw_in_period;
  protected int            am_miss;
  protected rs91_decoder_c dec;
  protected rs91_xdec_c    xdec;
  protected block66_t      out_q[$];

  function new(int nfl);
    this.nfl = nfl;
    per      = RS91_CW_BITS / nfl;
    dec      = new();
    xdec     = new();
    reset();
  endfunction

  function void reset();
    for (int p = 0; p < 4; p++) begin
      sr[p]    = '0;
      nseen[p] = 0;
      fl_of[p] = -1;
      q[p].delete();
    end
    aligned      = 0;
    cw_in_period = 0;
    am_miss      = 0;
    out_q.delete();
    xdec.reset();
  endfunction

  function bit is_aligned();
    return aligned;
  endfunction

  // 搜索窗内是否为周期首 AM：返回 FEC lane 号，否则 -1。
  // 25G：前 128bit 与常量 AM 组一致；100G：首个 AM 为 lane0 固定字节
  //（4 条 lane 相同）+ BIP7=~BIP3，紧随的第二个 AM 固定字节识别 lane
  protected function int match_am(logic [127:0] w);
    logic [63:0] a0, a1;
    if (nfl == 1) return (w == RS108_AM[127:0]) ? 0 : -1;
    a0 = w[63:0];
    a1 = w[127:64];
    if ((a0 & RS91_AM_FIXED) != (mld_am_payload(20, 0, 8'h00) & RS91_AM_FIXED) ||
        a0[63:56] != ~a0[31:24])
      return -1;
    for (int l = 0; l < 4; l++)
      if ((a1 & RS91_AM_FIXED) == (mld_am_payload(20, 4 + l, 8'h00) & RS91_AM_FIXED))
        return l;
    return -1;
  endfunction

  function void push_bit(int pl, logic b);
    if (fl_of[pl] >= 0) begin
      q[fl_of[pl]].push_back(b);
      if (aligned) pump();
      else         try_align();
      return;
    end
    sr[pl] = {b, sr[pl][127:1]};
    if (nseen[pl] < 128) nseen[pl]++;
    if (nseen[pl] < 128) return;
    begin
      int l;
      bit dup;
      l   = match_am(sr[pl]);
      dup = 0;
      if (l < 0) return;
      for (int p = 0; p < nfl; p++) if (fl_of[p] == l) dup = 1;
      if (dup) return;
      fl_of[pl] = l;
      for (int i = 0; i < 128; i++) q[l].push_back(sr[pl][i]);
      try_align();
    end
  endfunction

  // 全部 FEC lane 找到 AM 后对齐：比其余 lane 多出半个周期以上的 lane 是
  // 锁在了更早的某次 AM 上，逐周期丢弃直到差值落在半周期内。前提：真实
  // lane 偏斜小于半个 AM 周期（每 lane 10560bit ≈ 410ns，远大于 802.3
  // 允许的偏斜）—— 更大的偏斜与"锁在相邻一次 AM 上"本质上无法区分
  protected function void try_align();
    int mn;
    int period_bits;
    period_bits = RS91_AM_CWS * per;
    for (int p = 0; p < nfl; p++) if (fl_of[p] < 0) return;
    mn = q[0].size();
    for (int l = 1; l < nfl; l++) if (q[l].size() < mn) mn = q[l].size();
    for (int l = 0; l < nfl; l++)
      while (q[l].size() - mn > period_bits / 2)
        repeat (period_bits) void'(q[l].pop_front());
    aligned      = 1;
    cw_in_period = 0;
    am_miss      = 0;
    am_locks++;
    xdec.reset();
    pump();
  endfunction

  protected function void relock();
    int sc;
    sc = slip_count;
    reset();
    slip_count = sc + 1;
  endfunction

  protected function void pump();
    while (aligned) begin
      for (int l = 0; l < nfl; l++) if (q[l].size() < per) return;
      decode_cw();
    end
  endfunction

  // 周期首码字：信息区开头须为 AM（25G 常量组 / 100G 各 lane 首 AM 固定字节）
  protected function bit check_am(ref logic msg[RS91_MSG_BITS]);
    logic [63:0] a;
    if (nfl == 1) begin
      for (int i = 0; i < 128; i++) if (msg[i] != RS108_AM[i]) return 0;
      return 1;
    end
    for (int l = 0; l < 4; l++) begin
      for (int k = 0; k < 64; k++) a[k] = msg[RS91_M*(4*(k/RS91_M) + l) + k%RS91_M];
      if ((a & RS91_AM_FIXED) != (mld_am_payload(20, 0, 8'h00) & RS91_AM_FIXED))
        return 0;
    end
    return 1;
  endfunction

  protected function void decode_cw();
    rs91_sym_t cw[RS91_N];
    logic      msg[RS91_MSG_BITS];
    bit        ok;
    int        start;
    for (int i = 0; i < RS91_N; i++)
      for (int j = 0; j < RS91_M; j++)
        cw[i][j] = q[i % nfl][(i / nfl) * RS91_M + j];
    for (int l = 0; l < nfl; l++) repeat (per) void'(q[l].pop_front());

    ok = dec.decode(cw);
    if (!ok) rs_uncorrectable++;
    for (int i = 0; i < RS91_K; i++)
      for (int j = 0; j < RS91_M; j++) msg[i*RS91_M + j] = cw[i][j];

    start = 0;
    if (cw_in_period == 0) begin
      if (!check_am(msg)) begin
        am_miss++;
        am_miss_total++;
        // 连续 2 个周期 AM 不符：码字边界已失，整体重锁
        if (am_miss >= 2) begin
          relock();
          return;
        end
      end
      else am_miss = 0;
      start = (nfl == 4) ? RS91_AM4_BITS : 257;
    end

    for (int g = start; g + 257 <= RS91_MSG_BITS; g += 257) begin
      logic [256:0] t;
      block66_t     b4[4];
      for (int i = 0; i < 257; i++) t[i] = msg[g + i];
      xdec.decode(t, b4);
      // 不可纠码字：同步头标坏（2'b11），迫使 PCS 解码计错、帧被判损伤
      foreach (b4[i]) begin
        if (!ok) b4[i].sync = 2'b11;
        out_q.push_back(b4[i]);
      end
    end
    cw_in_period = (cw_in_period + 1) % RS91_AM_CWS;
  endfunction

  function bit pop_block(output block66_t b);
    if (out_q.size() == 0) return 0;
    b = out_q.pop_front();
    return 1;
  endfunction

  function int corrected_count();
    return dec.corrected_count;
  endfunction

endclass

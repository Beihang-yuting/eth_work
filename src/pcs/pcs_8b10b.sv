// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— 8b/10b 编解码（Clause 36，1000BASE-X / 2.5G）
// 职责：Widmer-Franaszek 8b/10b：字节(HGF EDCBA) + K 标志 + 当前运行
//   不均等性(RD) -> 10bit 码组(abcdei fghj) + 新 RD；反向解码并检出
//   码违例(code violation)与不均等性错误(disparity error)。
// 位序约定：code[9:0] = {a,b,c,d,e,i,f,g,h,j}，a 最先上线（MSB 先发）。
//   逗号（K28.5 前 7 位）因此为 0011111（RD-）或 1100000（RD+）。
// 依赖：无（纯函数 + 一个解码表类）。
// 所有权：basex PCS 的 TX/RX 各持 RD 状态；解码表全局静态构造一次。
// 实现策略：编码按 5b/6b + 3b/4b 子块规则实现；解码表**由编码器反推
//   生成**（遍历全部 256 个 D 码与所用 K 码 × 两种 RD），保证解码是编码
//   的严格逆，杜绝两张手抄表不一致。
// -----------------------------------------------------------------------------

// 常用 K 码（8bit 表示：K.x.y = {y[2:0], x[4:0]}）
localparam byte unsigned K28_5 = 8'hBC;   // 逗号，idle /I/ 与配置 /C/ 首码
localparam byte unsigned K27_7 = 8'hFB;   // /S/ 帧起始
localparam byte unsigned K29_7 = 8'hFD;   // /T/ 帧结束
localparam byte unsigned K23_7 = 8'hF7;   // /R/ 载波延伸
localparam byte unsigned K30_7 = 8'hFE;   // /V/ 错误传播

// 5b/6b 子块 RD- 形态（abcdei），下标 EDCBA
function automatic logic [5:0] enc_6b_rdn(logic [4:0] x);
  logic [5:0] t[32] = '{
    6'b100111, 6'b011101, 6'b101101, 6'b110001, 6'b110101, 6'b101001,
    6'b011001, 6'b111000, 6'b111001, 6'b100101, 6'b010101, 6'b110100,
    6'b001101, 6'b101100, 6'b011100, 6'b010111, 6'b011011, 6'b100011,
    6'b010011, 6'b110010, 6'b001011, 6'b101010, 6'b011010, 6'b111010,
    6'b110011, 6'b100110, 6'b010110, 6'b110110, 6'b001110, 6'b101110,
    6'b011110, 6'b101011 };
  return t[x];
endfunction

// 3b/4b 子块 RD- 形态（fghj），下标 HGF；7 为主形 P7
function automatic logic [3:0] enc_4b_rdn(logic [2:0] y);
  logic [3:0] t[8] = '{ 4'b1011, 4'b1001, 4'b0101, 4'b1100,
                        4'b1101, 4'b1010, 4'b0110, 4'b1110 };
  return t[y];
endfunction

localparam logic [3:0] ENC_4B_A7_RDN = 4'b0111;   // D.x.A7 / K.x.7 替代形

function automatic int ones6(logic [5:0] v);
  return v[0]+v[1]+v[2]+v[3]+v[4]+v[5];
endfunction
function automatic int ones4(logic [3:0] v);
  return v[0]+v[1]+v[2]+v[3];
endfunction

// 编码一个码组。rd：0 = RD-，1 = RD+；返回 10bit 码组并更新 rd。
// is_k 只支持 K28.y 与 K23/27/29/30.7（Clause 36 用到的全部 K 码）。
function automatic logic [9:0] enc_8b10b(byte unsigned b, bit is_k,
                                         ref bit rd);
  logic [4:0] x;
  logic [2:0] y;
  logic [5:0] c6;
  logic [3:0] c4;
  bit         k28;

  x   = b[4:0];
  y   = b[7:5];
  k28 = is_k && (x == 5'd28);

  // --- 5b/6b ---
  c6 = k28 ? 6'b001111 : enc_6b_rdn(x);
  // RD+ 时取补：不均衡码（±2）或 D.07 的双形态
  if (rd && (ones6(c6) != 3 || (!k28 && x == 5'd7))) c6 = ~c6;
  if (ones6(c6) != 3) rd = ~rd;

  // --- 3b/4b（按 6b 之后的 RD 选形）---
  if (y == 3'd7 && (is_k ||
      (!rd && (x == 17 || x == 18 || x == 20)) ||
      ( rd && (x == 11 || x == 13 || x == 14))))
    c4 = ENC_4B_A7_RDN;                     // A7：避免 5 连同符
  else
    c4 = enc_4b_rdn(y);

  if (rd && (ones4(c4) != 2 || y == 3'd3)) c4 = ~c4;
  // K28.1/2/5/6：RD- 时取 D 形的补（构成逗号，与数据码区分）
  if (k28 && !rd && (y == 1 || y == 2 || y == 5 || y == 6)) c4 = ~c4;
  if (ones4(c4) != 2) rd = ~rd;

  return {c6, c4};
endfunction

// ---------------- 解码表（由编码器反推）----------------

class pcs_8b10b_dec_c;

  // 表项：码组在某入口 RD 下是否合法，及其 K 标志/字节
  typedef struct packed {
    bit           valid;
    bit           is_k;
    byte unsigned data;
  } ent_t;

  static ent_t tab[1024][2];   // [码组][入口 RD]
  static bit   built = 0;

  static function void build();
    byte unsigned ks[5];
    bit           rd;
    logic [9:0]   c;
    if (built) return;
    ks = '{K28_5, K27_7, K29_7, K23_7, K30_7};
    for (int i = 0; i < 1024; i++) begin
      tab[i][0] = '0;
      tab[i][1] = '0;
    end
    for (int r = 0; r < 2; r++) begin
      for (int v = 0; v < 256; v++) begin
        rd = r;
        c  = enc_8b10b(v[7:0], 0, rd);
        tab[c][r].valid = 1;
        tab[c][r].is_k  = 0;
        tab[c][r].data  = v[7:0];
      end
      foreach (ks[i]) begin
        rd = r;
        c  = enc_8b10b(ks[i], 1, rd);
        tab[c][r].valid = 1;
        tab[c][r].is_k  = 1;
        tab[c][r].data  = ks[i];
      end
    end
    built = 1;
  endfunction

  // 解码一个码组。rd 为当前 RD（按码组内容推进）。
  // code_err = 码违例（任何 RD 下都不是合法码组）；
  // disp_err = 码组合法但不属于当前 RD（运行不均等性错误）。
  static function void decode(logic [9:0] c, ref bit rd,
                              output byte unsigned data, output bit is_k,
                              output bit code_err, output bit disp_err);
    int d;
    build();
    code_err = 0;
    disp_err = 0;
    data     = 8'h00;
    is_k     = 0;

    if (tab[c][rd].valid) begin
      data = tab[c][rd].data;
      is_k = tab[c][rd].is_k;
    end
    else if (tab[c][!rd].valid) begin
      data     = tab[c][!rd].data;
      is_k     = tab[c][!rd].is_k;
      disp_err = 1;
    end
    else begin
      code_err = 1;
    end

    // 按码组实际不均等性推进 RD（均衡码不变，+2 置 RD+，-2 置 RD-）
    d = c[0]+c[1]+c[2]+c[3]+c[4]+c[5]+c[6]+c[7]+c[8]+c[9];
    if (d > 5)      rd = 1;
    else if (d < 5) rd = 0;
  endfunction

endclass

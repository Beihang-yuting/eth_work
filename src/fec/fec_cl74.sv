// -----------------------------------------------------------------------------
// 所属：eth_work/src/fec —— Clause 74 BASE-R FEC (2112,2080) 编解码
// 职责：
//   编码：32 个 66b 块 -> 66b→65b 转码 -> 2080bit 信息位 -> 附 32bit 校验
//         （fire code，g(x)=x^32+x^23+x^21+x^11+x^2+1）-> PN-2112 加扰 ->
//         2112bit 码字按 bit 输出。
//   解码：bit 流上用"伴随式为零"搜索码字边界（连续 2 个干净码字锁定），
//         锁定后逐码字校验：伴随式非零时按 fire code 突发纠错能力
//         （单突发 ≤11bit）做纠正，不可纠时上报并透传。
// 依赖：pcs_types.sv（block66_t）。
// 所有权：编码器/解码器各为有状态对象，phy_bfm 每方向各持一个，随 BFM
//         存续；reset() 重建对齐与统计。
// -----------------------------------------------------------------------------

// 设计取舍（简单但完整）：
// 1. PN-2112 用 x^58+x^39+1、全 1 种子、每码字重启 —— 标准允许实现相关的
//    PN 细节，此处两端约定一致即可，重启式实现无需跨码字状态。
// 2. 突发纠错不用传统 error-trapping（移位陷阱对缩短码需要周期修正），
//    改用"逐位置线性求解"：预计算 x^i mod g 表，对每个候选突发起点解
//    GF(2) 线性方程组。仅在伴随式非零时触发，仿真代价可接受，
//    且对缩短码数学上无歧义。
// 3. 66b→65b 转码：压缩位 T = sync[1]（数据块 01 -> 0，控制块 10 -> 1），
//    重建 sync = T ? 2'b10 : 2'b01。非法同步头在编码前应已被 PCS 层拦截。

// ---------------- 公共参数 ----------------

// 码字总长 / 信息位长 / 校验位长（IEEE 802.3 Clause 74.7.4.4）
localparam int FEC_N = 2112;
localparam int FEC_K = 2080;
localparam int FEC_P = 32;

// 每码字承载的 66b 块数（2080 / 65）
localparam int FEC_BLOCKS = 32;

// fire code 可纠单突发最大长度
localparam int FEC_BURST = 11;

// g(x) 除 x^32 外的反馈系数：x^23+x^21+x^11+x^2+1
localparam logic [31:0] FEC_POLY = 32'h00A0_0805;

// ---------------- PN-2112 ----------------

// 对 2112bit 码字原位异或 PN 序列。发生成器 x^58+x^39+1、全 1 种子、
// 每码字重启；编码/解码调用同一函数保证两端一致。
function automatic void fec_pn_xor(ref logic cw[FEC_N]);
  logic [57:0] s = '1;
  for (int i = 0; i < FEC_N; i++) begin
    logic b = s[38] ^ s[57];
    cw[i] ^= b;
    s = {s[56:0], b};
  end
endfunction

// ---------------- 编码器 ----------------

class fec_cl74_encoder_c;

  // 待编码的 66b 块缓冲；集满 FEC_BLOCKS 个后产出一个码字
  protected block66_t blk_q[$];

  // 输入一个 66b 块。集满 32 块时输出完整码字（cw_out[0] 最先上线）并
  // 返回 1；块数不足时仅缓存并返回 0（无失败路径）。
  function bit push_block(block66_t b, output logic cw_out[FEC_N]);
    blk_q.push_back(b);
    if (blk_q.size() < FEC_BLOCKS) return 0;

    begin
      logic msg[FEC_K];
      logic [31:0] parity;
      int idx = 0;

      // 66b→65b 转码：压缩位在前，随后 payload LSB-first
      foreach (blk_q[k]) begin
        msg[idx++] = blk_q[k].sync[1];
        for (int i = 0; i < 64; i++) msg[idx++] = blk_q[k].payload[i];
      end
      blk_q.delete();

      // 系统码校验位：parity = m(x)·x^32 mod g(x)。
      // 除法 LFSR 按发送顺序移入信息位；msg[0] 先发，对应最高次项。
      parity = '0;
      for (int i = 0; i < FEC_K; i++) begin
        logic fb = msg[i] ^ parity[31];
        parity = {parity[30:0], 1'b0};
        if (fb) parity ^= FEC_POLY;
      end

      // 码字 = 信息位 + 校验位（校验位 MSB 先发以匹配除法方向）
      for (int i = 0; i < FEC_K; i++) cw_out[i] = msg[i];
      for (int i = 0; i < FEC_P; i++) cw_out[FEC_K + i] = parity[31 - i];

      // PN-2112 加扰：消除码字级周期性图案
      fec_pn_xor(cw_out);
    end
    return 1;
  endfunction

  function void reset();
    blk_q.delete();
  endfunction

endclass

// ---------------- 解码器 ----------------

class fec_cl74_decoder_c;

  // 对齐锁定需要的连续干净码字数
  localparam int LOCK_CLEAN = 2;

  protected logic bitbuf[$];       // 候选对齐位置起的 bit 缓冲
  protected bit   locked;
  protected int   clean_cnt;       // 未锁定时连续干净码字计数

  // 统计：可纠/不可纠计数与 slip 次数，供记分板与单测检查
  int corrected_count;
  int uncorrectable_count;
  int slip_count;

  // 单 bit 错误伴随式查表（懒初始化）；表内容只与 g 有关，静态共享。
  // 约定：cw[i]（发送序第 i 位）对应多项式次数 d = FEC_N-1-i；本实现的
  // 伴随式 LFSR 为"预乘 x^32"形式，故 xpow_tbl[d] = x^(d+32) mod g。
  static logic [31:0] xpow_tbl[FEC_N];
  static bit          tbl_init = 0;

  function new();
    reset();
  endfunction

  function void reset();
    bitbuf.delete();
    locked    = 0;
    clean_cnt = 0;
  endfunction

  function bit is_locked();
    return locked;
  endfunction

  // 推入一个线路 bit。集满一个候选码字后：
  //  - 未锁定：伴随式为零计连续干净数，达标锁定；非零则 slip 1 bit 重试。
  //  - 已锁定：伴随式非零先尝试突发纠错；不可纠计数后透传（Clause 74
  //    无失锁回退，链路质量由上层监控）。
  // 返回 1 时 blks_out 携带 32 个重建的 66b 块。
  function bit push_bit(logic b, output block66_t blks_out[FEC_BLOCKS]);
    logic cw[FEC_N];
    logic [31:0] syn;

    bitbuf.push_back(b);
    if (bitbuf.size() < FEC_N) return 0;

    for (int i = 0; i < FEC_N; i++) cw[i] = bitbuf[i];

    // 先去 PN 再算伴随式
    fec_pn_xor(cw);
    syn = syndrome(cw);

    if (!locked) begin
      if (syn == 0) begin
        clean_cnt++;
        bitbuf.delete();
        if (clean_cnt >= LOCK_CLEAN) locked = 1;

        // 锁定前的干净码字也向上递交：避免丢失锁定判据消耗的数据
        unpack_blocks(cw, blks_out);
        return 1;
      end
      else begin
        // 候选位置错误：slip 1 bit 重试
        clean_cnt = 0;
        slip_count++;
        void'(bitbuf.pop_front());
        return 0;
      end
    end

    bitbuf.delete();

    if (syn != 0) begin
      if (try_correct(cw, syn)) corrected_count++;
      else                      uncorrectable_count++;
    end

    unpack_blocks(cw, blks_out);
    return 1;
  endfunction

  // ---------------- 内部：伴随式与纠错 ----------------

  // 伴随式：整个 2112bit 码字按发送顺序过除法 LFSR，合法码字余数为零
  protected function logic [31:0] syndrome(logic cw[FEC_N]);
    logic [31:0] s = '0;
    for (int i = 0; i < FEC_N; i++) begin
      logic fb = cw[i] ^ s[31];
      s = {s[30:0], 1'b0};
      if (fb) s ^= FEC_POLY;
    end
    return s;
  endfunction

  // 突发纠错：突发在发送序上连续，对应连续递减的多项式次数区间。
  // 对每个突发最低次 p（突发首 bit 强制存在）：解
  //   xpow[p] ^ XOR_{j in 1..w, b_j=1} xpow[p+j] = syn
  // 有解即翻转对应 bit 并复核伴随式。返回 1 = 纠正成功。
  protected function bit try_correct(ref logic cw[FEC_N], input logic [31:0] syn);
    init_tbl();

    for (int p = 0; p < FEC_N; p++) begin
      logic [31:0] target = syn ^ xpow_tbl[p];
      logic [31:0] basis[FEC_BURST];
      logic [10:0] sel;
      int nb = 0;
      int wmax = (FEC_N - 1 - p < FEC_BURST - 1) ? (FEC_N - 1 - p)
                                                 : (FEC_BURST - 1);

      if (target == 0) begin
        cw[FEC_N - 1 - p] = ~cw[FEC_N - 1 - p];
        return 1;
      end

      for (int j = 1; j <= wmax; j++) basis[nb++] = xpow_tbl[p + j];

      if (solve_xor(basis, nb, target, sel)) begin
        cw[FEC_N - 1 - p] = ~cw[FEC_N - 1 - p];
        for (int j = 0; j < nb; j++)
          if (sel[j]) cw[FEC_N - 1 - (p + j + 1)] = ~cw[FEC_N - 1 - (p + j + 1)];

        // 复核：纠正后伴随式必须归零，否则回退继续搜索
        if (syndrome(cw) == 0) return 1;
        cw[FEC_N - 1 - p] = ~cw[FEC_N - 1 - p];
        for (int j = 0; j < nb; j++)
          if (sel[j]) cw[FEC_N - 1 - (p + j + 1)] = ~cw[FEC_N - 1 - (p + j + 1)];
      end
    end
    return 0;
  endfunction

  // GF(2) 线性方程组：找 sel 使被选 basis 向量异或等于 target。
  // 规范主元消元：pivot[b] 保存以 bit b 为最高位的规约向量。
  protected function bit solve_xor(logic [31:0] basis[FEC_BURST], int nb,
                                   logic [31:0] target, output logic [10:0] sel);
    logic [31:0] pivot_vec[32];
    logic [10:0] pivot_tag[32];
    bit          pivot_set[32];
    logic [31:0] acc;
    logic [10:0] acc_tag;

    for (int b = 0; b < 32; b++) pivot_set[b] = 0;

    // 逐个向量规约后登记主元
    for (int i = 0; i < nb; i++) begin
      logic [31:0] v = basis[i];
      logic [10:0] t = 11'h1 << i;
      for (int b = 31; b >= 0; b--) begin
        if (!v[b]) continue;
        if (pivot_set[b]) begin
          v ^= pivot_vec[b];
          t ^= pivot_tag[b];
        end
        else begin
          pivot_vec[b] = v;
          pivot_tag[b] = t;
          pivot_set[b] = 1;
          break;
        end
      end
    end

    // 规约 target；归零即有解
    acc     = target;
    acc_tag = '0;
    for (int b = 31; b >= 0; b--) begin
      if (!acc[b]) continue;
      if (!pivot_set[b]) return 0;
      acc     ^= pivot_vec[b];
      acc_tag ^= pivot_tag[b];
    end

    sel = acc_tag;
    return 1;
  endfunction

  // 预计算 x^(d+32) mod g，d = 0..FEC_N-1。
  // 初值即 x^32 mod g = g(x) - x^32 = FEC_POLY。
  protected function void init_tbl();
    logic [31:0] cur;
    if (tbl_init) return;

    cur = FEC_POLY;
    for (int d = 0; d < FEC_N; d++) begin
      xpow_tbl[d] = cur;
      begin
        logic msb = cur[31];
        cur = {cur[30:0], 1'b0};
        if (msb) cur ^= FEC_POLY;
      end
    end
    tbl_init = 1;
  endfunction

  // 码字 -> 32 个 66b 块（65b→66b 反转码）
  protected function void unpack_blocks(logic cw[FEC_N],
                                        output block66_t blks[FEC_BLOCKS]);
    int idx = 0;
    for (int k = 0; k < FEC_BLOCKS; k++) begin
      logic t = cw[idx++];
      blks[k].sync = t ? SYNC_CTRL : SYNC_DATA;
      for (int i = 0; i < 64; i++) blks[k].payload[i] = cw[idx++];
    end
  endfunction

endclass

// -----------------------------------------------------------------------------
// 所属：eth_work/src/pcs —— 10GBASE-R PCS 层公共类型与常量定义
// 职责：集中定义 XGMII 控制字符、Clause 49 66b 块类型码、块/XGMII 数据结构，
//       供编码器、解码器、块同步、FEC 与 agent 各层共用，避免魔法数字散落。
// 依赖：无（最底层头文件，被 eth_pcs_pkg.sv 首先 include）。
// 所有权：本文件只含类型与常量，无状态、无生命周期问题。
// -----------------------------------------------------------------------------

// 为什么需要这一层：PCS 编解码两侧、monitor 与单元测试都要引用同一套
// 块类型码表；若各自内联常量，任何一处笔误都会造成"编码器与解码器
// 各自成立但互不兼容"的隐蔽缺陷，因此必须单点定义。

// ---------------- XGMII 控制字符（IEEE 802.3 46.3.3） ----------------

// 空闲字符：帧间隙（IPG）期间填充
localparam byte unsigned XGMII_IDLE  = 8'h07;

// 帧起始字符：替换 preamble 第一字节，仅允许出现在 lane0
localparam byte unsigned XGMII_START = 8'hfb;

// 帧终止字符：紧跟帧最后一个数据字节
localparam byte unsigned XGMII_TERM  = 8'hfd;

// 错误指示字符：链路层向上传播错误
localparam byte unsigned XGMII_ERROR = 8'hfe;

// 序集起始字符（Sequence ordered set，如 Local/Remote Fault）
localparam byte unsigned XGMII_SEQ   = 8'h9c;

// ---------------- 66b 块同步头（IEEE 802.3 49.2.4.3） ----------------

// 数据块同步头：8 字节全为数据
localparam logic [1:0] SYNC_DATA = 2'b01;

// 控制块同步头：payload 首字节为块类型码
localparam logic [1:0] SYNC_CTRL = 2'b10;

// ---------------- 控制块类型码（IEEE 802.3 图 49-7） ----------------

// 全控制字符块（8 个 7bit C 码，通常为全 IDLE）
localparam byte unsigned BT_CTRL     = 8'h1e;

// 帧起始于 lane0：S + D1..D7
localparam byte unsigned BT_START0   = 8'h78;

// 帧起始于 lane4：C0..C3 + S + D5..D7（32bit XGMII 内核的另一合法起点）
localparam byte unsigned BT_START4   = 8'h33;

// 序集块：O0 + C4..C7 / O0 + O4（Local/Remote Fault 等经由这两种块传输）
localparam byte unsigned BT_OSET0    = 8'h4b;
localparam byte unsigned BT_OSET2    = 8'h55;

// 帧终止于 lane k：D0..D(k-1) + T + 其后 C 码
localparam byte unsigned BT_TERM0    = 8'h87;
localparam byte unsigned BT_TERM1    = 8'h99;
localparam byte unsigned BT_TERM2    = 8'haa;
localparam byte unsigned BT_TERM3    = 8'hb4;
localparam byte unsigned BT_TERM4    = 8'hcc;
localparam byte unsigned BT_TERM5    = 8'hd2;
localparam byte unsigned BT_TERM6    = 8'he1;
localparam byte unsigned BT_TERM7    = 8'hff;

// 块类型低半字节 -> 完整 8bit 块类型（Clause 49 合法类型的低半字节两两
// 不同）。256B/257B 转码只保留首个控制块类型的低 4 位，接收端据此复原
//（Clause 119 与 RS-FEC cl91/cl108 共用）；非法半字节返回 0
function automatic byte unsigned bt_from_low_nibble(logic [3:0] n);
  case (n)
    4'hE: return 8'h1E;  4'hD: return 8'h2D;  4'h3: return 8'h33;
    4'h6: return 8'h66;  4'h5: return 8'h55;  4'h8: return 8'h78;
    4'hB: return 8'h4B;  4'h7: return 8'h87;  4'h9: return 8'h99;
    4'hA: return 8'hAA;  4'h4: return 8'hB4;  4'hC: return 8'hCC;
    4'h2: return 8'hD2;  4'h1: return 8'hE1;  4'hF: return 8'hFF;
    default: return 8'h00;
  endcase
endfunction

// 7bit 控制字符 C 码映射（IEEE 802.3 表 49-1）
localparam logic [6:0] CC_IDLE  = 7'h00;
localparam logic [6:0] CC_ERROR = 7'h1e;

// ---------------- 数据结构 ----------------

// 一个 66bit 块：sync 在线路上先发（bit0、bit1），payload 随后 LSB-first。
// payload 对数据块是 8 字节原始数据（byte0 在 [7:0]）；对控制块 [7:0] 是
// 块类型码，其余按类型布局。
typedef struct packed {
  logic [63:0] payload;
  logic [1:0]  sync;
} block66_t;

// 一拍 64bit XGMII：ctl[i]=1 表示 data 字节 i 是控制字符。
// byte0（data[7:0]）是时间上最早的字节，与以太网线序一致。
typedef struct packed {
  logic [7:0]  ctl;
  logic [63:0] data;
} xgmii64_t;

// 常用整块常量：全 IDLE 控制块对应的 XGMII 视图
function automatic xgmii64_t xgmii_all_idle();
  xgmii64_t w;
  w.ctl = 8'hff;
  for (int i = 0; i < 8; i++) w.data[i*8 +: 8] = XGMII_IDLE;
  return w;
endfunction

// -----------------------------------------------------------------------------
// 所属：eth_work/src/agent —— agent 配置对象与帧级事务
// 职责：集中承载 agent 的运行模式开关（FEC 使能、主动/被动、IPG 空闲拍数）
//       与两个 virtual interface 句柄，经 uvm_config_db 下发给 agent 及其
//       子组件；同时定义记分板使用的帧级事务 eth_frame_txn。
// 依赖：eth_pcs_if.sv（接口类型）、UVM。
// 所有权：test 构造并配置 cfg，agent 各子组件只读引用；仿真全程存续。
//         txn 由 driver/monitor 逐帧 new，经 analysis port 移交记分板。
// -----------------------------------------------------------------------------

// 为什么用配置对象而不是散装 config_db 字段：FEC 开关同时影响 BFM 两个
// 方向的流水线选择，monitor 的检查预期也随之变化；单一对象保证一次配置、
// 全组件一致，杜绝"driver 开 FEC 而 monitor 没开"的错配。
class eth_pcs_cfg extends uvm_object;

  `uvm_object_utils(eth_pcs_cfg)

  // FEC 使能：1 = TX/RX 走 Clause 74 编解码；0 = 裸 64b/66b + 块同步
  bit fec_enable = 0;

  // 200GBASE-R 模式（Clause 119）：8 条 PCS lane，256B/257B + RS(544,514)
  // + 120bit AM。须同时置 num_lanes = num_phys = 8；不走 MLD（Clause 82）
  // 路径，66b 级不加扰（加扰在 257b 层）。不与其它 FEC/AN/LT 叠加。
  bit cl119 = 0;

  // BASE-X 模式（1000BASE-X / 2.5GBASE-X）：8b/10b + Clause 36 有序集，
  // MAC 侧走 vif_gmii。与 FEC/MLD/AN/LT/直驱均不叠加（agent 校验）。
  bit basex = 0;

  // RS-FEC（Clause 91，RS(528,514) over GF(2^10)）使能：与 fec_enable
  // 互斥（两者是不同的码，不叠加）。开启后 TX 走 256B/257B 转码 +
  // RS 编码，RX 反向；纠错能力 7 个 10bit 符号/码字。
  // 注：VIP 的 RS-FEC 只绑定 100G CSBI 接口，交叉验证随 100G 一并做。
  bit rs_fec_enable = 0;

  // 主动模式：1 = 例化 sequencer/driver 充当 MAC 发流；0 = 仅 BFM+monitor
  bit is_active = 1;

  // 每帧之后驱动的全空闲拍数（8 字节/拍；2 拍 = 16 字节 ≥ 最小 IPG 12）
  int idle_words_per_gap = 2;

  // XGMII 直驱模式（纯 MAC 功能验证提速用）：1 = 跳过 PCS/串行整条链路，
  // driver 的帧直接展开成 XGMII 拍经 BFM 驱向对端（rxd/rxc），对端 MAC
  // 发来的 XGMII 拍（txd/txc）直接采样交 monitor 装配。发包序列零适配。
  // 代价：无锁定/弹性/fault 等链路层时序。配套 +XGMII_DIRECT 插件参数
  //（test 置本位 + 宏关位钟省事件 + lb_env 环回 force 接线）。
  bit xgmii_direct = 0;

  // 多 lane（Clause 82 MLD，40G=4）：1 = 单 lane 经典路径；>1 时启用
  // MLD 分发/重组，串行接口用 vif_serial_lanes[0..num_lanes-1]，
  // vif_serial 不用。MLD 模式下 fec_enable 必须为 0（未支持叠加）。
  int num_lanes = 1;

  // 每 lane AM 间隔（标准 16384；仿真提速可调小，两端一致即可）
  int am_spacing = 16384;

  // 物理串行 lane 数（PMA bit 复用）：0 = 与 num_lanes 相同（40G 4:4）；
  // 100G CAUI-10 为 10（20 条 PCS lane 以 2:1 按 bit 交织上 10 条物理
  // lane，物理 lane p 相位 k 承载 PCS lane p*m+k，m = num_lanes/num_phys）。
  // 接收端不依赖该映射：各解复用流独立块同步，MLD 以 AM 自识别 lane。
  int num_phys = 0;

  // Clause 73 自协商（KR 电口建链）：1 = 上电先走 AN（DME 页交换），
  // 协商完成后自动切入数据模式（PCS 码流）；0 = 直接进数据模式
  //（force 速率，既有行为）。单 lane 路径有效；多 lane/FEC 叠加未做。
  bit an_enable = 0;

  // 本端 advertise 的技术能力位（A[24:0]，默认 A2 = 10GBASE-KR）
  logic [24:0] an_ability = 25'h4;

  // 本端 Transmit Nonce（两端须不同，全 0 会被判为碰撞）
  logic [4:0] an_nonce = 5'h05;

  // Clause 72 链路训练（KR 建链第二步，紧随 AN）：1 = AN 完成后先训练
  // 再进数据模式；0 = 跳过训练直接进数据（既有行为）。可独立于 AN 使用
  //（lt_enable=1 而 an_enable=0 时上电直接进训练阶段）。
  // 注：svt VIP 不支持 cl72，交叉验证时须保持 0；自环测试可开。
  bit lt_enable = 0;

  // 边界接口句柄：由 test 从 config_db 取得后填入
  virtual xgmii_if  vif_xgmii;
  // BASE-X（1G/2.5G，8b/10b，Clause 36）模式的 MAC 侧接口；basex=1 时
  // 取代 vif_xgmii（MAC 侧是 GMII 字节流而非 XGMII 64bit 拍）
  virtual gmii_if   vif_gmii;
  virtual serial_if vif_serial;
  virtual serial_if vif_serial_lanes[MLD_MAX_LANES];

  function new(string name = "eth_pcs_cfg");
    super.new(name);
  endfunction

endclass

// 帧级事务：monitor 观测结果与 driver 发送记录的统一载体。
// 与 net_packet 的 packet_item 相比只含原始字节与校验标志 —— 记分板按
// 字节比对即可判定协议完整性，协议字段级解析留给 net_packet parser 按需做。
class eth_frame_txn extends uvm_sequence_item;

  `uvm_object_utils(eth_frame_txn)

  // 帧字节（DA 起、不含 preamble/SFD/FCS）
  byte unsigned data[$];

  // 接收侧校验结果（发送侧恒为 1）
  bit crc_ok      = 1;
  bit preamble_ok = 1;

  function new(string name = "eth_frame_txn");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    eth_frame_txn t;
    super.do_copy(rhs);
    if ($cast(t, rhs)) begin
      data        = t.data;
      crc_ok      = t.crc_ok;
      preamble_ok = t.preamble_ok;
    end
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    eth_frame_txn t;
    if (!$cast(t, rhs)) return 0;
    if (data.size() != t.data.size()) return 0;
    foreach (data[i]) if (data[i] != t.data[i]) return 0;
    return 1;
  endfunction

  virtual function string convert2string();
    return $sformatf("frame len=%0d crc_ok=%0b preamble_ok=%0b",
                     data.size(), crc_ok, preamble_ok);
  endfunction

endclass

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

  // 主动模式：1 = 例化 sequencer/driver 充当 MAC 发流；0 = 仅 BFM+monitor
  bit is_active = 1;

  // 每帧之后驱动的全空闲拍数（8 字节/拍；2 拍 = 16 字节 ≥ 最小 IPG 12）
  int idle_words_per_gap = 2;

  // 多 lane（Clause 82 MLD，40G=4）：1 = 单 lane 经典路径；>1 时启用
  // MLD 分发/重组，串行接口用 vif_serial_lanes[0..num_lanes-1]，
  // vif_serial 不用。MLD 模式下 fec_enable 必须为 0（未支持叠加）。
  int num_lanes = 1;

  // 每 lane AM 间隔（标准 16384；仿真提速可调小，两端一致即可）
  int am_spacing = 16384;

  // 边界接口句柄：由 test 从 config_db 取得后填入
  virtual xgmii_if  vif_xgmii;
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

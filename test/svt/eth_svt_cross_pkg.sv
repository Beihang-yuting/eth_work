// -----------------------------------------------------------------------------
// 所属：eth_work/test/svt —— 阶段 2：与 Synopsys svt ethernet VIP 交叉验证
// 职责：装配 "VIP MAC agent（ETH_XSBI_SERIAL，10G BASE-KR）↔ 自研 PCS/
//       SerDes agent" 的对接环境，双向检查：
//   方向 A：VIP 发帧 -> 我方 RX 解码 -> 我方 CRC/preamble/块合法性检查
//           （CRC 过 = VIP 码流被我方逐 bit 正确还原）
//   方向 B：我方 driver 发 net_packet 帧 -> 我方 TX 编码 -> VIP RX 解析
//           （VIP monitor 收帧数匹配 + VIP 内建检查器零错误 = 我方码流
//           对 VIP 合法）
// 依赖：svt_ethernet_uvm_pkg（VIP）、eth_pcs_pkg（自研 agent）、
//       eth_tb_pkg（复用 net_packet 发包序列）。
// 所有权：UVM 组件树。VIP 接口经 config_db "if_port" 由 top 注入。
// 说明：本阶段 FEC 关闭 —— 我方 Clause 74 PN-2112 采用每码字重启的简化
//       种子约定，与 VIP 实现不保证互通；FEC 互通对接单独跟进。
// -----------------------------------------------------------------------------

package eth_svt_cross_pkg;

  `include "uvm_macros.svh"
  import uvm_pkg::*;
  import svt_uvm_pkg::*;
  import svt_ethernet_uvm_pkg::*;
  import svt_ethernet_enum_pkg::*;   // ETH_XSBI_SERIAL / ETH_MAC_DATA_FRAME 等枚举
  import eth_pcs_pkg::*;
  import eth_tb_pkg::*;

  // ---------------- VIP 配置 ----------------

  // 只定制接口模式：ETH_XSBI_SERIAL = 10G BASE-KR，tx_lane[0] 1bit 串行
  class cross_svt_cfg extends svt_ethernet_agent_configuration;

    `uvm_object_utils(cross_svt_cfg)

    function new(string name = "cross_svt_cfg");
      super.new(name);
    endfunction

    function void set_kr_cfg();
      interface_select = ETH_XSBI_SERIAL;
    endfunction

    // 25G 单 lane 串行（同 64b/66b 体系，仅时钟不同）
    function void set_25g_cfg();
      interface_select = ETH_25G_SERIAL;
    endfunction

  endclass

  // ---------------- 交叉记分板 ----------------

  // 只做计数与错误闸门：字节级完整性已由两侧各自的 CRC/协议检查器覆盖
  //（见文件头说明），此处校验"每一帧都被对端收到"。
  `uvm_analysis_imp_decl(_svt_tx)
  `uvm_analysis_imp_decl(_svt_rx)
  `uvm_analysis_imp_decl(_our_tx)
  `uvm_analysis_imp_decl(_our_rx)

  class cross_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(cross_scoreboard)

    uvm_analysis_imp_svt_tx #(svt_ethernet_transaction, cross_scoreboard) svt_tx_imp;
    uvm_analysis_imp_svt_rx #(svt_ethernet_transaction, cross_scoreboard) svt_rx_imp;
    uvm_analysis_imp_our_tx #(eth_frame_txn, cross_scoreboard) our_tx_imp;
    uvm_analysis_imp_our_rx #(eth_frame_txn, cross_scoreboard) our_rx_imp;

    int vip_tx_count;   // 方向 A 期望
    int our_rx_count;   // 方向 A 实际
    int our_tx_count;   // 方向 B 期望
    int vip_rx_count;   // 方向 B 实际
    int our_rx_bad;     // 方向 A 中 CRC/preamble 脏帧

    function new(string name, uvm_component parent);
      super.new(name, parent);
      svt_tx_imp = new("svt_tx_imp", this);
      svt_rx_imp = new("svt_rx_imp", this);
      our_tx_imp = new("our_tx_imp", this);
      our_rx_imp = new("our_rx_imp", this);
    endfunction

    function void write_svt_tx(svt_ethernet_transaction t);
      vip_tx_count++;
    endfunction

    function void write_svt_rx(svt_ethernet_transaction t);
      vip_rx_count++;
    endfunction

    function void write_our_tx(eth_frame_txn t);
      our_tx_count++;
    endfunction

    function void write_our_rx(eth_frame_txn t);
      our_rx_count++;
      if (!t.crc_ok || !t.preamble_ok) begin
        our_rx_bad++;
        `uvm_error("XSB", $sformatf("方向A 脏帧: %s", t.convert2string()))
      end
    endfunction

    virtual function void check_phase(uvm_phase phase);
      if (vip_tx_count == 0 || our_tx_count == 0)
        `uvm_error("XSB", "某方向未发任何帧")
      if (our_rx_count != vip_tx_count)
        `uvm_error("XSB", $sformatf("方向A 帧数不符: VIP发 %0d 我方收 %0d",
                                    vip_tx_count, our_rx_count))
      if (vip_rx_count != our_tx_count)
        `uvm_error("XSB", $sformatf("方向B 帧数不符: 我方发 %0d VIP收 %0d",
                                    our_tx_count, vip_rx_count))
      if (our_rx_bad != 0)
        `uvm_error("XSB", $sformatf("方向A 脏帧 %0d", our_rx_bad))
      `uvm_info("XSB", $sformatf(
        "A: vip_tx=%0d our_rx=%0d bad=%0d | B: our_tx=%0d vip_rx=%0d",
        vip_tx_count, our_rx_count, our_rx_bad, our_tx_count, vip_rx_count),
        UVM_LOW)
    endfunction

  endclass

  // ---------------- VIP 发帧序列（方向 A 激励） ----------------

  // 参照 VIP 示例 directed sequence 的字段用法；递增 payload 便于人工比流
  class vip_frame_seq extends uvm_sequence #(svt_ethernet_transaction);

    `uvm_object_utils(vip_frame_seq)

    // VIP 方向帧数：受 VIP 事务生成速率限制取 500；我方方向按大流量
    // 标准 1000（见 test run_phase）
    int num_frames = 500;

    function new(string name = "vip_frame_seq");
      super.new(name);
    endfunction

    virtual task body();
      repeat (num_frames) begin
        svt_ethernet_transaction t;
        `uvm_create(t)
        t.command_type      = ETH_MAC_DATA_FRAME;
        t.address           = 48'h112233445566;
        t.command_mode_data = ETH_INCR;
        t.byte_count        = 46 + $urandom_range(0, 200);
        `uvm_send(t)
      end
    endtask

  endclass

  // ---------------- 对接 env ----------------

  class cross_env extends uvm_env;

    `uvm_component_utils(cross_env)

    cross_svt_cfg   vip_cfg;
    eth_pcs_cfg     phy_cfg;

    svt_ethernet_agent vip_mac;
    eth_pcs_agent      phy_agent;
    cross_scoreboard   sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(cross_svt_cfg)::get(this, "", "vip_cfg", vip_cfg))
        `uvm_fatal("CFG", "cross_env 未取得 vip_cfg")
      if (!uvm_config_db#(eth_pcs_cfg)::get(this, "", "phy_cfg", phy_cfg))
        `uvm_fatal("CFG", "cross_env 未取得 phy_cfg")

      uvm_config_db#(svt_ethernet_agent_configuration)::set(
        this, "vip_mac*", "cfg", vip_cfg);
      uvm_config_db#(int)::set(this, "vip_mac*", "is_active", UVM_ACTIVE);
      uvm_config_db#(eth_pcs_cfg)::set(this, "phy_agent", "cfg", phy_cfg);

      vip_mac   = svt_ethernet_agent::type_id::create("vip_mac", this);
      phy_agent = eth_pcs_agent::type_id::create("phy_agent", this);
      sb        = cross_scoreboard::type_id::create("sb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      vip_mac.monitor.item_collected_port_tx.connect(sb.svt_tx_imp);
      vip_mac.monitor.item_collected_port_rx.connect(sb.svt_rx_imp);
      phy_agent.drv.tx_ap.connect(sb.our_tx_imp);
      phy_agent.mon.rx_ap.connect(sb.our_rx_imp);
    endfunction

  endclass

  // ---------------- 交叉验证测试 ----------------

  class eth_svt_cross_test extends uvm_test;

    `uvm_component_utils(eth_svt_cross_test)

    cross_env env;

    // 大流量：VIP 侧 500 帧 + 我方 1000 帧
    protected time run_timeout = 200ms;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      cross_svt_cfg vip_cfg;
      eth_pcs_cfg   phy_cfg;
      virtual xgmii_if  vx;
      virtual serial_if vs;

      super.build_phase(phase);

      if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif_xgmii_p", vx) ||
          !uvm_config_db#(virtual serial_if)::get(this, "", "vif_serial_p", vs))
        `uvm_fatal("CFG", "test 未取得自研 agent 接口句柄")

      vip_cfg = cross_svt_cfg::type_id::create("vip_cfg");

      // +SPEED=25g 切 25G 串行模式（与 top_svt 的时钟选择同一 plusarg）
      begin
        string speed = "10g";
        void'($value$plusargs("SPEED=%s", speed));
        if (speed == "25g") vip_cfg.set_25g_cfg();
        else                vip_cfg.set_kr_cfg();
      end

      vip_cfg.mac_address[0] = 48'h000000004455;

      phy_cfg = eth_pcs_cfg::type_id::create("phy_cfg");
      phy_cfg.is_active  = 1;
      phy_cfg.fec_enable = 0;
      phy_cfg.vif_xgmii  = vx;
      phy_cfg.vif_serial = vs;

      uvm_config_db#(cross_svt_cfg)::set(this, "env", "vip_cfg", vip_cfg);
      uvm_config_db#(eth_pcs_cfg)::set(this, "env", "phy_cfg", phy_cfg);

      env = cross_env::type_id::create("env", this);
    endfunction

    // 双向发流：先等我方 RX 对 VIP idle 码流锁定（VIP 侧对齐由其内部
    // 状态机完成，只能靠时间裕量），再并发两方向序列，最后等计数收齐。
    virtual task run_phase(uvm_phase phase);
      vip_frame_seq    seq_a = vip_frame_seq::type_id::create("seq_a");
      eth_loopback_seq seq_b = eth_loopback_seq::type_id::create("seq_b");

      seq_b.num_frames = 1000;

      phase.raise_objection(this);

      // 等锁加诊断与上限：每 20us 打印一次对齐状态（slip/invalid），
      // 500us 仍未锁按 FATAL 终止 —— 避免高事件密度速率下磨到全局
      // 超时（等价挂死），且现场数据直接指向失锁原因
      begin
        int waited_us = 0;
        while (!env.phy_agent.bfm.rx_locked()) begin
          #20us;
          waited_us += 20;
          `uvm_info("TEST", $sformatf(
            "等锁 %0dus: locked=%0b slip=%0d invalid=%0d",
            waited_us, env.phy_agent.bfm.rx_locked(),
            env.phy_agent.bfm.get_slip_count(),
            env.phy_agent.bfm.invalid_block_count), UVM_LOW)
          if (waited_us >= 500)
            `uvm_fatal("TEST", "500us 未锁定 —— 对端码流不兼容或未起流")
        end
      end
      #5us;

      fork
        seq_a.start(env.vip_mac.sequencer);
        seq_b.start(env.phy_agent.sqr);
      join

      fork begin
        fork
          wait (env.sb.our_rx_count >= seq_a.num_frames &&
                env.sb.vip_rx_count >= seq_b.num_frames);
          begin
            #run_timeout;
            `uvm_error("TEST", $sformatf(
              "超时: A vip_tx=%0d our_rx=%0d | B our_tx=%0d vip_rx=%0d",
              env.sb.vip_tx_count, env.sb.our_rx_count,
              env.sb.our_tx_count, env.sb.vip_rx_count))
          end
        join_any
        disable fork;
      end join

      #10us;   // 拖尾：让 monitor 收尾帧

      phase.drop_objection(this);
    endtask

  endclass

endpackage

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
  // VIP 组件接齐说明（用户 2026-09-10 要求）：
  //   ① 协议 checker：enable_all_protocol_checks（VIP 默认已开，显式置位
  //      防被随机化改写）—— MAC/PCS/AN 全套 err_check 生效
  //   ② 功能覆盖率：MAC/PCS/AN 三类 cov 收集器（默认关，须显式开）
  //   ③ 驱动分析端口：enable_driver_analysis_port（VIP 发出的激励流，
  //      与 monitor 观测流互为佐证）
  //   ④ 双向 monitor 端口：TX/RX 各自接记分板（已有）
  // 注：svt_ethernet_virtual_sequencer 只存在于 VIP 示例（OVM 本地类），
  //   VIP 包内无此类，故不例化。
  class cross_svt_cfg extends svt_ethernet_agent_configuration;

    `uvm_object_utils(cross_svt_cfg)

    function new(string name = "cross_svt_cfg");
      super.new(name);
    endfunction

    // 全部 VIP checker + 覆盖率收集器一次开齐（各 set_*_cfg 共用）
    function void enable_all_vip_components();
      enable_all_protocol_checks   = 1'b1;   // MAC/PCS/AN 全套协议检查
      enable_mac_transaction_cov   = 1'b1;   // MAC 事务覆盖率
      enable_mac_cov               = 1'b1;   // MAC 层覆盖率
      enable_pcs_cov               = 1'b1;   // PCS 层覆盖率
      enable_an_cov                = 1'b1;   // 自协商覆盖率
      enable_driver_analysis_port  = 1'b1;   // 驱动侧激励流分析端口
    endfunction

    function void set_kr_cfg();
      interface_select = ETH_XSBI_SERIAL;
      enable_all_vip_components();
    endfunction

    // 25G 单 lane 串行（同 64b/66b 体系，仅时钟不同）
    function void set_25g_cfg();
      interface_select = ETH_25G_SERIAL;
      enable_all_vip_components();
    endfunction

    // 40G 4 lane 串行（BASE-KR4，tx_lane[3:0]，MLD/AM 按标准 16384）
    // Clause 73 自协商：VIP 独立接口模式，AN 完成（HCD=10G BASE-R）后
    // 自动切入 10G 串行数据模式（tx_lane[0]，同 XSBI 通路）
    function void set_an73_cfg();
      interface_select = ETH_AN_CL73;
      enable_an73_hcd  = ENABLE_AN73_HCD_10G_BASER;
      enable_fec       = 2'h0;
      enable_an73_reneg = 0;
      enable_all_vip_components();
    endfunction

    // 1000BASE-X 串行（8b/10b，tx_lane[0]，1.25Gbaud）；关 Clause 37 AN
    //（我方 BASE-X 未实现 /C/ 配置交换，上电直接进数据态）
    function void set_1g_cfg();
      interface_select = ETH_1G_BASEX_1BIT;
      enable_an37_mode = 1'b0;
      enable_all_vip_components();
    endfunction

    // 2.5GBASE-X 串行（8b/10b，tx_lane[0]，3.125Gbaud）；关 Clause 37 AN
    function void set_2p5g_cfg();
      interface_select = ETH_2PT5G_BASEX_SERIAL;
      enable_an37_mode = 1'b0;
      enable_all_vip_components();
    endfunction

    function void set_40g_cfg();
      interface_select = ETH_XLSBI_SERIAL;
      // AM 间隔与我方 BFM 统一为 64（VIP 默认值，合理约束仅 {64,128,256}；
      // 标准 16384 超出 VIP 支持范围）。不配则 VIP RX 按 64 检查我方
      // 16384 间隔的码流，每周期报 invalid_align/bip，累计阈值后 VIP
      // 内部复位并扰乱其 TX（方向 A 固定 2277us 处 76 块乱码的根因）。
      xlsbi_40g_align_timer = 64;
      enable_all_vip_components();
    endfunction

  endclass

  // ---------------- 40G AM/BIP checker 降级 ----------------

  // 历史工具（现未注册）：AM/BIP 差异根因已定位为 VIP align_timer
  // 默认 64 与我方 16384 不一致，配置统一后 checker 应过。保留本类
  // 供后续调试单独降级使用。
  class xlsbi_am_bip_demoter extends uvm_report_catcher;

    `uvm_object_utils(xlsbi_am_bip_demoter)

    function new(string name = "xlsbi_am_bip_demoter");
      super.new(name);
    endfunction

    virtual function action_e catch();
      if (get_severity() == UVM_ERROR &&
          (!uvm_re_match(".*svt_err_xlsbi_invalid_bip.*", get_id()) ||
           !uvm_re_match(".*svt_err_xlsbi_invalid_align.*", get_id())))
        set_severity(UVM_WARNING);
      return THROW;
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

    // 收齐后置位：双向计数已达标，之后 A 向再来的帧是 VIP driver 收尾
    // /objection 拖尾期的线路伪影（非协议流量），只记 INFO 不计数。
    // 若真丢帧导致计数未达标，wait 不会满足、本位不会置位，错误照常暴露。
    bit draining;

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
      if (draining) begin
        `uvm_info("XSB", $sformatf("drain 期方向A 帧(忽略): %s",
                                   t.convert2string()), UVM_LOW)
        return;
      end
      our_rx_count++;
      if (!t.crc_ok || !t.preamble_ok) begin
        our_rx_bad++;
        `uvm_error("XSB", $sformatf("方向A 脏帧(第 %0d 帧): %s",
                                    our_rx_count, t.convert2string()))
      end
    endfunction

    // 段间清零（复位恢复测试用）：各方向计数与脏帧计数全清
    function void clear();
      vip_tx_count = 0;
      our_rx_count = 0;
      our_tx_count = 0;
      vip_rx_count = 0;
      our_rx_bad   = 0;
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

  // ---------------- 复位窗 VIP checker 降级 ----------------

  // 我方 PHY 中途复位会让对端 VIP 看到断流/失锁，其 register_fail:* 系
  // 列（sync/BER/align/bip 等）在复位窗内属预期扰动，降为 WARNING；
  // 窗外（active=0）原样放行 —— 只豁免预期窗口，不掩盖真实错误。
  class vip_err_window_demoter extends uvm_report_catcher;

    `uvm_object_utils(vip_err_window_demoter)

    bit active;

    function new(string name = "vip_err_window_demoter");
      super.new(name);
    endfunction

    virtual function action_e catch();
      if (active && get_severity() == UVM_ERROR) begin
        string id = get_id();
        if (id.len() >= 13 && id.substr(0, 12) == "register_fail")
          set_severity(UVM_WARNING);
      end
      return THROW;
    endfunction

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

    // 40G（MLD）模式标志：等锁上限放宽（标准 AM 间隔对齐需 ~百 us 级）
    protected bit mld_mode = 0;

    // 1G BASE-X 模式标志：我方 agent 走 GMII + 8b/10b
    protected bit basex_mode = 0;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      cross_svt_cfg vip_cfg;
      eth_pcs_cfg   phy_cfg;
      virtual xgmii_if  vx;
      virtual serial_if vs;

      super.build_phase(phase);

      if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif_xgmii_p", vx))
        `uvm_fatal("CFG", "test 未取得 XGMII 接口句柄")
      void'(uvm_config_db#(virtual serial_if)::get(this, "", "vif_serial_p", vs));

      vip_cfg = cross_svt_cfg::type_id::create("vip_cfg");

      // +SPEED=25g 切 25G 串行模式（与 top_svt 的时钟选择同一 plusarg）
      begin
        string speed = "10g";
        void'($value$plusargs("SPEED=%s", speed));
        case (speed)
          "25g":   vip_cfg.set_25g_cfg();
          "40g":   vip_cfg.set_40g_cfg();
          "an73":  vip_cfg.set_an73_cfg();
          "1g":    vip_cfg.set_1g_cfg();
          "2.5g":  vip_cfg.set_2p5g_cfg();
          default: vip_cfg.set_kr_cfg();
        endcase
        mld_mode   = (speed == "40g");
        basex_mode = (speed == "1g" || speed == "2.5g");
      end

      vip_cfg.mac_address[0] = 48'h000000004455;

      phy_cfg = eth_pcs_cfg::type_id::create("phy_cfg");
      phy_cfg.is_active  = 1;
      phy_cfg.fec_enable = 0;
      phy_cfg.vif_xgmii  = vx;
      phy_cfg.vif_serial = vs;

      // 1G BASE-X：MAC 侧改走 GMII
      if (basex_mode) begin
        phy_cfg.basex = 1;
        if (!uvm_config_db#(virtual gmii_if)::get(this, "", "vif_gmii_p",
                                                  phy_cfg.vif_gmii))
          `uvm_fatal("CFG", "未取得 vif_gmii_p（top_svt 下发）")
      end

      // 40G：4 lane + AM 间隔 64（与 VIP xlsbi_40g_align_timer 一致，
      // 见 set_40g_cfg 注释；必须与 VIP 一致才能互通）
      if (mld_mode) begin
        phy_cfg.num_lanes  = 4;
        phy_cfg.am_spacing = 64;
        for (int i = 0; i < 4; i++)
          if (!uvm_config_db#(virtual serial_if)::get(this, "",
                $sformatf("vif_serial_p_l%0d", i),
                phy_cfg.vif_serial_lanes[i]))
            `uvm_fatal("CFG", $sformatf("未取得 40g lane%0d 接口", i))
      end


      uvm_config_db#(cross_svt_cfg)::set(this, "env", "vip_cfg", vip_cfg);
      uvm_config_db#(eth_pcs_cfg)::set(this, "env", "phy_cfg", phy_cfg);

      env = cross_env::type_id::create("env", this);
    endfunction

    // 等锁加诊断与上限：每 20us 打印一次对齐状态（slip/invalid），
    // 超上限按 FATAL 终止 —— 避免高事件密度速率下磨到全局超时
    //（等价挂死），且现场数据直接指向失锁原因
    protected task wait_lock();
      int waited_us = 0;
      while (!env.phy_agent.bfm.rx_locked()) begin
        #20us;
        waited_us += 20;
        `uvm_info("TEST", $sformatf(
          "等锁 %0dus: locked=%0b slip=%0d invalid=%0d",
          waited_us, env.phy_agent.bfm.rx_locked(),
          env.phy_agent.bfm.get_slip_count(),
          env.phy_agent.bfm.invalid_block_count), UVM_LOW)
        if (waited_us >= (mld_mode ? 2000 : 500))
          `uvm_fatal("TEST", "等锁超时 —— 对端码流不兼容或未起流")
      end
      #5us;
    endtask

    // 一段双向流量：A 向 na 帧 + B 向 nb 帧并发，等计数收齐（相对当前
    // 计数为增量，段前如需清零由调用方 sb.clear()）
    protected task run_traffic(int na, int nb);
      vip_frame_seq    seq_a = vip_frame_seq::type_id::create("seq_a");
      eth_loopback_seq seq_b = eth_loopback_seq::type_id::create("seq_b");
      seq_a.num_frames = na;
      seq_b.num_frames = nb;

      fork
        seq_a.start(env.vip_mac.sequencer);
        seq_b.start(env.phy_agent.sqr);
      join

      fork begin
        fork
          wait (env.sb.our_rx_count >= na && env.sb.vip_rx_count >= nb);
          forever begin
            #10us;
            `uvm_info("TEST", $sformatf(
              "进度: A=%0d(bad=%0d) B=%0d invalid=%0d slip=%0d",
              env.sb.our_rx_count, env.sb.our_rx_bad, env.sb.vip_rx_count,
              env.phy_agent.bfm.invalid_block_count,
              env.phy_agent.bfm.get_slip_count()), UVM_LOW)
          end
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
    endtask

    // 双向发流：先等我方 RX 对 VIP idle 码流锁定（VIP 侧对齐由其内部
    // 状态机完成，只能靠时间裕量），再并发两方向序列，最后等计数收齐。
    virtual task run_phase(uvm_phase phase);
      int na = 500, nb = 1000;
      void'($value$plusargs("A_FRAMES=%d", na));
      void'($value$plusargs("B_FRAMES=%d", nb));

      phase.raise_objection(this);
      wait_lock();
      run_traffic(na, nb);

      env.sb.draining = 1;

      #10us;   // 拖尾：让 monitor 收尾帧

      phase.drop_objection(this);
    endtask

  endclass

  // ---------------- AN(cl73) DME 波形探针 ----------------

  // 目的：VIP 在 ETH_AN_CL73 下持续发送 DME 页；本测试只采样其 TX 线
  // 上的跳变时序（delta 时间 + 新值），作为我方 DME 编解码实现的
  // ground truth（凭规范记忆猜实现细节的教训见 40G AM 章节）。
  // 我方 TX 为 idle 码流，VIP checker 会报错 —— 全程降级。
  class eth_svt_an_probe_test extends eth_svt_cross_test;

    `uvm_component_utils(eth_svt_an_probe_test)

    protected vip_err_window_demoter dem;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      dem = vip_err_window_demoter::type_id::create("dem");
      dem.active = 1;
      uvm_report_cb::add(null, dem);
    endfunction

    virtual task run_phase(uvm_phase phase);
      virtual serial_if vs;
      logic prev;
      realtime tprev;
      int n = 0;

      if (!uvm_config_db#(virtual serial_if)::get(this, "", "vif_serial_p", vs))
        `uvm_fatal("CFG", "probe 未取得串行接口")

      phase.raise_objection(this);

      prev  = vs.rx_bit;
      tprev = $realtime;
      while (n < 2000) begin
        @(vs.rx_bit);
        $display("[ANPROBE] @%0t delta=%0t val=%b",
                 $realtime, $realtime - tprev, vs.rx_bit);
        tprev = $realtime;
        n++;
      end

      `uvm_info("TEST", "ANPROBE_DONE", UVM_LOW)
      phase.drop_objection(this);
    endtask

  endclass

  // ---------------- 交叉中途复位恢复测试 ----------------

  // 流量中途复位我方 PHY（VIP 持续在线），检验重锁与流量恢复：
  // 每轮 = 段流量收齐 -> 复位（复位窗内 VIP checker 降级、计分暂停）
  // -> 重锁 -> 清计数；末段流量后按段计数判定。覆盖多轮复位。
  class eth_svt_cross_reset_test extends eth_svt_cross_test;

    `uvm_component_utils(eth_svt_cross_reset_test)

    protected virtual tb_ctrl_if ctrl;
    protected vip_err_window_demoter dem;

    // 复位轮数（段数 = 轮数 + 1）
    localparam int RESET_ROUNDS = 3;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual tb_ctrl_if)::get(this, "", "tb_ctrl", ctrl))
        `uvm_fatal("CFG", "未取得 tb_ctrl 接口（top_svt 下发）")
      dem = vip_err_window_demoter::type_id::create("dem");
      uvm_report_cb::add(null, dem);
    endfunction

    virtual task run_phase(uvm_phase phase);
      int na = 100, nb = 200;
      void'($value$plusargs("A_FRAMES=%d", na));
      void'($value$plusargs("B_FRAMES=%d", nb));

      phase.raise_objection(this);
      wait_lock();

      for (int round = 0; round <= RESET_ROUNDS; round++) begin
        run_traffic(na, nb);
        `uvm_info("TEST", $sformatf(
          "第 %0d 段流量收齐: A=%0d B=%0d bad=%0d", round,
          env.sb.our_rx_count, env.sb.vip_rx_count, env.sb.our_rx_bad),
          UVM_LOW)
        if (env.sb.our_rx_bad != 0)
          `uvm_error("TEST", $sformatf("第 %0d 段方向A 脏帧 %0d",
                                       round, env.sb.our_rx_bad))
        if (round == RESET_ROUNDS) break;

        // 复位窗开：对端预期报错降级 + 我方计分暂停
        dem.active      = 1;
        env.sb.draining = 1;

        ctrl.reset_req = 1;
        wait (!ctrl.reset_req);   // top 完成复位脉冲的握手
        wait_lock();              // 我方重锁 VIP 码流（多 lane 含同周期
                                  // 锚定收敛，见 mld_rx 去偏斜注释）
        #20us;                    // VIP 端重对齐我方新码流裕量

        // 复位窗关：清段计数重新计
        env.sb.clear();
        env.sb.draining = 0;
        dem.active      = 0;
      end

      `uvm_info("TEST", $sformatf("CROSS_RESET_RECOVERY_PASS rounds=%0d",
                                  RESET_ROUNDS), UVM_LOW)
      env.sb.draining = 1;
      #10us;
      phase.drop_objection(this);
    endtask

  endclass

endpackage

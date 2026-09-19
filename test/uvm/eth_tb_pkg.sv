// -----------------------------------------------------------------------------
// 所属：eth_work/test/uvm —— 阶段 1 环回验证环境 package
// 职责：定义发包序列（复用 net_packet 生成真实协议报文）、字节级记分板、
//       双 agent 环回 env 与两个冒烟测试（FEC 关/开）。
// 依赖：eth_pcs_pkg（agent 组件）、third_party/net_packet（报文生成，
//       经 +incdir 以 include 方式并入本 package）。
// 所有权：UVM 组件树；run_test 创建 test，其余随树存续。
// -----------------------------------------------------------------------------

package eth_tb_pkg;

  `include "uvm_macros.svh"
  import uvm_pkg::*;
  import eth_pcs_pkg::*;

  // net_packet 以 include 并入（自带 include guard；只用 packet 类本身，
  // 不用其 UVM 包装，避免与本环境的事务体系重叠）
  `include "core/protocol_graph.sv"
  `include "core/template_registry.sv"
  `include "core/packet.sv"

  // ---------------- 发包序列 ----------------

  // 为什么在 sequence 层适配 net_packet：agent 只认字节流事务，报文
  // 结构知识（协议链、字段随机化、长度约束）全部留在生成端，两者可
  // 独立演化 —— 换发包器不动 agent，换 agent 不动发包器。
  class eth_loopback_seq extends uvm_sequence #(eth_frame_txn);

    `uvm_object_utils(eth_loopback_seq)

    // 发送帧数（test 配置）
    int num_frames = 20;

    function new(string name = "eth_loopback_seq");
      super.new(name);
    endfunction

    // 每帧：net_packet 随机模板构包 -> 打包字节 -> 交 driver。
    // 失败路径：raw_data 短于 60 字节时补零到最小帧长（FCS 由 driver
    // 层统一追加，此处不管）。
    virtual task body();
      packet_template_e tmpls[3] = '{ETH_IPV4_TCP, ETH_IPV4_UDP, ETH_ARP};

      repeat (num_frames) begin
        eth_frame_txn t = eth_frame_txn::type_id::create("tx_frame");
        packet pkt = new();

        pkt.build_from_template(tmpls[$urandom_range(0, 2)]);
        pkt.randomize_all();
        pkt.do_pack();

        t.data = pkt.raw_data;
        while (t.data.size() < 60) t.data.push_back(8'h00);

        // 源 MAC 强制单播：随机地址可能置组播位（SA[0].bit0），
        // 802.3 禁止组播源地址，对端 framing 检查器会报错
        if (t.data.size() > 6) t.data[6] &= 8'hfe;

        start_item(t);
        finish_item(t);
      end
    endtask

  endclass

  // ---------------- 记分板 ----------------

  // 期望流 = A 端 driver 发送记录；实际流 = B 端 monitor 观测。
  // 按序逐帧字节比对 —— PCS 链路不允许乱序/丢帧，任何差异即环境错误。
  `uvm_analysis_imp_decl(_exp)
  `uvm_analysis_imp_decl(_act)

  class eth_loopback_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(eth_loopback_scoreboard)

    uvm_analysis_imp_exp #(eth_frame_txn, eth_loopback_scoreboard) exp_imp;
    uvm_analysis_imp_act #(eth_frame_txn, eth_loopback_scoreboard) act_imp;

    protected eth_frame_txn exp_q[$];

    int match_count;
    int mismatch_count;

    // 宽松模式（链路扰动窗口用）：容忍丢帧与坏帧，只对"内容干净却与
    // 任何期望都不匹配"的帧计 mismatch —— 扰动只该毁帧，不该造出新帧
    bit lenient = 0;
    int lost_count;        // 宽松模式下按序跳过的期望帧数
    int disturbed_bad;     // 宽松模式下收到的坏帧（CRC/preamble 脏）

    // 段间清零：复位/扰动测试在严格段开始前调用
    function void clear();
      exp_q.delete();
      match_count    = 0;
      mismatch_count = 0;
      lost_count     = 0;
      disturbed_bad  = 0;
    endfunction

    // 结算未到达的期望帧（宽松段收尾时调用，全部计入 lost）
    function void flush_pending_as_lost();
      lost_count += exp_q.size();
      exp_q.delete();
    endfunction

    function new(string name, uvm_component parent);
      super.new(name, parent);
      exp_imp = new("exp_imp", this);
      act_imp = new("act_imp", this);
    endfunction

    function void write_exp(eth_frame_txn t);
      eth_frame_txn c;
      $cast(c, t.clone());
      exp_q.push_back(c);
    endfunction

    // 实际帧到达：与队首期望比对。接收侧 CRC/preamble 必须干净 ——
    // 这正是"协议完整性"的帧级判据。
    // 宽松模式：坏帧计 disturbed_bad；干净帧向后搜索期望队列，跳过的
    // 期望计 lost（扰动毁掉的在途帧），仍无匹配才算 mismatch。
    function void write_act(eth_frame_txn t);
      eth_frame_txn e;

      if (lenient) begin
        int idx = -1;

        if (!t.crc_ok || !t.preamble_ok) begin
          disturbed_bad++;
          return;
        end
        foreach (exp_q[i])
          if (exp_q[i].compare(t)) begin idx = i; break; end
        if (idx >= 0) begin
          lost_count += idx;
          repeat (idx + 1) void'(exp_q.pop_front());
          match_count++;
        end
        else begin
          `uvm_error("SB", $sformatf("宽松段出现无来源干净帧: %s",
                                     t.convert2string()))
          mismatch_count++;
        end
        return;
      end

      if (exp_q.size() == 0) begin
        `uvm_error("SB", $sformatf("多余接收帧: %s", t.convert2string()))
        mismatch_count++;
        return;
      end

      e = exp_q.pop_front();
      if (!t.crc_ok || !t.preamble_ok || !e.compare(t)) begin
        `uvm_error("SB", $sformatf("帧比对失败 exp=%s act=%s",
                                   e.convert2string(), t.convert2string()))
        mismatch_count++;
      end
      else begin
        match_count++;
      end
    endfunction

    virtual function void check_phase(uvm_phase phase);
      if (match_count == 0)
        `uvm_error("SB", "未收到任何匹配帧")
      if (exp_q.size() != 0)
        `uvm_error("SB", $sformatf("仍有 %0d 帧未接收", exp_q.size()))
      if (mismatch_count != 0)
        `uvm_error("SB", $sformatf("mismatch=%0d", mismatch_count))
      `uvm_info("SB", $sformatf("match=%0d mismatch=%0d",
                                match_count, mismatch_count), UVM_LOW)
    endfunction

  endclass

  // ---------------- 环回 env ----------------

  // A 端主动发流，B 端被动接收；top 已把 A.serial.tx 接到 B.serial.rx
  //（反向亦然，阶段 1 仅 A->B 方向承载流量）。
  class eth_loopback_env extends uvm_env;

    `uvm_component_utils(eth_loopback_env)

    eth_pcs_cfg cfg_a;
    eth_pcs_cfg cfg_b;

    eth_pcs_agent           agent_a;
    eth_pcs_agent           agent_b;
    eth_loopback_scoreboard sb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      // cfg 由 test 构造并放入 env 层 config_db（test 决定 FEC 开关）
      if (!uvm_config_db#(eth_pcs_cfg)::get(this, "", "cfg_a", cfg_a))
        `uvm_fatal("CFG", "env 未取得 cfg_a")
      if (!uvm_config_db#(eth_pcs_cfg)::get(this, "", "cfg_b", cfg_b))
        `uvm_fatal("CFG", "env 未取得 cfg_b")

      uvm_config_db#(eth_pcs_cfg)::set(this, "agent_a", "cfg", cfg_a);
      uvm_config_db#(eth_pcs_cfg)::set(this, "agent_b", "cfg", cfg_b);

      agent_a = eth_pcs_agent::type_id::create("agent_a", this);
      agent_b = eth_pcs_agent::type_id::create("agent_b", this);
      sb      = eth_loopback_scoreboard::type_id::create("sb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent_a.drv.tx_ap.connect(sb.exp_imp);
      agent_b.mon.rx_ap.connect(sb.act_imp);
    endfunction

  endclass

  // ---------------- 测试 ----------------

  class eth_loopback_test extends uvm_test;

    `uvm_component_utils(eth_loopback_test)

    eth_loopback_env env;

    // 子类翻转此开关复用全部装配逻辑
    protected bit fec_mode = 0;

    // 流量规模与时限（子类按场景放大；大流量为默认要求，冒烟基类保守）
    protected int  num_frames  = 20;
    protected time run_timeout = 2ms;

    // TB 控制接口（复位/扰动测试用；普通测试可为 null）
    protected virtual tb_ctrl_if vif_ctrl;

    // PCS lane 数（40g=4，100g/100g4/100gr=20，200g=8，400g=16，其余 1）与物理 lane 数
    protected int mld_lanes = 1;
    protected int mld_phys  = 1;
    protected bit is_200g   = 0;
    protected bit is_400g   = 0;
    protected bit is_100gr  = 0;   // 100GBASE-R + Clause 91 RS-FEC（4 FEC lane）

    // RX 引脚帧内见底必须为 0（形态 A 真实 MAC 看到的引脚流不能被插拍
    // 毁帧）；复位/扰动类测试会在帧中间断链，由子类关闭
    protected bit strict_pins = 1;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      eth_pcs_cfg cfg_a, cfg_b;
      virtual xgmii_if  vxa, vxb;
      virtual serial_if vsa, vsb;

      super.build_phase(phase);

      // +SPEED=40g：MLD 4 lane 模式（top 的 `eth_pcs_lb_env 提供每 lane 串行接口，
      // 键名 vif_serial_<a|b>_l<i>），AM 间隔用仿真加速值
      begin
        string speed = "10g";
        void'($value$plusargs("SPEED=%s", speed));
        mld_lanes = (speed == "40g")  ? 4  :
                    (speed == "50g")  ? 4  :
                    (speed == "200g") ? 8  :
                    (speed == "400g") ? 16 :
                    (speed == "100g" || speed == "100g4" || speed == "100gr") ? 20 : 1;
        is_200g   = (speed == "200g");
        is_400g   = (speed == "400g");
        is_100gr  = (speed == "100gr");
        mld_phys  = (speed == "50g")  ? 2  :              // 50GBASE-R：4 PCS lane → 2×25.78125G NRZ
                    (speed == "100g")  ? 10 :             // CAUI-10：2:1 复用
                    (speed == "100g4" || speed == "100gr") ? 4 : mld_lanes;
        // 100g4：CAUI-4 5:1 复用；100gr：20 PCS lane 经 RS-FEC 映射到 4 FEC lane
        // 200g：8 条 PCS lane 各占一条物理 lane（Clause 119，不走 MLD）
      end

      // +FEC：Clause 74 FEC 叠加（与各 *_fec 测试子类同效，可配任意 +SPEED）
      if ($test$plusargs("FEC")) fec_mode = 1;

      if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif_xgmii_a", vxa) ||
          !uvm_config_db#(virtual xgmii_if)::get(this, "", "vif_xgmii_b", vxb))
        `uvm_fatal("CFG", "test 未取得 XGMII 接口句柄")

      cfg_a = eth_pcs_cfg::type_id::create("cfg_a");
      cfg_a.is_active  = 1;
      cfg_a.fec_enable = fec_mode;
      cfg_a.vif_xgmii  = vxa;

      cfg_b = eth_pcs_cfg::type_id::create("cfg_b");
      cfg_b.is_active  = 0;
      cfg_b.fec_enable = fec_mode;
      cfg_b.vif_xgmii  = vxb;

      // XGMII 直驱模式（纯 MAC 功能验证提速）：发包序列零适配，
      // 链路层（PCS/串行/锁定）整体旁路，接线见 lb_env 宏的 force 段
      if ($test$plusargs("XGMII_DIRECT")) begin
        cfg_a.xgmii_direct = 1;
        cfg_b.xgmii_direct = 1;
      end

      // +LANE4：A 端 driver 奇数帧从 lane4 起帧（Clause 49 单 lane 专用，
      // 覆盖 0x33 块的编码 -> 解码 -> 帧装配）
      if ($test$plusargs("LANE4")) cfg_a.lane4_start = 1;

      // 1g/2.5g：BASE-X（8b/10b，Clause 36），MAC 侧改走 GMII
      begin
        string speed = "10g";
        void'($value$plusargs("SPEED=%s", speed));
        if (speed == "1g" || speed == "2.5g") begin
          if (fec_mode)
            `uvm_fatal("CFG", "BASE-X 不支持 FEC 测试变体");
          cfg_a.basex = 1;
          cfg_b.basex = 1;
          if (!uvm_config_db#(virtual gmii_if)::get(this, "", "vif_gmii_a",
                                                    cfg_a.vif_gmii) ||
              !uvm_config_db#(virtual gmii_if)::get(this, "", "vif_gmii_b",
                                                    cfg_b.vif_gmii))
            `uvm_fatal("CFG", "未取得 GMII 接口（lb_env 应下发 vif_gmii_a/b）")
        end
      end

      // RS-FEC：+RSFEC 开单 lane RS-FEC（25g 即 Clause 108）；100gr 自带
      // Clause 91 RS-FEC。与 cl74 的 fec_mode 互斥
      if ($test$plusargs("RSFEC") || is_100gr) begin
        if (fec_mode)
          `uvm_fatal("CFG", "RS-FEC 与 cl74 FEC 测试变体互斥");
        if (mld_lanes > 1 && !is_100gr)
          `uvm_fatal("CFG", "多 lane RS-FEC 仅 +SPEED=100gr 形态");
        cfg_a.rs_fec_enable = 1;
        cfg_b.rs_fec_enable = 1;
      end

      // BER 监视（hi_ber）：25G 及以上按 IEEE 781250 块窗 / 97 个坏头
      //（cfg 默认 10GBASE-R 的 19531 / 16）
      begin
        string speed = "10g";
        void'($value$plusargs("SPEED=%s", speed));
        if (speed == "25g" || speed == "50g" || speed == "40g" || speed == "100g" ||
            speed == "100g4" || speed == "100gr" || speed == "200g" ||
            speed == "400g") begin
          cfg_a.ber_limit = 97;
          cfg_b.ber_limit = 97;
          cfg_a.ber_window_blocks = 781250;
          cfg_b.ber_window_blocks = 781250;
        end
      end

      // Clause 72 链路训练：+LT 开启（可与 +AN 组合成完整 KR 建链
      // 序列 AN -> LT -> 数据；VIP 不支持 cl72，仅自环用）
      if ($test$plusargs("LT")) begin
        if (mld_lanes > 1)
          `uvm_fatal("CFG", "LT(cl72) 仅单 lane 路径支持");
        cfg_a.lt_enable = 1;
        cfg_b.lt_enable = 1;
      end

      // Clause 73 自协商：+AN 开启，两端 nonce 必须不同（避免碰撞）
      if ($test$plusargs("AN")) begin
        if (mld_lanes > 1)
          `uvm_fatal("CFG", "AN(cl73) 仅单 lane 路径支持");
        cfg_a.an_enable = 1;
        cfg_b.an_enable = 1;
        cfg_a.an_nonce  = 5'h05;
        cfg_b.an_nonce  = 5'h12;
      end

      if (mld_lanes > 1) begin
        cfg_a.num_lanes  = mld_lanes;
        cfg_b.num_lanes  = mld_lanes;
        cfg_a.num_phys   = mld_phys;
        cfg_b.num_phys   = mld_phys;
        cfg_a.cl119      = is_200g;
        cfg_b.cl119      = is_200g;
        cfg_a.cl400      = is_400g;
        cfg_b.cl400      = is_400g;
        // AM 间隔：40G 环回沿用 512；100G 取 64（与 VIP csbi_100g_align_timer
        // 默认一致，交叉/环回同一值；须与 top 字钟扣减的 +AM_SPACING 一致）
        cfg_a.am_spacing = is_400g ? 5440 : ((mld_lanes == 20) ? 64 :
                           ((mld_lanes == 4 && mld_phys == 2) ? 1280 : 512));
        cfg_b.am_spacing = is_400g ? 5440 : ((mld_lanes == 20) ? 64 :
                           ((mld_lanes == 4 && mld_phys == 2) ? 1280 : 512));
        // cl74 叠加（fec_mode）按 PCS lane 各一套，40g/100g 均可；与 200g /
        // 100gr 自带 RS-FEC 的冲突由 agent 配置校验拦截
        for (int i = 0; i < mld_phys; i++) begin
          if (!uvm_config_db#(virtual serial_if)::get(this, "",
                $sformatf("vif_serial_a_l%0d", i), cfg_a.vif_serial_lanes[i]) ||
              !uvm_config_db#(virtual serial_if)::get(this, "",
                $sformatf("vif_serial_b_l%0d", i), cfg_b.vif_serial_lanes[i]))
            `uvm_fatal("CFG", $sformatf("未取得 lane%0d 串行接口", i))
        end
      end
      else begin
        if (!uvm_config_db#(virtual serial_if)::get(this, "", "vif_serial_a", vsa) ||
            !uvm_config_db#(virtual serial_if)::get(this, "", "vif_serial_b", vsb))
          `uvm_fatal("CFG", "test 未取得串行接口句柄")
        cfg_a.vif_serial = vsa;
        cfg_b.vif_serial = vsb;
      end

      uvm_config_db#(eth_pcs_cfg)::set(this, "env", "cfg_a", cfg_a);
      uvm_config_db#(eth_pcs_cfg)::set(this, "env", "cfg_b", cfg_b);

      void'(uvm_config_db#(virtual tb_ctrl_if)::get(this, "", "vif_ctrl",
                                                    vif_ctrl));

      // +NUM_FRAMES=<n>：命令行临时覆盖流量规模（如 5000 帧专项复跑），
      // 不改各测试的默认标准
      begin
        int n;
        if ($value$plusargs("NUM_FRAMES=%d", n) && n > 0) begin
          num_frames  = n;
          run_timeout = 100ms;
        end
      end

      env = eth_loopback_env::type_id::create("env", this);
    endfunction

    // 等待双向链路可用（锁定且非 hi_ber）+ 解扰自同步裕量（link-up；复位
    // 后亦复用）。AN(cl73) 开启时 rx_locked() 内含"AN 完成"条件
    protected task wait_link_up();
      int waited_us = 0;
      while (!(env.agent_a.bfm.rx_link_up() && env.agent_b.bfm.rx_link_up()))
      begin
        #100ns;
        waited_us++;
        // 每 100us 打一次建链阶段现场：AN/LT 卡住时直接指出停在哪一步
        if (waited_us % 1000 == 0 &&
            (env.agent_a.cfg.an_enable || env.agent_a.cfg.lt_enable))
          `uvm_info("TEST", $sformatf(
            "建链等待 %0dus: A[AN=%s(%0d页) LT=%s(taps=%0d,%0d帧)] B[AN=%s(%0d页) LT=%s(taps=%0d,%0d帧)]",
            waited_us / 10,
            env.agent_a.bfm.an_state(), env.agent_a.bfm.an_pages(),
            env.agent_a.bfm.lt_state(), env.agent_a.bfm.lt_taps(),
            env.agent_a.bfm.lt_frames(),
            env.agent_b.bfm.an_state(), env.agent_b.bfm.an_pages(),
            env.agent_b.bfm.lt_state(), env.agent_b.bfm.lt_taps(),
            env.agent_b.bfm.lt_frames()), UVM_LOW)
      end
      if (env.agent_a.cfg.an_enable)
        `uvm_info("TEST", $sformatf("AN 完成: A=%s(%0d页) B=%s(%0d页)",
                  env.agent_a.bfm.an_state(), env.agent_a.bfm.an_pages(),
                  env.agent_b.bfm.an_state(), env.agent_b.bfm.an_pages()),
                  UVM_LOW)
      if (env.agent_a.cfg.lt_enable)
        `uvm_info("TEST", $sformatf(
                  "LT 完成: A=%s(taps=%0d,%0d帧) B=%s(taps=%0d,%0d帧)",
                  env.agent_a.bfm.lt_state(), env.agent_a.bfm.lt_taps(),
                  env.agent_a.bfm.lt_frames(),
                  env.agent_b.bfm.lt_state(), env.agent_b.bfm.lt_taps(),
                  env.agent_b.bfm.lt_frames()), UVM_LOW)
      #1us;
    endtask

    // 发 n 帧并等待记分板收齐（或超时报错）。base 为当前已结算帧数，
    // 分段测试第二段传入 0 前需先 sb.clear()。
    protected task run_traffic(int n, time tmo);
      eth_loopback_seq seq = eth_loopback_seq::type_id::create("seq");
      int base = env.sb.match_count + env.sb.mismatch_count + env.sb.lost_count;

      seq.num_frames = n;
      seq.start(env.agent_a.sqr);

      fork begin
        fork
          wait (env.sb.match_count + env.sb.mismatch_count +
                env.sb.lost_count >= base + n);
          begin
            #tmo;
            `uvm_error("TEST", $sformatf(
              "超时: match=%0d mismatch=%0d lost=%0d (期望 %0d 帧)",
              env.sb.match_count, env.sb.mismatch_count,
              env.sb.lost_count, base + n))
          end
        join_any
        disable fork;
      end join
    endtask

    // 严格段结算：该段 n 帧必须全部匹配、零错配零丢失，否则按失败上报。
    // 分段测试每个严格段都调用 —— 不能只靠末尾的完成打印或末段计数
    //（中间段超时只报 1 个 uvm_error，曾被只看汇总行的判据漏过）
    protected function void check_strict(string seg, int n);
      if (env.sb.match_count != n || env.sb.mismatch_count != 0 ||
          env.sb.lost_count != 0)
        `uvm_error("TEST", $sformatf(
          "%s 未全净: match=%0d/%0d mismatch=%0d lost=%0d", seg,
          env.sb.match_count, n, env.sb.mismatch_count, env.sb.lost_count))
    endfunction

    virtual function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (strict_pins && (env.agent_a.bfm.rxpin_midframe_underrun != 0 ||
                          env.agent_b.bfm.rxpin_midframe_underrun != 0))
        `uvm_error("TEST", $sformatf("RX 引脚帧内见底 A=%0d B=%0d",
                   env.agent_a.bfm.rxpin_midframe_underrun,
                   env.agent_b.bfm.rxpin_midframe_underrun))
    endfunction

    // 发流后等记分板收齐或超时。超时按失败处理 —— 挂死型缺陷（失锁、
    // 流水线断流）必须显式暴露而不是靠全局 timeout 掩盖。
    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);

      // link-up：双向对齐锁定 + 裕量，否则锁定期内发出的帧必然丢失
      wait_link_up();
      run_traffic(num_frames, run_timeout);

      phase.drop_objection(this);
    endtask

  endclass

  // FEC 使能版冒烟测试
  class eth_loopback_fec_test extends eth_loopback_test;

    `uvm_component_utils(eth_loopback_fec_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      fec_mode = 1;
    endfunction

  endclass

  // ---------------- 大流量压力测试 ----------------

  // 1000 帧背靠背随机模板/长度（大流量标准）；判据与冒烟相同：
  // 零丢零错，另在 check 里核对 tx_underrun==0（速率匹配无断流）
  // AN(cl73) 建链后跑流量：验证"协商完成 -> 数据模式切换 -> 流量正常"
  // 的完整 KR 上电路径。判据 = AN 双端完成 + 帧全匹配。
  class eth_an_loopback_test extends eth_loopback_test;

    `uvm_component_utils(eth_an_loopback_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      num_frames  = 100;
      run_timeout = 10ms;
    endfunction

    virtual function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (!env.agent_a.bfm.an_done() || !env.agent_b.bfm.an_done())
        `uvm_error("TEST", "AN 未完成")
      else
        `uvm_info("TEST", $sformatf("AN_LINKUP_PASS A页=%0d B页=%0d",
                  env.agent_a.bfm.an_pages(), env.agent_b.bfm.an_pages()),
                  UVM_LOW)
    endfunction

  endclass

  // KR 完整建链：AN(cl73) -> LT(cl72) -> 数据模式 -> 流量。
  // 判据 = 双端 AN 完成 + LT 三抽头收敛 + 帧全匹配。
  class eth_kr_linkup_test extends eth_loopback_test;

    `uvm_component_utils(eth_kr_linkup_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      num_frames  = 100;
      run_timeout = 10ms;
    endfunction

    virtual function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (!env.agent_a.bfm.an_done() || !env.agent_b.bfm.an_done())
        `uvm_error("TEST", "AN 未完成")
      else if (!env.agent_a.bfm.lt_done() || !env.agent_b.bfm.lt_done())
        `uvm_error("TEST", "LT 未完成")
      else if (env.agent_a.bfm.lt_taps() != 3 ||
               env.agent_b.bfm.lt_taps() != 3)
        `uvm_error("TEST", "LT 抽头未全部收敛")
      else
        `uvm_info("TEST", $sformatf(
                  "KR_LINKUP_PASS AN页=%0d/%0d LT帧=%0d/%0d",
                  env.agent_a.bfm.an_pages(), env.agent_b.bfm.an_pages(),
                  env.agent_a.bfm.lt_frames(), env.agent_b.bfm.lt_frames()),
                  UVM_LOW)
    endfunction

  endclass

  class eth_stress_test extends eth_loopback_test;

    `uvm_component_utils(eth_stress_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      num_frames  = 1000;
      run_timeout = 20ms;
    endfunction

    virtual function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      if (env.agent_a.bfm.tx_underrun_count != 0)
        `uvm_error("TEST", $sformatf("发送断流 %0d 次",
                                     env.agent_a.bfm.tx_underrun_count))
    endfunction

  endclass

  // FEC 使能大流量
  class eth_stress_fec_test extends eth_stress_test;

    `uvm_component_utils(eth_stress_fec_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      fec_mode = 1;
    endfunction

  endclass

  // ---------------- 中途复位恢复测试 ----------------

  // 段1 大流量收齐 -> 中途复位 -> 重新 link-up -> 段2 大流量必须
  // 零丢零错 —— 验证复位清态彻底、复位后链路与流量完全正常
  class eth_reset_recovery_test extends eth_loopback_test;

    `uvm_component_utils(eth_reset_recovery_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      num_frames  = 500;     // 每段 500，全测试合计 1000 帧
      run_timeout = 100ms;
      strict_pins = 0;       // 复位斩断在途帧
    endfunction

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);

      if (vif_ctrl == null)
        `uvm_fatal("TEST", "复位测试需要 top 提供 tb_ctrl_if")

      // 段1：正常大流量
      wait_link_up();
      run_traffic(num_frames, run_timeout);
      check_strict("段1", num_frames);
      `uvm_info("TEST", $sformatf("段1 完成 match=%0d", env.sb.match_count),
                UVM_LOW)

      // 中途复位：请求脉冲并等待 top 完成握手
      vif_ctrl.reset_req = 1;
      wait (vif_ctrl.reset_req == 0);

      // 复位丢弃在途状态；清零记分板后重新 link-up
      env.sb.clear();
      wait_link_up();

      // 段2：复位后的流量必须完全干净
      run_traffic(num_frames, run_timeout);
      check_strict("段2(复位后)", num_frames);
      `uvm_info("TEST", $sformatf("段2(复位后) 完成 match=%0d",
                                  env.sb.match_count), UVM_LOW)

      phase.drop_objection(this);
    endtask

  endclass

  // ---------------- 多次复位覆盖测试 ----------------

  // 多轮"流量进行中拉复位"：每轮先起流量、中途随机时刻复位（宽松结算
  // 被斩断的在途帧），重新 link-up 后跑严格段验证复位后流量完全干净。
  // 覆盖点：复位打断帧传输、连续多次复位后状态清理彻底性、每轮
  // 重新锁定与恢复。
  class eth_multi_reset_test extends eth_loopback_test;

    `uvm_component_utils(eth_multi_reset_test)

    // 复位轮数与每段帧数
    protected int num_rounds = 5;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      num_frames  = 500;
      run_timeout = 100ms;
      strict_pins = 0;       // 复位斩断在途帧
    endfunction

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);

      if (vif_ctrl == null)
        `uvm_fatal("TEST", "多次复位测试需要 top 提供 tb_ctrl_if")

      wait_link_up();

      for (int round = 0; round < num_rounds; round++) begin

        // 流量进行中复位：宽松模式起流，随机延迟后拉复位斩断在途帧
        env.sb.lenient = 1;
        fork
          begin
            eth_loopback_seq s = eth_loopback_seq::type_id::create("s_mid");
            s.num_frames = num_frames;
            s.start(env.agent_a.sqr);
          end
          begin
            #($urandom_range(5, 30) * 1us);
            vif_ctrl.reset_req = 1;
            wait (vif_ctrl.reset_req == 0);
          end
        join

        // 排空 + 结算：被复位毁掉的帧计 lost，凭空帧零容忍。先等 driver
        // 队列发空（速率无关，同扰动测试的教训）再留管线裕量
        while (!env.agent_a.drv.is_idle()) #1us;   // 轮询，理由见扰动测试
        #50us;
        env.sb.flush_pending_as_lost();
        `uvm_info("TEST", $sformatf(
          "第 %0d 轮复位段: match=%0d lost=%0d bad=%0d mismatch=%0d",
          round + 1, env.sb.match_count, env.sb.lost_count,
          env.sb.disturbed_bad, env.sb.mismatch_count), UVM_LOW)
        if (env.sb.mismatch_count != 0)
          `uvm_error("TEST", $sformatf("第 %0d 轮复位段出现错配帧", round + 1))

        // 复位后重建：清残帧装配态、清记分板、重新 link-up
        env.agent_b.mon.reset_assembler();
        env.sb.clear();
        env.sb.lenient = 0;
        wait_link_up();

        // 复位后严格段：全净才算恢复成功（逐轮判定）
        run_traffic(num_frames, run_timeout);
        check_strict($sformatf("第 %0d 轮复位后严格段", round + 1), num_frames);
        `uvm_info("TEST", $sformatf("第 %0d 轮复位后严格段 完成 match=%0d",
                                    round + 1, env.sb.match_count), UVM_LOW)

        // 末轮结果保留给 check_phase 汇总，其余轮间清零
        if (round != num_rounds - 1) env.sb.clear();
      end

      `uvm_info("TEST", $sformatf("多次复位覆盖完成: %0d 轮", num_rounds),
                UVM_LOW)

      phase.drop_objection(this);
    endtask

  endclass

  // ---------------- 链路扰动（反压）恢复测试 ----------------

  // 段1 大流量进行中注入串行线扰动（等效链路误码 + 瞬断）：
  // 宽松比对 —— 允许扰动毁帧，不允许凭空出帧；撤扰后段2 严格
  // 零丢零错 —— 验证失锁重锁与流量恢复，无卡死。
  // 扰动分两段：先整位翻转（误码：FEC/MLD/BASE-X 因码字/AM/码组非法
  // 而受损），再线路断开（全 0：64b/66b 同步头非法，各模式必失锁）——
  // 仅翻转对 64b/66b 同步头仍合法（01<->10），BASE-R 不会失锁
  class eth_disturb_recovery_test extends eth_loopback_test;

    `uvm_component_utils(eth_disturb_recovery_test)

    // 扰动窗口时长（翻转 + 断线各占一半，覆盖多个码字与锁定窗口）
    protected time disturb_len = 20us;

    function new(string name, uvm_component parent);
      int us;
      super.new(name, parent);
      num_frames  = 500;     // 每段 500，全测试合计 1000 帧
      run_timeout = 100ms;
      strict_pins = 0;       // 扰动/断线斩断在途帧
      // +DISTURB_US=<n>：加长扰动窗（AN 模式下断线超过 an_link_fail_inhibit
      // 即触发链路失效重协商，覆盖 AN_GOOD -> 重新协商 -> 恢复）
      if ($value$plusargs("DISTURB_US=%d", us) && us > 0) disturb_len = us * 1us;
    endfunction

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (env.agent_a.cfg.an_enable)
        `uvm_info("TEST", $sformatf("AN 重协商 A=%0d B=%0d",
                  env.agent_a.bfm.an_restarts(), env.agent_b.bfm.an_restarts()),
                  UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);

      if (vif_ctrl == null)
        `uvm_fatal("TEST", "扰动测试需要 top 提供 tb_ctrl_if")

      wait_link_up();

      // 段1：宽松模式发流，流量中段注入扰动
      env.sb.lenient = 1;
      fork
        begin
          eth_loopback_seq seq = eth_loopback_seq::type_id::create("seq1");
          seq.num_frames = num_frames;
          seq.start(env.agent_a.sqr);
        end
        begin
          // 等流量跑起来再扰动，确保扰动落在帧中间
          wait (env.sb.match_count > 10);
          vif_ctrl.err_inject = 1;
          #(disturb_len / 2);
          vif_ctrl.err_inject = 0;
          vif_ctrl.los        = 1;
          #(disturb_len / 2);
          vif_ctrl.los        = 0;
          `uvm_info("TEST", "扰动窗口结束（翻转 + 断线）", UVM_LOW)
        end
      join

      // 排空在途，未到帧全部按扰动损失结算。排空按 driver 队列实际发空
      // 判定（再留管线裕量），不能用固定延时：sequencer 供帧不耗时，
      // 500 帧整批入队，1G 下线上发完约 336us，固定 100us 会把仍在
      // 队列里的帧误结算成丢失、随后在段 2 冒出成"多余帧"（已实测）
      // 注意必须轮询：wait(func()) 不会因函数返回值变化而重新求值
      //（只对表达式中的变量敏感），首次为假即永久阻塞（已实测死锁）
      while (!env.agent_a.drv.is_idle()) #1us;
      #20us;
      env.sb.flush_pending_as_lost();
      `uvm_info("TEST", $sformatf(
        "段1(扰动) match=%0d lost=%0d bad=%0d mismatch=%0d",
        env.sb.match_count, env.sb.lost_count, env.sb.disturbed_bad,
        env.sb.mismatch_count), UVM_LOW)
      if (env.sb.mismatch_count != 0)
        `uvm_error("TEST", "扰动段出现凭空帧/错配帧")

      // 恢复检查：撤扰后必须能重新锁定
      env.sb.clear();
      env.sb.lenient = 0;
      wait_link_up();

      // 段2：恢复后的流量必须完全干净
      run_traffic(num_frames, run_timeout);
      check_strict("段2(恢复后)", num_frames);
      `uvm_info("TEST", $sformatf("段2(恢复后) 完成 match=%0d",
                                  env.sb.match_count), UVM_LOW)

      phase.drop_objection(this);
    endtask

  endclass

  // ---------------- 链路故障信令测试（Local Fault / hi_ber） ----------------

  // RX 链路未起时 MAC 侧（B 端 XGMII RX 引脚）必须持续为 Local Fault：
  //   ① 上电建链前；② 断线（多 lane 另测仅 lane0 断线：单 lane 失锁即整体
  //   失去对齐）；③ hi_ber：A->B 稀疏单 bit 误码使坏同步头超限而块锁不丢，
  //   hi_ber 期间驱 LF，撤扰后一个干净窗口清除。前后各一个 500 帧严格段。
  // 仅适用无 FEC 的 BASE-R：本测试要的是"块锁保持、同步头坏"这一机制；
  // 同样误码密度下 cl74 码字不可纠会失锁（UNLOCK_BAD），RS-FEC/cl119 则把
  // 不可纠码字的块同步头标坏 —— 机制不同，不在本测试范围。BER 窗口统一取
  // 10G 值（19531 块 / 16 个）：25G+ 的 IEEE 窗口 781250 块，清除一次要数
  // ms 仿真时间，本测试只验证机制
  class eth_link_fault_test extends eth_loopback_test;

    `uvm_component_utils(eth_link_fault_test)

    // 稀疏误码间隔（位钟拍）：约 3 块一次，64 块内坏头期望 < 1（远低于
    // 失锁门限 16）；一个 BER 窗口内坏头 10G 约 200、40G（只翻 lane0，窗口
    // 按全部 lane 计块）约 49，均远超 hi_ber 门限 16
    protected int flip_period_bits = 200;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      num_frames  = 500;
      run_timeout = 100ms;
      strict_pins = 0;       // 断线斩断在途帧
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      foreach (cfg_names[i]) begin
        eth_pcs_cfg c;
        if (!uvm_config_db#(eth_pcs_cfg)::get(this, "env", cfg_names[i], c))
          `uvm_fatal("CFG", "未取得 agent 配置")
        if (c.fec_enable || c.rs_fec_enable || c.cl119 || c.cl400 || c.basex ||
            c.xgmii_direct || c.an_enable || c.lt_enable)
          `uvm_fatal("CFG", "link_fault 仅适用无 FEC 的 BASE-R 模式")
        c.ber_limit         = 16;
        c.ber_window_blocks = 19531;
      end
    endfunction

    protected string cfg_names[2] = '{"cfg_a", "cfg_b"};

    // B 端 XGMII RX 引脚当前是否为 Local Fault（多 lane 为 Clause 82 格式）
    protected function bit pins_lf();
      xgmii64_t lf = xgmii_local_fault(env.agent_b.cfg.num_lanes > 1);
      return env.agent_b.cfg.vif_xgmii.rxc === lf.ctl &&
             env.agent_b.cfg.vif_xgmii.rxd === lf.data;
    endfunction

    // dur 内每 50ns 采样 B 端：链路连续两次采样未起（引脚已跟上）时必须
    // 为 LF。until_up=1 时链路一起即结束。须至少采到 1 次且全为 LF
    protected task sample_lf(string what, time dur, bit until_up = 0);
      int n_down = 0, n_bad = 0;
      bit prev_down = 0;
      for (time t = 0; t < dur; t += 50ns) begin
        bit down = !env.agent_b.bfm.rx_link_up();
        if (until_up && !down) break;
        if (down && prev_down) begin
          n_down++;
          if (!pins_lf()) n_bad++;
        end
        prev_down = down;
        #50ns;
      end
      if (n_down == 0 || n_bad != 0)
        `uvm_error("TEST", $sformatf(
          "%s: 链路未起采样 %0d 次，其中引脚非 Local Fault %0d 次（期望 >0 / 0）",
          what, n_down, n_bad))
      else
        `uvm_info("TEST", $sformatf("%s: 链路未起采样 %0d 次，引脚全为 Local Fault",
                  what, n_down), UVM_LOW)
    endtask

    virtual task run_phase(uvm_phase phase);
      virtual serial_if vs;
      bit stop_flip = 0;

      phase.raise_objection(this);
      if (vif_ctrl == null)
        `uvm_fatal("TEST", "链路故障测试需要 top 提供 tb_ctrl_if")
      vs = (env.agent_b.cfg.num_lanes > 1) ? env.agent_b.cfg.vif_serial_lanes[0]
                                           : env.agent_b.cfg.vif_serial;

      // ① 上电建链前
      sample_lf("建链前", 1ms, 1);
      wait_link_up();
      run_traffic(num_frames, run_timeout);
      check_strict("段1", num_frames);
      env.sb.clear();

      // ② 断线：全部 lane；多 lane 另测仅 lane0
      vif_ctrl.los = 1;
      sample_lf("断线", 5us);
      vif_ctrl.los = 0;
      wait_link_up();
      if (env.agent_b.cfg.num_lanes > 1) begin
        vif_ctrl.los_lane0 = 1;
        sample_lf("仅 lane0 断线", 5us);
        vif_ctrl.los_lane0 = 0;
        wait_link_up();
      end

      // ③ hi_ber：每 flip_period_bits 个位钟翻转 1 bit（多 lane 注在 lane0）
      fork
        while (!stop_flip) begin
          repeat (flip_period_bits - 1) @(vs.rx_cb);
          vif_ctrl.err_inject = 1;
          @(vs.rx_cb);
          vif_ctrl.err_inject = 0;
        end
      join_none
      fork begin
        fork
          while (!env.agent_b.bfm.is_hi_ber()) #100ns;
          begin
            #1ms;
            `uvm_error("TEST", "稀疏误码 1ms 内 hi_ber 未置位")
          end
        join_any
        disable fork;
      end join
      if (!env.agent_b.bfm.rx_locked())
        `uvm_error("TEST", "hi_ber 阶段块锁丢失（应只触发 hi_ber）")
      sample_lf("hi_ber", 2us);
      stop_flip = 1;
      wait (vif_ctrl.err_inject == 0);
      wait_link_up();          // hi_ber 需一个干净的完整窗口才清除

      // 故障期间无流量，记分板不应有任何帧；恢复后严格段
      check_strict("故障段（无流量）", 0);
      run_traffic(num_frames, run_timeout);
      check_strict("段2(故障恢复后)", num_frames);
      `uvm_info("TEST", $sformatf("链路故障信令覆盖完成 hi_ber=%0d",
                env.agent_b.bfm.get_hi_ber_count()), UVM_LOW)

      phase.drop_objection(this);
    endtask

  endclass

endpackage

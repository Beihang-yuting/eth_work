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
    function void write_act(eth_frame_txn t);
      eth_frame_txn e;

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

    // 等待接收完成的仿真时限（bit 时钟 100ps；FEC 锁定与流水线延迟
    // 需要数十万 bit 拍，留足裕量）
    protected time run_timeout = 2ms;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      eth_pcs_cfg cfg_a, cfg_b;
      virtual xgmii_if  vxa, vxb;
      virtual serial_if vsa, vsb;

      super.build_phase(phase);

      if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif_xgmii_a", vxa) ||
          !uvm_config_db#(virtual xgmii_if)::get(this, "", "vif_xgmii_b", vxb) ||
          !uvm_config_db#(virtual serial_if)::get(this, "", "vif_serial_a", vsa) ||
          !uvm_config_db#(virtual serial_if)::get(this, "", "vif_serial_b", vsb))
        `uvm_fatal("CFG", "test 未取得 top 的接口句柄")

      cfg_a = eth_pcs_cfg::type_id::create("cfg_a");
      cfg_a.is_active  = 1;
      cfg_a.fec_enable = fec_mode;
      cfg_a.vif_xgmii  = vxa;
      cfg_a.vif_serial = vsa;

      cfg_b = eth_pcs_cfg::type_id::create("cfg_b");
      cfg_b.is_active  = 0;
      cfg_b.fec_enable = fec_mode;
      cfg_b.vif_xgmii  = vxb;
      cfg_b.vif_serial = vsb;

      uvm_config_db#(eth_pcs_cfg)::set(this, "env", "cfg_a", cfg_a);
      uvm_config_db#(eth_pcs_cfg)::set(this, "env", "cfg_b", cfg_b);

      env = eth_loopback_env::type_id::create("env", this);
    endfunction

    // 发流后等记分板收齐或超时。超时按失败处理 —— 挂死型缺陷（失锁、
    // 流水线断流）必须显式暴露而不是靠全局 timeout 掩盖。
    virtual task run_phase(uvm_phase phase);
      eth_loopback_seq seq = eth_loopback_seq::type_id::create("seq");

      phase.raise_objection(this);

      // link-up：双向对齐锁定 + 1us 裕量（解扰器自同步、流水线冲净），
      // 否则锁定期内发出的帧必然丢失
      while (!(env.agent_a.bfm.rx_locked() && env.agent_b.bfm.rx_locked()))
        #100ns;
      #1us;

      seq.start(env.agent_a.sqr);

      fork begin
        fork
          wait (env.sb.match_count + env.sb.mismatch_count >= seq.num_frames);
          begin
            #run_timeout;
            `uvm_error("TEST", $sformatf(
              "超时: match=%0d mismatch=%0d (期望 %0d 帧)",
              env.sb.match_count, env.sb.mismatch_count, seq.num_frames))
          end
        join_any
        disable fork;
      end join

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

endpackage

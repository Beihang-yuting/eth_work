// -----------------------------------------------------------------------------
// 所属：eth_work/test/svt —— 阶段 2 交叉验证仿真顶层
// 职责：实例化 VIP 侧（svt_ethernet_txrx_if + xxm bfm/monitor 模型）与
//       自研侧（xgmii_if + serial_if），把 VIP 的 XSBI serial 线
//       （tx_lane[0]/rx_lane[0]，10.3125GHz）与自研 serial_if 交叉连接；
//       产生 VIP 所需的全套时钟（沿用 VIP 示例数值）与复位脉冲。
// 依赖：svt_ethernet.uvm.pkg、svt_ethernet_txrx_if.svi（VIP 安装树）、
//       eth_pcs_if.sv、eth_svt_cross_pkg。
// 所有权：仿真进程顶层，持有全部接口与模型实例。
// -----------------------------------------------------------------------------

// 高精度时钟生成复用 aip_core（third_party/aip_core，vendored 1fs 精度版）。
// include 须在本文件 timescale 之前。
`include "aip_log.sv"
`include "aip_time.sv"
`include "aip_clk.sv"

`timescale 1ps/1fs

`include "agent/eth_pcs_macros.svh"

// VIP 包与接口由 svt_pkg_bootstrap.sv 先行编译（见 filelist_svt.f 顺序）

module top_svt;

  import uvm_pkg::*;
  import svt_ethernet_uvm_pkg::*;
  import eth_svt_cross_pkg::*;

  // ---------------- 时钟与复位 ----------------

  // VIP 全套接口时钟：集成宏一键生成（v_ 前缀）。声明/翻转半部在此，
  // 接线半部在接口实例之后；此前只接子集导致 25G 模式 TX 恒值假死
  `eth_pcs_svt_clock_gen(v)

  // +SPEED=25g/40g 切模式（默认 10g/BASE-KR）。时钟起振前由 initial
  // 设定；test 侧读同一 plusarg 选 VIP cfg
  bit use_25g = 0;
  bit use_5g  = 0;     // 5GBASE-R（VIP ETH_5G_BASER_SERIAL，5.15625G）
  bit use_50g = 0;     // 50GBASE-R Mode 1：2 x NRZ PCS/物理 lane（25.78125G）
  bit use_40g = 0;
  bit use_100g = 0;
  bit use_100g4 = 0;
  bit use_100gr = 0;   // 100GBASE-R + RS-FEC（VIP ETH_CSBI_4_LANE，4 × 25.78G）
  bit use_200g = 0;
  bit use_400g = 0;
  bit use_1g  = 0;
  bit use_2p5g = 0;

  initial begin
    string speed = "10g";
    void'($value$plusargs("SPEED=%s", speed));
    use_25g = (speed == "25g");
    use_5g  = (speed == "5g");
    use_50g = (speed == "50g");
    use_40g = (speed == "40g");
    use_100g = (speed == "100g");
    use_100g4 = (speed == "100g4");
    use_100gr = (speed == "100gr");
    use_200g = (speed == "200g");
    use_400g = (speed == "400g");
    use_1g  = (speed == "1g");
    use_2p5g = (speed == "2.5g");
  end

  // 自研侧字时钟：aip_clk 独立产生 156.25MHz；与 VIP 串行位时钟的微小
  // 速率差（非严格 66:1）由 BFM 弹性 idle 插入/删除吸收
  aip_clk_if our_word_clk_if ();
  aip_clk our_word_clk_gen;
  wire our_word_clk = our_word_clk_if.clk;

  logic tb_reset = 0;
  logic our_rst_n = 0;

  // Lane clock is used by the reset/bring-up monitor below and by the
  // multi-lane interface declaration.  Keep the net declaration before any
  // procedural blocks so VCS resolves it consistently when compiling from a
  // clean build directory.
  // ETH_50G_SERIAL physical NRZ lanes are 25.78125G; the VIP's
  // serial_50g_* clock is a 2x PMA reference used internally by its 4:2
  // gearbox.  Drive/sample our two PMA lanes at the actual data rate.
  wire p_lane_clk = use_50g ? v_serial_25g_clk :
                    (use_100g4 || use_100gr) ? v_serial_25g_clk :
                    (use_200g || use_400g) ? v_scd_clk : v_serial_baser_clk;


  initial begin
    our_word_clk_gen = new("our_word_clk", our_word_clk_if);
    #1;   // 等 use_25g 决议
    if (use_40g)
      // 40G：4 lane 合流字率，扣 AM 间隔 64（与 VIP align_timer 一致）
      // 的带宽开销
      our_word_clk_gen.set_freq(4.0 * 10.3125e9 / 66.0 * 63.0 / 64.0);
    else if (use_100g)
      // 100G CAUI-10：10 条物理 lane 合流字率，扣 AM 间隔 64 开销
      our_word_clk_gen.set_freq(10.0 * 10.3125e9 / 66.0 * 63.0 / 64.0);
    else if (use_100g4 || use_100gr)
      // 100G CAUI-4 / RS-FEC：4 × 25.78125G 合流字率，扣 AM 间隔 64 开销
      //（RS-FEC 转码省出的带宽正好抵掉校验位）
      our_word_clk_gen.set_freq(4.0 * 25.78125e9 / 66.0 * 63.0 / 64.0);
    else if (use_200g)
      // 200G：3.125G 块/s 扣 AM+填充占用（每 16 码字 320 组中 4 组）
      our_word_clk_gen.set_freq(3.125e9 * 316.0 / 320.0);
    else if (use_400g)
      // 400G CDMII：64-bit MAC 拍为 6.25GHz；PCS/FEC 开销在 16 条
      // 26.5625G PMA lane 上由 CDBI/RS(544,514) 吸收。
      our_word_clk_gen.set_freq(6.25e9);
    else if (use_1g)
      // 1G BASE-X：GMII 字节时钟 = 1.25Gbaud / 10 = 125MHz
      our_word_clk_gen.set_freq(1.25e9 / 10.0);
    else if (use_2p5g)
      // 2.5G BASE-X：GMII 字节时钟 = 3.125Gbaud / 10 = 312.5MHz
      our_word_clk_gen.set_freq(3.125e9 / 10.0);
    else if (use_50g)
      // 50GBASE-R 双 lane NRZ：合计字率 = 2 x 25.78125G / 66
      our_word_clk_gen.set_freq(51.5625e9 / 66.0);
    else
      // 单 lane；+RSFEC 时每 AM 周期 320 个 257b 组中 1 组让给 AM。
      // 5G 串行位钟由宏按 +SPEED=5g 切到 5.15625GHz（v_serial_baser_clk）
      our_word_clk_gen.set_freq((use_25g ? 25.78125e9 :
                                 use_5g  ? 5.15625e9  : 10.3125e9) / 66.0 *
                                ($test$plusargs("RSFEC") ? 319.0 / 320.0 : 1.0));
    // +100ppm：删除主导域（生产恒盈余，弹性删除只删帧间 idle），
    // 覆盖 fs 舍入与 VIP 位钟的微小速率差
    our_word_clk_gen.set_ppm(100);
    our_word_clk_gen.start();
  end

  // 我方单 lane 串行位时钟随速率选择（50G 多 lane 不使用 p_serial）
  wire our_serial_clk = use_50g ? v_serial_25g_clk :
                        use_25g ? v_serial_25g_clk :
                        (use_1g || use_2p5g) ? v_sx_clk : v_serial_baser_clk;

  // 复位：VIP 侧一个 gmii 时钟宽度的高脉冲（同示例 reset 序列时序）；
  // 自研侧低有效复位同窗释放
  initial begin
    repeat (4) @(posedge v_gmii_clk);
    tb_reset = 1;
    @(posedge v_gmii_clk);
    tb_reset = 0;
    repeat (2) @(posedge v_gmii_clk);
    our_rst_n = 1;
  end

  // ---------------- VIP 侧 ----------------

  svt_ethernet_txrx_if mac_ethernet_if (v_reference_clk);

  // xxm 模型：BFM 驱动器 + 监视/检查器（VIP 的实际引擎，必须实例化）
  svt_ethernet_xxm_bfm_driver     ethernet_mac_txrx (mac_ethernet_if);
  svt_ethernet_xxm_mon_chk_driver ethernet_mac_mon  (mac_ethernet_if);

  // 全套接口时钟接线（宏另一半）
  `eth_pcs_svt_clock_wire(v, mac_ethernet_if)

  assign mac_ethernet_if.reset     = tb_reset;
  assign mac_ethernet_if.stream_id = 0;

  // ---------------- 自研侧 ----------------

  // 集成宏：一行实例化 agent 接口对（p_xgmii / p_serial）
  `eth_pcs_port(p, our_word_clk, our_serial_clk, our_rst_n)

  // 40G 模式的 4 条串行 lane（位钟同 BASE-R 10.3125G）；
  // 50G 使用 2 条 25.78125G NRZ lane，和 VIP ETH_50G_SERIAL 对应。
  // 1G BASE-X 的 MAC 侧 GMII 口（其余模式闲置），vif 键 vif_gmii_p
  gmii_if p_gmii (our_word_clk, our_rst_n);
  initial uvm_config_db#(virtual gmii_if)::set(null, "uvm_test_top",
                                               "vif_gmii_p", p_gmii);

  // 集成宏：lane 组声明（实例 p_l[i]，vif 键 vif_serial_p_l<i>）
  // 物理 lane 位钟随模式：CAUI-4 为 25.78G，其余多 lane 为 10.3125G
  // SVT ETH_50G_SERIAL exposes serial_50g_{tx,rx}_clk at a 2x PMA
  // reference; its two NRZ data lanes run at 25.78125GHz.  Use the
  // 25G serial clock for the DUT PMA interfaces above.
  `eth_pcs_mld_lanes(p, 20, p_lane_clk, our_rst_n)

  // Optional short 400G serial capture for CDBI layout diagnosis.  Captures
  // VIP TX and our RX at the PMA reference clock without enabling the very
  // high volume event based lane_dump probe.  Kept behind +CAP400 only.
  initial begin : cap400_probe
    integer cfd, ncap;
    if ($test$plusargs("CAP400") && use_400g) begin
      cfd = $fopen("cap400.txt", "w");
      #40ns;
      ncap = 0;
      while (ncap < 12000) begin
        @(posedge p_lane_clk);
        $fdisplay(cfd, "%0t %016b %016b", $realtime,
                  mac_ethernet_if.tx_lane[15:0],
                  {p_l[15].tx_bit,p_l[14].tx_bit,p_l[13].tx_bit,p_l[12].tx_bit,
                   p_l[11].tx_bit,p_l[10].tx_bit,p_l[9].tx_bit,p_l[8].tx_bit,
                   p_l[7].tx_bit,p_l[6].tx_bit,p_l[5].tx_bit,p_l[4].tx_bit,
                   p_l[3].tx_bit,p_l[2].tx_bit,p_l[1].tx_bit,p_l[0].tx_bit});
        ncap++;
      end
      $fclose(cfd);
      // CAP400 is a finite diagnostic run; terminate once the requested
      // number of PMA samples is collected so protocol-checker errors cannot
      // stretch this probe into the normal long SVT timeout.
      $finish;
    end
  end


  // ---------------- 串行链路交叉连接 ----------------

  // VIP MAC 的接收线 = 我方发送；我方接收 = VIP MAC 的发送。
  // 单 lane（10G/25G）走 lane bit0；40G 走 [3:0]；100G CAUI-10 走 [9:0]。
  // rx_lane 按模式 mux（不能双驱动，故不复用 connect_svt 宏）
  assign mac_ethernet_if.rx_lane =
    use_50g ? {'0, p_l[1].tx_bit, p_l[0].tx_bit} :
    use_400g ? {'0, p_l[15].tx_bit, p_l[14].tx_bit, p_l[13].tx_bit,
                    p_l[12].tx_bit, p_l[11].tx_bit, p_l[10].tx_bit,
                    p_l[9].tx_bit, p_l[8].tx_bit, p_l[7].tx_bit,
                    p_l[6].tx_bit, p_l[5].tx_bit, p_l[4].tx_bit,
                    p_l[3].tx_bit, p_l[2].tx_bit, p_l[1].tx_bit,
                    p_l[0].tx_bit} :
    use_200g ? {'0, p_l[7].tx_bit, p_l[6].tx_bit, p_l[5].tx_bit,
                    p_l[4].tx_bit, p_l[3].tx_bit, p_l[2].tx_bit,
                    p_l[1].tx_bit, p_l[0].tx_bit} :
    use_100g ? {'0, p_l[9].tx_bit, p_l[8].tx_bit, p_l[7].tx_bit,
                    p_l[6].tx_bit, p_l[5].tx_bit, p_l[4].tx_bit,
                    p_l[3].tx_bit, p_l[2].tx_bit, p_l[1].tx_bit,
                    p_l[0].tx_bit} :
    (use_40g || use_100g4 || use_100gr) ? {'0, p_l[3].tx_bit, p_l[2].tx_bit,
                                                p_l[1].tx_bit, p_l[0].tx_bit}
                                        : {'0, p_serial.tx_bit};
  assign p_serial.rx_bit = mac_ethernet_if.tx_lane[0];

  // 集成宏：多 lane 接收方向接线 + vif 下发
  `eth_pcs_mld_rx_wire(p, mac_ethernet_if, 20)
  `eth_pcs_mld_vifs(p, 20)

  // ---------------- TB 控制（中途复位钩子） ----------------

  // 复位仅作用我方 PHY 域（our_rst_n）；VIP 持续运行，覆盖"对端在线、
  // 我方复位重连"的恢复场景（键名 tb_ctrl，测试握手协议见 tb_ctrl_if）
  tb_ctrl_if ctrl ();

  always @(posedge our_word_clk) begin
    if (ctrl.reset_req) begin
      our_rst_n = 0;
      repeat (20) @(posedge our_word_clk);
      our_rst_n = 1;
      ctrl.reset_req = 0;
    end
  end

  initial uvm_config_db#(virtual tb_ctrl_if)::set(null, "uvm_test_top",
                                                  "tb_ctrl", ctrl);

  // ---------------- 多 lane 码流探针（+LANE_DUMP_NS=<ns>）----------------
  // 把 tx_lane（VIP 发）与 rx_lane（我方发）的每次跳变写入 lane_dump.txt
  //（每行：时间 tx_lane rx_lane），供离线标定新模式（AM 图案/周期/位钟）
  // 或核对线上码字（伴随式）。+LANE_DUMP_FROM_NS=<ns> 只 dump 该时刻之后
  // 的窗口。只在显式开启时生效。
  initial begin
    int dump_ns, from_ns, fd;
    from_ns = 0;
    if ($value$plusargs("LANE_DUMP_NS=%d", dump_ns)) begin
      void'($value$plusargs("LANE_DUMP_FROM_NS=%d", from_ns));
      fd = $fopen("lane_dump.txt", "w");
      fork
        forever begin
          @(mac_ethernet_if.tx_lane or mac_ethernet_if.rx_lane);
          if ($realtime > dump_ns * 1ns) break;
          if ($realtime >= from_ns * 1ns)
            $fdisplay(fd, "%0t %b %b", $realtime, mac_ethernet_if.tx_lane[19:0],
                      mac_ethernet_if.rx_lane[19:0]);
        end
      join
      $fclose(fd);
    end
  end

  // ---------------- UVM 启动 ----------------

  // 集成宏：下发 p 端口的 virtual interface（键名 vif_xgmii_p / vif_serial_p）
  `eth_pcs_vifs(p)

  initial begin
    uvm_config_db#(virtual svt_ethernet_txrx_if)::set(
      uvm_root::get(), "uvm_test_top.env.vip_mac*", "if_port", mac_ethernet_if);
    run_test();
  end

endmodule

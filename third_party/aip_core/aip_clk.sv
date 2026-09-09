// ==============================================
// AIP 时钟生成器 - 高精度、可配置、支持即时停止
// 依赖：aip_log, aip_time
// ==============================================
`ifndef AIP_CLK_SV
`define AIP_CLK_SV

// 强制 1ps 精度，保证亚 ns 半周期/相位/抖动精确
`timescale 1ns/1fs  // eth_work vendored: 精度提到 1fs，10G 串行半周期 48.485ps 需亚 ps 精度

// 时钟接口
interface aip_clk_if;
   logic clk;
endinterface

// 高精度时钟生成器类
class aip_clk;
   // 公共只读属性（可通过方法修改）
   protected string name;
   protected virtual aip_clk_if vif;

   // 频率配置
   protected bit pll_mode = 0;            // 0:直接频率, 1:PLL模式
   protected real base_freq_mhz = 1.0;    // 基准频率（MHz）
   protected int mul = 1;                 // 乘数
   protected int div = 1;                 // 除数
   protected real target_freq_mhz = 1.0;  // 直接目标频率（MHz）

   // 精度与相位
   protected real ppm = 0;                // 百万分比误差（±）
   protected real phase_delay_ns = 0;     // 初始相位延迟（ns）
   protected real duty_cycle = 0.5;       // 占空比（0~1）

   // PLL行为仿真参数
   protected real lock_time_ns = 0;       // 模拟PLL锁定时间（ns）
   protected real jitter_rms_ns = 0;      // 抖动均方根（ns）
   protected int seed = 100;              // 随机种子

   // 内部状态
   protected real period_ns;              // 实际时钟周期（ns）
   protected real actual_freq_mhz;        // 实际频率（MHz）
   protected bit running = 0;             // 生成器运行标志
   protected event stop_event;            // 停止事件（用于即时中断延时）

   // 构造函数
   function new(string name, virtual aip_clk_if vif);
      this.name = name;
      this.vif = vif;
      recalc_period();
   endfunction

   // ---------- 状态查询接口 ----------
   function bit is_running();
      return running;
   endfunction

   function real get_freq_hz();
      return actual_freq_mhz * 1e6;
   endfunction

   function real get_period_ns();
      return period_ns;
   endfunction

   function string get_name();
      return name;
   endfunction

   // ---------- 私有方法：重新计算周期（单位：ns）----------
   protected function void recalc_period();
      real nom_freq_mhz;
      if (pll_mode) begin
         nom_freq_mhz = base_freq_mhz * mul / div;
      end else begin
         nom_freq_mhz = target_freq_mhz;
      end
      actual_freq_mhz = nom_freq_mhz * (1.0 + ppm / 1e6);
      period_ns = 1000.0 / actual_freq_mhz;

      if (period_ns <= 0.0) begin
         period_ns = 1.0;
         `aip_nwarning(this.name, ("calculated period is too small, set to 1 ns"));
      end
   endfunction

   // ---------- 公共配置方法 ----------
   // 设置直接频率（单位：Hz）
   function void set_freq(real freq_hz);
      if (freq_hz <= 0) begin
         `aip_nerror(this.name, ("frequency must be positive"));
         return;
      end
      pll_mode = 0;
      target_freq_mhz = freq_hz / 1e6;
      recalc_period();
   endfunction

   // 设置PLL参数（乘数M，除数D，基准频率可选，单位：Hz）
   function void set_pll_params(int m, int d, real base_hz = 0);
      if (d == 0) begin
         `aip_nerror(this.name, ("divider cannot be zero"));
         return;
      end
      if (m <= 0 || d <= 0) begin
         `aip_nerror(this.name, ("multiplier and divider must be positive"));
         return;
      end
      pll_mode = 1;
      mul = m;
      this.div = d;
      if (base_hz > 0) begin
         base_freq_mhz = base_hz / 1e6;
      end
      recalc_period();
   endfunction

   // 设置PPM值
   function void set_ppm(real value);
      ppm = value;
      recalc_period();
   endfunction

   // 设置占空比
   function void set_duty_cycle(real dc);
      if (dc <= 0.0 || dc >= 1.0) begin
         `aip_nerror(this.name, ("duty cycle must be in (0, 1), got %0.3f", dc));
         return;
      end
      duty_cycle = dc;
   endfunction

   // 设置相位延迟（秒）
   function void set_phase(real delay_sec);
      if (delay_sec < 0) begin
         `aip_nwarning(this.name, ("phase delay negative, setting to 0"));
         phase_delay_ns = 0;
      end else begin
         phase_delay_ns = delay_sec * 1e9;
      end
   endfunction

   // 设置相位角度（度），基于当前周期
   function void set_phase_deg(real deg);
      if (period_ns <= 0) begin
         `aip_nerror(this.name, ("cannot set phase angle when period is invalid"));
         return;
      end
      phase_delay_ns = (deg / 360.0) * period_ns;
   endfunction

   // 设置PLL锁定时间（秒）
   function void set_lock_time(real t);
      lock_time_ns = t * 1e9;
   endfunction

   // 设置抖动（RMS，秒）
   function void set_jitter(real rms_sec, int new_seed = -1);
      jitter_rms_ns = rms_sec * 1e9;
      if (new_seed >= 0) seed = new_seed;
   endfunction

   // ---------- 运行时动态调整 ----------
   task rephase(real new_delay_sec);
      if (running) begin
         stop();
         phase_delay_ns = new_delay_sec * 1e9;
         start();
      end else begin
         phase_delay_ns = new_delay_sec * 1e9;
      end
   endtask

   task update_ppm(real new_ppm);
      if (running) begin
         stop();
         ppm = new_ppm;
         recalc_period();
         start();
      end else begin
         ppm = new_ppm;
         recalc_period();
      end
   endtask

   // ---------- 启停控制 ----------
   task start();
      if (running) begin
         `aip_nwarning(this.name, ("already running"));
         return;
      end
      running = 1;
      fork
         run();
      join_none
   endtask

   task start_sync(event sync);
      @sync;
      start();
   endtask

   task stop();
      running = 0;
      -> stop_event;
   endtask

   // ---------- 等待沿（带超时）----------
   task wait_for_posedge(time timeout = 0);
      fork
         begin
            @(posedge vif.clk);
         end
         begin
            if (timeout > 0) #(timeout);
            else wait(0);
         end
      join_any
      disable fork;
   endtask

   task wait_for_negedge(time timeout = 0);
      fork
         begin
            @(negedge vif.clk);
         end
         begin
            if (timeout > 0) #(timeout);
            else wait(0);
         end
      join_any
      disable fork;
   endtask

   // ---------- 多时钟同步启动 ----------
   static task start_all(aip_clk clks[]);
      event sync;
      foreach (clks[i]) begin
         automatic int idx = i;
         fork
            clks[idx].start_sync(sync);
         join_none
      end
      #0;
      -> sync;
   endtask

   // ---------- 内部运行任务 ----------
   // eth_work vendored 修改：相位累加器（DDS 式）消除逐半周期取整的
   // 系统性频偏。原实现每个半周期独立做 real->realtime 取整，凡半周期
   // 不是精度单位整数倍的频率都有 ~精度/半周期 量级频偏（1fs 精度下
   // 10.3GHz 约 10~20ppm）。此版记录"理想累计相位"，每拍延时 =
   // 理想目标时刻 - 当前实际时刻，取整误差不累积（恒 <1 个精度单位）。
   // 抖动只偏移上升沿目标时刻，不进入相位累加器，同样不累积。
   protected task run();
      real high_ns, low_ns;
      real jitter_ns;
      real base_ns;      // 主循环起始参考时刻
      real ideal_ns;     // 相位累加器：自 base_ns 起的理想累计时间
      real delay_now;

      // 立即拉 0，避免 lock/phase 期间 X 态泄露
      vif.clk = 0;

      // 模拟PLL锁定时间
      if (lock_time_ns > 0) begin
         fork
            aip_time::delay_ns(lock_time_ns);
            @(stop_event);
         join_any
         disable fork;
         if (!running) return;
      end

      // 初始相位延迟
      if (phase_delay_ns > 0) begin
         fork
            aip_time::delay_ns(phase_delay_ns);
            @(stop_event);
         join_any
         disable fork;
         if (!running) return;
      end

      base_ns  = aip_time::get_sim_time("ns");
      ideal_ns = 0.0;

      // 主循环：生成时钟（所有沿对齐理想相位网格）
      while (running) begin
         high_ns = period_ns * duty_cycle;
         low_ns  = period_ns * (1.0 - duty_cycle);

         // 生成抖动（高斯分布）
         if (jitter_rms_ns > 0.0) begin
            jitter_ns = $dist_normal(seed, 0, jitter_rms_ns * 1000) / 1000.0;
            // 保护：确保两个半周期都不为负
            if (high_ns + jitter_ns <= 0.0)
               jitter_ns = -high_ns + 0.001;
            if (low_ns - jitter_ns <= 0.0)
               jitter_ns = low_ns - 0.001;
         end else begin
            jitter_ns = 0.0;
         end

         // 低电平半周期：上升沿目标 = 理想网格 - 抖动偏移
         ideal_ns  = ideal_ns + low_ns;
         delay_now = (base_ns + ideal_ns - jitter_ns)
                     - aip_time::get_sim_time("ns");
         if (delay_now > 0.0) begin
            fork
               aip_time::delay_ns(delay_now);
               @(stop_event);
            join_any
            disable fork;
         end
         if (!running) break;
         vif.clk = 1;

         // 高电平半周期：下降沿回到理想网格（抖动自然抵消）
         ideal_ns  = ideal_ns + high_ns;
         delay_now = (base_ns + ideal_ns)
                     - aip_time::get_sim_time("ns");
         if (delay_now > 0.0) begin
            fork
               aip_time::delay_ns(delay_now);
               @(stop_event);
            join_any
            disable fork;
         end
         if (!running) break;
         vif.clk = 0;
      end
   endtask
endclass

// ========================== 宏封装 ==========================

// 快速生成时钟（接口 + 实例 + 配置 + 启动）
// 用法：`aip_clk_create(clk0, 100e6)
// 用法：`aip_clk_create(clk0, 100e6, 50, 10e-9)
`define aip_clk_create(name, freq_hz, ppm=0, phase_sec=0) \
   aip_clk_if name``_if(); \
   aip_clk name; \
   initial begin \
      name = new(`"name`", name``_if); \
      name.set_freq(freq_hz); \
      name.set_ppm(ppm); \
      name.set_phase(phase_sec); \
      name.start(); \
   end

// 完整版（频率 + ppm + 相位 + 占空比 + 抖动）
// 用法：`aip_clk_create_full(clk0, 100e6, 50, 0, 0.5, 1e-12)
`define aip_clk_create_full(name, freq_hz, ppm=0, phase_sec=0, duty=0.5, jitter_sec=0) \
   aip_clk_if name``_if(); \
   aip_clk name; \
   initial begin \
      name = new(`"name`", name``_if); \
      name.set_freq(freq_hz); \
      name.set_ppm(ppm); \
      name.set_phase(phase_sec); \
      name.set_duty_cycle(duty); \
      if (jitter_sec > 0) name.set_jitter(jitter_sec); \
      name.start(); \
   end

// ---------- 配置宏（在 initial 块内使用）----------
// 设置抖动：`aip_clk_jitter(clk0, 1e-12)
`define aip_clk_jitter(name, rms_sec, seed=-1) \
   name.set_jitter(rms_sec, seed);

// 设置占空比：`aip_clk_duty(clk0, 0.6)
`define aip_clk_duty(name, dc) \
   name.set_duty_cycle(dc);

// 设置 PLL 模式：`aip_clk_pll(clk0, 10, 2, 25e6)
`define aip_clk_pll(name, mul, div, base_hz) \
   name.set_pll_params(mul, div, base_hz);

// 设置 PLL 锁定时间：`aip_clk_lock(clk0, 1e-6)
`define aip_clk_lock(name, lock_sec) \
   name.set_lock_time(lock_sec);

`endif // AIP_CLK_SV

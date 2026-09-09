//===========================================================
// 时间工具类：提供仿真时间获取和精确延迟功能
// 支持 longint 和 real 类型延迟，与 timescale 无关
//===========================================================
`ifndef AIP_TIME_SV
`define AIP_TIME_SV

// 强制 1ps 精度，保证亚 ns 延迟（高频时钟 half-period < 1ns）不被截断
`timescale 1ns/1fs  // eth_work vendored: 精度提到 1fs，10G 串行半周期 48.485ps 需亚 ps 精度

class aip_time;

    // ---------- 静态成员（用于延迟测量结果缓存）----------
    static bit   measured = 0;          // 是否已完成测量
    static real  unit_fs;                // 当前 timescale 的每个时间单位对应的飞秒数

    // ---------- 公共静态方法：获取当前仿真时间（指定单位）----------
    // 支持的单位：fs, ps, ns, us, ms, s, m, h
    // 返回：当前仿真时间（实数），若单位非法返回 -1000.0，解析失败返回 -2000.0
    static function real get_sim_time(string unit = "ns");
        real time_fs = real'($realtime / 1fs);
        real divisor;
        case (unit)
            "fs": divisor = 1.0;
            "ps": divisor = 1e3;
            "ns": divisor = 1e6;
            "us": divisor = 1e9;
            "ms": divisor = 1e12;
            "s":  divisor = 1e15;
            "m":  divisor = 60.0 * 1e15;
            "h":  divisor = 3600.0 * 1e15;
            default: return -1000.0;
        endcase
        return time_fs / divisor;
    endfunction

    // ---------- 内部方法：确保测量完成（消耗 #1 仿真时间）----------
    // 保留供 get_sim_time 等场景使用，delay_ns 不再依赖此方法
    protected static task ensure_measured();
        longint unsigned start_fs, end_fs, delta_fs;

        if (measured) return;

        start_fs = longint'(get_sim_time("fs"));
        #1;
        end_fs   = longint'(get_sim_time("fs"));
        delta_fs = end_fs - start_fs;

        if (delta_fs <= 0 || delta_fs >= 1000000000) begin
            `aip_error(("timescale measurement failed (delta = %0d fs). Ensure unit is 1ns/100ps/10ps/1ps/100fs/10fs/1fs", delta_fs));
            $finish;
        end

        unit_fs = real'(delta_fs);
        measured = 1;
    endtask

    // ---------- 公共静态任务：延迟指定的纳秒数（与 timescale 无关）----------
    // 使用 1ns 时间字面量直接转换，零额外仿真时间开销
    static task delay_ns(real ns);
        realtime delay_time;

        if (ns <= 0) return;

        delay_time = ns * 1ns;
        #(delay_time);
    endtask

    // ---------- 整数版本（保持向后兼容）----------
    static task delay_ns_int(longint ns);
        delay_ns(real'(ns));
    endtask

endclass
`endif // AIP_TIME_SV

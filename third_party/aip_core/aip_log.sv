// ==============================================
// aip_log — 彩色日志系统 V3.0
// 特性：彩色分级、仿真时间、文件:行号、级别过滤、通配符、统计
// FATAL 桥接 UVM 走正常退出流程
// 无外部依赖（aip_str/aip_time 的简单逻辑已内联），可最先 include
// 依赖：uvm_pkg
//
// 宏用法（双括号内嵌 $sformatf，省去手写）：
//   `aip_info(("simple message"))
//   `aip_info(("val=%0d addr=0x%0h", val, addr))
//   `aip_ninfo(this.name, ("val=%0d", val))     // 带实例名
//   `aip_uinfo(("msg"))                          // UVM 组件内
//
// 配置：
//   aip_log::set_verbosity(aip_log::DEBUG);
//   aip_log::set_inst_verbosity("top.dut.*", aip_log::WARNING);
// ==============================================
`ifndef AIP_LOG_SV
`define AIP_LOG_SV

import uvm_pkg::*;

class aip_log;

    // -------------------- 级别定义 --------------------
    typedef enum int {
        FATAL   = 0,
        ERROR   = 1,
        WARNING = 2,
        INFO    = 3,
        DEBUG   = 4,
        TRACE   = 5
    } level_t;

    // -------------------- 配置 --------------------
    static level_t verbosity    = INFO;
    static bit     enable_color = 1;
    static string  time_unit    = "";    // 空=自动从 timescale 推算，可手动 set

    // 实例级别：精确匹配
    static level_t inst_v[string];

    // 实例级别：通配符匹配
    typedef struct { string pat; level_t v; } wrule_t;
    static wrule_t wrules[$];

    // -------------------- 统计 --------------------
    static int cnt[level_t] = '{default:0};

    // ==================== 公共 API ====================

    static function void set_verbosity(level_t v);
        verbosity = v;
    endfunction

    // 手动指定时间单位（覆盖自动推算）；传空串恢复自动
    static function void set_time_unit(string unit);
        time_unit = unit;
    endfunction

    // 支持通配符 * ?
    static function void set_inst_verbosity(string inst, level_t v);
        if (has_wildcard(inst))
            wrules.push_back('{pat: inst, v: v});
        else
            inst_v[inst] = v;
    endfunction

    static function int get_count(level_t level);
        return cnt[level];
    endfunction

    static function void summary();
        $display("");
        $display("=== Log Summary ===");
        $display("  FATAL   : %0d", cnt[FATAL]);
        $display("  ERROR   : %0d", cnt[ERROR]);
        $display("  WARNING : %0d", cnt[WARNING]);
        $display("  INFO    : %0d", cnt[INFO]);
        $display("  DEBUG   : %0d", cnt[DEBUG]);
        $display("  TRACE   : %0d", cnt[TRACE]);
        $display("===================");
    endfunction

    // ==================== 核心打印 ====================

    // 格式（参考 UVM）：
    //   [LEVEL] file(line) @ time unit: msg
    //   [LEVEL] file(line) @ time unit: inst: msg
    static function void log(level_t level, string file, int line, string inst, string msg);
        string out;
        string lvl_s;
        real   now;

        // 1. 级别过滤
        if (!is_printable(level, inst)) return;

        // 2. 统计
        cnt[level] = cnt[level] + 1;

        // 3. 级别名（固定 5 字符宽度，对齐）
        case (level)
            FATAL:   lvl_s = "FATAL";
            ERROR:   lvl_s = "ERROR";
            WARNING: lvl_s = "WARN ";
            INFO:    lvl_s = "INFO ";
            DEBUG:   lvl_s = "DEBUG";
            TRACE:   lvl_s = "TRACE";
            default: lvl_s = "?????";
        endcase

        // 4. 仿真时间（自动推算单位，或使用手动设置的单位）
        begin
            string unit_s;
            if (time_unit != "") begin
                unit_s = time_unit;
                now = get_sim_time(unit_s);
            end else begin
                unit_s = detect_unit();
                now = $realtime;
            end

            // 5. 格式化
            if (inst != "")
                out = $sformatf("[%s] %s(%0d) @ %.2f %s: %s: %s",
                                lvl_s, file, line, now, unit_s, inst, msg);
            else
                out = $sformatf("[%s] %s(%0d) @ %.2f %s: %s",
                                lvl_s, file, line, now, unit_s, msg);
        end

        // 6. 颜色输出
        if (enable_color)
            $write("%s%s\033[0m\n", get_color(level), out);
        else
            $write("%s\n", out);

        // 7. FATAL → 桥接 UVM 正常退出
        if (level == FATAL) begin
            if (uvm_top != null)
                uvm_top.uvm_report_fatal("AIP_FATAL", msg, UVM_NONE, file, line);
            else
                $fatal(1, "[AIP_FATAL] %s (%s:%0d)", msg, file, line);
        end
    endfunction

    // ==================== 内部方法 ====================

    // 颜色码
    local static function string get_color(level_t level);
        case (level)
            FATAL:   return "\033[31;1m";  // 粗体红
            ERROR:   return "\033[91m";    // 亮红
            WARNING: return "\033[33m";    // 黄色
            INFO:    return "\033[0m";     // 默认
            DEBUG:   return "\033[90m";    // 灰色
            TRACE:   return "\033[36m";    // 青色
            default: return "\033[0m";
        endcase
    endfunction

    // 自动推算 timescale 单位：用 real'(1ns) 判断当前 timescale
    // -timescale=1ns/1ps → real'(1ns)=1.0    → "ns"
    // -timescale=1ps/1ps → real'(1ns)=1000.0  → "ps"
    // -timescale=1us/1ns → real'(1ns)=0.001   → "us"
    local static function string detect_unit();
        real one_ns = real'(1ns);
        if (one_ns > 5e5)       return "fs";
        else if (one_ns > 500)  return "ps";
        else if (one_ns > 0.5)  return "ns";
        else if (one_ns > 5e-4) return "us";
        else if (one_ns > 5e-7) return "ms";
        else                    return "s";
    endfunction

    // 手动单位时的时间转换（用 $realtime/1fs 获取绝对飞秒再换算）
    local static function real get_sim_time(string unit);
        real time_fs = real'($realtime / 1fs);
        case (unit)
            "fs": return time_fs;
            "ps": return time_fs / 1e3;
            "ns": return time_fs / 1e6;
            "us": return time_fs / 1e9;
            "ms": return time_fs / 1e12;
            "s":  return time_fs / 1e15;
            default: return time_fs / 1e6;
        endcase
    endfunction

    // 检查字符串是否含通配符
    local static function bit has_wildcard(string s);
        foreach (s[i])
            if (s[i] == "*" || s[i] == "?") return 1;
        return 0;
    endfunction

    // 级别过滤
    local static function bit is_printable(level_t level, string inst);
        level_t threshold;

        // 精确匹配优先
        if (inst != "" && inst_v.exists(inst))
            return level <= inst_v[inst];

        // 通配符匹配（最长 pattern 优先）
        threshold = verbosity;
        if (inst != "") begin
            int best_len = -1;
            foreach (wrules[i]) begin
                if (wrules[i].pat.len() > best_len && glob_match(inst, wrules[i].pat)) begin
                    best_len = wrules[i].pat.len();
                    threshold = wrules[i].v;
                end
            end
        end

        return level <= threshold;
    endfunction

    // 通配符匹配 — 贪心算法，O(1) 空间
    local static function bit glob_match(string s, string p);
        int si = 0, pi = 0, star_p = -1, star_s = -1;
        while (si < s.len()) begin
            if (pi < p.len() && (p[pi] == "?" || p[pi] == s[si])) begin
                si = si + 1;
                pi = pi + 1;
            end else if (pi < p.len() && p[pi] == "*") begin
                star_p = pi;
                star_s = si;
                pi = pi + 1;
            end else if (star_p != -1) begin
                pi = star_p + 1;
                star_s = star_s + 1;
                si = star_s;
            end else begin
                return 0;
            end
        end
        while (pi < p.len() && p[pi] == "*") pi = pi + 1;
        return (pi == p.len());
    endfunction

endclass

// ========================== 宏定义 ==========================
// --- 无实例名 ---
`define aip_fatal(args)   aip_log::log(aip_log::FATAL,   `__FILE__, `__LINE__, "", $sformatf args)
`define aip_error(args)   aip_log::log(aip_log::ERROR,   `__FILE__, `__LINE__, "", $sformatf args)
`define aip_warning(args) aip_log::log(aip_log::WARNING, `__FILE__, `__LINE__, "", $sformatf args)
`define aip_info(args)    aip_log::log(aip_log::INFO,    `__FILE__, `__LINE__, "", $sformatf args)
`define aip_debug(args)   aip_log::log(aip_log::DEBUG,   `__FILE__, `__LINE__, "", $sformatf args)
`define aip_trace(args)   aip_log::log(aip_log::TRACE,   `__FILE__, `__LINE__, "", $sformatf args)

// --- 带实例名（inst 在前，args 在后）---
`define aip_nfatal(inst, args)   aip_log::log(aip_log::FATAL,   `__FILE__, `__LINE__, inst, $sformatf args)
`define aip_nerror(inst, args)   aip_log::log(aip_log::ERROR,   `__FILE__, `__LINE__, inst, $sformatf args)
`define aip_nwarning(inst, args) aip_log::log(aip_log::WARNING, `__FILE__, `__LINE__, inst, $sformatf args)
`define aip_ninfo(inst, args)    aip_log::log(aip_log::INFO,    `__FILE__, `__LINE__, inst, $sformatf args)
`define aip_ndebug(inst, args)   aip_log::log(aip_log::DEBUG,   `__FILE__, `__LINE__, inst, $sformatf args)
`define aip_ntrace(inst, args)   aip_log::log(aip_log::TRACE,   `__FILE__, `__LINE__, inst, $sformatf args)

// --- UVM 组件内（自动取 get_full_name()）---
`define aip_ufatal(args)   aip_log::log(aip_log::FATAL,   `__FILE__, `__LINE__, get_full_name(), $sformatf args)
`define aip_uerror(args)   aip_log::log(aip_log::ERROR,   `__FILE__, `__LINE__, get_full_name(), $sformatf args)
`define aip_uwarning(args) aip_log::log(aip_log::WARNING, `__FILE__, `__LINE__, get_full_name(), $sformatf args)
`define aip_uinfo(args)    aip_log::log(aip_log::INFO,    `__FILE__, `__LINE__, get_full_name(), $sformatf args)
`define aip_udebug(args)   aip_log::log(aip_log::DEBUG,   `__FILE__, `__LINE__, get_full_name(), $sformatf args)
`define aip_utrace(args)   aip_log::log(aip_log::TRACE,   `__FILE__, `__LINE__, get_full_name(), $sformatf args)

`endif // AIP_LOG_SV

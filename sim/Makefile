# -----------------------------------------------------------------------------
# 所属：eth_work/sim —— VCS 编译与运行入口（在 10.11.10.53 上执行）
# 职责：单元测试（unit）、双 agent 环回族（依赖 loopback_simv，一次编译
#       多测试复用）、与 svt VIP 交叉族（依赖 svt_simv）。目标按"模式 ×
#       环回/1000 帧/多次复位/扰动/VIP 交叉/交叉复位"组织，速率与 FEC 由
#       +SPEED/+FEC/+RSFEC/+AN/+LT 插件参数切换。全量 PHY 回归：
#         make -k all      （= unit + LOOPBACK_TARGETS + SVT_TARGETS）
#       UVM 目标判据 = 汇总行 grep + UVM_ERROR/UVM_FATAL 计数为 0（CHECK_CLEAN）。
# 依赖：VCS_HOME 环境（53 上 ~/.bashrc 已配）；UVM-1.2 用 -ntb_opts；
#       svt 目标另需 DESIGNWARE_HOME（VIP R-2020.12）。
# -----------------------------------------------------------------------------

VCS      = vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ps/1ps +vcs+flush+all
BUILD    = build

# 单元测试单独编译（独立 top，不需要 TB package）
UNIT_SRCS = ../src/agent/eth_pcs_if.sv ../src/pkg/eth_pcs_pkg.sv \
            ../test/unit/tb_pcs_unit.sv

# 全量目标清单（新增目标须同步加入，否则 make all 漏跑）
LOOPBACK_TARGETS = \
  loopback fec stress stress_fec reset_recovery disturb multi_reset \
  multi_reset_fec disturb_fec link_fault link_fault_40g \
  stress_lane4 stress_lane4_fec stress_lane4_rsfec stress_lane4_5g \
  loopback_direct stress_direct multi_reset_direct \
  loopback_an stress_an multi_reset_an disturb_an disturb_an_relink \
  loopback_lt stress_lt multi_reset_lt disturb_lt \
  loopback_kr stress_kr multi_reset_kr disturb_kr \
  loopback_rsfec stress_rsfec multi_reset_rsfec disturb_rsfec \
  loopback_1g stress_1g multi_reset_1g disturb_1g \
  loopback_2p5g stress_2p5g multi_reset_2p5g disturb_2p5g \
  loopback_5g stress_5g multi_reset_5g disturb_5g \
  loopback_25g stress_25g multi_reset_25g disturb_25g \
  loopback_25g_fec stress_25g_fec multi_reset_25g_fec disturb_25g_fec \
  loopback_25g_rsfec stress_25g_rsfec multi_reset_25g_rsfec disturb_25g_rsfec \
  loopback_40g stress_40g multi_reset_40g disturb_40g \
  loopback_40g_fec stress_40g_fec multi_reset_40g_fec disturb_40g_fec \
  loopback_100g stress_100g multi_reset_100g disturb_100g \
  loopback_100g_fec stress_100g_fec multi_reset_100g_fec disturb_100g_fec \
  loopback_100g4 stress_100g4 multi_reset_100g4 disturb_100g4 \
  loopback_100gr stress_100gr multi_reset_100gr disturb_100gr \
  loopback_200g stress_200g multi_reset_200g disturb_200g

SVT_TARGETS = \
  svt svt_reset svt_lane4 svt_fec svt_fec_reset svt_an svt_an_reset \
  svt_5g svt_5g_reset svt_25g svt_25g_reset svt_25g_fec svt_25g_fec_reset \
  svt_25g_rsfec svt_25g_rsfec_reset svt_40g svt_40g_reset \
  svt_40g_fec svt_40g_fec_reset svt_100g svt_100g_reset \
  svt_100g_fec svt_100g_fec_reset svt_100g4 svt_100g4_reset \
  svt_100gr svt_100gr_reset svt_200g svt_200g_reset \
  svt_1g svt_1g_reset svt_2p5g svt_2p5g_reset \
  svt_50g svt_50g_reset

# 400G 仍保留为实验性目标：当前 Clause 119 CDBI 映射尚未与 SVT
# ETH_400G_SERIAL 对齐，普通/复位目标均不得混入默认 all。
SVT_EXPERIMENTAL_TARGETS = svt_400g svt_400g_reset

.PHONY: all unit clean $(LOOPBACK_TARGETS) $(SVT_TARGETS) $(SVT_EXPERIMENTAL_TARGETS)

all: unit $(LOOPBACK_TARGETS) $(SVT_TARGETS)

# 判据：UVM 目标除 grep 汇总行外，日志中 UVM_ERROR / UVM_FATAL 计数须为 0
#（+UVM_MAX_QUIT_COUNT=5 下 1~4 个错误不会中止仿真，只 grep 汇总行会漏过）
CHECK_CLEAN = grep -qE '^UVM_ERROR : +0$$' $(1) && grep -qE '^UVM_FATAL : +0$$' $(1)

# 环回可执行文件共用：一次编译多测试复用（VCS 自身增量编译）
LOOPBACK_SIMV = $(BUILD)/loopback/simv

.PHONY: loopback_simv
loopback_simv:
	mkdir -p $(BUILD)/loopback
	$(VCS) -f filelist.f -top top \
	  -o $(LOOPBACK_SIMV) -l $(BUILD)/loopback/compile.log

# 大流量压力（1000 帧背靠背，FEC 关/开）
stress: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/stress.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress.log)

stress_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_fec_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/stress_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_fec.log)

# 多次复位覆盖：5 轮"流量中复位 + 复位后严格段"，末轮 500 帧全净
multi_reset: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/multi_reset.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset.log
	grep -q "第 5 轮复位后严格段 完成 match=500" $(BUILD)/loopback/multi_reset.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset.log)

# 中途复位恢复（段2 复位后 500 帧必须全净）
reset_recovery: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_reset_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/reset.log
	grep -q "段2(复位后) 完成 match=500" $(BUILD)/loopback/reset.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/reset.log)

# 链路扰动（反压等效）恢复（段2 撤扰后 500 帧必须全净）
disturb: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/disturb.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb.log)

unit:
	mkdir -p $(BUILD)/unit
	$(VCS) +incdir+../src $(UNIT_SRCS) -top tb_pcs_unit \
	  -o $(BUILD)/unit/simv -l $(BUILD)/unit/compile.log
	$(BUILD)/unit/simv -l $(BUILD)/unit/run.log
	grep -q UNIT_TEST_PASS $(BUILD)/unit/run.log

# Clause 73 自协商建链（AN 完成后自动切数据模式再跑流量）
loopback_an: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_an_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN -l $(BUILD)/loopback/run_an.log
	grep -q "AN_LINKUP_PASS" $(BUILD)/loopback/run_an.log
	grep -q "match=100 mismatch=0" $(BUILD)/loopback/run_an.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_an.log)

stress_an: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN -l $(BUILD)/loopback/stress_an.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_an.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_an.log)

multi_reset_an: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN -l $(BUILD)/loopback/multi_reset_an.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_an.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_an.log)

# 1G / 2.5G BASE-X（8b/10b，Clause 36，MAC 侧 GMII）：同一 simv，+SPEED 切换
loopback_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/run_1g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_1g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_1g.log)

stress_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/stress_1g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_1g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_1g.log)

multi_reset_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/multi_reset_1g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_1g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_1g.log)

disturb_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/disturb_1g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_1g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_1g.log)

loopback_2p5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/loopback/run_2p5g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_2p5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_2p5g.log)

stress_2p5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/loopback/stress_2p5g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_2p5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_2p5g.log)

multi_reset_2p5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/loopback/multi_reset_2p5g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_2p5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_2p5g.log)

# 单 lane RS-FEC（RS(528,514)，码流格式同 Clause 108）自环系，默认 10G
# 线速；25G 即 25GBASE-R + Clause 108（见下方 *_25g_rsfec 与 svt_25g_rsfec）
loopback_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/run_rsfec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_rsfec.log)

stress_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/stress_rsfec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_rsfec.log)

multi_reset_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/multi_reset_rsfec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_rsfec.log)

# 链路扰动下的 RS-FEC 纠错能力：注错期间帧仍应全净（7 符号/码字内）
disturb_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/disturb_rsfec.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_rsfec.log)

# Clause 72 链路训练（自环；VIP 不支持 cl72 故无交叉档）
loopback_lt: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_an_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +LT -l $(BUILD)/loopback/run_lt.log
	grep -q "match=100 mismatch=0" $(BUILD)/loopback/run_lt.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_lt.log)

# KR 完整建链：AN(cl73) -> LT(cl72) -> 数据模式 -> 流量
loopback_kr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_kr_linkup_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +LT -l $(BUILD)/loopback/run_kr.log
	grep -q "KR_LINKUP_PASS" $(BUILD)/loopback/run_kr.log
	grep -q "match=100 mismatch=0" $(BUILD)/loopback/run_kr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_kr.log)

stress_kr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +LT -l $(BUILD)/loopback/stress_kr.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_kr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_kr.log)

multi_reset_kr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +LT -l $(BUILD)/loopback/multi_reset_kr.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_kr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_kr.log)

# XGMII 直驱（纯 MAC 功能验证提速：跳过 PCS/串行，位钟关闭）
loopback_direct: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +XGMII_DIRECT -l $(BUILD)/loopback/run_direct.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_direct.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_direct.log)

stress_direct: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +XGMII_DIRECT -l $(BUILD)/loopback/stress_direct.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_direct.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_direct.log)

loopback: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/run.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run.log)

fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_fec_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/fec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/fec.log)

# 25G / 5G 单 lane（同一编译产物，+SPEED 换时钟；流程同 10G）
loopback_25g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/loopback/run_25g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_25g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_25g.log)

stress_25g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/loopback/stress_25g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_25g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_25g.log)

multi_reset_25g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/loopback/multi_reset_25g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_25g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_25g.log)

stress_5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/loopback/stress_5g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_5g.log)

multi_reset_5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/loopback/multi_reset_5g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_5g.log)

svt_25g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/svt/run_25g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_25g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_25g.log)

# 40G（4 lane MLD）环回系：统一 top（`eth_pcs_lb_env 超集），仅
# +SPEED=40g 切换 —— 与 10g/25g/5g 共用一个 simv
loopback_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/run_40g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_40g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_40g.log)

stress_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/stress_40g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_40g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_40g.log)

multi_reset_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/multi_reset_40g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_40g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_40g.log)

# 100G（CAUI-10：20 条 PCS lane 以 2:1 bit 复用上 10 条物理 lane）环回系
loopback_100g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/loopback/run_100g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_100g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_100g.log)

stress_100g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/loopback/stress_100g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_100g.log)

multi_reset_100g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/loopback/multi_reset_100g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_100g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_100g.log)

loopback_100g4: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/loopback/run_100g4.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_100g4.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_100g4.log)

stress_100g4: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/loopback/stress_100g4.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100g4.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_100g4.log)

# 200GBASE-R（Clause 119：8 lane × 26.5625G，256B/257B + RS(544,514)）环回系
loopback_200g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/loopback/run_200g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_200g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_200g.log)

stress_200g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/loopback/stress_200g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_200g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_200g.log)

multi_reset_200g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/loopback/multi_reset_200g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_200g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_200g.log)

svt_40g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/svt/run_40g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_40g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_40g.log)

# 100G CAUI-10 与 VIP（ETH_CAUI）交叉
svt_100g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/svt/run_100g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_100g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100g.log)

# 100G CAUI-4 与 VIP（ETH_CAUI_25X4）交叉
svt_100g4: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/svt/run_100g4.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_100g4.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100g4.log)

# 200GBASE-R 与 VIP（ETH_200G_SERIAL）交叉
svt_200g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/svt/run_200g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_200g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_200g.log)

# 1G BASE-X 与 VIP（ETH_1G_BASEX_1BIT）交叉
svt_1g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/svt/run_1g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_1g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_1g.log)

# 2.5G BASE-X 与 VIP（ETH_2PT5G_BASEX_SERIAL）交叉
svt_2p5g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/svt/run_2p5g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_2p5g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_2p5g.log)

# svt 交叉中途复位恢复：3 轮复位 × 每段 A100+B200，末段按段计数判定
svt_25g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/svt/run_25g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_25g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_25g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_25g_reset.log)

svt_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/svt/run_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_reset.log)

svt_1g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/svt/run_1g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_1g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_1g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_1g_reset.log)

svt_2p5g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/svt/run_2p5g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_2p5g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_2p5g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_2p5g_reset.log)

svt_100g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/svt/run_100g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_100g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_100g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100g_reset.log)

svt_100g4_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/svt/run_100g4_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_100g4_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_100g4_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100g4_reset.log)

svt_200g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/svt/run_200g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_200g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_200g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_200g_reset.log)

svt_40g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/svt/run_40g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_40g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_40g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_40g_reset.log)

# ---------------- MLD + FEC 叠加（第 ⑤ 项）----------------
# +FEC = Clause 74（单 lane / 每 PCS lane）；+RSFEC = 单 lane RS-FEC
#（25G 即 Clause 108）；+SPEED=100gr = 100GBASE-R + Clause 91 RS-FEC
#（20 PCS lane -> 4 FEC lane × 25.78G）。码流格式均由 VIP 实抓标定。
loopback_40g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/loopback/run_40g_fec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_40g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_40g_fec.log)

stress_40g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/loopback/stress_40g_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_40g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_40g_fec.log)

multi_reset_40g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/loopback/multi_reset_40g_fec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_40g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_40g_fec.log)

stress_100g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g +FEC -l $(BUILD)/loopback/stress_100g_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_100g_fec.log)

stress_25g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/loopback/stress_25g_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_25g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_25g_fec.log)

loopback_25g_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/loopback/run_25g_rsfec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_25g_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_25g_rsfec.log)

stress_25g_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/loopback/stress_25g_rsfec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_25g_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_25g_rsfec.log)

multi_reset_25g_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/loopback/multi_reset_25g_rsfec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_25g_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_25g_rsfec.log)

loopback_100gr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/loopback/run_100gr.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_100gr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_100gr.log)

stress_100gr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/loopback/stress_100gr.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100gr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_100gr.log)

multi_reset_100gr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/loopback/multi_reset_100gr.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_100gr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_100gr.log)

# ---------------- 覆盖矩阵补齐（每模式 环回/1000帧/多次复位/扰动）----------------
# 扰动 = 10us 整位翻转 + 10us 断线（全 0），各模式必经失锁 -> 重锁；
# XGMII 直驱无串行线，扰动不适用

loopback_5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/loopback/run_5g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_5g.log)

loopback_25g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/loopback/run_25g_fec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_25g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_25g_fec.log)

loopback_100g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g +FEC -l $(BUILD)/loopback/run_100g_fec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_100g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/run_100g_fec.log)

stress_lt: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +LT -l $(BUILD)/loopback/stress_lt.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_lt.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_lt.log)

multi_reset_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +FEC -l $(BUILD)/loopback/multi_reset_fec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_fec.log)

multi_reset_lt: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +LT -l $(BUILD)/loopback/multi_reset_lt.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_lt.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_lt.log)

multi_reset_25g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/loopback/multi_reset_25g_fec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_25g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_25g_fec.log)

multi_reset_100g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g +FEC -l $(BUILD)/loopback/multi_reset_100g_fec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_100g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_100g_fec.log)

multi_reset_100g4: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/loopback/multi_reset_100g4.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_100g4.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_100g4.log)

multi_reset_direct: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +XGMII_DIRECT -l $(BUILD)/loopback/multi_reset_direct.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_direct.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/multi_reset_direct.log)

disturb_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +FEC -l $(BUILD)/loopback/disturb_fec.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_fec.log)

disturb_an: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN -l $(BUILD)/loopback/disturb_an.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_an.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_an.log)

# AN 链路失效重协商：断线 30us（> an_link_fail_inhibit 20us）使 B 回 AN，
# A 随后见 DME 失锁也回 AN，双方重新协商后流量恢复（两端重协商均 >= 1）
disturb_an_relink: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +DISTURB_US=60 -l $(BUILD)/loopback/disturb_an_relink.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_an_relink.log
	grep -qE "AN 重协商 A=[1-9][0-9]* B=[1-9]" $(BUILD)/loopback/disturb_an_relink.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_an_relink.log)

disturb_lt: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +LT -l $(BUILD)/loopback/disturb_lt.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_lt.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_lt.log)

disturb_kr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +LT -l $(BUILD)/loopback/disturb_kr.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_kr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_kr.log)

disturb_5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/loopback/disturb_5g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_5g.log)

disturb_25g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/loopback/disturb_25g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_25g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_25g.log)

disturb_25g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/loopback/disturb_25g_fec.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_25g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_25g_fec.log)

disturb_25g_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/loopback/disturb_25g_rsfec.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_25g_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_25g_rsfec.log)

disturb_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/disturb_40g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_40g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_40g.log)

disturb_40g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/loopback/disturb_40g_fec.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_40g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_40g_fec.log)

disturb_100g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/loopback/disturb_100g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_100g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_100g.log)

disturb_100g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g +FEC -l $(BUILD)/loopback/disturb_100g_fec.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_100g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_100g_fec.log)

disturb_100g4: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/loopback/disturb_100g4.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_100g4.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_100g4.log)

disturb_100gr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/loopback/disturb_100gr.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_100gr.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_100gr.log)

disturb_200g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/loopback/disturb_200g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_200g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_200g.log)

disturb_2p5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/loopback/disturb_2p5g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_2p5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/disturb_2p5g.log)

# 链路故障信令：建链前/断线/hi_ber 期间 RX 引脚为 Local Fault（无 FEC 的
# BASE-R；40g 另测仅 lane0 断线）
link_fault: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_link_fault_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/link_fault.log
	grep -q "链路故障信令覆盖完成" $(BUILD)/loopback/link_fault.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/link_fault.log)

link_fault_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_link_fault_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/link_fault_40g.log
	grep -q "链路故障信令覆盖完成" $(BUILD)/loopback/link_fault_40g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/link_fault_40g.log)

# lane4 起帧（Clause 49：奇数帧 S 落 lane4，0x33 块）大流量：裸 / cl74 / RS-FEC / 5G
stress_lane4: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +LANE4 -l $(BUILD)/loopback/stress_lane4.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_lane4.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_lane4.log)

stress_lane4_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +LANE4 +FEC -l $(BUILD)/loopback/stress_lane4_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_lane4_fec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_lane4_fec.log)

stress_lane4_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +LANE4 +RSFEC -l $(BUILD)/loopback/stress_lane4_rsfec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_lane4_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_lane4_rsfec.log)

stress_lane4_5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +LANE4 +SPEED=5g -l $(BUILD)/loopback/stress_lane4_5g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_lane4_5g.log
	$(call CHECK_CLEAN,$(BUILD)/loopback/stress_lane4_5g.log)

# 与 VIP 交叉：同一 simv（svt_simv 编译一次，同一次 make 内多目标共用）
SVT_SIMV = $(BUILD)/svt/simv
SVT_OK   = "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000"
SVT_ROK  = "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200"

.PHONY: svt_simv
svt_simv:
	mkdir -p $(BUILD)/svt
	ETH_SVT_DESIGN=$(ETH_SVT_DESIGN) $(VCS) \
	  -f filelist_svt.f -top top_svt \
	  -o $(SVT_SIMV) -l $(BUILD)/svt/compile.log

svt_fec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +FEC -l $(BUILD)/svt/run_fec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_fec.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_fec.log)

# Clause 73 AN 交叉：双方协商（HCD=10GBASE-KR）后切 10G 数据模式跑流量；
# 复位版每轮我方复位 -> VIP internal_restart 重新协商 -> 恢复流量
svt_an: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=an73 -l $(BUILD)/svt/run_an.log
	grep -q "AN 双方完成: VIP AN_GOOD" $(BUILD)/svt/run_an.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_an.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_an.log)

svt_an_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=an73 -l $(BUILD)/svt/run_an_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_an_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_an_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_an_reset.log)

# 我方 lane4 起帧（0x33）由 VIP 10G 接收检查
svt_lane4: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +LANE4 -l $(BUILD)/svt/run_lane4.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_lane4.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_lane4.log)

svt_25g_fec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/svt/run_25g_fec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_25g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_25g_fec.log)

svt_40g_fec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/svt/run_40g_fec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_40g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_40g_fec.log)

svt_25g_rsfec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/svt/run_25g_rsfec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_25g_rsfec.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_25g_rsfec.log)

svt_100gr: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/svt/run_100gr.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_100gr.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100gr.log)

svt_fec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +FEC -l $(BUILD)/svt/run_fec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_fec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_fec_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_fec_reset.log)

svt_40g_fec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/svt/run_40g_fec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_40g_fec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_40g_fec_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_40g_fec_reset.log)

svt_25g_rsfec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/svt/run_25g_rsfec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_25g_rsfec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_25g_rsfec_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_25g_rsfec_reset.log)

svt_100gr_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/svt/run_100gr_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_100gr_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_100gr_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100gr_reset.log)

# ---------------- 覆盖矩阵补齐（VIP 交叉 / 交叉复位）----------------
# 5G：VIP ETH_5G_BASER_SERIAL（宏按 +SPEED=5g 切 XGMII/串行/XSBI 时钟）；
# 100G CAUI-10 + cl74：VIP ETH_CAUI + enable_fec（20 路 cl74，同 40G 路径）

svt_5g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/svt/run_5g.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_5g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_5g.log)

svt_5g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/svt/run_5g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_5g_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_5g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_5g_reset.log)

svt_50g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=50g -l $(BUILD)/svt/run_50g.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_50g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_50g.log)

svt_50g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=50g -l $(BUILD)/svt/run_50g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_50g_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_50g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_50g_reset.log)

# 400GBASE-R CDBI 与 VIP（ETH_400G_SERIAL，16 × 26.5625G NRZ）交叉。
# VIP 两个独立 8-lane PCS 的 CDBI 码字映射仍待标定，故保持实验性目标。
svt_400g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=400g -l $(BUILD)/svt/run_400g.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_400g.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_400g.log)

svt_400g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=400g -l $(BUILD)/svt/run_400g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_400g_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_400g_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_400g_reset.log)

svt_100g_fec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g +FEC -l $(BUILD)/svt/run_100g_fec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_100g_fec.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100g_fec.log)

svt_100g_fec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g +FEC -l $(BUILD)/svt/run_100g_fec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_100g_fec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_100g_fec_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_100g_fec_reset.log)

svt_25g_fec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/svt/run_25g_fec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_25g_fec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_25g_fec_reset.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run_25g_fec_reset.log)

# 阶段 2：与 svt ethernet VIP 交叉验证（需 DESIGNWARE_HOME 与
# dw_vip_setup 生成的 ETH_SVT_DESIGN，见 filelist_svt.f 头注）
ETH_SVT_DESIGN ?= /home/ubuntu/ryan/eth_svt_design

svt: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/svt/run.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run.log
	$(call CHECK_CLEAN,$(BUILD)/svt/run.log)

clean:
	rm -rf $(BUILD) csrc simv* ucli.key vc_hdrs.h

# -----------------------------------------------------------------------------
# 所属：eth_work/sim —— VCS 编译与运行入口（在 10.11.10.53 上执行）
# 职责：三个目标：
#   unit     单元测试（tb_pcs_unit，判定 UNIT_TEST_PASS）
#   loopback 环回冒烟（eth_loopback_test，FEC 关）
#   fec      环回冒烟（eth_loopback_fec_test，FEC 开）
# 依赖：VCS_HOME 环境（53 上 ~/.bashrc 已配）；UVM-1.2 用 -ntb_opts。
# -----------------------------------------------------------------------------

VCS      = vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ps/1ps +vcs+flush+all
BUILD    = build

# 单元测试单独编译（独立 top，不需要 TB package）
UNIT_SRCS = ../src/agent/eth_pcs_if.sv ../src/pkg/eth_pcs_pkg.sv \
            ../test/unit/tb_pcs_unit.sv

.PHONY: all unit loopback fec stress stress_fec reset_recovery disturb clean

all: unit loopback fec stress stress_fec reset_recovery disturb

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

stress_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_fec_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/stress_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_fec.log

# 多次复位覆盖：5 轮"流量中复位 + 复位后严格段"，末轮 500 帧全净
multi_reset: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/multi_reset.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset.log
	grep -q "第 5 轮复位后严格段 完成 match=500" $(BUILD)/loopback/multi_reset.log

# 中途复位恢复（段2 复位后 500 帧必须全净）
reset_recovery: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_reset_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/reset.log
	grep -q "段2(复位后) 完成 match=500" $(BUILD)/loopback/reset.log

# 链路扰动（反压等效）恢复（段2 撤扰后 500 帧必须全净）
disturb: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/disturb.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb.log

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

stress_an: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN -l $(BUILD)/loopback/stress_an.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_an.log

multi_reset_an: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN -l $(BUILD)/loopback/multi_reset_an.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_an.log

# 1G / 2.5G BASE-X（8b/10b，Clause 36，MAC 侧 GMII）：同一 simv，+SPEED 切换
loopback_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/run_1g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_1g.log

stress_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/stress_1g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_1g.log

multi_reset_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/multi_reset_1g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_1g.log

disturb_1g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/loopback/disturb_1g.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_1g.log

loopback_2p5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/loopback/run_2p5g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_2p5g.log

stress_2p5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/loopback/stress_2p5g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_2p5g.log

multi_reset_2p5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/loopback/multi_reset_2p5g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_2p5g.log

# 单 lane RS-FEC（RS(528,514)，码流格式同 Clause 108）自环系，默认 10G
# 线速；25G 即 25GBASE-R + Clause 108（见下方 *_25g_rsfec 与 svt_25g_rsfec）
loopback_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/run_rsfec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_rsfec.log

stress_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/stress_rsfec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_rsfec.log

multi_reset_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/multi_reset_rsfec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_rsfec.log

# 链路扰动下的 RS-FEC 纠错能力：注错期间帧仍应全净（7 符号/码字内）
disturb_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_disturb_recovery_test +UVM_MAX_QUIT_COUNT=5 \
	  +RSFEC -l $(BUILD)/loopback/disturb_rsfec.log
	grep -q "段2(恢复后) 完成 match=500" $(BUILD)/loopback/disturb_rsfec.log

# Clause 72 链路训练（自环；VIP 不支持 cl72 故无交叉档）
loopback_lt: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_an_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +LT -l $(BUILD)/loopback/run_lt.log
	grep -q "match=100 mismatch=0" $(BUILD)/loopback/run_lt.log

# KR 完整建链：AN(cl73) -> LT(cl72) -> 数据模式 -> 流量
loopback_kr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_kr_linkup_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +LT -l $(BUILD)/loopback/run_kr.log
	grep -q "KR_LINKUP_PASS" $(BUILD)/loopback/run_kr.log
	grep -q "match=100 mismatch=0" $(BUILD)/loopback/run_kr.log

stress_kr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +LT -l $(BUILD)/loopback/stress_kr.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_kr.log

multi_reset_kr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +AN +LT -l $(BUILD)/loopback/multi_reset_kr.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_kr.log

# XGMII 直驱（纯 MAC 功能验证提速：跳过 PCS/串行，位钟关闭）
loopback_direct: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +XGMII_DIRECT -l $(BUILD)/loopback/run_direct.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_direct.log

stress_direct: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +XGMII_DIRECT -l $(BUILD)/loopback/stress_direct.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_direct.log

loopback: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/run.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run.log

fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_fec_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/loopback/fec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/fec.log

# 25G / 5G 单 lane（同一编译产物，+SPEED 换时钟；流程同 10G）
loopback_25g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/loopback/run_25g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_25g.log

stress_25g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/loopback/stress_25g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_25g.log

multi_reset_25g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/loopback/multi_reset_25g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_25g.log

stress_5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/loopback/stress_5g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_5g.log

multi_reset_5g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=5g -l $(BUILD)/loopback/multi_reset_5g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_5g.log

svt_25g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/svt/run_25g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_25g.log

# 40G（4 lane MLD）环回系：统一 top（`eth_pcs_lb_env 超集），仅
# +SPEED=40g 切换 —— 与 10g/25g/5g 共用一个 simv
loopback_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/run_40g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_40g.log

stress_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/stress_40g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_40g.log

multi_reset_40g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/loopback/multi_reset_40g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_40g.log

# 100G（CAUI-10：20 条 PCS lane 以 2:1 bit 复用上 10 条物理 lane）环回系
loopback_100g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/loopback/run_100g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_100g.log

stress_100g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/loopback/stress_100g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100g.log

multi_reset_100g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/loopback/multi_reset_100g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_100g.log

loopback_100g4: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/loopback/run_100g4.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_100g4.log

stress_100g4: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/loopback/stress_100g4.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100g4.log

# 200GBASE-R（Clause 119：8 lane × 26.5625G，256B/257B + RS(544,514)）环回系
loopback_200g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/loopback/run_200g.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_200g.log

stress_200g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/loopback/stress_200g.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_200g.log

multi_reset_200g: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/loopback/multi_reset_200g.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_200g.log

svt_40g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/svt/run_40g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_40g.log

# 100G CAUI-10 与 VIP（ETH_CAUI）交叉
svt_100g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/svt/run_100g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_100g.log

# 100G CAUI-4 与 VIP（ETH_CAUI_25X4）交叉
svt_100g4: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/svt/run_100g4.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_100g4.log

# 200GBASE-R 与 VIP（ETH_200G_SERIAL）交叉
svt_200g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/svt/run_200g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_200g.log

# 1G BASE-X 与 VIP（ETH_1G_BASEX_1BIT）交叉
svt_1g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/svt/run_1g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_1g.log

# 2.5G BASE-X 与 VIP（ETH_2PT5G_BASEX_SERIAL）交叉
svt_2p5g: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/svt/run_2p5g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_2p5g.log

# svt 交叉中途复位恢复：3 轮复位 × 每段 A100+B200，末段按段计数判定
svt_25g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/svt/run_25g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_25g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_25g_reset.log

svt_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/svt/run_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_reset.log

svt_1g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=1g -l $(BUILD)/svt/run_1g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_1g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_1g_reset.log

svt_2p5g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=2.5g -l $(BUILD)/svt/run_2p5g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_2p5g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_2p5g_reset.log

svt_100g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g -l $(BUILD)/svt/run_100g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_100g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_100g_reset.log

svt_100g4_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g4 -l $(BUILD)/svt/run_100g4_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_100g4_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_100g4_reset.log

svt_200g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=200g -l $(BUILD)/svt/run_200g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_200g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_200g_reset.log

svt_40g_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g -l $(BUILD)/svt/run_40g_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_40g_reset.log
	grep -q "A: vip_tx=100 our_rx=100 bad=0 | B: our_tx=200 vip_rx=200" $(BUILD)/svt/run_40g_reset.log

# ---------------- MLD + FEC 叠加（第 ⑤ 项）----------------
# +FEC = Clause 74（单 lane / 每 PCS lane）；+RSFEC = 单 lane RS-FEC
#（25G 即 Clause 108）；+SPEED=100gr = 100GBASE-R + Clause 91 RS-FEC
#（20 PCS lane -> 4 FEC lane × 25.78G）。码流格式均由 VIP 实抓标定。
loopback_40g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/loopback/run_40g_fec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_40g_fec.log

stress_40g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/loopback/stress_40g_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_40g_fec.log

multi_reset_40g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/loopback/multi_reset_40g_fec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_40g_fec.log

stress_100g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100g +FEC -l $(BUILD)/loopback/stress_100g_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100g_fec.log

stress_25g_fec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/loopback/stress_25g_fec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_25g_fec.log

loopback_25g_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/loopback/run_25g_rsfec.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_25g_rsfec.log

stress_25g_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/loopback/stress_25g_rsfec.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_25g_rsfec.log

multi_reset_25g_rsfec: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/loopback/multi_reset_25g_rsfec.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_25g_rsfec.log

loopback_100gr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_loopback_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/loopback/run_100gr.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run_100gr.log

stress_100gr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_stress_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/loopback/stress_100gr.log
	grep -q "match=1000 mismatch=0" $(BUILD)/loopback/stress_100gr.log

multi_reset_100gr: loopback_simv
	$(LOOPBACK_SIMV) +UVM_TESTNAME=eth_multi_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/loopback/multi_reset_100gr.log
	grep -q "多次复位覆盖完成: 5 轮" $(BUILD)/loopback/multi_reset_100gr.log

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

svt_25g_fec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +FEC -l $(BUILD)/svt/run_25g_fec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_25g_fec.log

svt_40g_fec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/svt/run_40g_fec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_40g_fec.log

svt_25g_rsfec: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/svt/run_25g_rsfec.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_25g_rsfec.log

svt_100gr: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/svt/run_100gr.log
	grep -q $(SVT_OK) $(BUILD)/svt/run_100gr.log

svt_fec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +FEC -l $(BUILD)/svt/run_fec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_fec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_fec_reset.log

svt_40g_fec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=40g +FEC -l $(BUILD)/svt/run_40g_fec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_40g_fec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_40g_fec_reset.log

svt_25g_rsfec_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g +RSFEC -l $(BUILD)/svt/run_25g_rsfec_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_25g_rsfec_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_25g_rsfec_reset.log

svt_100gr_reset: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_reset_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=100gr -l $(BUILD)/svt/run_100gr_reset.log
	grep -q "CROSS_RESET_RECOVERY_PASS rounds=3" $(BUILD)/svt/run_100gr_reset.log
	grep -q $(SVT_ROK) $(BUILD)/svt/run_100gr_reset.log

# 阶段 2：与 svt ethernet VIP 交叉验证（需 DESIGNWARE_HOME 与
# dw_vip_setup 生成的 ETH_SVT_DESIGN，见 filelist_svt.f 头注）
ETH_SVT_DESIGN ?= /home/ubuntu/ryan/eth_svt_design

svt: svt_simv
	$(SVT_SIMV) +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/svt/run.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run.log

clean:
	rm -rf $(BUILD) csrc simv* ucli.key vc_hdrs.h

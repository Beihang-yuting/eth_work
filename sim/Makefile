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

svt_25g:
	mkdir -p $(BUILD)/svt
	ETH_SVT_DESIGN=$(ETH_SVT_DESIGN) $(VCS) \
	  -f filelist_svt.f -top top_svt \
	  -o $(BUILD)/svt/simv -l $(BUILD)/svt/compile.log
	$(BUILD)/svt/simv +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  +SPEED=25g -l $(BUILD)/svt/run_25g.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run_25g.log

# 阶段 2：与 svt ethernet VIP 交叉验证（需 DESIGNWARE_HOME 与
# dw_vip_setup 生成的 ETH_SVT_DESIGN，见 filelist_svt.f 头注）
ETH_SVT_DESIGN ?= /home/ubuntu/ryan/eth_svt_design

svt:
	mkdir -p $(BUILD)/svt
	ETH_SVT_DESIGN=$(ETH_SVT_DESIGN) $(VCS) \
	  -f filelist_svt.f -top top_svt \
	  -o $(BUILD)/svt/simv -l $(BUILD)/svt/compile.log
	$(BUILD)/svt/simv +UVM_TESTNAME=eth_svt_cross_test +UVM_MAX_QUIT_COUNT=5 \
	  -l $(BUILD)/svt/run.log
	grep -q "A: vip_tx=500 our_rx=500 bad=0 | B: our_tx=1000 vip_rx=1000" $(BUILD)/svt/run.log

clean:
	rm -rf $(BUILD) csrc simv* ucli.key vc_hdrs.h

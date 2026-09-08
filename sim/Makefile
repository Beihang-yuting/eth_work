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

.PHONY: all unit loopback fec clean

all: unit loopback fec

unit:
	mkdir -p $(BUILD)/unit
	$(VCS) +incdir+../src $(UNIT_SRCS) -top tb_pcs_unit \
	  -o $(BUILD)/unit/simv -l $(BUILD)/unit/compile.log
	$(BUILD)/unit/simv -l $(BUILD)/unit/run.log
	grep -q UNIT_TEST_PASS $(BUILD)/unit/run.log

loopback:
	mkdir -p $(BUILD)/loopback
	$(VCS) -f filelist.f -top top \
	  -o $(BUILD)/loopback/simv -l $(BUILD)/loopback/compile.log
	$(BUILD)/loopback/simv +UVM_TESTNAME=eth_loopback_test \
	  -l $(BUILD)/loopback/run.log
	grep -q "match=20 mismatch=0" $(BUILD)/loopback/run.log

fec:
	mkdir -p $(BUILD)/fec
	$(VCS) -f filelist.f -top top \
	  -o $(BUILD)/fec/simv -l $(BUILD)/fec/compile.log
	$(BUILD)/fec/simv +UVM_TESTNAME=eth_loopback_fec_test \
	  -l $(BUILD)/fec/run.log
	grep -q "match=20 mismatch=0" $(BUILD)/fec/run.log

clean:
	rm -rf $(BUILD) csrc simv* ucli.key vc_hdrs.h

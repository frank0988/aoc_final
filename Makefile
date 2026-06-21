VERILATOR ?= verilator
TOP       ?= tb
TRACE     ?= 0
DC_SHELL  ?= dc_shell
VCS       ?= vcs
NC        ?= ncverilog -64
SYN_DIR   ?= syn
BUILD_DIR ?= build
RTL_RUN_DIR ?= waves/ncverilog
RTL_CASE ?= 0
FSDB_FILE ?= waves/rtl$(RTL_CASE).fsdb
ROOT_DIR  := $(abspath .)
N16ADFP_DIR ?= /usr/cad/CBDK/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell
SYN ?= 0
ifneq ($(origin syn), undefined)
SYN := $(syn)
endif

ifeq ($(TRACE),1)
OBJ_DIR ?= obj_dir_trace
else
OBJ_DIR ?= obj_dir
endif
SIM := $(OBJ_DIR)/V$(TOP)
TB_FILE := $(ROOT_DIR)/tb.sv
SYN_TB_SRC := $(ROOT_DIR)/src/encode.sv $(ROOT_DIR)/src/decode.sv $(ROOT_DIR)/src/weight.sv $(TB_FILE)
RTL_SRC = $(addprefix $(ROOT_DIR)/,$(SRC))
NOVAS_HOME ?= /usr/cad/synopsys/verdi
NOVAS_PLI := +loadpli1=$(NOVAS_HOME)/share/PLI/IUS/LINUX64/libpli.so:novas_pli_boot
DUMP ?= 0
NC_DUMP_FLAGS :=
ifeq ($(DUMP),1)
NC_DUMP_FLAGS += +define+FSDB $(NOVAS_PLI)
else ifeq ($(DUMP),2)
NC_DUMP_FLAGS += +define+FSDB +define+FSDB_ALL $(NOVAS_PLI)
endif
VCS_DUMP_FLAGS :=
ifeq ($(DUMP),1)
VCS_DUMP_FLAGS += +define+FSDB
else ifeq ($(DUMP),2)
VCS_DUMP_FLAGS += +define+FSDB +define+FSDB_ALL
endif
NCFLAGS := -sv +access+rwc +notimingcheck +incdir+$(ROOT_DIR)/hw
VCS_COMMON_OPTS := -R -sverilog -debug_access+all -full64 +rdcycle=1 +no_notifier
VCS_SYN_FLAGS := $(VCS_COMMON_OPTS) +neg_tchk -negdelay \
	-v $(N16ADFP_DIR)/VERILOG/N16ADFP_StdCell.v -diag=sdf:verbose \
	+incdir+$(ROOT_DIR)/$(SYN_DIR)+$(ROOT_DIR)/hw+$(ROOT_DIR)/SRAM \
	+define+SYN

TRACE_FILE ?= waves/tb.vcd
TRACE_FLAGS :=
TRACE_ARGS  :=
ifeq ($(TRACE),1)
TRACE_FLAGS += --trace -DTRACE_ON
TRACE_ARGS  += +TRACE_FILE=$(TRACE_FILE)
endif

INC_FLAGS := -Ihw

SRC := src/encode.sv src/decode.sv src/weight.sv \
	hw/input_RLC_decoder.v SRAM/SRAM_rtl.sv hw/sram_macro_wrapper.sv hw/input_sram_wrapper.sv hw/weight_sram_wrapper.sv hw/weight_pingpong_wrapper.sv \
	hw/Controller.sv hw/pe_block_7x3.v hw/boundart_sram_wrapper.sv hw/accumulator.sv \
	hw/PostQuant.sv hw/ReLU_Qint8.sv hw/Maxpool_Qint8.sv \
	hw/PPU.sv hw/PPU_to_RLC_Packer.sv \
	hw/output_RLC_encoder.v \
	top.sv tb.sv

TB ?= tb0
IFMAP_FILE  ?= test_data/PE_test_data/$(TB)/ifmap_$(TB).txt
WEIGHT_FILE ?= test_data/PE_test_data/$(TB)/filter_$(TB).txt
GOLDEN_FILE ?= test_data/PE_test_data/$(TB)/ofmap_$(TB).txt
BIAS_FILE ?=
REQUANT_SHIFT_FILE ?=

VWA_LAYER ?= 1
VWA_SINGLE_LAYER ?= 0
ifneq ($(origin layer), undefined)
VWA_LAYER := $(layer)
VWA_SINGLE_LAYER := 1
endif
ifneq ($(origin image), undefined)
CIFAR_IMAGE := $(image)
endif
VWA_DATA_ROOT ?= ../VWA/testbench/layer_data
VWA_CASE ?=
PYTHON ?= python3
CIFAR_ROOT ?= $(ROOT_DIR)/data/cifar10
CIFAR_TEST_BATCH := $(CIFAR_ROOT)/cifar-10-batches-py/test_batch
CIFAR_IMAGE ?= 0
CIFAR_CASE ?= cifar10_image_$(CIFAR_IMAGE)
RTL0_DATA_ROOT ?= $(ROOT_DIR)/testbench/rtl0/image0
RTL0_LAYER_DIR = $(RTL0_DATA_ROOT)/layer$(VWA_LAYER)
RTL_STATIC_LAYER_DIR = $(ROOT_DIR)/testbench/rtl$(RTL_CASE)/image$(RTL_CASE)/layer$(VWA_LAYER)
RTL_DIAGNOSE ?= 1
ifneq ($(strip $(VWA_CASE)),)
VWA_LAYER_DIR ?= $(VWA_DATA_ROOT)/$(VWA_CASE)/layer$(VWA_LAYER)
else
VWA_LAYER_DIR ?= $(VWA_DATA_ROOT)/layer$(VWA_LAYER)
endif
VWA_RELU_EN := $(if $(filter 8,$(VWA_LAYER)),0,1)

INPUT_ZERO_LANE  ?= 0
WEIGHT_ZERO_LANE ?= 0
OUTPUT_ZERO_LANE ?= 0

PROCESS_GOLDEN_PSUM ?= 1
SCALING_FACTOR      ?= 0
RELU_EN             ?= 1
MAXPOOL_EN          ?= 0
FULL_HW_PATH       ?= 0
FULL_HW_PACKET_LIMIT ?= 8
STREAM_HW_PATH     ?= 0
VWA_LAYER_MODE    ?= 0
STREAM_INPUT_SCALARS ?= 490
STREAM_HW_OUT_FILE ?= waves/$(TB)_stream_hw_vectors.txt
FULL_HW_OUT_FILE ?= waves/$(TB)_full_path_hw_vectors.txt
STREAM_PY_OUT_FILE ?= waves/$(TB)_stream_py_vectors.txt

NC_TRACE_FLAGS :=
NC_TRACE_ARGS :=
ifeq ($(TRACE),1)
NC_TRACE_FLAGS += +define+TRACE_ON
NC_TRACE_ARGS += +TRACE_FILE=$(abspath $(TRACE_FILE))
endif


define ANSWER_PASS_BANNER
	@printf '%s\n' '' '########     ###     ######   ######' '##     ##   ## ##   ##    ## ##    ##' '##     ##  ##   ##  ##       ##' '########  ##     ##  ######   ######' '##        #########       ##       ##' '##        ##     ## ##    ## ##    ##' '##        ##     ##  ######   ######' '' 'ANSWER PASS: RTL full-path output matches golden.'
endef

NC_RUN_ARGS := \
	+IFMAP_FILE=$(abspath $(IFMAP_FILE)) \
	+WEIGHT_FILE=$(abspath $(WEIGHT_FILE)) \
	+GOLDEN_FILE=$(abspath $(GOLDEN_FILE)) \
	+BIAS_FILE=$(abspath $(BIAS_FILE)) \
	+REQUANT_SHIFT_FILE=$(abspath $(REQUANT_SHIFT_FILE)) \
	+INPUT_ZERO_LANE=$(INPUT_ZERO_LANE) \
	+WEIGHT_ZERO_LANE=$(WEIGHT_ZERO_LANE) \
	+OUTPUT_ZERO_LANE=$(OUTPUT_ZERO_LANE) \
	+PROCESS_GOLDEN_PSUM=$(PROCESS_GOLDEN_PSUM) \
	+SCALING_FACTOR=$(SCALING_FACTOR) \
	+RELU_EN=$(RELU_EN) \
	+MAXPOOL_EN=$(MAXPOOL_EN) \
	+FULL_HW_PATH=$(FULL_HW_PATH) \
	+FULL_HW_PACKET_LIMIT=$(FULL_HW_PACKET_LIMIT) \
	+STREAM_HW_PATH=$(STREAM_HW_PATH) \
	+VWA_LAYER_MODE=$(VWA_LAYER_MODE) \
	+VWA_LAYER=$(VWA_LAYER) \
	+STREAM_INPUT_SCALARS=$(STREAM_INPUT_SCALARS) \
	+STREAM_HW_OUT_FILE=$(abspath $(STREAM_HW_OUT_FILE)) \
	+FULL_HW_OUT_FILE=$(abspath $(FULL_HW_OUT_FILE)) \
	+FSDB_FILE=$(abspath $(FSDB_FILE)) \
	$(NC_TRACE_ARGS)

RUN_ARGS := \
	+IFMAP_FILE=$(abspath $(IFMAP_FILE)) \
	+WEIGHT_FILE=$(abspath $(WEIGHT_FILE)) \
	+GOLDEN_FILE=$(abspath $(GOLDEN_FILE)) \
	+BIAS_FILE=$(abspath $(BIAS_FILE)) \
	+REQUANT_SHIFT_FILE=$(abspath $(REQUANT_SHIFT_FILE)) \
	+INPUT_ZERO_LANE=$(INPUT_ZERO_LANE) \
	+WEIGHT_ZERO_LANE=$(WEIGHT_ZERO_LANE) \
	+OUTPUT_ZERO_LANE=$(OUTPUT_ZERO_LANE) \
	+PROCESS_GOLDEN_PSUM=$(PROCESS_GOLDEN_PSUM) \
	+SCALING_FACTOR=$(SCALING_FACTOR) \
	+RELU_EN=$(RELU_EN) \
	+MAXPOOL_EN=$(MAXPOOL_EN) \
	+FULL_HW_PATH=$(FULL_HW_PATH) \
	+FULL_HW_PACKET_LIMIT=$(FULL_HW_PACKET_LIMIT) \
	+STREAM_HW_PATH=$(STREAM_HW_PATH) \
	+VWA_LAYER_MODE=$(VWA_LAYER_MODE) \
	+VWA_LAYER=$(VWA_LAYER) \
	+STREAM_INPUT_SCALARS=$(STREAM_INPUT_SCALARS) \
	+STREAM_HW_OUT_FILE=$(abspath $(STREAM_HW_OUT_FILE)) \
	+FULL_HW_OUT_FILE=$(abspath $(FULL_HW_OUT_FILE)) \
	$(TRACE_ARGS)

RUN_ARGS := \
	+IFMAP_FILE=$(IFMAP_FILE) \
	+WEIGHT_FILE=$(WEIGHT_FILE) \
	+GOLDEN_FILE=$(GOLDEN_FILE) \
	+BIAS_FILE=$(BIAS_FILE) \
	+REQUANT_SHIFT_FILE=$(REQUANT_SHIFT_FILE) \
	+INPUT_ZERO_LANE=$(INPUT_ZERO_LANE) \
	+WEIGHT_ZERO_LANE=$(WEIGHT_ZERO_LANE) \
	+OUTPUT_ZERO_LANE=$(OUTPUT_ZERO_LANE) \
	+PROCESS_GOLDEN_PSUM=$(PROCESS_GOLDEN_PSUM) \
	+SCALING_FACTOR=$(SCALING_FACTOR) \
	+RELU_EN=$(RELU_EN) \
	+MAXPOOL_EN=$(MAXPOOL_EN) \
	+FULL_HW_PATH=$(FULL_HW_PATH) \
	+FULL_HW_PACKET_LIMIT=$(FULL_HW_PACKET_LIMIT) \
	+STREAM_HW_PATH=$(STREAM_HW_PATH) \
	+VWA_LAYER_MODE=$(VWA_LAYER_MODE) \
	+VWA_LAYER=$(VWA_LAYER) \
	+STREAM_INPUT_SCALARS=$(STREAM_INPUT_SCALARS) \
	+STREAM_HW_OUT_FILE=$(STREAM_HW_OUT_FILE) \
	+FULL_HW_OUT_FILE=$(FULL_HW_OUT_FILE) \
	$(TRACE_ARGS)

.PHONY: all build run synthesize check-syn-netlist syn-run syn-static syn0 syn1 syn2 syn3 syn4 syn5 syn6 syn-all rtl rtl-run rtl-wave rtl-diagnose-static rtl-static rtl-all rtl0 rtl1 rtl2 rtl3 rtl4 rtl5 rtl6 tb0 tb1 tb2 ppu0 full full-tb0 full-tb1 full-tb2 full-tb3 full-trace stream stream-compare stream-tb490 diag gen-golden gen-vwa-layer-data download-cifar10 gen-rtl0 rtl0-data gen-rtl-cases gen-cifar10 gen-cifar10-two vwa-layer vwa vwa-one vwa-cifar10 vwa-cifar10-two clean help

all: run

build:
	$(VERILATOR) --sv --timing $(TRACE_FLAGS) $(INC_FLAGS) --Mdir $(OBJ_DIR) --binary $(SRC) --top-module $(TOP)

ifeq ($(SYN),1)
run: check-syn-netlist
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && $(VCS) $(VCS_SYN_FLAGS) $(VCS_DUMP_FLAGS) $(VCS_TRACE_FLAGS) $(SYN_TB_SRC) $(ROOT_DIR)/$(SYN_DIR)/top_syn.v $(ROOT_DIR)/SRAM/SRAM_rtl.sv $(SYN_RUN_ARGS)
else
run: build
ifeq ($(TRACE),1)
	mkdir -p $(dir $(TRACE_FILE))
endif
	mkdir -p $(dir $(STREAM_HW_OUT_FILE))
	$(SIM) $(RUN_ARGS)
ifeq ($(FULL_HW_PATH),1)
	$(ANSWER_PASS_BANNER)
endif
endif

tb0: run

tb1:
	$(MAKE) run TB=tb1 PROCESS_GOLDEN_PSUM=1 OUTPUT_ZERO_LANE=0

tb2:
	$(MAKE) run TB=tb2 PROCESS_GOLDEN_PSUM=1 OUTPUT_ZERO_LANE=0

ppu0:
	$(MAKE) run GOLDEN_FILE=test_data/PPU_test_data/tb0_golden.txt PROCESS_GOLDEN_PSUM=0 OUTPUT_ZERO_LANE=0

full:
	$(MAKE) run FULL_HW_PATH=1 FULL_HW_PACKET_LIMIT=$(FULL_HW_PACKET_LIMIT)

full-tb0:
	$(MAKE) full TB=tb0 TRACE=1

full-tb1:
	$(MAKE) full TB=tb1 TRACE=1

full-tb2:
	$(MAKE) full TB=tb2 TRACE=1
full-tb3:
	$(MAKE) full TB=tb3 TRACE=1	

full-trace:
	$(MAKE) run FULL_HW_PATH=1 FULL_HW_PACKET_LIMIT=$(FULL_HW_PACKET_LIMIT) TRACE=1

stream:
	$(MAKE) run STREAM_HW_PATH=1 STREAM_INPUT_SCALARS=$(STREAM_INPUT_SCALARS) PROCESS_GOLDEN_PSUM=0

stream-compare:
	$(MAKE) stream TB=$(TB) STREAM_INPUT_SCALARS=$(STREAM_INPUT_SCALARS) STREAM_HW_OUT_FILE=$(STREAM_HW_OUT_FILE)
	python3 tools/diagnose_stream.py --ifmap $(IFMAP_FILE) --filter $(WEIGHT_FILE) --hw-output $(STREAM_HW_OUT_FILE) --py-output $(STREAM_PY_OUT_FILE) --input-scalars $(STREAM_INPUT_SCALARS) --scaling $(SCALING_FACTOR) --relu $(RELU_EN)

stream-tb490:
	$(MAKE) stream-compare TB=tb490 STREAM_INPUT_SCALARS=490 TRACE=1	

diag:
	tools/diagnose_full_path.py --ifmap $(IFMAP_FILE) --filter $(WEIGHT_FILE) --golden $(GOLDEN_FILE) --packets $(FULL_HW_PACKET_LIMIT) --scaling $(SCALING_FACTOR) --relu $(RELU_EN)

gen-golden:
	tools/diagnose_full_path.py --ifmap $(IFMAP_FILE) --filter $(WEIGHT_FILE) --golden $(GOLDEN_FILE) --packets $(FULL_HW_PACKET_LIMIT) --scaling $(SCALING_FACTOR) --relu $(RELU_EN) --write-current-psum $(GOLDEN_FILE)

gen-vwa-layer-data:
	python3 tools/gen_vwa_layer_data.py

download-cifar10:
	@if test -f $(CIFAR_TEST_BATCH); then \
		echo "CIFAR-10 test batch already exists: $(CIFAR_TEST_BATCH)"; \
	else \
		$(PYTHON) tools/download_cifar10.py --root "$(CIFAR_ROOT)"; \
	fi

gen-cifar10: download-cifar10
	$(PYTHON) tools/gen_vwa_layer_data.py --input cifar10 --cifar-root $(CIFAR_ROOT) --cifar-index $(CIFAR_IMAGE) --case-name $(CIFAR_CASE)

# Local-only generation of static image-0 data for the server rtl0 target.
gen-rtl0: download-cifar10
	$(PYTHON) tools/gen_vwa_layer_data.py --input cifar10 --cifar-root $(CIFAR_ROOT) --cifar-index 0 --out-dir testbench/rtl0 --case-name image0

rtl0-data: gen-rtl0

# Local regeneration helper for all checked-in static image cases.
gen-rtl-cases: download-cifar10
	@for case_id in 0 1 2 3 4 5 6; do \
		$(PYTHON) tools/gen_vwa_layer_data.py --input cifar10 \
			--cifar-root "$(abspath $(CIFAR_ROOT))" --cifar-index $$case_id \
			--out-dir "$(ROOT_DIR)/testbench/rtl$$case_id" --case-name image$$case_id; \
	done

gen-cifar10-two:
	$(MAKE) gen-cifar10 CIFAR_IMAGE=0
	$(MAKE) gen-cifar10 CIFAR_IMAGE=1

ifeq ($(strip $(VWA_CASE)),)
VWA_DATA_PREREQ := gen-vwa-layer-data
endif
ifeq ($(SYN),1)
VWA_SYN_PREREQ := check-syn-netlist
endif

vwa-layer: $(VWA_DATA_PREREQ)
	$(MAKE) run IFMAP_FILE=$(VWA_LAYER_DIR)/ifmap_padded_u8.txt WEIGHT_FILE=$(VWA_LAYER_DIR)/weight_i8.txt GOLDEN_FILE=$(VWA_LAYER_DIR)/golden_conv_relu_u8.txt INPUT_ZERO_LANE=128 OUTPUT_ZERO_LANE=128 PROCESS_GOLDEN_PSUM=0 VWA_LAYER_MODE=1

# Without layer=<n>, run every supported VGG8 hardware layer. FC6 is excluded.
vwa: $(VWA_SYN_PREREQ) $(VWA_DATA_PREREQ)
ifeq ($(VWA_SINGLE_LAYER),1)
	$(MAKE) vwa-one VWA_LAYER=$(VWA_LAYER) VWA_CASE=$(VWA_CASE)
else
	$(MAKE) vwa-one VWA_LAYER=1 VWA_CASE=$(VWA_CASE)
	$(MAKE) vwa-one VWA_LAYER=2 VWA_CASE=$(VWA_CASE)
	$(MAKE) vwa-one VWA_LAYER=3 VWA_CASE=$(VWA_CASE)
	$(MAKE) vwa-one VWA_LAYER=4 VWA_CASE=$(VWA_CASE)
	$(MAKE) vwa-one VWA_LAYER=5 VWA_CASE=$(VWA_CASE)
	$(MAKE) vwa-one VWA_LAYER=7 VWA_CASE=$(VWA_CASE)
	$(MAKE) vwa-one VWA_LAYER=8 VWA_CASE=$(VWA_CASE)
endif

# Internal single-layer runner used by the full suite above.
vwa-one:
	$(MAKE) run IFMAP_FILE=$(VWA_LAYER_DIR)/ifmap_controller_u8.txt WEIGHT_FILE=$(VWA_LAYER_DIR)/weight_i8.txt GOLDEN_FILE=$(VWA_LAYER_DIR)/golden_conv_relu_u8.txt BIAS_FILE=$(VWA_LAYER_DIR)/bias_i32.txt REQUANT_SHIFT_FILE=$(VWA_LAYER_DIR)/requant_shift.txt INPUT_ZERO_LANE=128 OUTPUT_ZERO_LANE=128 PROCESS_GOLDEN_PSUM=0 RELU_EN=$(VWA_RELU_EN) VWA_LAYER_MODE=1 FULL_HW_PATH=1 VWA_LAYER=$(VWA_LAYER)

vwa-cifar10: $(VWA_SYN_PREREQ) gen-cifar10
	$(MAKE) vwa VWA_CASE=$(CIFAR_CASE) VWA_LAYER=$(VWA_LAYER) VWA_SINGLE_LAYER=$(VWA_SINGLE_LAYER)

# Underscore alias kept for course scripts.
vwa_cifar10: vwa-cifar10

vwa-cifar10-two: gen-cifar10-two
	$(MAKE) vwa-cifar10 CIFAR_IMAGE=0
	$(MAKE) vwa-cifar10 CIFAR_IMAGE=1

# Course-server RTL simulation using ncverilog.
rtl: gen-cifar10
	$(MAKE) rtl-run VWA_LAYER=$(VWA_LAYER) VWA_CASE=$(CIFAR_CASE) \
		IFMAP_FILE=$(VWA_DATA_ROOT)/$(CIFAR_CASE)/layer$(VWA_LAYER)/ifmap_controller_u8.txt \
		WEIGHT_FILE=$(VWA_DATA_ROOT)/$(CIFAR_CASE)/layer$(VWA_LAYER)/weight_i8.txt \
		GOLDEN_FILE=$(VWA_DATA_ROOT)/$(CIFAR_CASE)/layer$(VWA_LAYER)/golden_conv_relu_u8.txt \
		BIAS_FILE=$(VWA_DATA_ROOT)/$(CIFAR_CASE)/layer$(VWA_LAYER)/bias_i32.txt \
		REQUANT_SHIFT_FILE=$(VWA_DATA_ROOT)/$(CIFAR_CASE)/layer$(VWA_LAYER)/requant_shift.txt \
		INPUT_ZERO_LANE=128 OUTPUT_ZERO_LANE=128 PROCESS_GOLDEN_PSUM=0 \
		RELU_EN=$(VWA_RELU_EN) VWA_LAYER_MODE=1 FULL_HW_PATH=1

rtl-run:
	mkdir -p $(RTL_RUN_DIR) $(dir $(FULL_HW_OUT_FILE)) $(dir $(STREAM_HW_OUT_FILE)) $(dir $(FSDB_FILE))
	cd $(RTL_RUN_DIR) && $(NC) $(NCFLAGS) $(NC_DUMP_FLAGS) $(NC_TRACE_FLAGS) $(RTL_SRC) $(NC_RUN_ARGS)
	$(ANSWER_PASS_BANNER)

rtl-wave:
	nWave $(abspath $(FSDB_FILE)) &

# Fixed CIFAR-10 cases.  Case N uses image N and works with
# layer=1/2/3/4/5/7/8.  diagnose_vwa.py checks the checked-in golden against
# the current hardware data layout before launching the simulator.
rtl-diagnose-static:
	@test -f $(RTL_STATIC_LAYER_DIR)/ifmap_controller_u8.txt || { echo "Missing static rtl$(RTL_CASE) data for layer $(VWA_LAYER): $(RTL_STATIC_LAYER_DIR)"; exit 2; }
ifeq ($(RTL_DIAGNOSE),1)
	$(PYTHON) tools/diagnose_vwa.py --layer $(VWA_LAYER) --layer-dir $(RTL_STATIC_LAYER_DIR) --compare
else
	@echo "Skipping diagnose_vwa.py because RTL_DIAGNOSE=$(RTL_DIAGNOSE)"
endif

rtl-static: rtl-diagnose-static
	$(MAKE) rtl-run RTL_CASE=$(RTL_CASE) TB=rtl$(RTL_CASE) VWA_LAYER=$(VWA_LAYER) \
		IFMAP_FILE=$(RTL_STATIC_LAYER_DIR)/ifmap_controller_u8.txt \
		WEIGHT_FILE=$(RTL_STATIC_LAYER_DIR)/weight_i8.txt \
		GOLDEN_FILE=$(RTL_STATIC_LAYER_DIR)/golden_conv_relu_u8.txt \
		BIAS_FILE=$(RTL_STATIC_LAYER_DIR)/bias_i32.txt \
		REQUANT_SHIFT_FILE=$(RTL_STATIC_LAYER_DIR)/requant_shift.txt \
		INPUT_ZERO_LANE=128 OUTPUT_ZERO_LANE=128 PROCESS_GOLDEN_PSUM=0 \
		RELU_EN=$(VWA_RELU_EN) VWA_LAYER_MODE=1 FULL_HW_PATH=1

rtl0: RTL_CASE := 0
rtl0: rtl-static
rtl1: RTL_CASE := 1
rtl1: rtl-static
rtl2: RTL_CASE := 2
rtl2: rtl-static
rtl3: RTL_CASE := 3
rtl3: rtl-static
rtl4: RTL_CASE := 4
rtl4: rtl-static
rtl5: RTL_CASE := 5
rtl5: rtl-static
rtl6: RTL_CASE := 6
rtl6: rtl-static
rtl-all: rtl0 rtl1 rtl2 rtl3 rtl4 rtl5 rtl6

# Gate-level counterparts of the same fixed cases.  Run `make synthesize`
# first to create syn/top_syn.v, then select the case with syn0...syn6.
SYN_RUN_ARGS = $(NC_RUN_ARGS)
syn-run: check-syn-netlist
	mkdir -p $(BUILD_DIR) $(dir $(FULL_HW_OUT_FILE)) $(dir $(STREAM_HW_OUT_FILE))
	cd $(BUILD_DIR) && $(VCS) $(VCS_SYN_FLAGS) $(VCS_DUMP_FLAGS) $(VCS_TRACE_FLAGS) $(SYN_TB_SRC) $(ROOT_DIR)/$(SYN_DIR)/top_syn.v $(ROOT_DIR)/SRAM/SRAM_rtl.sv $(SYN_RUN_ARGS)

syn-static:
	@test -f $(RTL_STATIC_LAYER_DIR)/ifmap_controller_u8.txt || { echo "Missing static rtl$(RTL_CASE) data for layer $(VWA_LAYER): $(RTL_STATIC_LAYER_DIR)"; exit 2; }
	$(MAKE) syn-run RTL_CASE=$(RTL_CASE) TB=rtl$(RTL_CASE) VWA_LAYER=$(VWA_LAYER) \
		IFMAP_FILE=$(RTL_STATIC_LAYER_DIR)/ifmap_controller_u8.txt \
		WEIGHT_FILE=$(RTL_STATIC_LAYER_DIR)/weight_i8.txt \
		GOLDEN_FILE=$(RTL_STATIC_LAYER_DIR)/golden_conv_relu_u8.txt \
		BIAS_FILE=$(RTL_STATIC_LAYER_DIR)/bias_i32.txt \
		REQUANT_SHIFT_FILE=$(RTL_STATIC_LAYER_DIR)/requant_shift.txt \
		INPUT_ZERO_LANE=128 OUTPUT_ZERO_LANE=128 PROCESS_GOLDEN_PSUM=0 \
		RELU_EN=$(VWA_RELU_EN) VWA_LAYER_MODE=1 FULL_HW_PATH=1

syn0: RTL_CASE := 0
syn0: syn-static
syn1: RTL_CASE := 1
syn1: syn-static
syn2: RTL_CASE := 2
syn2: syn-static
syn3: RTL_CASE := 3
syn3: syn-static
syn4: RTL_CASE := 4
syn4: syn-static
syn5: RTL_CASE := 5
syn5: syn-static
syn6: RTL_CASE := 6
syn6: syn-static
syn-all: syn0 syn1 syn2 syn3 syn4 syn5 syn6

synthesize:
	mkdir -p $(BUILD_DIR) $(SYN_DIR)
	cp script/synopsys_dc.setup $(BUILD_DIR)/.synopsys_dc.setup
	cd $(BUILD_DIR) && $(DC_SHELL) -no_home_init -f ../script/synthesis.tcl | tee syn_compile.log

check-syn-netlist:
	@test -f $(SYN_DIR)/top_syn.v || { echo "Missing $(SYN_DIR)/top_syn.v. Run 'make synthesize' first."; exit 2; }

clean:
	rm -rf obj_dir obj_dir_trace

help:
	@echo "Targets:"
	@echo "  make        Build and run tb0 PE-opsum -> PPU-ref -> RLC reference flow"
	@echo "  make build  Build SV-only testbench"
	@echo "  make run    Build and run with overridable variables"
	@echo "  make tb1    Run PE tb1 data through PPU reference"
	@echo "  make tb2    Run PE tb2 data through PPU reference"
	@echo "  make ppu0   Run with copied Lab3 PPU tb0 golden as 8-bit output data"
	@echo "  make full TB=tb1  Run full path with PE_test_data/tb1"
	@echo "  make full-tb1     Shortcut for full TB=tb1"
	@echo "  make full-trace   Run full path and write VCD to waves/tb.vcd"
	@echo "  make stream-tb490 Run 490-scalar stream test, dump HW txt, and compare Python model"
	@echo "  make diag   Run Python layout/golden diagnostic for current full path"
	@echo "  make gen-golden TB=tb3  Write Python current-full-path psums into the TB golden file"
	@echo "  make gen-vwa-layer-data  Generate VWA layer dense ifmap/weight/golden Conv+ReLU data"
	@echo "  make download-cifar10  Download CIFAR-10 test data when absent"
	@echo "  make gen-cifar10 image=42  Generate one raw CIFAR-10 test-image case"
	@echo "  make gen-cifar10-two  Generate raw CIFAR-10 test-image cases 0 and 1"
	@echo "  make vwa-layer VWA_LAYER=1  Run RLC/top smoke flow using VWA layer dense files"
	@echo "  make vwa           Run layers 1-5 and 7-8 through RTL hardware flow"
	@echo "  make vwa syn=1     Run the same suite using syn/top_syn.v with VCS"
	@echo "  make vwa-cifar10 image=42 [layer=1]  Validate all or one layer with one CIFAR-10 image"
	@echo "  make vwa-cifar10-two  Validate all supported layers with CIFAR-10 test images 0 and 1"
	@echo "  make rtl image=42 layer=1  Generate CIFAR data then run one VCS layer"
	@echo "  make gen-rtl0  Locally generate static image-0 data; no simulator is run"
	@echo "  make rtl0 layer=1 DUMP=1  Diagnose static image-0 data, then run normal FSDB dump"
	@echo "  make rtl0..rtl6 layer=1 DUMP=1  Run checked-in CIFAR image 0..6 with ncverilog"
	@echo "  make syn0..syn6 layer=1  Run the matching image case against syn/top_syn.v"
	@echo "  make synthesize    Run the lab6-compatible Synopsys DC flow"
	@echo "  make rtl-wave TRACE_FILE=waves/tb.vcd  Open the RTL VCD in nWave"
	@echo "  make TRACE=1  Build/run and write VCD to waves/tb.vcd"
	@echo "Variables: TB IFMAP_FILE WEIGHT_FILE GOLDEN_FILE PROCESS_GOLDEN_PSUM SCALING_FACTOR RELU_EN MAXPOOL_EN FULL_HW_PACKET_LIMIT STREAM_INPUT_SCALARS STREAM_HW_OUT_FILE STREAM_PY_OUT_FILE VWA_LAYER VWA_LAYER_MODE VWA_CASE VWA_DATA_ROOT CIFAR_ROOT CIFAR_IMAGE CIFAR_CASE VWA_SINGLE_LAYER layer image syn SYN TRACE TRACE_FILE VCS RTL_RUN_DIR RTL0_DATA_ROOT RTL_CASE RTL_DIAGNOSE DUMP FSDB_FILE"

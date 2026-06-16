VERILATOR ?= verilator
TOP       ?= tb
TRACE     ?= 0

ifeq ($(TRACE),1)
OBJ_DIR ?= obj_dir_trace
else
OBJ_DIR ?= obj_dir
endif
SIM := $(OBJ_DIR)/V$(TOP)

TRACE_FILE ?= waves/tb.vcd
TRACE_FLAGS :=
TRACE_ARGS  :=
ifeq ($(TRACE),1)
TRACE_FLAGS += --trace -DTRACE_ON
TRACE_ARGS  += +TRACE_FILE=$(TRACE_FILE)
endif

INC_FLAGS := -Ihw

SRC := src/encode.sv src/decode.sv src/weight.sv \
	hw/input_RLC_decoder.v hw/input_sram_reg.v hw/weight_sram_reg.v \
	hw/Controller.sv hw/pe_block_7x3.v hw/boundary_regfile.sv hw/accumulator.sv \
	hw/PostQuant.sv hw/ReLU_Qint8.sv hw/Maxpool_Qint8.sv \
	hw/PPU.sv hw/PPU_to_RLC_Packer.sv \
	hw/output_RLC_encoder.v \
	top.sv tb.sv

TB ?= tb0
IFMAP_FILE  ?= test_data/PE_test_data/$(TB)/ifmap_$(TB).txt
WEIGHT_FILE ?= test_data/PE_test_data/$(TB)/filter_$(TB).txt
GOLDEN_FILE ?= test_data/PE_test_data/$(TB)/ofmap_$(TB).txt

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
STREAM_INPUT_SCALARS ?= 490
STREAM_HW_OUT_FILE ?= waves/$(TB)_stream_hw_vectors.txt
STREAM_PY_OUT_FILE ?= waves/$(TB)_stream_py_vectors.txt

RUN_ARGS := \
	+IFMAP_FILE=$(IFMAP_FILE) \
	+WEIGHT_FILE=$(WEIGHT_FILE) \
	+GOLDEN_FILE=$(GOLDEN_FILE) \
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
	+STREAM_INPUT_SCALARS=$(STREAM_INPUT_SCALARS) \
	+STREAM_HW_OUT_FILE=$(STREAM_HW_OUT_FILE) \
	$(TRACE_ARGS)

.PHONY: all build run tb0 tb1 tb2 ppu0 full full-tb0 full-tb1 full-tb2 full-tb3 full-trace stream stream-compare stream-tb490 diag gen-golden clean help

all: run

build:
	$(VERILATOR) --sv --timing $(TRACE_FLAGS) $(INC_FLAGS) --Mdir $(OBJ_DIR) --binary $(SRC) --top-module $(TOP)

run: build
ifeq ($(TRACE),1)
	mkdir -p $(dir $(TRACE_FILE))
endif
	mkdir -p $(dir $(STREAM_HW_OUT_FILE))
	$(SIM) $(RUN_ARGS)

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
	@echo "  make TRACE=1  Build/run and write VCD to waves/tb.vcd"
	@echo "Variables: TB IFMAP_FILE WEIGHT_FILE GOLDEN_FILE PROCESS_GOLDEN_PSUM SCALING_FACTOR RELU_EN MAXPOOL_EN FULL_HW_PACKET_LIMIT STREAM_INPUT_SCALARS STREAM_HW_OUT_FILE STREAM_PY_OUT_FILE TRACE TRACE_FILE"

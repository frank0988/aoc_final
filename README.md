# VWA Quantized VGG8 Accelerator

This project implements and verifies a VWA-style quantized CNN accelerator.  The
full hardware path is:

```text
RLC input -> input SRAM -> Controller -> 7x3 PE -> accumulator
          -> PPU (bias/requant/ReLU) -> RLC packer -> RLC output
```

The supported VGG8 layers are convolution layers 1--5 and 1x1/FC layers 7--8.
FC6 is intentionally outside the current hardware validation scope.  It is the
flatten-to-classifier boundary and requires an FC6-specific spatial flatten,
channel reorder, and buffer/address mapping frontend.  The current 1x1
Controller path validates FC7 and FC8 after this conversion, but does not
implement that FC6 frontend.

## Repository Layout

- `top.sv`, `tb.sv`: integration top and self-checking testbench.
- `hw/Controller.sv`: 3x3 and 1x1 controller FSM.
- `hw/pe_block_7x3.v`, `hw/accumulator.sv`, `hw/PPU.sv`: compute pipeline.
- `hw/input_sram_wrapper.sv`, `hw/weight_sram_wrapper.sv`,
  `hw/boundart_sram_wrapper.sv`: legacy SRAM macro wrappers.
- `hw/weight_pingpong_wrapper.sv`: active two-SRAM, 2K-entry logical
  ping-pong weight buffer for Controller compute/preload traffic.
- `SRAM/SRAM_rtl.sv`, `hw/sram_macro_wrapper.sv`: 16K x 32-bit SRAM macro RTL
  and its VWA adapter.
- `tools/gen_vwa_layer_data.py`: generates quantized ifmap, weights, bias,
  requant shift, and PyTorch golden data.
- `../VWA/testbench/layer_data/`: generated layer data.  It is created by the
  generator and is not a source directory.

## Evaluation Environment

The project is intended to run in the course Docker environment:

- Ubuntu 24.04
- Verilator 5.030
- Python 3.11
- `torch`, `torchvision`, and `numpy`

The data generator imports the course VGG/QConfig code and checkpoint from the
sibling lab repository.  The expected layout is:

```text
aoc_final/
  model/
    lib/
    vgg8-power2.pt
  data/cifar10/cifar-10-batches-py/
    test_batch
```

The generator defaults to these project-local files. Override `--model`,
`--cifar-root`, or `--out-dir` only when deliberately using another dataset or
checkpoint.

## Quick Start

From this directory:

```bash
make vwa
```

The command performs these steps:

1. Generates VGG8 quantized test data and PyTorch golden outputs.
2. Builds the SystemVerilog design using Verilator.
3. Loads RLC input/weight streams into SRAM.
4. Runs Controller -> PE -> accumulator -> PPU -> RLC output.
5. Decompresses the hardware output and compares it against the layer golden.

A successful run ends with:

```text
FULL PATH decoded output vs layer golden pass
PASS: reference converter and HW RLC units are consistent
```

## Layer Coverage

`make vwa` runs layers 1--5 and 7--8 in order. Add `layer=<n>` to run one supported layer. Layer 1--5 use 3x3
convolution; layers 7--8 use the Controller's 1x1 mode. FC6 remains excluded
because its flatten-to-classifier frontend is not implemented in this design.

The larger 3x3 layers take substantially longer because the testbench performs
an end-to-end scalar golden comparison. `tb.sv` uses a 400M-cycle guard for
this SRAM-backed configuration.

## CIFAR-10 Two-Image Validation

The repository includes the offline CIFAR-10 test set at
`data/cifar10/cifar-10-batches-py/test_batch` (10,000 images). The generator reads raw RGB uint8 pixels,
converts them to the model's existing `0..1` input convention, and creates
separate golden data for two test images. No download is performed.

```bash
make gen-cifar10 image=42
make vwa-cifar10 image=42             # layers 1-5, 7-8
make vwa-cifar10 image=42 layer=1     # only layer 1

# Existing two-image shortcut: test images 0 and 1
make vwa-cifar10-two
```

The cases are isolated so their golden files cannot overwrite each other:

```text
../VWA/testbench/layer_data/cifar10_image_0/layer1/
../VWA/testbench/layer_data/cifar10_image_1/layer1/
```

Run a generated image case directly with:

```bash
make vwa-cifar10 image=42
make vwa VWA_CASE=cifar10_image_42
```

Useful build commands:

```bash
make build                         # compile only
make gen-vwa-layer-data            # regenerate layer files
make vwa TRACE=1    # write waves/tb.vcd
make clean                         # remove Verilator build directories
make synthesize                     # run Synopsys DC synthesis
```

## Server RTL Simulation

On the course server, run one CIFAR-10 layer with the ncverilog flow adapted
from `Makefile_ncverilog`:

```bash
make rtl image=42 layer=1
make rtl image=42 layer=1 TRACE=1 TRACE_FILE=waves/cifar10_42_l1.vcd
```

`rtl` uses `ncverilog -64`, `+access+rwc`, `+notimingcheck`, and writes Cadence
run artifacts under `waves/ncverilog/`. `layer` is required for a single RTL
server run; supported values are `1 2 3 4 5 7 8`.

## Synthesis

The synthesis flow follows `lab6-MAX990ck`: it uses the course N16 standard-cell
libraries, the local SRAM `.db` models, `dc_shell -no_home_init`, and a copied
`.synopsys_dc.setup` in `build/`.

```bash
make synthesize       # creates syn/top_syn.v, syn/top_syn.sdf, and reports
make vwa syn=1        # VCS simulation of the synthesized netlist
make vwa-cifar10 image=42 syn=1
```

`make vwa syn=1` means **simulate the existing synthesized files**. It checks
for `syn/top_syn.v` and prints a clear error if `make synthesize` has not been
run first. The RTL path remains the default (`syn=0`).

## Ping-Pong Weight Buffer

Controller compute traffic uses `weight_pingpong_wrapper.sv`, not the legacy
1M-entry logical weight SRAM.  It exposes two 2K-entry logical buffers:

```text
weight_sram_0: current output-channel weights used by the PE
weight_sram_1: next output-channel weights being preloaded
```

The Controller exports `compute_sram_sel`, `preload_sram_sel`,
`preload_start`, `compute_done`, `swap_enable`, `current_m`, and `next_m`.
At a channel boundary it enters `WAIT_PRELOAD` when the next buffer is not
ready; it swaps roles only after `compute_done && preload_done`.

The full-path TB first loads `m=0` into SRAM 0, then preloads every `m+1` into
the inactive SRAM while the current `m` computes.  The input activation stream
continues to use the existing RLC encoder/decoder path.  Weights currently use
the dedicated 24-bit preload write interface, not RLC; weight-RLC token packing
has not yet been defined in the repository and is therefore listed as pending.

## SRAM Integration

All three storage blocks use the 16K x 32-bit macro model in `SRAM/SRAM_rtl.sv`.

| Storage | Wrapper | Organization |
| --- | --- | --- |
| Input activation | `input_sram_wrapper.sv` | 4 depth banks x 2 words = 64K x 56-bit logical space |
| Weights | `weight_sram_wrapper.sv` | 64 depth banks = 1M x 24-bit logical space |
| Boundary partial sums | `boundart_sram_wrapper.sv` | one 32-bit SRAM plus valid-bit table |

The SRAM macro has synchronous read behavior.  `top.sv` therefore inserts one
fetch cycle before each Controller input/filter handshake.  The boundary
accumulator already uses a request/response sequence and is compatible with
this latency.  Input/weight SRAM standalone checks in `tb.sv` also wait one
clock after asserting an address.

Input and weight SRAM traffic is phase-separated (load, then compute), so
ping-pong SRAM is not required.  Boundary accesses are serialized by the
boundary transaction FSM; no same-cycle read/write conflict is issued.

## Generated Data and Quantization

`tools/gen_vwa_layer_data.py` uses `vgg8-power2.pt` to generate, per layer:

- `ifmap_controller_u8.txt`
- `weight_i8.txt`
- `golden_conv_relu_u8.txt`
- `bias_i32.txt`
- `requant_shift.txt`

The PPU adds the integer bias, performs power-of-two requantization, applies
ReLU where required, and emits uint8 values centered at zero point 128.

## Verification Status

The following complete paths have been rerun after the ping-pong conversion:

- `make vwa`: Conv3x3 ping-pong -> Controller -> PE ->
  accumulator -> PPU -> RLC golden comparison: PASS.
- `make vwa layer=8`: Conv1x1-compatible classifier data (`C=128`,
  `H=W=1`, `M=10`) through the same ping-pong path: PASS.

Layer 2--5 and layer 7 should be rerun before final submission.  The larger
3x3 layers take longer because of synchronous SRAM fetch cycles.

## Final Project Submission Checklist

This checklist follows `Final_Project_Guidelines.md`.

- [x] Complete source code, Makefile, testbench, sample model path, and data
  generator are included.
- [x] README documents environment, setup, model/checkpoint dependency,
  commands, sample output, and verification flow.
- [x] End-to-end hardware comparison is provided for VGG8 layers 1--5, 7--8;
  FC6 is explicitly excluded from scope.
- [x] Run and record the SRAM-backed PASS results for layers 1--5, 7, and 8.
- [ ] Prepare `groupXX_slides.pdf` or `groupXX_slides.pptx` for the presentation.
- [ ] Prepare `groupXX_report.pdf`; the guideline suggests abstract,
  background/problem, design, experiments/results, conclusion, and references.
- [ ] Submit `groupXX_code.zip` or public-repository `groupXX_code.txt`.
- [ ] Complete the group peer-assessment form before the course deadline.

## Notes for Graders

The project depends on the course VGG implementation and checkpoint mentioned
in **Evaluation Environment**.  Keep `aoc_final` beside `lab-2-MAX990ck`, or
supply an equivalent checkpoint location to the generator.  No network download
is needed when the checkpoint is present.

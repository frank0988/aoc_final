#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np


LAYER_SHAPES = {
    1: dict(C=3, H=32, W=32, M=64, E=32, F=32, R=3, S=3, mode_1x1=False),
    2: dict(C=64, H=16, W=16, M=192, E=16, F=16, R=3, S=3, mode_1x1=False),
    3: dict(C=192, H=8, W=8, M=384, E=8, F=8, R=3, S=3, mode_1x1=False),
    4: dict(C=384, H=8, W=8, M=256, E=8, F=8, R=3, S=3, mode_1x1=False),
    5: dict(C=256, H=8, W=8, M=256, E=8, F=8, R=3, S=3, mode_1x1=False),
    7: dict(C=256, H=1, W=1, M=128, E=1, F=1, R=1, S=1, mode_1x1=True),
    8: dict(C=128, H=1, W=1, M=10, E=1, F=1, R=1, S=1, mode_1x1=True),
}

LANES = 7
INPUT_ZERO_POINT = 128


@dataclass(frozen=True)
class LayerFiles:
    ifmap_u8: np.ndarray
    weight_i8: np.ndarray
    bias_i32: np.ndarray
    requant_shift: int


@dataclass
class StageTrace:
    entries: list[tuple[str, tuple[int, ...] | str]]

    def add(self, name: str, value: np.ndarray | str) -> None:
        if isinstance(value, np.ndarray):
            self.entries.append((name, value.shape))
        else:
            self.entries.append((name, value))

    def print(self) -> None:
        if not self.entries:
            return
        print("[diagnose_vwa] stage summary")
        for name, value in self.entries:
            print(f"  {name}: {value}")


# -----------------------------------------------------------------------------
# File parsing helpers.
# -----------------------------------------------------------------------------

def read_ints(path: Path) -> list[int]:
    text = path.read_text()
    return [int(x) for x in re.findall(r"-?\d+", text)]


def write_ints(path: Path, values: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = values.reshape(-1)
    path.write_text("".join(f"{int(value)}\n" for value in flat))


def as_u8_array(path: Path, expected_count: int, label: str) -> np.ndarray:
    values = read_ints(path)
    if len(values) != expected_count:
        raise ValueError(f"{label}: got {len(values)} value(s), expected {expected_count}")
    for idx, value in enumerate(values):
        if value < 0 or value > 255:
            raise ValueError(f"{label}[{idx}]={value} is outside uint8 range")
    return np.asarray(values, dtype=np.uint8)


def as_i8_array(path: Path, expected_count: int, label: str) -> np.ndarray:
    values = read_ints(path)
    if len(values) != expected_count:
        raise ValueError(f"{label}: got {len(values)} value(s), expected {expected_count}")
    signed = []
    for idx, value in enumerate(values):
        if value < -128 or value > 255:
            raise ValueError(f"{label}[{idx}]={value} does not fit one 8-bit lane")
        if value >= 128:
            value -= 256
        signed.append(value)
    return np.asarray(signed, dtype=np.int16)


def as_i32_array(path: Path, expected_count: int, label: str) -> np.ndarray:
    values = read_ints(path)
    if len(values) != expected_count:
        raise ValueError(f"{label}: got {len(values)} value(s), expected {expected_count}")
    return np.asarray(values, dtype=np.int64)


def layer_runtime_counts(shape: dict[str, Any]) -> tuple[int, int, int, int]:
    mode_1x1 = bool(shape["mode_1x1"])
    c_cfg = (shape["C"] + 2) // 3 if mode_1x1 else shape["C"]
    ifmap_c_vectors = c_cfg * 3 if mode_1x1 else shape["C"]
    raw_w_span = shape["F"] if mode_1x1 else shape["F"] + 2
    w_span = raw_w_span if mode_1x1 else ((raw_w_span + 2) // 3) * 3
    weight_lanes_per_c = 3 if mode_1x1 else 9
    return c_cfg, ifmap_c_vectors, w_span, weight_lanes_per_c


def load_layer_files(layer_dir: Path, shape: dict[str, Any]) -> LayerFiles:
    c_cfg, ifmap_c_vectors, w_span, weight_lanes_per_c = layer_runtime_counts(shape)
    expected_ifmap = ifmap_c_vectors * shape["E"] * w_span * LANES
    expected_weight = shape["M"] * c_cfg * weight_lanes_per_c

    shifts = read_ints(layer_dir / "requant_shift.txt")
    if len(shifts) != 1:
        raise ValueError(f"requant_shift: got {len(shifts)} value(s), expected 1")

    return LayerFiles(
        ifmap_u8=as_u8_array(layer_dir / "ifmap_controller_u8.txt", expected_ifmap, "ifmap"),
        weight_i8=as_i8_array(layer_dir / "weight_i8.txt", expected_weight, "weight"),
        bias_i32=as_i32_array(layer_dir / "bias_i32.txt", shape["M"], "bias"),
        requant_shift=shifts[0],
    )


# -----------------------------------------------------------------------------
# Controller/input SRAM stage.
# -----------------------------------------------------------------------------

def controller_ifmap_stream_3x3(ifmap_u8: np.ndarray, shape: dict[str, Any]) -> np.ndarray:
    c_count = shape["C"]
    e_count = shape["E"]
    raw_w_span = shape["F"] + 2
    w_span = ((raw_w_span + 2) // 3) * 3
    return ifmap_u8.reshape(c_count, e_count, w_span, LANES)


def controller_ifmap_stream_1x1(ifmap_u8: np.ndarray, shape: dict[str, Any]) -> np.ndarray:
    # v6 writes three consecutive 56-bit vectors into SRAM bank0/1/2.
    # Only lane0 is a real 1x1 activation; lanes 1..6 are zero-point padding.
    c_groups = (shape["C"] + 2) // 3
    c_padded = c_groups * 3
    by_channel = ifmap_u8.reshape(c_padded, shape["E"], shape["F"], LANES)
    return by_channel.reshape(c_groups, 3, shape["E"], shape["F"], LANES)


def controller_signed_ifmap_3x3(ifmap_stream: np.ndarray, shape: dict[str, Any]) -> np.ndarray:
    f_count = shape["F"]
    signed_stream = ifmap_stream.astype(np.int64) - INPUT_ZERO_POINT
    windows = np.empty((shape["C"], shape["E"], f_count, 3, 3), dtype=np.int64)

    # stream[c,e,w,lane] is padded_ifmap[c,e+lane,w].  The controller advances
    # w for the horizontal kernel column and lane for the vertical kernel row.
    for s in range(3):
        for r in range(3):
            windows[:, :, :, s, r] = signed_stream[:, :, s : s + f_count, r]
    return windows


def controller_signed_ifmap_1x1(ifmap_stream: np.ndarray) -> np.ndarray:
    # Shape in: [G,bank,E,F,7].  Controller sends the three SRAM banks to the
    # PE columns; PE row0 is the only non-padding 1x1 row.
    lane0_by_bank = ifmap_stream[:, :, :, :, 0]
    return lane0_by_bank.transpose(0, 2, 3, 1).astype(np.int64) - INPUT_ZERO_POINT


# -----------------------------------------------------------------------------
# Weight SRAM/controller filter stage.
# -----------------------------------------------------------------------------

def controller_weight_bank_3x3(weight_i8: np.ndarray, shape: dict[str, Any]) -> np.ndarray:
    # Generated order matches Controller filter SRAM beats:
    # weight[m,c,s,r], where one 24-bit beat holds r=0..2 at fixed s.
    return weight_i8.reshape(shape["M"], shape["C"], 3, 3).astype(np.int64)


def controller_weight_bank_1x1(weight_i8: np.ndarray, shape: dict[str, Any]) -> np.ndarray:
    c_groups = (shape["C"] + 2) // 3
    return weight_i8.reshape(shape["M"], c_groups, 3).astype(np.int64)


# -----------------------------------------------------------------------------
# PE stage.
# -----------------------------------------------------------------------------

def pe_mac_3x3_per_channel(ifmap_windows: np.ndarray, weights: np.ndarray) -> np.ndarray:
    # Output: partial[m,c,e,f].  This is one channel contribution before the
    # accumulator sums across c.
    return np.einsum("cefsr,mcsr->mcef", ifmap_windows, weights, optimize=True)


def pe_mac_1x1_per_group(activations: np.ndarray, weights: np.ndarray) -> np.ndarray:
    # Output: partial[m,g,e,f].  g is the packed three-channel group.
    return np.einsum("gefl,mgl->mgef", activations, weights, optimize=True)


# -----------------------------------------------------------------------------
# Accumulator stage.
# -----------------------------------------------------------------------------

def accumulator_sum_channels(partial_psums: np.ndarray) -> np.ndarray:
    # The current single-PE-block VWA path completes one output scalar by adding
    # every input-channel or channel-group contribution.
    return partial_psums.sum(axis=1, dtype=np.int64)


# -----------------------------------------------------------------------------
# PPU stage.
# -----------------------------------------------------------------------------

def ppu_add_bias(accum: np.ndarray, bias: np.ndarray) -> np.ndarray:
    return accum.astype(np.int64) + bias[:, None, None]


def ppu_round_and_shift(biased: np.ndarray, shift: int) -> np.ndarray:
    if shift < 0 or shift > 31:
        raise ValueError(f"requant shift {shift} is outside 0..31")
    rounding = 0 if shift == 0 else (1 << (shift - 1))
    return (biased + rounding) >> shift


def ppu_clip_signed_qint8(shifted: np.ndarray) -> np.ndarray:
    return np.clip(shifted, -128, 127)


def ppu_add_output_zero_point(clipped: np.ndarray) -> np.ndarray:
    return clipped + INPUT_ZERO_POINT


def ppu_relu_qint8(values_u8: np.ndarray, relu: bool) -> np.ndarray:
    if relu:
        values_u8 = np.maximum(values_u8, INPUT_ZERO_POINT)
    return values_u8.astype(np.uint8)


def ppu_stage(accum: np.ndarray, bias: np.ndarray, shift: int, relu: bool) -> np.ndarray:
    biased = ppu_add_bias(accum, bias)
    shifted = ppu_round_and_shift(biased, shift)
    clipped = ppu_clip_signed_qint8(shifted)
    with_zero_point = ppu_add_output_zero_point(clipped)
    return ppu_relu_qint8(with_zero_point, relu)


# -----------------------------------------------------------------------------
# Full VWA diagnose flow.
# -----------------------------------------------------------------------------

def run_3x3_flow(files: LayerFiles, shape: dict[str, Any], trace: StageTrace) -> np.ndarray:
    ifmap_stream = controller_ifmap_stream_3x3(files.ifmap_u8, shape)
    ifmap_windows = controller_signed_ifmap_3x3(ifmap_stream, shape)
    weights = controller_weight_bank_3x3(files.weight_i8, shape)
    pe_partial = pe_mac_3x3_per_channel(ifmap_windows, weights)
    accum = accumulator_sum_channels(pe_partial)

    trace.add("input_sram/controller ifmap stream [C,E,F+2,7]", ifmap_stream)
    trace.add("controller signed 3x3 windows [C,E,F,S,R]", ifmap_windows)
    trace.add("controller weight bank [M,C,S,R]", weights)
    trace.add("PE partial psums [M,C,E,F]", pe_partial)
    trace.add("accumulator output psums [M,E,F]", accum)
    return accum


def run_1x1_flow(files: LayerFiles, shape: dict[str, Any], trace: StageTrace) -> np.ndarray:
    ifmap_stream = controller_ifmap_stream_1x1(files.ifmap_u8, shape)
    activations = controller_signed_ifmap_1x1(ifmap_stream)
    weights = controller_weight_bank_1x1(files.weight_i8, shape)
    pe_partial = pe_mac_1x1_per_group(activations, weights)
    accum = accumulator_sum_channels(pe_partial)

    trace.add("input_sram/controller ifmap stream [G,bank,E,F,7]", ifmap_stream)
    trace.add("controller signed 1x1 bank lane0 [G,E,F,3]", activations)
    trace.add("controller weight bank [M,G,3]", weights)
    trace.add("PE partial psums [M,G,E,F]", pe_partial)
    trace.add("accumulator output psums [M,E,F]", accum)
    return accum


def diagnose_layer(layer: int, layer_dir: Path, relu: bool, verbose: bool) -> np.ndarray:
    shape = LAYER_SHAPES[layer]
    trace = StageTrace([])
    trace.add("layer", f"layer{layer}, mode={'1x1' if shape['mode_1x1'] else '3x3'}")

    files = load_layer_files(layer_dir, shape)
    trace.add("raw ifmap file", files.ifmap_u8)
    trace.add("raw weight file", files.weight_i8)
    trace.add("bias_i32", files.bias_i32)
    trace.add("requant_shift", str(files.requant_shift))

    if shape["mode_1x1"]:
        accum = run_1x1_flow(files, shape, trace)
    else:
        accum = run_3x3_flow(files, shape, trace)

    ppu_out = ppu_stage(accum, files.bias_i32, files.requant_shift, relu)
    trace.add("PPU output uint8 [M,E,F]", ppu_out)
    trace.add("ReLU", "enabled" if relu else "disabled")

    if verbose:
        trace.print()
    return ppu_out


# Backward-compatible name used by earlier notes/scripts.
def generate_hw_golden(layer: int, layer_dir: Path, relu: bool) -> np.ndarray:
    return diagnose_layer(layer, layer_dir, relu, verbose=False)


# -----------------------------------------------------------------------------
# Comparison/output helpers.
# -----------------------------------------------------------------------------


def print_pass_art() -> None:
    print(r"""
 ____   _    ____ ____
|  _ \ / \  / ___/ ___|
| |_) / _ \ \___ \___ \
|  __/ ___ \ ___) |__) |
|_| /_/   \_\____/____/
""")

def compare_golden(expected: np.ndarray, golden_path: Path, mismatch_limit: int) -> bool:
    got = as_u8_array(golden_path, expected.size, "golden").reshape(expected.shape)
    mismatches = np.argwhere(got != expected)
    if mismatches.size == 0:
        print_pass_art()
        print(f"PASS: {golden_path} matches hardware-semantics golden ({expected.size} scalar(s))")
        return True

    print(f"FAIL: {golden_path} mismatch count = {len(mismatches)} / {expected.size}")
    for m_idx, e_idx, f_idx in mismatches[:mismatch_limit]:
        print(
            f"  m={m_idx} e={e_idx} f={f_idx}: "
            f"file={int(got[m_idx, e_idx, f_idx])} expected={int(expected[m_idx, e_idx, f_idx])}"
        )
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--layer", type=int, required=True, choices=sorted(LAYER_SHAPES))
    parser.add_argument("--layer-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, help="write diagnosed hardware-semantics golden to this path")
    parser.add_argument(
        "--write-golden",
        action="store_true",
        help="overwrite layer-dir/golden_conv_relu_u8.txt with diagnosed values",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="compare diagnosed values against layer-dir/golden_conv_relu_u8.txt",
    )
    parser.add_argument(
        "--relu",
        type=int,
        choices=(0, 1),
        help="override ReLU enable; default is off for layer8 and on otherwise",
    )
    parser.add_argument("--mismatch-limit", type=int, default=8)
    parser.add_argument("--verbose", action="store_true", help="print stage-by-stage tensor summary")
    args = parser.parse_args()

    layer_dir = args.layer_dir.resolve()
    relu = (args.layer != 8) if args.relu is None else bool(args.relu)
    generated = diagnose_layer(args.layer, layer_dir, relu, verbose=args.verbose)

    if args.out:
        write_ints(args.out.resolve(), generated)
        print(f"Wrote diagnosed VWA golden to {args.out.resolve()}")

    if args.write_golden:
        golden_path = layer_dir / "golden_conv_relu_u8.txt"
        write_ints(golden_path, generated)
        print(f"Overwrote {golden_path}")

    ok = True
    if args.compare:
        ok = compare_golden(generated, layer_dir / "golden_conv_relu_u8.txt", args.mismatch_limit)

    if not args.out and not args.write_golden and not args.compare:
        for value in generated.reshape(-1):
            print(int(value))

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

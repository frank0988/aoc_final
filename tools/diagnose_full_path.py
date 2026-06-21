#!/usr/bin/env python3
"""
  TB packed ifmap -> SRAM -> Controller lane unpack/qint8 conversion
  -> pe_block_7x3 math -> PPU quant/ReLU -> 7-lane RLC vector packing
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

LANES = 7


def read_ints(path: Path) -> List[int]:
    text = path.read_text()
    return [int(x) for x in re.findall(r"-?\d+", text)]


def write_ints(path: Path, values: Sequence[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(",".join(str(x) for x in values) + "\n")


def u8(value: int) -> int:
    return value & 0xFF


def s8(value: int) -> int:
    value &= 0xFF
    return value - 256 if value >= 128 else value


def qint8_to_signed(value: int) -> int:
    # Same math as Controller's {~x[7], x[6:0]} then signed interpretation.
    return (value & 0xFF) - 128


def post_quant_qint8(psum: int, scaling: int) -> int:
    shifted = psum >> scaling
    if shifted > 127:
        clipped = 127
    elif shifted < -128:
        clipped = -128
    else:
        clipped = shifted
    return clipped + 128


def ppu_ref(values: Sequence[int], scaling: int, relu: bool) -> List[int]:
    out: List[int] = []
    for value in values:
        q = post_quant_qint8(value, scaling)
        if relu and q < 128:
            q = 128
        out.append(q)
    return out


def pack_ifmap_vectors(values: Sequence[int], pad: int = 0) -> List[int]:
    vecs: List[int] = []
    for base in range(0, len(values), LANES):
        vec = 0
        for lane in range(LANES):
            idx = base + lane
            byte = u8(values[idx]) if idx < len(values) else u8(pad)
            # Current TB/RLC spec: lane0 is the most-significant byte.
            vec |= byte << ((LANES - 1 - lane) * 8)
        vecs.append(vec)
    return vecs


def pack_weight_beats(values: Sequence[int], pad: int = 0) -> List[int]:
    beats: List[int] = []
    for base in range(0, len(values), 3):
        beat = 0
        for lane in range(3):
            idx = base + lane
            byte = u8(values[idx]) if idx < len(values) else u8(pad)
            beat |= byte << (lane * 8)
        beats.append(beat)
    return beats


def vector_bytes(vec: int, layout: str) -> List[int]:
    if layout == "spec-msb":
        return [(vec >> ((LANES - 1 - lane) * 8)) & 0xFF for lane in range(LANES)]
    if layout == "controller-lsb":
        return [(vec >> (lane * 8)) & 0xFF for lane in range(LANES)]
    raise ValueError(f"unknown layout {layout}")


def weight_bytes(beat: int) -> List[int]:
    return [(beat >> (lane * 8)) & 0xFF for lane in range(3)]


def first_nonzero_weight_beat(beats: Sequence[int]) -> int:
    for idx, beat in enumerate(beats):
        if beat != 0:
            return idx
    return 0


def pe_3x3(ifmap: Sequence[int], weight: Sequence[int]) -> List[int]:
    a = list(ifmap)
    w = list(weight)
    return [
        a[0] * w[2],
        a[0] * w[1] + a[1] * w[2],
        a[0] * w[0] + a[1] * w[1] + a[2] * w[2],
        a[1] * w[0] + a[2] * w[1] + a[3] * w[2],
        a[2] * w[0] + a[3] * w[1] + a[4] * w[2],
        a[3] * w[0] + a[4] * w[1] + a[5] * w[2],
        a[4] * w[0] + a[5] * w[1] + a[6] * w[2],
        a[5] * w[0] + a[6] * w[1],
        a[6] * w[0],
    ]


def current_controller_filter_cols() -> List[int]:
    # Mirrors tb.sv's current full-path config:
    # mode=3x3, cfg_c=1, cfg_m=1, cfg_e_last=0, cfg_f_last=0.
    return [0, 0, 1, 0, 1, 2, 1, 2, 2]


def controller_filter_bank(weight_beats: Sequence[int], base: int) -> List[int]:
    bank: List[int] = []
    for col in range(3):
        idx = base + col
        bank.append(weight_beats[idx] if idx < len(weight_beats) else 0)
    return bank


def pack_output_vectors(values: Sequence[int], pad: int = 0) -> List[int]:
    vecs: List[int] = []
    for base in range(0, len(values), LANES):
        vec = 0
        for lane in range(LANES):
            idx = base + lane
            byte = u8(values[idx]) if idx < len(values) else u8(pad)
            # PPU_to_RLC_Packer: earliest scalar goes to [55:48].
            vec |= byte << ((LANES - 1 - lane) * 8)
        vecs.append(vec)
    return vecs


def model_full_path_with_layout(
    ifmap_vecs: Sequence[int],
    filter_bank: Sequence[int],
    packets: int,
    scaling: int,
    relu: bool,
    layout: str,
) -> Tuple[List[int], List[int], List[int]]:
    filter_cols = current_controller_filter_cols()
    modeled_packets = min(packets, len(ifmap_vecs), len(filter_cols))
    psums: List[int] = []
    for packet_idx in range(modeled_packets):
        lanes = [qint8_to_signed(x) for x in vector_bytes(ifmap_vecs[packet_idx], layout)]
        beat = filter_bank[filter_cols[packet_idx]]
        weights = [s8(x) for x in weight_bytes(beat)]
        psums.extend(pe_3x3(lanes, weights))
    q = ppu_ref(psums, scaling, relu)
    return psums, q, pack_output_vectors(q, pad=0)


def model_current_full_path(
    ifmap_vecs: Sequence[int],
    filter_bank: Sequence[int],
    packets: int,
    scaling: int,
    relu: bool,
) -> Tuple[List[int], List[int], List[int]]:
    return model_full_path_with_layout(ifmap_vecs, filter_bank, packets, scaling, relu, "controller-lsb")


def model_spec_lane_path(
    ifmap_vecs: Sequence[int],
    filter_bank: Sequence[int],
    packets: int,
    scaling: int,
    relu: bool,
) -> Tuple[List[int], List[int], List[int]]:
    return model_full_path_with_layout(ifmap_vecs, filter_bank, packets, scaling, relu, "spec-msb")


def first_mismatch(a: Sequence[int], b: Sequence[int]) -> int | None:
    for idx, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return idx
    if len(a) != len(b):
        return min(len(a), len(b))
    return None


def fmt_vec(vec: int) -> str:
    return f"0x{vec:014x}"


def fmt_ints(values: Sequence[int], limit: int) -> str:
    clipped = list(values[:limit])
    suffix = " ..." if len(values) > limit else ""
    return ",".join(str(x) for x in clipped) + suffix


def print_vector_table(label: str, vecs: Sequence[int], limit: int) -> None:
    print(f"\n[{label}] first {min(limit, len(vecs))}/{len(vecs)} vectors")
    for idx, vec in enumerate(vecs[:limit]):
        print(f"  vec[{idx:02d}] = {fmt_vec(vec)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ifmap", type=Path, default=Path("test_data/PE_test_data/tb0/ifmap_tb0.txt"))
    parser.add_argument("--filter", type=Path, default=Path("test_data/PE_test_data/tb0/filter_tb0.txt"))
    parser.add_argument("--golden", type=Path, default=Path("test_data/PE_test_data/tb0/ofmap_tb0.txt"))
    parser.add_argument("--packets", type=int, default=8)
    parser.add_argument("--scaling", type=int, default=0)
    parser.add_argument("--relu", type=int, default=1)
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument(
        "--write-current-psum",
        type=Path,
        help="Write current RTL full-path model psums for use as PROCESS_GOLDEN_PSUM=1 golden data.",
    )
    args = parser.parse_args()

    ifmap_values = read_ints(args.ifmap)
    filter_values = read_ints(args.filter)
    golden_psum = read_ints(args.golden)

    ifmap_vecs = pack_ifmap_vectors(ifmap_values, pad=0)
    weight_beats = pack_weight_beats(filter_values, pad=0)
    filter_base = first_nonzero_weight_beat(weight_beats)
    filter_bank = controller_filter_bank(weight_beats, filter_base)

    full_psum, full_q, full_vecs = model_current_full_path(
        ifmap_vecs, filter_bank, args.packets, args.scaling, bool(args.relu)
    )
    spec_psum, spec_q, spec_vecs = model_spec_lane_path(
        ifmap_vecs, filter_bank, args.packets, args.scaling, bool(args.relu)
    )

    golden_q = ppu_ref(golden_psum, args.scaling, bool(args.relu))
    golden_prefix = golden_q[: len(full_q)]
    golden_vecs = pack_output_vectors(golden_prefix, pad=0)

    print("[inputs]")
    print(f"  ifmap scalars={len(ifmap_values)} vectors={len(ifmap_vecs)}")
    print(f"  filter scalars={len(filter_values)} beats={len(weight_beats)} first_nonzero_beat={filter_base}")
    print(f"  golden psum scalars={len(golden_psum)}")
    print(f"  packets requested={args.packets} modeled={len(full_q) // 9} -> modeled scalars={len(full_q)}")

    if ifmap_vecs:
        vec0 = ifmap_vecs[0]
        spec_q_lanes = vector_bytes(vec0, "spec-msb")
        ctrl_q_lanes = vector_bytes(vec0, "controller-lsb")
        print("\n[first ifmap vector]")
        print(f"  SRAM vector      = {fmt_vec(vec0)}")
        print(f"  spec-msb qint8   = {fmt_ints(spec_q_lanes, 7)}")
        print(f"  spec-msb signed  = {fmt_ints([qint8_to_signed(x) for x in spec_q_lanes], 7)}")
        print(f"  controller qint8 = {fmt_ints(ctrl_q_lanes, 7)}")
        print(f"  controller sign  = {fmt_ints([qint8_to_signed(x) for x in ctrl_q_lanes], 7)}")

    print("\n[controller filter bank]")
    for col, beat in enumerate(filter_bank):
        print(f"  bank[{col}] <= beat[{filter_base + col}] = 0x{beat:06x} signed={fmt_ints([s8(x) for x in weight_bytes(beat)], 3)}")
    print(f"  fire cols = {fmt_ints(current_controller_filter_cols()[:args.packets], args.packets)}")

    print("\n[current RTL full-path model]")
    print(f"  psum prefix  = {fmt_ints(full_psum, 24)}")
    print(f"  qint8 prefix = {fmt_ints(full_q, 24)}")

    print("\n[spec-msb lane alternative]")
    print(f"  psum prefix  = {fmt_ints(spec_psum, 24)}")
    print(f"  qint8 prefix = {fmt_ints(spec_q, 24)}")

    print("\n[lab3 golden after PPU reference]")
    print(f"  qint8 prefix = {fmt_ints(golden_prefix, 24)}")

    print_vector_table("current RTL full-path model", full_vecs, args.limit)
    print_vector_table("spec-msb lane alternative", spec_vecs, args.limit)
    print_vector_table("lab3 golden prefix", golden_vecs, args.limit)

    mismatch = first_mismatch(full_vecs, golden_vecs)
    print("\n[compare current RTL model vs lab3 golden prefix]")
    if mismatch is None:
        print("  PASS")
    else:
        got = fmt_vec(full_vecs[mismatch]) if mismatch < len(full_vecs) else "<missing>"
        exp = fmt_vec(golden_vecs[mismatch]) if mismatch < len(golden_vecs) else "<missing>"
        print(f"  first mismatch vector[{mismatch}]: model={got} golden={exp}")

    mismatch = first_mismatch(spec_vecs, golden_vecs)
    print("\n[compare spec-msb lane alternative vs lab3 golden prefix]")
    if mismatch is None:
        print("  PASS")
    else:
        got = fmt_vec(spec_vecs[mismatch]) if mismatch < len(spec_vecs) else "<missing>"
        exp = fmt_vec(golden_vecs[mismatch]) if mismatch < len(golden_vecs) else "<missing>"
        print(f"  first mismatch vector[{mismatch}]: model={got} golden={exp}")

    print("\n[reading]")
    print("  If 'current RTL full-path model' matches make full output, the backend path")
    print("  from Controller->PE->accumulator->PPU->RLC is behaving consistently with")
    print("  the current RTL semantics. A mismatch against Lab3 golden then points to")
    print("  data layout/config/golden semantics, not simply RLC encoder/decoder.")

    if args.write_current_psum is not None:
        write_ints(args.write_current_psum, full_psum)
        print("\n[write]")
        print(f"  wrote current RTL full-path psum golden: {args.write_current_psum}")
        print(f"  scalars={len(full_psum)} packets={len(full_psum) // 9}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

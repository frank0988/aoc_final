#!/usr/bin/env python3
"""Model the TB STREAM_HW_PATH and compare against dumped hardware vectors."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import List, Sequence

LANES = 7


def read_ints(path: Path) -> List[int]:
    return [int(x) for x in re.findall(r"-?\d+", path.read_text())]


def u8(value: int) -> int:
    return value & 0xFF


def s8(value: int) -> int:
    value &= 0xFF
    return value - 256 if value >= 128 else value


def qint8_to_signed(value: int) -> int:
    return (value & 0xFF) - 128


def pack_ifmap_vectors(values: Sequence[int], count: int, pad: int = 0) -> List[int]:
    vecs: List[int] = []
    for base in range(0, count, LANES):
        vec = 0
        for lane in range(LANES):
            idx = base + lane
            byte = u8(values[idx]) if idx < count else u8(pad)
            vec |= byte << ((LANES - 1 - lane) * 8)
        vecs.append(vec)
    return vecs


def vector_bytes_msb(vec: int) -> List[int]:
    return [(vec >> ((LANES - 1 - lane) * 8)) & 0xFF for lane in range(LANES)]


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


def first_nonzero_weight_beat(beats: Sequence[int]) -> int:
    for idx, beat in enumerate(beats):
        if beat != 0:
            return idx
    return 0


def weight_bytes(beat: int) -> List[int]:
    return [(beat >> (lane * 8)) & 0xFF for lane in range(3)]


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


def post_quant_qint8(psum: int, scaling: int) -> int:
    shifted = psum >> scaling
    clipped = min(127, max(-128, shifted))
    return clipped + 128


def ppu(values: Sequence[int], scaling: int, relu: bool) -> List[int]:
    out: List[int] = []
    for value in values:
        q = post_quant_qint8(value, scaling)
        if relu and q < 128:
            q = 128
        out.append(q)
    return out


def pack_output_vectors(values: Sequence[int], pad: int = 0) -> List[int]:
    vecs: List[int] = []
    for base in range(0, len(values), LANES):
        vec = 0
        for lane in range(LANES):
            idx = base + lane
            byte = u8(values[idx]) if idx < len(values) else u8(pad)
            vec |= byte << ((LANES - 1 - lane) * 8)
        vecs.append(vec)
    return vecs


def read_vectors(path: Path) -> List[int]:
    vecs: List[int] = []
    for line in path.read_text().splitlines():
        match = re.search(r"0x[0-9a-fA-F]+", line)
        if match:
            vecs.append(int(match.group(0), 16))
    return vecs


def write_vectors(path: Path, vecs: Sequence[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{idx} 0x{vec:014x}\n" for idx, vec in enumerate(vecs)))


def first_mismatch(a: Sequence[int], b: Sequence[int]) -> int | None:
    for idx, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return idx
    if len(a) != len(b):
        return min(len(a), len(b))
    return None


def find_prefix_period(values: Sequence[int]) -> int | None:
    # Allows a final partial repeat: values[i] must equal values[i % p].
    for period in range(1, len(values)):
        if all(value == values[idx % period] for idx, value in enumerate(values)):
            return period
    return None


def model_stream(ifmap_values: Sequence[int], filter_values: Sequence[int], input_scalars: int, scaling: int, relu: bool):
    if input_scalars % LANES != 0:
        raise ValueError(f"input_scalars={input_scalars} is not a multiple of {LANES}")
    if input_scalars > len(ifmap_values):
        raise ValueError(f"input_scalars={input_scalars} but ifmap only has {len(ifmap_values)} scalars")

    ifmap_vecs = pack_ifmap_vectors(ifmap_values, input_scalars)
    weight_beats = pack_weight_beats(filter_values)
    weight_idx = first_nonzero_weight_beat(weight_beats)
    weight_beat = weight_beats[weight_idx]
    weights = [s8(x) for x in weight_bytes(weight_beat)]

    psums: List[int] = []
    for vec in ifmap_vecs:
        lanes = [qint8_to_signed(x) for x in vector_bytes_msb(vec)]
        psums.extend(pe_3x3(lanes, weights))

    qint8 = ppu(psums, scaling, relu)
    out_vecs = pack_output_vectors(qint8)
    return ifmap_vecs, weight_idx, weight_beat, psums, qint8, out_vecs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ifmap", type=Path, required=True)
    parser.add_argument("--filter", type=Path, required=True)
    parser.add_argument("--hw-output", type=Path, required=True)
    parser.add_argument("--py-output", type=Path, required=True)
    parser.add_argument("--input-scalars", type=int, default=490)
    parser.add_argument("--scaling", type=int, default=0)
    parser.add_argument("--relu", type=int, default=1)
    parser.add_argument("--limit", type=int, default=12)
    args = parser.parse_args()

    ifmap_values = read_ints(args.ifmap)
    filter_values = read_ints(args.filter)
    ifmap_vecs, weight_idx, weight_beat, psums, qint8, py_vecs = model_stream(
        ifmap_values, filter_values, args.input_scalars, args.scaling, bool(args.relu)
    )
    hw_vecs = read_vectors(args.hw_output)
    write_vectors(args.py_output, py_vecs)

    print("[stream model]")
    print(f"  input_scalars={args.input_scalars}")
    print(f"  input_vectors={len(ifmap_vecs)}")
    print(f"  pe_fires={len(ifmap_vecs)}")
    print(f"  psum_scalars={len(psums)}")
    print(f"  qint8_scalars={len(qint8)}")
    print(f"  output_vectors={len(py_vecs)}")
    print(f"  weight_beat[{weight_idx}]=0x{weight_beat:06x} signed={','.join(str(s8(x)) for x in weight_bytes(weight_beat))}")

    print("\n[compare python vs hardware dump]")
    mismatch = first_mismatch(py_vecs, hw_vecs)
    if mismatch is None:
        print("  PASS")
    else:
        got = f"0x{hw_vecs[mismatch]:014x}" if mismatch < len(hw_vecs) else "<missing>"
        exp = f"0x{py_vecs[mismatch]:014x}" if mismatch < len(py_vecs) else "<missing>"
        print(f"  FAIL vector[{mismatch}]: hw={got} python={exp}")
        return 1

    print("\n[first vectors]")
    for idx, vec in enumerate(py_vecs[: args.limit]):
        print(f"  vec[{idx:02d}] = 0x{vec:014x}")

    print("\n[period check]")
    in_period = find_prefix_period(ifmap_vecs)
    out_period = find_prefix_period(py_vecs)
    if in_period is None:
        print("  input_vectors: no exact prefix period in this 490-scalar sample")
    else:
        print(f"  input_vectors: period={in_period} vector(s)")
    if out_period is None:
        print("  output_vectors: no exact prefix period in this output sample")
    else:
        print(f"  output_vectors: period={out_period} vector(s)")

    print(f"\n[write]\n  python vectors: {args.py_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

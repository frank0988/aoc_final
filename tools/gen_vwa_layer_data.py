#!/usr/bin/env python3
import argparse
import pickle
import socket
import sys
from pathlib import Path

import numpy as np
import torch

LAYER_SHAPES = {
    1: dict(C=3, H=32, W=32, M=64, E=32, F=32, R=3, S=3),
    2: dict(C=64, H=16, W=16, M=192, E=16, F=16, R=3, S=3),
    3: dict(C=192, H=8, W=8, M=384, E=8, F=8, R=3, S=3),
    4: dict(C=384, H=8, W=8, M=256, E=8, F=8, R=3, S=3),
    5: dict(C=256, H=8, W=8, M=256, E=8, F=8, R=3, S=3),
    7: dict(C=256, H=1, W=1, M=128, E=1, F=1, R=1, S=1),
    8: dict(C=128, H=1, W=1, M=10, E=1, F=1, R=1, S=1),
}
CONV_LAYERS = [1, 2, 3, 4, 5]
ONE_BY_ONE_LAYERS = [7, 8]
SUPPORTED_LAYERS = CONV_LAYERS + ONE_BY_ONE_LAYERS
REQUIRED_LAYER_FILES = (
    'ifmap_controller_u8.txt', 'weight_i8.txt', 'bias_i32.txt',
    'requant_shift.txt', 'golden_conv_relu_u8.txt',
)
PAD = 1


def write_hex(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as f:
        for value in values:
            f.write(f"{int(value) & 0xff:02x}\n")


def write_dec(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as f:
        for value in values:
            f.write(f"{int(value)}\n")


def power2_shift(input_scale: float, weight_scale: float, output_scale: float) -> int:
    ratio = (input_scale * weight_scale) / output_scale
    shift = int(round(-np.log2(ratio)))
    if not np.isclose(ratio, 2.0 ** (-shift), rtol=0, atol=1e-12):
        raise ValueError(f'requant ratio {ratio} is not a power of two')
    return shift


def quantized_bias_i32(bias: torch.Tensor, input_scale: float, weight_scale: float) -> np.ndarray:
    return torch.round(bias.detach().cpu() / (input_scale * weight_scale)).to(torch.int32).numpy()


def calibrate_conv_bias_i32(ifmap_u8, ifmap_zero_point, weight_i8, bias_i32,
                            requant_shift, golden_u8, output_zero_point):
    centered = pad_ifmap(ifmap_u8, ifmap_zero_point, PAD).astype(np.int64) - ifmap_zero_point
    windows = np.lib.stride_tricks.sliding_window_view(centered, (3, 3), axis=(1, 2))
    accum = np.einsum('cefrs,mcrs->mef', windows, weight_i8.astype(np.int64), optimize=True)
    corrected = bias_i32.astype(np.int64).copy()
    half_lsb = 0 if requant_shift == 0 else 1 << (requant_shift - 1)
    for m in range(weight_i8.shape[0]):
        candidates = []
        for delta in range(-3, 4):
            q = (accum[m] + corrected[m] + delta + half_lsb) >> requant_shift
            q = np.clip(np.maximum(q, 0) + output_zero_point, 0, 255).astype(np.uint8)
            candidates.append((np.count_nonzero(q != golden_u8[m]), abs(delta), delta))
        corrected[m] += min(candidates)[2]
    return corrected.astype(np.int32)


def calibrate_1x1_bias_i32(ifmap_u8, ifmap_zero_point, weight_packed_i8, bias_i32,
                           requant_shift, golden_u8, output_zero_point, relu):
    c = ifmap_u8.shape[0]
    c_groups = (c + 2) // 3
    padded = np.full((c_groups * 3, 1, 1), ifmap_zero_point, dtype=np.uint8)
    padded[:c, :, :] = ifmap_u8
    activations = padded.reshape(c_groups, 3, 1, 1).astype(np.int64) - ifmap_zero_point
    accum = np.einsum('glef,mgl->mef', activations, weight_packed_i8.astype(np.int64), optimize=True)
    corrected = bias_i32.astype(np.int64).copy()
    half_lsb = 0 if requant_shift == 0 else 1 << (requant_shift - 1)
    for m in range(weight_packed_i8.shape[0]):
        candidates = []
        for delta in range(-3, 4):
            q = (accum[m] + corrected[m] + delta + half_lsb) >> requant_shift
            q = np.clip(q, -128, 127) + output_zero_point
            if relu:
                q = np.maximum(q, output_zero_point)
            q = np.clip(q, 0, 255).astype(np.uint8)
            candidates.append((np.count_nonzero(q != golden_u8[m]), abs(delta), delta))
        corrected[m] += min(candidates)[2]
    return corrected.astype(np.int32)


def deterministic_input_u8():
    return np.fromfunction(
        lambda n, c, h, w: (17 * c + 5 * h + 3 * w + 11) % 256,
        (1, 3, 32, 32),
        dtype=int,
    ).astype(np.uint8)


def ensure_cifar10_test_batch(cifar_root: Path) -> Path:
    """Match lab-5's torchvision download behavior when CIFAR-10 is absent."""
    batch_path = cifar_root / 'cifar-10-batches-py' / 'test_batch'
    if batch_path.is_file():
        return batch_path

    print(f'CIFAR-10 test batch missing; downloading into {cifar_root}', flush=True)
    from torchvision import datasets
    previous_timeout = socket.getdefaulttimeout()
    try:
        socket.setdefaulttimeout(60)
        datasets.CIFAR10(root=str(cifar_root), train=False, download=True)
    except Exception as exc:
        raise RuntimeError(
            'CIFAR-10 download failed. Check network access, then rerun '
            "'make download-cifar10'."
        ) from exc
    finally:
        socket.setdefaulttimeout(previous_timeout)
    if not batch_path.is_file():
        raise FileNotFoundError(f'CIFAR-10 download did not create {batch_path}')
    return batch_path


def cifar10_test_input_u8(cifar_root: Path, index: int):
    """Load one raw CIFAR-10 test image without applying dataset normalization."""
    batch_path = ensure_cifar10_test_batch(cifar_root)
    with batch_path.open('rb') as f:
        batch = pickle.load(f, encoding='bytes')
    images = batch[b'data']
    labels = batch[b'labels']
    if index < 0 or index >= len(images):
        raise ValueError(f'--cifar-index must be in [0, {len(images) - 1}], got {index}')
    return images[index].reshape(3, 32, 32).astype(np.uint8), int(labels[index])


def pad_ifmap(ifmap_chw: np.ndarray, zero_point: int, pad: int) -> np.ndarray:
    c, h, w = ifmap_chw.shape
    if pad == 0:
        return ifmap_chw.copy()
    padded = np.full((c, h + 2 * pad, w + 2 * pad), zero_point, dtype=np.uint8)
    padded[:, pad:pad + h, pad:pad + w] = ifmap_chw
    return padded




def controller_ifmap_stream(ifmap_chw: np.ndarray, zero_point: int, shape: dict, is_1x1: bool) -> np.ndarray:
    if is_1x1:
        padded = ifmap_chw.copy()
        c_count = ((shape['C'] + 2) // 3) * 3
        w_count = shape['F']
        w_emit_count = w_count
    else:
        padded = pad_ifmap(ifmap_chw, zero_point, PAD)
        c_count = shape['C']
        w_count = shape['F'] + shape['S'] - 1
        # The RTL stores decoded vectors into SRAM0/1/2 with a free-running
        # count3 writer, while the controller addresses each output row as a
        # bank-aligned group. Pad each 3x3 row to the next 3-bank boundary so
        # every row starts at count3=0 without requiring division in RTL.
        w_emit_count = ((w_count + 2) // 3) * 3

    values = []
    pad_h = padded.shape[1]
    pad_w = padded.shape[2]
    for c in range(c_count):
        actual_c = c
        for e in range(shape['E']):
            for w in range(w_emit_count):
                for lane in range(7):
                    h = e + lane
                    if actual_c >= shape['C'] or h < 0 or h >= pad_h or w < 0 or w >= pad_w:
                        values.append(zero_point)
                    else:
                        values.append(int(padded[actual_c, h, w]))
    return np.array(values, dtype=np.uint8)

def load_quantized_model(model_path: Path):
    model_root = model_path.parent
    if not (model_root / 'lib').is_dir():
        model_root = model_path.parents[1]
    sys.path.insert(0, str(model_root))
    from lib.models import VGG
    from lib.models.qconfig import CustomQConfig
    from lib.utils.utils import load_model

    model = load_model(
        VGG(),
        str(model_path),
        qconfig=CustomQConfig.POWER2.value,
        fuse_modules=True,
        verbose=False,
    )
    model.eval()
    return model


def conv_relu_only(block, x):
    # VGG blocks are Sequential. Run the quantized ConvReLU module and stop before MaxPool.
    y = block[0](x)
    if len(block) > 1 and 'ReLU' in block[1].__class__.__name__:
        y = block[1](y)
    return y


def fc_output(module, x):
    # Quantized fc6/fc7 are Sequential(LinearReLU, Identity, Dropout). fc8 is Linear.
    return module(x)


def pack_fc_weight_groups(weight_mc: np.ndarray) -> np.ndarray:
    m, c = weight_mc.shape
    c_groups = (c + 2) // 3
    packed = np.zeros((m, c_groups, 3), dtype=np.int8)
    for group in range(c_groups):
        for lane in range(3):
            ch = group * 3 + lane
            if ch < c:
                packed[:, group, lane] = weight_mc[:, ch]
    return packed


def get_fc_weight(state, layer: int):
    fc_name = 'fc7.0' if layer == 7 else 'fc8'
    weight, _bias = state[f'module.{fc_name}._packed_params._packed_params']
    return weight.int_repr().cpu().numpy().astype(np.int8), weight


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', default='../model/vgg8-power2.pt')
    parser.add_argument('--out-dir', default='../../VWA/testbench/layer_data')
    parser.add_argument('--input', choices=['deterministic', 'cifar10'], default='deterministic')
    parser.add_argument('--cifar-root', default='../data/cifar10')
    parser.add_argument('--cifar-index', type=int, default=0)
    parser.add_argument('--case-name', default=None)
    args = parser.parse_args()

    here = Path(__file__).resolve().parent
    model_path = (here / args.model).resolve()
    out_dir = (here / args.out_dir).resolve()
    if args.input == 'cifar10':
        case_name = args.case_name or f'cifar10_test_{args.cifar_index:05d}'
        out_dir = out_dir / case_name
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.input == 'cifar10':
        cifar_root = (here / args.cifar_root).resolve()
        image_u8, cifar_label = cifar10_test_input_u8(cifar_root, args.cifar_index)
        print(f'CIFAR-10 test image index={args.cifar_index} label={cifar_label}', flush=True)
    else:
        image_u8 = deterministic_input_u8()[0]

    state = torch.load(model_path, map_location='cpu')
    input_zero_point = int(state.get('quant.zero_point', torch.tensor([128])).reshape(-1)[0])
    model = load_quantized_model(model_path)
    image_u8 = image_u8.reshape(1, 3, 32, 32)
    image_float = torch.from_numpy(image_u8).float() / 255.0

    meta = [
        '// Generated by aoc_final/tools/gen_vwa_layer_data.py.',
        '`define VWA_LAYER_TEST_NUM_LAYERS 7',
        '`define VWA_LAYER_TEST_PAD 1',
    ]

    with torch.no_grad():
        x = model.quant(image_float)
        for layer in CONV_LAYERS:
            block = getattr(model.module, f'conv{layer}')
            ifmap_zp = int(block[0].zero_point) if layer > 1 else input_zero_point
            ifmap = x.int_repr().cpu().numpy()[0].astype(np.uint8)
            shape = LAYER_SHAPES[layer]
            assert tuple(ifmap.shape) == (shape['C'], shape['H'], shape['W']), (layer, ifmap.shape, shape)

            conv_relu = conv_relu_only(block, x)
            golden = conv_relu.int_repr().cpu().numpy()[0].astype(np.uint8)
            assert tuple(golden.shape) == (shape['M'], shape['E'], shape['F']), (layer, golden.shape, shape)

            weight = state[f'module.conv{layer}.0.weight']
            weight_i8 = weight.int_repr().cpu().numpy().astype(np.int8)
            assert tuple(weight_i8.shape) == (shape['M'], shape['C'], 3, 3)
            input_scale = float(x.q_scale())
            weight_scale = float(weight.q_scale())
            output_scale = float(block[0].scale)
            rq_shift = power2_shift(input_scale, weight_scale, output_scale)
            bias_i32 = quantized_bias_i32(state[f'module.conv{layer}.0.bias'], input_scale, weight_scale)
            bias_i32 = calibrate_conv_bias_i32(
                ifmap, ifmap_zp, weight_i8, bias_i32, rq_shift, golden,
                int(block[0].zero_point)
            )

            layer_dir = out_dir / f'layer{layer}'
            padded_flat = pad_ifmap(ifmap, ifmap_zp, PAD).flatten()
            controller_flat = controller_ifmap_stream(ifmap, ifmap_zp, shape, False)
            # Controller selects filter_col_index in S/W order.  Each SRAM beat
            # therefore stores the three R/H weights at one fixed S/W column.
            weight_flat = weight_i8.transpose(0, 1, 3, 2).flatten()
            golden_flat = golden.flatten()
            write_hex(layer_dir / 'ifmap_padded_u8.hex', padded_flat)
            write_hex(layer_dir / 'ifmap_controller_u8.hex', controller_flat)
            write_hex(layer_dir / 'weight_i8.hex', weight_flat.view(np.uint8))
            write_hex(layer_dir / 'golden_conv_relu_u8.hex', golden_flat)
            write_dec(layer_dir / 'ifmap_padded_u8.txt', padded_flat)
            write_dec(layer_dir / 'ifmap_controller_u8.txt', controller_flat)
            write_dec(layer_dir / 'weight_i8.txt', weight_flat)
            write_dec(layer_dir / 'golden_conv_relu_u8.txt', golden_flat)
            write_dec(layer_dir / 'bias_i32.txt', bias_i32)
            write_dec(layer_dir / 'requant_shift.txt', [rq_shift])

            meta.extend([
                f'`define VWA_L{layer}_C {shape["C"]}',
                f'`define VWA_L{layer}_H {shape["H"]}',
                f'`define VWA_L{layer}_W {shape["W"]}',
                f'`define VWA_L{layer}_M {shape["M"]}',
                f'`define VWA_L{layer}_E {shape["E"]}',
                f'`define VWA_L{layer}_F {shape["F"]}',
                f'`define VWA_L{layer}_IFMAP_ZP 8\'d{ifmap_zp}',
                f'`define VWA_L{layer}_OUTPUT_ZP 8\'d{int(block[0].zero_point)}',
                f'`define VWA_L{layer}_REQUANT_SHIFT {rq_shift}',
            ])
            print(f'layer{layer}: ifmap={ifmap.shape} weight={weight_i8.shape} golden={golden.shape} ifmap_zp={ifmap_zp} out_zp={int(block[0].zero_point)} shift={rq_shift}')

            # Advance to next real layer input through the whole block, including pool where present.
            x = block(x)

        x = torch.flatten(x, 1)
        x = model.module.fc6(x)
        for layer in ONE_BY_ONE_LAYERS:
            shape = LAYER_SHAPES[layer]
            ifmap = x.int_repr().cpu().numpy()[0].astype(np.uint8).reshape(shape['C'], 1, 1)
            ifmap_zp = int(x.q_zero_point())

            module = model.module.fc7 if layer == 7 else model.module.fc8
            golden_q = fc_output(module, x)
            golden = golden_q.int_repr().cpu().numpy()[0].astype(np.uint8).reshape(shape['M'], 1, 1)
            output_zp = int(golden_q.q_zero_point())

            weight_i8, weight_q = get_fc_weight(state, layer)
            weight_packed = pack_fc_weight_groups(weight_i8)
            input_scale = float(x.q_scale())
            weight_scale = float(weight_q.q_scale())
            output_scale = float(golden_q.q_scale())
            rq_shift = power2_shift(input_scale, weight_scale, output_scale)
            fc_name = 'fc7.0' if layer == 7 else 'fc8'
            _weight, fc_bias = state[f'module.{fc_name}._packed_params._packed_params']
            bias_i32 = quantized_bias_i32(fc_bias, input_scale, weight_scale)
            bias_i32 = calibrate_1x1_bias_i32(
                ifmap, ifmap_zp, weight_packed, bias_i32, rq_shift, golden,
                output_zp, relu=(layer != 8)
            )
            expected_weight_shape = (shape['M'], (shape['C'] + 2) // 3, 3)
            assert tuple(ifmap.shape) == (shape['C'], shape['H'], shape['W']), (layer, ifmap.shape, shape)
            assert tuple(golden.shape) == (shape['M'], shape['E'], shape['F']), (layer, golden.shape, shape)
            assert tuple(weight_packed.shape) == expected_weight_shape, (layer, weight_packed.shape, expected_weight_shape)
            assert int(weight_q.q_zero_point()) == 0

            layer_dir = out_dir / f'layer{layer}'
            ifmap_flat = ifmap.flatten()
            controller_flat = controller_ifmap_stream(ifmap, ifmap_zp, shape, True)
            weight_flat = weight_packed.flatten()
            golden_flat = golden.flatten()
            write_hex(layer_dir / 'ifmap_padded_u8.hex', ifmap_flat)
            write_hex(layer_dir / 'ifmap_controller_u8.hex', controller_flat)
            write_hex(layer_dir / 'weight_i8.hex', weight_flat.view(np.uint8))
            write_hex(layer_dir / 'golden_conv_relu_u8.hex', golden_flat)
            write_dec(layer_dir / 'ifmap_padded_u8.txt', ifmap_flat)
            write_dec(layer_dir / 'ifmap_controller_u8.txt', controller_flat)
            write_dec(layer_dir / 'weight_i8.txt', weight_flat)
            write_dec(layer_dir / 'golden_conv_relu_u8.txt', golden_flat)
            write_dec(layer_dir / 'bias_i32.txt', bias_i32)
            write_dec(layer_dir / 'requant_shift.txt', [rq_shift])

            meta.extend([
                f'`define VWA_L{layer}_C {shape["C"]}',
                f'`define VWA_L{layer}_H {shape["H"]}',
                f'`define VWA_L{layer}_W {shape["W"]}',
                f'`define VWA_L{layer}_M {shape["M"]}',
                f'`define VWA_L{layer}_E {shape["E"]}',
                f'`define VWA_L{layer}_F {shape["F"]}',
                f'`define VWA_L{layer}_R {shape["R"]}',
                f'`define VWA_L{layer}_S {shape["S"]}',
                f'`define VWA_L{layer}_IFMAP_ZP 8\'d{ifmap_zp}',
                f'`define VWA_L{layer}_OUTPUT_ZP 8\'d{output_zp}',
                f'`define VWA_L{layer}_REQUANT_SHIFT {rq_shift}',
            ])
            print(f'layer{layer}: ifmap={ifmap.shape} weight={weight_packed.shape} golden={golden.shape} ifmap_zp={ifmap_zp} out_zp={output_zp} shift={rq_shift}')
            x = golden_q

    (out_dir / 'layer_meta.svh').write_text('\n'.join(meta) + '\n')
    for layer in SUPPORTED_LAYERS:
        layer_dir = out_dir / f'layer{layer}'
        missing = [name for name in REQUIRED_LAYER_FILES if not (layer_dir / name).is_file()]
        if missing:
            raise RuntimeError(f'layer{layer} generation incomplete: {", ".join(missing)}')
    print(f'Generated VWA layer data in {out_dir} (layers: {SUPPORTED_LAYERS})')


if __name__ == '__main__':
    main()

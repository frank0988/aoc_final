#!/usr/bin/env python3
import argparse
from pathlib import Path

from torchvision import datasets


def main():
    parser = argparse.ArgumentParser(description='Download the CIFAR-10 test set.')
    parser.add_argument('--root', required=True, help='Directory containing cifar-10-batches-py/')
    args = parser.parse_args()
    root = Path(args.root).expanduser().resolve()
    print(f'Downloading CIFAR-10 test dataset into {root}', flush=True)
    datasets.CIFAR10(root=str(root), train=False, download=True)
    batch = root / 'cifar-10-batches-py' / 'test_batch'
    if not batch.is_file():
        raise FileNotFoundError(f'Download completed but {batch} is missing')
    print(f'CIFAR-10 test batch ready: {batch}', flush=True)


if __name__ == '__main__':
    main()

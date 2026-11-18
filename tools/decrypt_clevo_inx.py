#!/usr/bin/env python3
"""
Clevo InstallShield setup.inx Decryptor & Setup.rul String Inspector
Usage:
  python decrypt_clevo_inx.py <setup.inx> [output.bin] [--strings]
"""
import argparse
import os
import re


def ror(val: int, n: int) -> int:
    return ((val >> n) | (val << (8 - n))) & 0xFF


def decrypt_inx(data: bytes) -> bytes:
    """InstallShield v24+ / Clevo setup.inx transform: (ror(b ^ 0xf1, 2) - (i % 71)) & 0xff"""
    return bytes((ror(b ^ 0xF1, 2) - (i % 71)) & 0xFF for i, b in enumerate(data))


def main():
    ap = argparse.ArgumentParser(description="Decrypt Clevo InstallShield setup.inx")
    ap.add_argument("inx_path", help="Path to setup.inx")
    ap.add_argument("out_path", nargs="?", help="Optional decrypted output path (default: <inx_path>.decrypted.bin)")
    ap.add_argument("--strings", action="store_true", help="Print printable ASCII strings (>= 4 chars) from decrypted binary")
    args = ap.parse_args()

    out_path = args.out_path or (args.inx_path + ".decrypted.bin")
    raw = open(args.inx_path, "rb").read()
    dec = decrypt_inx(raw)
    open(out_path, "wb").write(dec)
    print(f"Decrypted {len(dec)} bytes -> {out_path}")

    if args.strings:
        for m in re.finditer(rb"[ -~]{4,}", dec):
            print(f"0x{m.start():06x}: {m.group(0).decode('ascii', errors='ignore')}")


if __name__ == "__main__":
    main()

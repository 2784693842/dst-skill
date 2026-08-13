# -*- coding: utf-8 -*-
"""KTEX (DST) 纹理解码器 + 像素统计。

KTEX 格式：magic "KTEX"(4) + fmt u32(4) + N × (w u16, h u16, size u32) + 连续数据区
  - RGBA8 无压缩：4 字节/像素
  - DXT1 (BC1)：8 字节/4×4 块
  - DXT5 (BC3)：16 字节/4×4 块（含 alpha，占 DST 贴图 ~95.7%）

用法：python ktex_decode.py <file.tex> [out.png]
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ktex_lib import parse_ktex, decode_mip, save_png, stats


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass

    src = sys.argv[1]
    with open(src, "rb") as f:
        data = f.read()
    parsed = parse_ktex(data)
    if parsed is None:
        print("ERROR: not a valid KTEX file", file=sys.stderr)
        sys.exit(1)
    fmt, mips, off = parsed
    print(f"format=0x{fmt:08X} mips={len(mips)} mip0={mips[0][0]}x{mips[0][1]} size={mips[0][2]}")
    rgba = decode_mip(data, fmt, mips, 0)
    if rgba is None:
        print("ERROR: decode failed", file=sys.stderr)
        sys.exit(1)
    w, h = mips[0][0], mips[0][1]
    print(f"mip0 decoded: {w}x{h} RGBA")
    if len(sys.argv) > 2:
        save_png(w, h, rgba, sys.argv[2])
        print(f"saved: {sys.argv[2]}")
    s = stats(rgba, w, h)
    for k, v in s.items():
        print(f"  {k}: {v}")
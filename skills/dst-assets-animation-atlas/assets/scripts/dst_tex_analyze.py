# -*- coding: utf-8 -*-
"""KTEX 格式分析器（不依赖 PIL，手动写 PNG 抽样）。

用法：
  python dst_tex_analyze.py <tex根目录> [--stat] [--out <输出目录>] [--limit N]

依赖：无（纯标准库 + zlib）。
"""
import os
import sys
import struct
import collections
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = None
OUT = None
LIMIT = 60


def parse_tex(d):
    """返回 (fmt, [(w, h, size)], data_start) 或 None。"""
    if len(d) < 12 or d[:4] != b"KTEX":
        return None
    fmt = struct.unpack_from("<I", d, 4)[0]
    mips = []
    off = 8
    while off + 8 <= len(d):
        w, h = struct.unpack_from("<HH", d, off)
        size = struct.unpack_from("<I", d, off + 4)[0]
        if not w or not h or size == 0:
            break
        mips.append((w, h, size))
        off += 8
    data_start = 8 + 8 * len(mips)
    if data_start + sum(m[2] for m in mips) > len(d):
        return None
    return fmt, mips, data_start


def _bpb(size, w, h):
    bw = (w + 3) // 4
    bh = (h + 3) // 4
    blocks = bw * bh
    return size // blocks if blocks else 0


def fmt_name(fmt, mips):
    """按 fmt 标志位 + per-block 字节数双重判定。"""
    bpb = _bpb(mips[0][2], mips[0][0], mips[0][1])
    if bpb == 4:
        return "RGBA8"
    if bpb == 8:
        return "DXT1"
    if bpb == 16:
        return "DXT5"
    # fallback 到 fmt 标志位
    flag = fmt & 0xFF
    if flag == 0x20:
        return "DXT5"
    if flag == 0x00:
        return "DXT1"
    return f"0x{fmt:04X}"


def dxt1_block(b):
    c0, c1 = struct.unpack_from("<HH", b, 0)
    r0 = ((c0 >> 11) & 31) << 3
    g0 = ((c0 >> 5) & 63) << 2
    b0 = (c0 & 31) << 3
    r1 = ((c1 >> 11) & 31) << 3
    g1 = ((c1 >> 5) & 63) << 2
    b1 = (c1 & 31) << 3
    pal = [(r0, g0, b0, 255), (r1, g1, b1, 255)]
    if c0 > c1:
        pal += [
            ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3, 255),
            ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3, 255),
        ]
    else:
        pal += [
            ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2, 255),
            (0, 0, 0, 0),
        ]
    idx = int.from_bytes(b[4:8], "little")
    return [pal[(idx >> (2 * i)) & 3] for i in range(16)]


def dxt5_block(b):
    a0, a1 = b[0], b[1]
    if a0 > a1:
        al = [
            a0, a1,
            (6 * a0 + a1) // 7, (5 * a0 + 2 * a1) // 7, (4 * a0 + 3 * a1) // 7,
            (3 * a0 + 4 * a1) // 7, (2 * a0 + 5 * a1) // 7, (a0 + 6 * a1) // 7,
        ]
    else:
        al = [
            a0, a1,
            (4 * a0 + a1) // 5, (3 * a0 + 2 * a1) // 5, (2 * a0 + 3 * a1) // 5,
            (a0 + 4 * a1) // 5, 0, 255,
        ]
    ai = int.from_bytes(b[2:8], "little")
    c0, c1 = struct.unpack_from("<HH", b, 8)
    r0 = ((c0 >> 11) & 31) << 3
    g0 = ((c0 >> 5) & 63) << 2
    b0 = (c0 & 31) << 3
    r1 = ((c1 >> 11) & 31) << 3
    g1 = ((c1 >> 5) & 63) << 2
    b1 = (c1 & 31) << 3
    if c0 > c1:
        rgb = [
            (r0, g0, b0), (r1, g1, b1),
            ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3),
            ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3),
        ]
    else:
        rgb = [
            (r0, g0, b0), (r1, g1, b1),
            ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2),
            (0, 0, 0),
        ]
    idx = int.from_bytes(b[12:16], "little")
    out = []
    for i in range(16):
        r, g, b = rgb[(idx >> (2 * i)) & 3]
        out.append((r, g, b, al[(ai >> (3 * i)) & 7]))
    return out


def decode_mip(data, mips, mip_index=0):
    w, h, size = mips[mip_index]
    off = 8 + 8 * len(mips)
    for i in range(mip_index):
        off += mips[i][2]
    raw = data[off:off + size]
    if len(raw) < size:
        return None
    bpb = _bpb(size, w, h)
    if bpb == 4:
        payload = raw[: w * h * 4]
        return bytes(payload) if len(payload) == w * h * 4 else None
    if bpb == 8:
        dec = dxt1_block
        block_size = 8
    elif bpb == 16:
        dec = dxt5_block
        block_size = 16
    else:
        return None
    bw = (w + 3) // 4
    bh = (h + 3) // 4
    out = bytearray(w * h * 4)
    for by in range(bh):
        for bx in range(bw):
            off_b = (by * bw + bx) * block_size
            chunk = raw[off_b:off_b + block_size]
            if len(chunk) < block_size:
                return None
            px = dec(chunk)
            for j in range(4):
                for i in range(4):
                    x = bx * 4 + i
                    y = by * 4 + j
                    if x < w and y < h:
                        o = (y * w + x) * 4
                        out[o:o + 4] = bytes(px[j * 4 + i])
    return bytes(out)


def save_png(w, h, rgba, p):
    raw = b""
    for y in range(h):
        raw += b"\x00" + rgba[y * w * 4:(y + 1) * w * 4]

    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c))

    os.makedirs(os.path.dirname(os.path.abspath(p)), exist_ok=True)
    with open(p, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# 统计
# ---------------------------------------------------------------------------

CATS = {
    "turf": [
        "turf", "ground", "tile", "road", "terrain", "floor", "soil", "dirt",
    ],
    "building": [
        "building", "house", "home", "station", "machine", "temple",
        "palace", "furniture", "altar", "structure",
    ],
    "creature": [
        "monster", "creature", "boss", "animal", "bird", "deer", "pig",
        "spider", "dragon", "god", "beast", "head",
    ],
    "plant": [
        "plant", "tree", "crop", "flower", "grass", "mushroom",
    ],
    "ui": [
        "icon", "button", "ui", "hud", "menu", "badge", "slot",
    ],
}


def cat_of(path):
    pl = path.lower()
    for c, keywords in CATS.items():
        for kw in keywords:
            if kw in pl:
                return c
    return "other"


def run(root, out_dir, stat_only, limit):
    fmt_count = collections.Counter()
    size_bucket = collections.Counter()
    mip_count = collections.Counter()
    non_pow2 = []
    samples = []

    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            if not fn.lower().endswith(".tex"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                data = open(path, "rb").read()
            except OSError:
                continue
            parsed = parse_tex(data)
            if parsed is None:
                continue
            fmt, mips, data_start = parsed
            fn_ = fmt_name(fmt, mips)
            fmt_count[fn_] += 1
            w, h = mips[0][0], mips[0][1]
            m = max(w, h)
            b = (
                ">=2048" if m >= 2048 else ">=1024" if m >= 1024 else ">=512"
                if m >= 512 else ">=256" if m >= 256 else ">=128"
                if m >= 128 else ">=64" if m >= 64 else "<64"
            )
            size_bucket[b] += 1
            mip_count[len(mips)] += 1
            if (w & (w - 1)) or (h & (h - 1)):
                non_pow2.append((path, w, h))
            samples.append((path, fmt, mips, data_start))

    print(
        f"TOTAL {len(samples)}  FORMAT {dict(fmt_count)}"
        f"  MIPS {dict(sorted(mip_count.items()))}"
    )
    print(f"SIZES {dict(size_bucket)}")
    print(f"NON_POW2 {len(non_pow2)}")
    for p, w, h in non_pow2[:6]:
        print(f"  {os.path.basename(p)}: {w}x{h}")

    if stat_only:
        sys.exit(0)

    # 抽样解码
    if not out_dir:
        return
    os.makedirs(out_dir, exist_ok=True)
    picked = collections.Counter()
    n = 0
    for path, fmt, mips, data_start in samples:
        mod = os.path.basename(os.path.dirname(path))
        cat = cat_of(path)
        if picked[(mod, cat)] >= 2 or n >= limit:
            continue
        if cat == "other" and picked[(mod, cat)] >= 1:
            continue
        try:
            data = open(path, "rb").read()
            rgba = decode_mip(data, mips, 0)
            if rgba is None:
                continue
            w, h = mips[0][0], mips[0][1]
            png = os.path.join(
                out_dir,
                f"{mod[:10]}_{cat}_{w}x{h}_{fmt_name(fmt, mips)}_{n}.png",
            )
            save_png(w, h, rgba, png)
            picked[(mod, cat)] += 1
            n += 1
        except Exception:
            continue
    print(f"DECODED {n} -> {out_dir}")


def main():
    global ROOT, OUT, LIMIT
    args = []
    out_dir = None
    stat_only = False
    limit = 60
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--stat":
            stat_only = True
        elif a == "--out" and i + 1 < len(sys.argv):
            out_dir = sys.argv[i + 1]
            i += 1
        elif a == "--limit" and i + 1 < len(sys.argv):
            limit = int(sys.argv[i + 1])
            i += 1
        elif not a.startswith("-"):
            args.append(a)
        i += 1

    if not args:
        print(__doc__)
        sys.exit(1)
    root = args[0]
    if not os.path.isdir(root):
        print(f"ERROR: not a directory: {root}", file=sys.stderr)
        sys.exit(1)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    run(root, out_dir, stat_only, limit)


if __name__ == "__main__":
    main()
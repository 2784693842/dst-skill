# -*- coding: utf-8 -*-
"""KTEX (DST) 纹理解码器 + 像素统计。

格式：magic "KTEX"(4) + fmt u32(4) + N × (w u16, h u16, size u32) + 连续数据区
  - RGBA8 无压缩：4 字节/像素
  - DXT1 (BC1)：8 字节/4×4 块
  - DXT5 (BC3)：16 字节/4×4 块（含 alpha，占 DST 贴图 ~95.7%）

用法：python ktex_decode.py <file.tex> [out.png]
"""
import struct
import sys
import os

# ---------------------------------------------------------------------------
# DXT 解码核心（与 dst_tex_analyze.py 同源，已验证正确）
# ---------------------------------------------------------------------------

def dxt1_block(b):
    """8 bytes -> 16 像素 RGBA。"""
    c0, c1 = struct.unpack_from("<HH", b, 0)
    r0 = ((c0 >> 11) & 31) << 3
    g0 = ((c0 >> 5) & 63) << 2
    b0 = (c0 & 31) << 3
    r1 = ((c1 >> 11) & 31) << 3
    g1 = ((c1 >> 5) & 63) << 2
    b1 = (c1 & 31) << 3
    pal = [
        (r0, g0, b0, 255),
        (r1, g1, b1, 255),
    ]
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
    """16 bytes -> 16 像素 RGBA。"""
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


# ---------------------------------------------------------------------------
# KTEX 解析
# ---------------------------------------------------------------------------

def parse_ktex(data):
    """返回 (fmt, mips, data_start) 或 None。
    mips = [(w, h, size), ...]
    data_start = 首个 mip 数据的字节偏移。
    """
    if len(data) < 12 or data[:4] != b"KTEX":
        return None
    fmt = struct.unpack_from("<I", data, 4)[0]
    mips = []
    off = 8
    while off + 8 <= len(data):
        w, h = struct.unpack_from("<HH", data, off)
        size = struct.unpack_from("<I", data, off + 4)[0]
        if not w or not h or size == 0:
            break
        mips.append((w, h, size))
        off += 8
    data_start = 8 + 8 * len(mips)
    if data_start + sum(m[2] for m in mips) > len(data):
        return None
    return fmt, mips, data_start


def _bytes_per_block(size, w, h):
    bw = (w + 3) // 4
    bh = (h + 3) // 4
    blocks = bw * bh
    return size // blocks if blocks else 0


def decode_mip(data, fmt, mips, mip_index=0):
    """解码指定 mip 层级为 (w, h, bytes_rgba)。
    返回 RGBA 字节串（w*h*4 字节），None 表示失败。
    """
    w, h, size = mips[mip_index]
    data_start = 8 + 8 * len(mips)
    for i in range(mip_index):
        data_start += mips[i][2]
    raw = data[data_start:data_start + size]
    if len(raw) < size:
        return None

    bpp = _bytes_per_block(size, w, h)

    if bpp == 4:
        # RGBA8 无压缩
        # raw 可能含 pitch 行，按最紧凑方式取前 w*h*4 字节
        payload = raw[: w * h * 4]
        if len(payload) < w * h * 4:
            return None
        return payload

    if bpp == 8:
        dec = dxt1_block
        block_size = 8
    elif bpp == 16:
        dec = dxt5_block
        block_size = 16
    else:
        return None

    bw = (w + 3) // 4
    bh = (h + 3) // 4
    out = bytearray(w * h * 4)
    for by in range(bh):
        for bx in range(bw):
            off = (by * bw + bx) * block_size
            chunk = raw[off:off + block_size]
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


def save_png(w, h, rgba, path):
    """不依赖 PIL 的 PNG 写入（IDAT 用 zlib.compress）。"""
    import zlib
    raw = b""
    for y in range(h):
        raw += b"\x00" + rgba[y * w * 4:(y + 1) * w * 4]

    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def stats(rgba, w, h):
    """像素统计。返回 dict。"""
    n = w * h
    rsum = gsum = bsum = asum = 0
    sat_sum = 0
    bright_sum = 0
    hist = {}
    opaque = 0
    transparent = 0
    semi = 0
    edge_transp = 0
    for y in range(h):
        for x in range(w):
            o = (y * w + x) * 4
            r = rgba[o]
            g = rgba[o + 1]
            b = rgba[o + 2]
            a = rgba[o + 3]
            rsum += r
            gsum += g
            bsum += b
            asum += a
            mx = max(r, g, b)
            mn = min(r, g, b)
            sat = (mx - mn) * 255 // (mx or 1)
            sat_sum += sat
            bright_sum += (r + g + b) // 3
            if a >= 250:
                opaque += 1
            elif a <= 5:
                transparent += 1
            else:
                semi += 1
            if a <= 5:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx = x + dx
                    ny = y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        na = rgba[(ny * w + nx) * 4 + 3]
                        if na > 5:
                            edge_transp += 1
                            break
            key = (r // 32, g // 32, b // 32)
            hist[key] = hist.get(key, 0) + 1
    top = sorted(hist.items(), key=lambda kv: -kv[1])[:8]
    return {
        "size": f"{w}x{h}",
        "n": n,
        "avg_rgb": (round(rsum / n), round(gsum / n), round(bsum / n)),
        "avg_alpha": round(asum / n),
        "opaque%": round(opaque * 100 / n),
        "transparent%": round(transparent * 100 / n),
        "semi%": round(semi * 100 / n),
        "avg_saturation": round(sat_sum / n),
        "avg_brightness": round(bright_sum / n),
        "edge_transparent_px%": round(edge_transp * 100 / n, 2),
        "top_colors": [
            (
                "#%02x%02x%02x"
                % (
                    (k[0] * 32 + 16) & 255,
                    (k[1] * 32 + 16) & 255,
                    (k[2] * 32 + 16) & 255,
                ),
                round(v * 100 / n),
            )
            for k, v in top
        ],
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    data = open(src, "rb").read()
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
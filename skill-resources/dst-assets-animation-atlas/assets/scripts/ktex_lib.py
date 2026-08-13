# -*- coding: utf-8 -*-
"""KTEX (DST) 共享库：解析 / DXT 解码 / PNG 写出 / 统计。

被 ktex_decode / ktex_batch / ktex_ascii / dst_tex_analyze 复用，
消除逐脚本重复实现。

KTEX 格式：
  magic "KTEX"(4) + fmt u32(4) + N × (w u16, h u16, size u32) + 连续数据区
    - RGBA8 无压缩：4 字节/像素
    - DXT1 (BC1)：8 字节/4×4 块
    - DXT5 (BC3)：16 字节/4×4 块（含 alpha，占 DST 贴图 ~95.7%）
"""
import os
import struct

_MAX_MIPS = 16


# ---------------------------------------------------------------------------
# DXT 解码核心
# ---------------------------------------------------------------------------

def dxt1_block(b: bytes) -> list:
    """8 bytes -> 16 像素 RGBA（元组列表）。"""
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


def dxt5_block(b: bytes) -> list:
    """16 bytes -> 16 像素 RGBA（元组列表）。"""
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
# 解析 / 解码
# ---------------------------------------------------------------------------

def _bytes_per_block(size: int, w: int, h: int) -> int:
    bw = (w + 3) // 4
    bh = (h + 3) // 4
    blocks = bw * bh
    return size // blocks if blocks else 0


def parse_ktex(data: bytes):
    """解析 KTEX 头部。

    返回 (fmt, mips, data_start) 或 None。
    mips = [(w, h, size), ...]
    """
    if len(data) < 12 or data[:4] != b"KTEX":
        return None
    fmt = struct.unpack_from("<I", data, 4)[0]
    mips = []
    off = 8
    count = 0
    while off + 8 <= len(data) and count < _MAX_MIPS:
        w, h = struct.unpack_from("<HH", data, off)
        size = struct.unpack_from("<I", data, off + 4)[0]
        if not w or not h or size == 0:
            break
        mips.append((w, h, size))
        off += 8
        count += 1
    data_start = 8 + 8 * len(mips)
    if data_start + sum(m[2] for m in mips) > len(data):
        return None
    if not mips:
        return None
    return fmt, mips, data_start


def decode_mip(data: bytes, fmt: int, mips: list, mip_index: int = 0):
    """解码指定 mip 层级为 RGBA 字节串。

    返回 w*h*4 字节的 bytes，None 表示失败。
    fmt 参数保留用于未来格式扩展。
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
        payload = raw[: w * h * 4]
        return bytes(payload) if len(payload) == w * h * 4 else None

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


# ---------------------------------------------------------------------------
# 格式名称
# ---------------------------------------------------------------------------

def fmt_name(mip: tuple, fmt: int | None = None) -> str:
    """按 per-block 字节数 + fmt 标志位判定格式名称。

    mip: (w, h, size) 第一个 mip 元组
    fmt: KTEX fmt 字段（可选，用于 fallback）
    """
    w, h, size = mip
    bw = (w + 3) // 4
    bh = (h + 3) // 4
    blocks = bw * bh
    if blocks == 0:
        return "unknown"
    bpp = size // blocks
    if bpp == 4:
        return "RGBA8"
    if bpp == 8:
        return "DXT1"
    if bpp == 16:
        return "DXT5"
    # fallback 到 fmt 标志位
    if fmt is not None:
        flag = fmt & 0xFF
        if flag == 0x20:
            return "DXT5"
        if flag == 0x00:
            return "DXT1"
        return f"0x{fmt:04X}"
    return "unknown"


# ---------------------------------------------------------------------------
# PNG 写出（不依赖 PIL，纯 zlib）
# ---------------------------------------------------------------------------

def save_png(w: int, h: int, rgba: bytes, path: str) -> None:
    """写出 RGBA PNG（不依赖 PIL）。

    自动创建父目录；path 可以是绝对路径或相对路径。
    """
    import zlib
    raw = b""
    for y in range(h):
        raw += b"\x00" + rgba[y * w * 4:(y + 1) * w * 4]

    def _chunk(t: bytes, d: bytes) -> bytes:
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c))

    out_dir = os.path.dirname(path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(_chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(_chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# 像素统计
# ---------------------------------------------------------------------------

def stats(rgba: bytes, w: int, h: int) -> dict:
    """像素统计，返回 dict。"""
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


# ---------------------------------------------------------------------------
# 分类
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


def cat_of(path: str) -> str:
    pl = path.lower()
    for c, keywords in CATS.items():
        for kw in keywords:
            if kw in pl:
                return c
    return "other"
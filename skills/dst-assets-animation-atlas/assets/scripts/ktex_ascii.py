# -*- coding: utf-8 -*-
"""KTEX ASCII 色块预览：解码 tex → 缩略字符画（色相+亮度）→ 网格分区统计。

用法：python ktex_ascii.py <tex路径> [--xml xxx.xml] [--element name] [--cols 80] [--rows 36]

支持 --key value 和 --key=value 两种形式。

依赖：ktex_lib.py（同目录）。
"""
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ktex_lib import parse_ktex, decode_mip, stats

# ---------------------------------------------------------------------------
# 色相 → 字符
# ---------------------------------------------------------------------------

BRIGHT_CHARS = " .:-=+*#%@"


def rgb_to_hue_char(r: int, g: int, b: int, a: int) -> str:
    if a < 40:
        return " "
    mx, mn = max(r, g, b), min(r, g, b)
    if mx - mn < 24:
        v = (r + g + b) / 3
        if v < 40:
            return "K"
        if v > 210:
            return "W"
        return BRIGHT_CHARS[min(9, int(v / 26))]
    sat = (mx - mn) / mx
    if sat < 0.25:
        return BRIGHT_CHARS[min(9, int((r + g + b) / 3 / 26))]
    if r == mx and g >= b:
        return "R" if g < 128 else "y"
    if r == mx and b > g:
        return "m"
    if g == mx and r >= b:
        return "G"
    if g == mx and b > r:
        return "c"
    if b == mx:
        return "B"
    return "?"


def ascii_preview(rgba: bytes, w: int, h: int, cols: int = 72, rows: int = 34) -> list[str]:
    """纯字节操作实现缩略字符画。"""
    scale_x = w / max(cols, 1)
    scale_y = h / max(rows, 1)
    out = []
    for y in range(rows):
        line = []
        for x in range(cols):
            x0 = int(x * scale_x)
            y0 = int(y * scale_y)
            x1 = min(x0 + 2, w)
            y1 = min(y0 + 2, h)
            rsum = gsum = bsum = asum = 0
            cnt = 0
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    o = (yy * w + xx) * 4
                    rsum += rgba[o]
                    gsum += rgba[o + 1]
                    bsum += rgba[o + 2]
                    asum += rgba[o + 3]
                    cnt += 1
            if cnt == 0:
                line.append(" ")
                continue
            r, g, b, a = rsum // cnt, gsum // cnt, bsum // cnt, asum // cnt
            line.append(rgb_to_hue_char(r, g, b, a))
        out.append("".join(line))
    return out


def grid_stats(rgba: bytes, w: int, h: int, grid: int = 4) -> list[str]:
    cw = w // max(grid, 1)
    ch = h // max(grid, 1)
    lines = []
    for gy in range(grid):
        row = []
        for gx in range(grid):
            rsum = gsum = bsum = asum = 0
            cnt = 0
            for yy in range(gy * ch, min((gy + 1) * ch, h)):
                for xx in range(gx * cw, min((gx + 1) * cw, w)):
                    o = (yy * w + xx) * 4
                    rsum += rgba[o]
                    gsum += rgba[o + 1]
                    bsum += rgba[o + 2]
                    asum += rgba[o + 3]
                    cnt += 1
            if cnt == 0:
                row.append("???000")
                continue
            r, g, b, a = rsum // cnt, gsum // cnt, bsum // cnt, asum // cnt
            row.append(f"{rgb_to_hue_char(r, g, b, a)}{int((r + g + b) / 3):03d}")
        lines.append(" ".join(row))
    return lines


def _parse_args(argv: list[str]) -> tuple[str, dict[str, str]]:
    """解析 CLI 参数。支持 --key value 和 --key=value。

    返回 (位置参数列表, 选项字典)。
    """
    args = []
    opts = {}
    i = 0
    while i < len(argv):
        a = argv[i]
        if "=" in a and a.startswith("--"):
            key, _, val = a.partition("=")
            opts[key[2:]] = val
        elif a.startswith("--") and i + 1 < len(argv) and not argv[i + 1].startswith("--"):
            opts[a[2:]] = argv[i + 1]
            i += 1
        else:
            args.append(a)
        i += 1
    return args, opts


def main() -> None:
    args, opts = _parse_args(sys.argv[1:])
    if not args:
        print(__doc__)
        sys.exit(1)
    tex = args[0]
    cols = int(opts.get("cols", 72))
    rows = int(opts.get("rows", 34))

    with open(tex, "rb") as f:
        data = f.read()
    parsed = parse_ktex(data)
    if parsed is None:
        print("ERROR: not a valid KTEX file", file=sys.stderr)
        sys.exit(1)
    fmt, mips, off = parsed
    rgba = decode_mip(data, fmt, mips, 0)
    if rgba is None:
        print("ERROR: decode failed", file=sys.stderr)
        sys.exit(1)
    w, h = mips[0][0], mips[0][1]

    # 如果给了 xml + element，裁剪元素区域
    xml_path = opts.get("xml")
    element = opts.get("element")
    if xml_path and element:
        with open(xml_path, encoding="utf-8", errors="ignore") as f:
            xml = f.read()
        m = re.search(
            r'<Element name="%s" u1="([\d.]+)" u2="([\d.]+)" v1="([\d.]+)" v2="([\d.]+)"'
            % re.escape(element),
            xml,
        )
        if m:
            u1, u2, v1, v2 = [float(x) for x in m.groups()]
            x0 = int(u1 * w)
            y0 = int((1 - v2) * h)
            x1 = int(u2 * w)
            y1 = int((1 - v1) * h)
            if x1 > x0 and y1 > y0:
                cw = x1 - x0
                ch = y1 - y0
                cropped = bytearray(cw * ch * 4)
                for dy in range(ch):
                    src_row = ((y0 + dy) * w + x0) * 4
                    dst_row = (dy * cw) * 4
                    cropped[dst_row : dst_row + cw * 4] = rgba[src_row : src_row + cw * 4]
                rgba = bytes(cropped)
                w, h = cw, ch

    print(
        f"== {os.path.basename(tex)} fmt=0x{fmt:08X} mip0={mips[0][0]}x{mips[0][1]}"
        f" (裁剪后 {w}x{h}, 预览 {cols}x{rows}) =="
    )
    for line in ascii_preview(rgba, w, h, cols, rows):
        print(line)
    print(
        "-- 4x4 网格 (字符=色相 R红G绿B蓝c青m品y黄K黑W白.灰, 数字=亮度) --"
    )
    for line in grid_stats(rgba, w, h, 4):
        print("  " + line)

    s = stats(rgba, w, h)
    print(
        f'-- avg_rgb={s["avg_rgb"]} alpha={s["avg_alpha"]} 不透明{s["opaque%"]}% '
        f'透明{s["transparent%"]}% 饱和{s["avg_saturation"]} '
        f'亮度{s["avg_brightness"]} 描边像素{s["edge_transparent_px%"]}%'
    )
    print(f'-- 主色: {s["top_colors"][:6]}')


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    main()
# -*- coding: utf-8 -*-
"""人物贴图模板生成器 + 部位尺寸校验器（基于 esctemplate 官方标准）。

用法：
  python char_sheet_gen.py --parts-json <parts.json> [-o out.png] [--font <path.ttf>]
      生成空白 1024x512 RGBA 动画贴图模板（分区网格 + 部位名标注层）。
  python char_sheet_gen.py --check <部位png目录> --parts-json <parts.json>
      校验目录内 png 尺寸是否与 SCML folder 标准一致，输出核对表。

--parts-json 由 scml_analyze.py -j 生成：
  python scml_analyze.py <xxx.scml> -j parts.json --json-only

依赖：Pillow（与 ktex_decode/dst_tex_analyze 可共用）。
"""
import sys
import os
import json
import glob
import argparse

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except AttributeError:
    pass

SHEET_W, SHEET_H = 1024, 512  # 硬标准：动画贴图
MIN_SIDE = 64


def load_parts(parts_json):
    with open(parts_json, encoding="utf-8") as fh:
        data = json.load(fh)
    parts = {}
    for f in data["folders"]:
        if not f["files"]:
            continue
        dims = sorted({(x["width"], x["height"]) for x in f["files"]})
        pivots = sorted({(x["pivot_x"], x["pivot_y"]) for x in f["files"]})
        parts[f["name"]] = {
            "id": f["id"],
            "frames": len(f["files"]),
            "dims": dims,
            "pivots": pivots,
        }
    return parts


def _next_pow2(n, minv=MIN_SIDE):
    side = minv
    while side < n:
        side *= 2
    return side


def gen_sheet(parts, out_png, font_path=None):
    from PIL import Image, ImageDraw, ImageFont

    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    if font_path and os.path.isfile(font_path):
        try:
            font = ImageFont.truetype(font_path, 14)
            font_sm = ImageFont.truetype(font_path, 11)
        except (OSError, ValueError):
            font = font_sm = ImageFont.load_default()
    else:
        font = font_sm = ImageFont.load_default()

    names = sorted(parts.keys())
    x, y = 0, 0
    for name in names:
        p = parts[name]
        maxdim = max((max(w, h) for w, h in p["dims"]), default=1)
        side = _next_pow2(maxdim)
        if x + side > SHEET_W:
            x, y = 0, y + max(side, MIN_SIDE)
        if y + side > SHEET_H:
            break
        draw.rectangle(
            [x, y, x + side, y + side], outline=(120, 120, 120, 255), width=1
        )
        draw.text(
            (x + 4, y + 2),
            f"{name} x{p['frames']}",
            fill=(220, 220, 220, 255),
            font=font,
        )
        dims_txt = " / ".join(f"{w}x{h}" for w, h in p["dims"][:3])
        draw.text(
            (x + 4, y + 18),
            dims_txt,
            fill=(150, 150, 150, 255),
            font=font_sm,
        )
        x += side

    img.save(out_png)
    print(f"sheet -> {out_png} ({SHEET_W}x{SHEET_H} RGBA, {len(names)} 部位分区)")


def check_dir(png_dir, parts):
    from PIL import Image

    checks = []
    all_bad = []
    for sub in sorted(os.listdir(png_dir)):
        subpath = os.path.join(png_dir, sub)
        if not os.path.isdir(subpath):
            continue
        if sub not in parts:
            checks.append((sub, "未知部位（不在 SCML folder 表）", "SKIP"))
            continue
        pngs = sorted(glob.glob(os.path.join(subpath, "*.png")))
        std_dims = set(parts[sub]["dims"])
        bad = []
        for png in pngs:
            try:
                with Image.open(png) as im:
                    if (im.width, im.height) not in std_dims:
                        bad.append((os.path.basename(png), (im.width, im.height)))
            except OSError as e:
                bad.append((os.path.basename(png), f"ERROR: {e}"))
        if bad:
            all_bad.append((sub, bad))
        status = "OK" if not bad else f"FAIL {len(bad)} 帧尺寸偏离标准"
        checks.append((sub, f"{len(pngs)} 帧, 标准 {sorted(std_dims)}", status))

    for sub, detail, status in checks:
        print(f"{status:6s} {sub:24s} {detail}")
    if all_bad:
        print("\n偏离帧明细：")
        for sub, bad in all_bad:
            for name, dim in bad:
                print(f"  {sub}/{name}: {dim}")
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--parts-json", required=True, help="scml_analyze.py -j 的 JSON 输出")
    ap.add_argument("-o", default="char_sheet_1024x512_RGBA.png", help="模板输出路径")
    ap.add_argument("--check", metavar="DIR", help="校验目录（部位 png 目录）")
    ap.add_argument("--font", metavar="PATH", help="TTF 字体路径（可选，用于模板标注）")
    args = ap.parse_args()

    parts = load_parts(args.parts_json)
    print(f"部位标准：{len(parts)} 个（来自 SCML）")
    if args.check:
        sys.exit(check_dir(args.check, parts))
    gen_sheet(parts, args.o, args.font)


if __name__ == "__main__":
    main()
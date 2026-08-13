# -*- coding: utf-8 -*-
"""批量 KTEX 分析：统计目录中全部 tex 的格式分布，并对代表性样本做像素统计。

用法：python ktex_batch.py <tex根目录>

依赖：ktex_lib.py（同目录）。
"""
import sys
import os
import glob
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ktex_lib import parse_ktex, decode_mip, stats, fmt_name, cat_of

BKT_ORDER = [">=2048", ">=1024", ">=512", ">=256", ">=128", ">=64", "<64"]


def size_bucket(w: int, h: int) -> str:
    m = max(w, h)
    if m >= 2048:
        return ">=2048"
    if m >= 1024:
        return ">=1024"
    if m >= 512:
        return ">=512"
    if m >= 256:
        return ">=256"
    if m >= 128:
        return ">=128"
    if m >= 64:
        return ">=64"
    return "<64"


def analyze(root: str) -> None:
    all_tex = glob.glob(os.path.join(root, "**", "*.tex"), recursive=True)
    if not all_tex:
        print(f"WARNING: no *.tex found under {root}", file=sys.stderr)
        return

    fmt_stats = Counter()
    size_stats = Counter()
    mip_stats = Counter()
    cat_stats = Counter()
    non_pow2 = []
    total = 0
    samples = []

    for p in all_tex:
        with open(p, "rb") as f:
            data = f.read()
        parsed = parse_ktex(data)
        if parsed is None:
            continue
        fmt, mips, data_start = parsed
        total += 1
        w, h = mips[0][0], mips[0][1]
        fn = fmt_name(mips[0], fmt)
        fmt_stats[fn] += 1
        size_stats[size_bucket(w, h)] += 1
        mip_stats[len(mips)] += 1
        cat_stats[cat_of(p)] += 1
        if (w & (w - 1)) or (h & (h - 1)):
            non_pow2.append((p, w, h))
        samples.append((p, fmt, mips, data_start))

    print("=" * 60)
    print("全量 tex 统计")
    print("=" * 60)
    print(f"总数: {total}")
    print(f"格式分布: {dict(fmt_stats)}")
    print(f"Mip 层级分布: {dict(sorted(mip_stats.items()))}")
    print(f"尺寸分布: {dict(sorted(size_stats.items(), key=lambda kv: BKT_ORDER.index(kv[0])))}")
    print(f"分类分布: {dict(cat_stats)}")
    print(f"非 2 的幂: {len(non_pow2)} 个")
    for p, w, h in non_pow2[:6]:
        print(f"  {os.path.basename(p)}: {w}x{h}")

    print("\n" + "=" * 60)
    print("代表性样本像素统计（每类最多 2 张）")
    print("=" * 60)
    picked = Counter()
    n = 0
    for p, fmt, mips, data_start in samples:
        cat = cat_of(p)
        if picked[cat] >= 2 or n >= 40:
            continue
        if cat == "other" and picked[cat] >= 1:
            continue
        try:
            with open(p, "rb") as f:
                data = f.read()
            rgba = decode_mip(data, fmt, mips, 0)
            if rgba is None:
                continue
            w, h = mips[0][0], mips[0][1]
            s = stats(rgba, w, h)
            picked[cat] += 1
            n += 1
            print(
                f"[{cat}] {os.path.basename(p)}"
                f" {s['size']} {fmt_name(mips[0], fmt)}"
                f" avg_rgb={s['avg_rgb']} alpha={s['avg_alpha']}"
                f" opaque={s['opaque%']}% trans={s['transparent%']}%"
                f" sat={s['avg_saturation']} bright={s['avg_brightness']}"
            )
        except Exception as e:
            print(f"[{cat}] {os.path.basename(p)} ERROR: {e}", file=sys.stderr)

    print(f"\n抽样解码: {n} 张")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    root = sys.argv[1]
    if not os.path.isdir(root):
        print(f"ERROR: not a directory: {root}", file=sys.stderr)
        sys.exit(1)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    analyze(root)
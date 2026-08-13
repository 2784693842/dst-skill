# -*- coding: utf-8 -*-
"""KTEX 格式分析器（不依赖 PIL，手动写 PNG 抽样）。

用法：
  python dst_tex_analyze.py <tex根目录> [--stat] [--out <输出目录>] [--limit N]

依赖：ktex_lib.py（同目录）。
"""
import sys
import os
import collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ktex_lib import parse_ktex, decode_mip, fmt_name, cat_of, save_png

BKT_ORDER = [">=2048", ">=1024", ">=512", ">=256", ">=128", ">=64", "<64"]


def _size_bucket(w: int, h: int) -> str:
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


def run(root: str, out_dir: str | None, stat_only: bool, limit: int) -> None:
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
                with open(path, "rb") as f:
                    data = f.read()
            except OSError:
                continue
            parsed = parse_ktex(data)
            if parsed is None:
                continue
            fmt, mips, data_start = parsed
            fn_ = fmt_name(mips[0], fmt)
            fmt_count[fn_] += 1
            w, h = mips[0][0], mips[0][1]
            b = _size_bucket(w, h)
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
        return

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
            with open(path, "rb") as f:
                data = f.read()
            rgba = decode_mip(data, fmt, mips, 0)
            if rgba is None:
                continue
            w, h = mips[0][0], mips[0][1]
            png = os.path.join(
                out_dir,
                f"{mod[:10]}_{cat}_{w}x{h}_{fmt_name(mips[0], fmt)}_{n}.png",
            )
            save_png(w, h, rgba, png)
            picked[(mod, cat)] += 1
            n += 1
        except Exception:
            continue
    print(f"DECODED {n} -> {out_dir}")


def _parse_args(argv: list[str]):
    """解析 CLI 参数，支持 --key value 和 --key=value。"""
    args = []
    out_dir = None
    stat_only = False
    limit = 60
    i = 0
    while i < len(argv):
        a = argv[i]
        if "=" in a and a.startswith("--"):
            key, _, val = a.partition("=")
            k = key[2:]
            if k == "out":
                out_dir = val
            elif k == "limit":
                limit = int(val)
        elif a == "--stat":
            stat_only = True
        elif (
            a in ("--out", "--limit")
            and i + 1 < len(argv)
            and not argv[i + 1].startswith("--")
        ):
            if a == "--out":
                out_dir = argv[i + 1]
            else:
                limit = int(argv[i + 1])
            i += 1
        elif not a.startswith("-"):
            args.append(a)
        i += 1
    return args, out_dir, stat_only, limit


def main() -> None:
    args, out_dir, stat_only, limit = _parse_args(sys.argv[1:])
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
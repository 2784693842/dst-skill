#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""截图差异检测引擎

三级递进:
  L1: pixel_diff(before, after) → {changed, bbox, diff_ratio}
  L2: capture_region(img, bbox) → cropped PIL.Image
  L3: semantic_diff(before, after) → str

设计原则: 先像素 diff 过滤，有变化才走识图 API。
"""

import os
import sys
import json
import argparse
import subprocess

from PIL import Image, ImageChops

# 确保标准输出使用 UTF-8 编码
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


# ==============================================================================
# L1: 像素级差异检测
# ==============================================================================

def pixel_diff(before: Image, after: Image, threshold: int = 30) -> dict:
    """
    计算两张图的像素级差异。

    参数:
      before: 操作前截图
      after:  操作后截图
      threshold: 差异阈值（0-255），超过此值的像素算"变化"

    返回:
      {
          "changed": bool,          # 是否有显著变化（diff_ratio >= 0.001）
          "bbox": (int, int, int, int) | None,  # 变化区域包围盒 (x1, y1, x2, y2)
          "diff_ratio": float,      # 变化像素占比 (0.0 - 1.0)
          "changed_pixels": int     # 变化像素总数
      }
    """
    # 确保两张图尺寸一致
    if before.size != after.size:
        after = after.resize(before.size)

    w, h = before.size
    total = w * h

    # 计算逐像素差异并转为灰度
    diff = ImageChops.difference(before, after)
    gray = diff.convert("L")
    diff_data = gray.getdata()

    # 纯 PIL 遍历：统计变化像素并记录包围盒
    changed_pixels = 0
    min_x, min_y = w, h
    max_x, max_y = 0, 0

    for y in range(h):
        row_offset = y * w
        for x in range(w):
            if diff_data[row_offset + x] > threshold:
                changed_pixels += 1
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y

    diff_ratio = changed_pixels / total if total > 0 else 0.0

    # 变化像素占比不足 0.1%，视为无变化
    if diff_ratio < 0.001:
        return {
            "changed": False,
            "bbox": None,
            "diff_ratio": diff_ratio,
            "changed_pixels": changed_pixels,
        }

    # 构建包围盒 (x1, y1, x2, y2)，x2/y2 为右/下边界（含 1）
    bbox = (min_x, min_y, max_x + 1, max_y + 1)

    return {
        "changed": True,
        "bbox": bbox,
        "diff_ratio": diff_ratio,
        "changed_pixels": changed_pixels,
    }


# ==============================================================================
# L2: 区域截取
# ==============================================================================

def capture_region(img: Image, bbox: tuple) -> Image:
    """
    截取指定区域。

    参数:
      img:  原始 PIL.Image
      bbox: 包围盒 (x1, y1, x2, y2)

    返回:
      截取后的 PIL.Image
    """
    return img.crop(bbox)


# ==============================================================================
# L3: 语义级差异对比
# ==============================================================================

def semantic_diff(before: Image, after: Image, workdir: str,
                  prompt: str | None = None) -> str:
    """
    语义级对比：将两张图传给识图 API。

    调用 caption-vision.ps1（sensenova-vision skill 的核心脚本）。
    先保存两张临时 PNG，然后用特殊 prompt 传两张图的 base64。

    参数:
      before: 操作前截图
      after:  操作后截图
      workdir: 临时文件工作目录
      prompt: 自定义对比 prompt（可选）

    返回: str，识图 API 的描述文本
    """
    if prompt is None:
        prompt = (
            "对比图A和图B。图A是操作前的截图，图B是操作后的截图。"
            "请用1-2句话精确描述图B相比图A的具体变化。"
            "如果没有变化，回答'无变化'。"
        )

    # 确保工作目录存在
    os.makedirs(workdir, exist_ok=True)

    # 保存临时文件
    before_path = os.path.join(workdir, "before.png")
    after_path = os.path.join(workdir, "after.png")
    before.save(before_path)
    after.save(after_path)

    # 找到 caption-vision.ps1 路径
    # __file__ 位于 skills/modtool-automation/assets/scripts/
    # skill 根目录 = __file__ 的 ../../.. 即 skills/
    script_dir = os.path.dirname(os.path.abspath(__file__))
    skills_dir = os.path.join(script_dir, "..", "..")
    # sensenova-vision 在同一 skills/ 目录下
    sensenova_dir = os.path.join(skills_dir, "sensenova-vision")
    caption_script = os.path.join(sensenova_dir, "assets", "scripts", "caption-vision.ps1")

    # 调用 caption-vision.ps1 对"变化后"的截图做描述
    if os.path.exists(caption_script):
        cmd = (
            f'& "{caption_script}" '
            f'-Image "{after_path}" '
            f'-Prompt "{prompt}"'
        )
        result = subprocess.run(
            ["powershell", "-Command", cmd],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode == 0:
            return result.stdout.strip()

    # fallback：返回占位信息
    return f"[识图不可用] 截图已保存: {before_path}, {after_path}"


# ==============================================================================
# 完整工作流
# ==============================================================================

def full_diff(before: Image, after: Image, workdir: str,
              verify: bool = True) -> dict:
    """
    完整差异检测工作流:
      1. pixel_diff()
      2. 无变化 → 跳过识图，直接返回
      3. 有变化 → 截取变化区域 → semantic_diff()

    返回:
      {
          "changed": bool,
          "bbox": tuple | None,
          "diff_ratio": float,
          "changed_pixels": int,
          "description": str | None   # 语义描述（有变化且 verify=True 时）
      }
    """
    result = pixel_diff(before, after)

    if not result["changed"]:
        return {
            "changed": False,
            "bbox": None,
            "diff_ratio": result["diff_ratio"],
            "changed_pixels": result["changed_pixels"],
            "description": "无变化",
        }

    if not verify:
        return {**result, "description": None}

    # 有变化且需要语义验证：调用识图 API
    description = semantic_diff(before, after, workdir)
    return {**result, "description": description}


# ==============================================================================
# CLI 入口
# ==============================================================================

def _print_result(result: dict, as_json: bool = False) -> None:
    """格式化输出检测结果"""
    if as_json:
        # 将 tuple 转为 list 以便 JSON 序列化
        output = {
            "changed": result["changed"],
            "bbox": list(result["bbox"]) if result["bbox"] else None,
            "diff_ratio": result["diff_ratio"],
            "changed_pixels": result["changed_pixels"],
            "description": result.get("description"),
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        changed = result["changed"]
        bbox = result["bbox"]
        diff_ratio = result["diff_ratio"]
        changed_pixels = result["changed_pixels"]
        description = result.get("description")

        print(f"变化检测: {'有变化' if changed else '无变化'}")
        print(f"变化像素数: {changed_pixels}")
        print(f"变化占比:   {diff_ratio:.4%}")
        if bbox:
            print(f"变化区域:   ({bbox[0]}, {bbox[1]}, {bbox[2]}, {bbox[3]})")
        if description is not None:
            print(f"语义描述:   {description}")


def _load_image(path: str) -> Image:
    """加载图片文件，不存在则报错退出"""
    if not os.path.isfile(path):
        print(f"错误: 文件不存在 — {path}", file=sys.stderr)
        sys.exit(1)
    try:
        return Image.open(path).convert("RGB")
    except Exception as e:
        print(f"错误: 无法打开图片 {path} — {e}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="截图差异检测引擎 — 三级递进（像素 → 区域 → 语义）",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # 子命令: compare（仅 L1 像素差异）
    p_compare = sub.add_parser(
        "compare", help="纯像素级差异对比（L1），不含识图"
    )
    p_compare.add_argument("before", help="操作前截图路径")
    p_compare.add_argument("after", help="操作后截图路径")
    p_compare.add_argument("--json", action="store_true", help="以 JSON 格式输出")
    p_compare.add_argument("--threshold", type=int, default=30, help="差异阈值（默认 30）")

    # 子命令: full（完整工作流 L1+L3）
    p_full = sub.add_parser(
        "full", help="完整工作流：像素差异 + 语义识别"
    )
    p_full.add_argument("before", help="操作前截图路径")
    p_full.add_argument("after", help="操作后截图路径")
    p_full.add_argument("--json", action="store_true", help="以 JSON 格式输出")
    p_full.add_argument("--threshold", type=int, default=30, help="差异阈值（默认 30）")
    p_full.add_argument("--workdir", default=None, help="临时文件工作目录")
    p_full.add_argument("--no-verify", action="store_true", help="跳过语义验证")

    args = parser.parse_args()

    # 加载两张截图
    before = _load_image(args.before)
    after = _load_image(args.after)

    if args.command == "compare":
        result = pixel_diff(before, after, threshold=args.threshold)
        result["description"] = None if result["changed"] else "无变化"
        _print_result(result, as_json=args.json)

    elif args.command == "full":
        workdir = args.workdir or os.path.join(os.getcwd(), "tmp_diff")
        verify = not args.no_verify
        result = full_diff(
            before, after,
            workdir=workdir,
            verify=verify,
        )
        _print_result(result, as_json=args.json)


if __name__ == "__main__":
    main()

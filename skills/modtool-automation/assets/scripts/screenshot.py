#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""DST Mod Tool DPI-aware 截图引擎

功能:
  - 查找工具窗口 hwnd
  - 获取窗口坐标和客户区坐标
  - DPI-aware 区域截图（ImageGrab）
  - 坐标系转换（client ↔ screen）
"""

from __future__ import annotations

import argparse
import ctypes
import re
import sys
from ctypes import wintypes
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from PIL import Image

# ---------------------------------------------------------------------------
# 模块初始化
# ---------------------------------------------------------------------------

# 强制 UTF-8 输出，避免 Windows 控制台编码问题
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

user32 = ctypes.windll.user32

# 标题匹配正则（默认匹配包含 "Mod Tool" 的窗口）
_DEFAULT_TITLE_REGEX = r".*Mod Tool.*"


# ---------------------------------------------------------------------------
# 窗口查找
# ---------------------------------------------------------------------------

def find_window(title_regex: str = _DEFAULT_TITLE_REGEX) -> int | None:
    """遍历所有顶层窗口，返回标题匹配 title_regex 的最后一个 hwnd。

    参数:
        title_regex: 窗口标题正则表达式，默认匹配包含 "Mod Tool" 的窗口。

    返回:
        匹配的窗口句柄 hwnd，若未找到则返回 None。
        返回最后一个匹配（工具窗口通常在最前面）。
    """
    pattern = re.compile(title_regex)
    results: list[int] = []

    def _callback(hwnd: int, _lparam: int) -> bool:
        buf = ctypes.create_unicode_buffer(256)
        length = user32.GetWindowTextW(hwnd, buf, 256)
        if length > 0 and pattern.search(buf.value):
            results.append(hwnd)
        return True  # 继续枚举

    user32.EnumWindows(ctypes.WNDENUMPROC(_callback), 0)
    return results[-1] if results else None


# ---------------------------------------------------------------------------
# 窗口几何
# ---------------------------------------------------------------------------

def get_window_rect(hwnd: int) -> tuple[int, int, int, int]:
    """获取窗口在屏幕上的边界矩形。

    参数:
        hwnd: 窗口句柄。

    返回:
        (x, y, width, height) — 窗口左上角屏幕坐标和宽高。
    """
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return (rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)


def get_client_rect(hwnd: int) -> tuple[int, int, int, int]:
    """获取窗口客户区矩形。

    客户区从 (0, 0) 开始，不包含标题栏和非客户区边框。

    参数:
        hwnd: 窗口句柄。

    返回:
        (0, 0, width, height) — 客户区宽高。
    """
    rect = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    return (0, 0, rect.right, rect.bottom)


# ---------------------------------------------------------------------------
# DPI
# ---------------------------------------------------------------------------

def get_dpi_scale(hwnd: int) -> float:
    """获取窗口所在监视器的 DPI 缩放比例。

    参数:
        hwnd: 窗口句柄。

    返回:
        DPI 缩放比例（例如 1.5 = 150%）。
    """
    dpi = user32.GetDpiForWindow(hwnd)
    return dpi / 96.0  # 96 是标准（100%）DPI


# ---------------------------------------------------------------------------
# 截图
# ---------------------------------------------------------------------------

def capture(
    hwnd: int | None = None,
    region: tuple[int, int, int, int] | None = None,
) -> "Image":
    """DPI-aware 截图，基于 ImageGrab.grab()（适配 gpui GPU 渲染窗口）。

    参数:
        hwnd: 目标窗口句柄，为 None 时自动查找 DST Mod Tool 窗口。
        region: 截图区域 (left, top, width, height)，坐标相对于窗口客户区。
                为 None 时截取整个屏幕。

    返回:
        PIL.Image 对象。

    异常:
        RuntimeError: 当 hwnd 为 None 且未找到 Mod Tool 窗口时抛出。
    """
    from PIL import ImageGrab

    # region 为 None → 截取整个屏幕
    if region is None:
        return ImageGrab.grab()

    # 未指定 hwnd → 自动查找
    if hwnd is None:
        hwnd = find_window()
        if hwnd is None:
            raise RuntimeError("未找到 DST Mod Tool 窗口")

    # region 是 (left, top, width, height)，坐标相对于窗口客户区
    # 转换为屏幕坐标
    window_x, window_y, _window_w, _window_h = get_window_rect(hwnd)
    region_left, region_top, region_w, region_h = region
    screen_left = window_x + region_left
    screen_top = window_y + region_top
    bbox = (screen_left, screen_top, screen_left + region_w, screen_top + region_h)
    return ImageGrab.grab(bbox=bbox)


# ---------------------------------------------------------------------------
# 坐标转换
# ---------------------------------------------------------------------------

def client_to_screen(
    hwnd: int,
    client_x: int,
    client_y: int,
) -> tuple[int, int]:
    """将窗口客户区坐标转换为屏幕坐标。

    参数:
        hwnd:     窗口句柄。
        client_x: 客户区 X 坐标。
        client_y: 客户区 Y 坐标。

    返回:
        (screen_x, screen_y) — 对应的屏幕坐标。

    注意:
        简化实现：直接用 GetWindowRect 的偏移叠加。
        若要精确计算非客户区（标题栏/边框）偏移，应使用
        user32.ClientToScreen()。
    """
    window_x, window_y, _window_w, _window_h = get_window_rect(hwnd)
    return (window_x + client_x, window_y + client_y)


def screen_to_logical(
    hwnd: int,
    screen_x: int,
    screen_y: int,
) -> tuple[float, float]:
    """将屏幕坐标转换为逻辑坐标（消除 DPI 缩放影响）。

    参数:
        hwnd:     窗口句柄。
        screen_x: 屏幕 X 坐标。
        screen_y: 屏幕 Y 坐标。

    返回:
        (logical_x, logical_y) — DPI 归一化后的逻辑坐标。
    """
    scale = get_dpi_scale(hwnd)
    return (screen_x / scale, screen_y / scale)


# ---------------------------------------------------------------------------
# CLI 入口
# ---------------------------------------------------------------------------

def _cmd_info(args: argparse.Namespace) -> None:
    """打印窗口信息子命令。"""
    hwnd = find_window(args.title_regex)
    if hwnd is None:
        print("未找到匹配的窗口。", file=sys.stderr)
        sys.exit(1)

    x, y, w, h = get_window_rect(hwnd)
    _, _, cw, ch = get_client_rect(hwnd)
    scale = get_dpi_scale(hwnd)
    dpi = int(scale * 96)

    print(f"窗口信息")
    print(f"========")
    print(f"  hwnd         : 0x{hwnd:X}")
    print(f"  window_rect  : x={x}, y={y}, w={w}, h={h}")
    print(f"  client_rect  : w={cw}, h={ch}")
    print(f"  dpi          : {dpi}")
    print(f"  scale        : {scale:.2f}")


def _cmd_capture(args: argparse.Namespace) -> None:
    """截图子命令。"""
    region = None
    if args.region is not None:
        parts = [int(p.strip()) for p in args.region.split(",")]
        if len(parts) != 4:
            print(
                "region 格式错误，应为 'x,y,w,h'（四个逗号分隔的整数）。",
                file=sys.stderr,
            )
            sys.exit(1)
        region = tuple(parts)

    img = capture(hwnd=None, region=region)

    if args.save:
        img.save(args.save)
        print(f"截图已保存: {args.save}")
        print(f"  尺寸: {img.size[0]} x {img.size[1]}")
    else:
        # 未指定 --save → 显示图片
        img.show()
        print(f"截图: {img.size[0]} x {img.size[1]}（已打开查看器）")


def build_parser() -> argparse.ArgumentParser:
    """构建命令行参数解析器。"""
    parser = argparse.ArgumentParser(
        prog="screenshot",
        description="DST Mod Tool DPI-aware 截图工具",
    )
    parser.add_argument(
        "--title-regex",
        default=_DEFAULT_TITLE_REGEX,
        help=f"窗口标题匹配正则（默认: {_DEFAULT_TITLE_REGEX}）",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    # -- info --
    info_parser = sub.add_parser("info", help="打印窗口信息")

    # -- capture --
    cap_parser = sub.add_parser("capture", help="截取窗口区域")
    cap_parser.add_argument(
        "region",
        nargs="?",
        default=None,
        help="截图区域 'x,y,w,h'，相对于窗口客户区；省略则截全屏",
    )
    cap_parser.add_argument(
        "--save",
        default=None,
        help="保存路径（如 output.png），省略则打开查看器",
    )

    return parser


def main() -> None:
    """CLI 主入口。"""
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "info":
        _cmd_info(args)
    elif args.command == "capture":
        _cmd_capture(args)


if __name__ == "__main__":
    main()

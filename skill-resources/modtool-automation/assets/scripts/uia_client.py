#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""DST Mod Tool UIA 客户端

基于 pywinauto，后端必须为 'uia'。
gpui/Zed 框架通过 UIA 暴露完整控件树（47 Buttons + 1 Slider + 1 MenuBar）。

用法:
  from uia_client import connect, find_control, click_control
  w = connect()
  btn = find_control(w, "Import")
  click_control(btn)
"""
import sys
import argparse
from typing import Optional

# 确保 UTF-8 输出
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, ValueError):
    # Python < 3.7 不支持 reconfigure
    pass


def connect(
    title_regex: str = r".*Mod Tool.*",
    timeout: int = 10,
):
    """
    连接到已运行的 DST Mod Tool 窗口。

    注意: 用 start /B 启动时可能产生两个匹配窗口（终端窗口 + 工具窗口），
    需要选最后一个（工具窗口）。

    参数:
        title_regex: 窗口标题正则表达式
        timeout: 等待窗口出现的最长时间（秒）

    返回:
        pywinauto WindowSpecification 对象，或 None（未找到）
    """
    try:
        from pywinauto import Desktop
    except ImportError:
        print("缺少 pywinauto 依赖，请先安装: pip install pywinauto", file=sys.stderr)
        return None

    try:
        desktop = Desktop(backend="uia")
        windows = desktop.windows(title_re=title_regex, timeout=timeout)
        if not windows:
            return None
        # 选最后一个（通常是工具主窗口）
        return windows[-1]
    except Exception as e:
        print(f"UIA 连接失败: {e}", file=sys.stderr)
        return None


def get_control(window, ctrl_type=None, title=None, idx=None):
    """
    定位控件，支持三种方式:
      - 按类型: get_control(w, ctrl_type="Button")
      - 按标题: get_control(w, title="Import")
      - 按索引: get_control(w, idx=3)

    组合使用: get_control(w, ctrl_type="Button", title="Import")

    参数:
        window: pywinauto WindowSpecification 对象
        ctrl_type: 控件友好类型名，如 "Button"、"Slider"、"MenuBar"
        title: 控件标题文本（部分匹配，使用 in 判断）
        idx: 匹配结果中的索引

    返回:
        pywinauto UIAControlWrapper 对象，或 None（未找到）
    """
    try:
        descendants = window.descendants()
    except Exception as e:
        print(f"获取控件列表失败: {e}", file=sys.stderr)
        return None

    results = []
    for ctrl in descendants:
        # 按类型过滤
        if ctrl_type and ctrl.friendlyclassname != ctrl_type:
            continue
        # 按标题过滤
        if title and title not in ctrl.window_text():
            continue
        results.append(ctrl)

    if not results:
        return None

    # 按索引返回
    if idx is not None:
        if 0 <= idx < len(results):
            return results[idx]
        return None
    return results[0]


def find_control(window, title=None, ctrl_type=None, idx=None):
    """
    查找控件（别名方法，语义更清晰）。

    等价于 get_control，但命名上更强调"查找"的意图。
    """
    return get_control(window, ctrl_type=ctrl_type, title=title, idx=idx)


def click_control(control):
    """
    精确点击控件。pywinauto 自动处理:
      - UIA client 坐标 → client_to_screen() → 屏幕坐标
      - DPI 缩放（如有）
      - SendInput 发送鼠标事件

    坐标精度: 1px（UIA 返回的 bounding rect 是整数像素）

    参数:
        control: pywinauto 控件对象
    """
    try:
        # 等待控件可见
        control.wait("visible", timeout=5)
        # 使用 click_input()，通过 SendInput 发送真实鼠标事件
        control.click_input()
    except Exception as e:
        print(f"点击控件失败: {e}", file=sys.stderr)


def list_controls(window, limit: int = 50):
    """
    列出窗口所有控件，用于调试。

    返回格式:
      [
          {"idx": 0, "type": "Button", "title": "Play", "rect": (x, y, w, h)},
          ...
      ]

    参数:
        window: pywinauto WindowSpecification 对象
        limit: 最多返回的控件数量

    返回:
        字典列表，每个字典包含 idx/type/title/rect/visible/enabled
    """
    results = []
    try:
        descendants = list(window.descendants())[:limit]
    except Exception as e:
        print(f"获取控件列表失败: {e}", file=sys.stderr)
        return results

    for i, ctrl in enumerate(descendants):
        try:
            rect = ctrl.rectangle()
            rect_tuple = (rect.left, rect.top, rect.width(), rect.height())
            visible = ctrl.is_visible()
            enabled = ctrl.is_enabled()
        except Exception:
            rect_tuple = (0, 0, 0, 0)
            visible = False
            enabled = False

        results.append({
            "idx": i,
            "type": ctrl.friendlyclassname,
            "title": ctrl.window_text(),
            "rect": rect_tuple,
            "visible": visible,
            "enabled": enabled,
        })
    return results


def wait_for_window(title_regex: str, timeout: int = 30):
    """
    等待窗口出现，用于启动工具后等待就绪。

    参数:
        title_regex: 窗口标题正则表达式
        timeout: 最长等待时间（秒）

    返回:
        pywinauto WindowSpecification 对象，或 None（超时未找到）
    """
    from time import time, sleep

    deadline = time() + timeout
    while time() < deadline:
        w = connect(title_regex)
        if w:
            return w
        sleep(0.5)
    return None


def _print_info(window):
    """打印窗口基本信息"""
    try:
        print(f"窗口标题: {window.window_text()}")
        print(f"窗口类名: {window.class_name()}")
        try:
            rect = window.rectangle()
            print(f"窗口尺寸: {rect.width()}x{rect.height()} @ ({rect.left}, {rect.top})")
        except Exception:
            pass
        print(f"可见: {window.is_visible()}")
        print(f"启用: {window.is_enabled()}")
    except Exception as e:
        print(f"获取窗口信息失败: {e}", file=sys.stderr)


def main():
    """CLI 入口"""
    parser = argparse.ArgumentParser(description="DST Mod Tool UIA 客户端")
    subparsers = parser.add_subparsers(dest="command", help="子命令")

    # list 子命令
    list_parser = subparsers.add_parser("list", help="列出所有控件")
    list_parser.add_argument(
        "--limit", type=int, default=50, help="最多列出的控件数量（默认 50）"
    )
    list_parser.add_argument(
        "--type", dest="ctrl_type", default=None, help="按类型过滤"
    )
    list_parser.add_argument(
        "--title", default=None, help="按标题过滤"
    )

    # click 子命令
    click_parser = subparsers.add_parser("click", help="点击控件")
    click_parser.add_argument("--title", default=None, help="按标题查找控件")
    click_parser.add_argument("--type", dest="ctrl_type", default=None, help="按类型查找控件")
    click_parser.add_argument("--idx", type=int, default=0, help="匹配结果索引（默认 0）")

    # info 子命令
    subparsers.add_parser("info", help="打印窗口信息")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "list":
        window = connect()
        if window is None:
            print("未找到 DST Mod Tool 窗口", file=sys.stderr)
            sys.exit(1)
        controls = list_controls(window, limit=args.limit)
        # 如果指定了过滤条件，从结果中再筛选
        if args.ctrl_type or args.title:
            controls = [
                c for c in controls
                if (not args.ctrl_type or c["type"] == args.ctrl_type)
                and (not args.title or args.title in c["title"])
            ]
        print(f"共找到 {len(controls)} 个控件:\n")
        print(f"{'Idx':>4}  {'Type':<12}  {'Title':<30}  {'Rect':<22}  {'Vis':<5}  {'Ena'}")
        print("-" * 85)
        for c in controls:
            rect = c["rect"]
            rect_str = f"({rect[0]},{rect[1]},{rect[2]}x{rect[3]})"
            title = c["title"][:28]
            print(
                f"{c['idx']:>4}  {c['type']:<12}  {title:<30}  {rect_str:<22}  "
                f"{'Y' if c['visible'] else 'N':<5}  {'Y' if c['enabled'] else 'N'}"
            )

    elif args.command == "click":
        window = connect()
        if window is None:
            print("未找到 DST Mod Tool 窗口", file=sys.stderr)
            sys.exit(1)
        ctrl = get_control(
            window,
            ctrl_type=args.ctrl_type,
            title=args.title,
            idx=args.idx,
        )
        if ctrl is None:
            print("未找到匹配控件", file=sys.stderr)
            sys.exit(1)
        print(f"点击控件: {ctrl.friendlyclassname} '{ctrl.window_text()}'")
        click_control(ctrl)
        print("点击完成")

    elif args.command == "info":
        window = connect()
        if window is None:
            print("未找到 DST Mod Tool 窗口", file=sys.stderr)
            sys.exit(1)
        _print_info(window)


if __name__ == "__main__":
    main()

# -*- coding: utf-8 -*-
"""DST Mod Tool 自动化编排工作流

组合 lua_client + screenshot + diff_detector + uia_client
实现完整的自动化操作链路。

用法:
  from workflow import (
      open_file,
      run_lua,
      verify_operation,
      auto_operation,
  )

典型流程:
  1. open_file(exe, anim_zip)     # 启动工具并打开动画文件
  2. run_lua("inspect_doc.lua")    # 查看文档状态
  3. verify_operation(...)          # 执行操作 + 截图验证
"""
import os
import sys
import json
import time
import subprocess

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except AttributeError:
    pass

# 导入同目录下的模块
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from lua_client import run as lua_run, LuaResult, _resolve_exe
from screenshot import find_window, get_window_rect, capture, get_dpi_scale
from diff_detector import pixel_diff, full_diff, capture_region
from uia_client import connect as uia_connect, get_control, click_control


def open_file(exe: str | None = None, file_path: str | None = None) -> subprocess.CompletedProcess:
    """
    启动 DST Mod Tool 并打开动画文件。

    参数:
      exe: 工具可执行文件路径（默认从环境变量或默认值解析）
      file_path: 要打开的动画文件路径

    返回: subprocess.CompletedProcess

    注意: 文件通过位置参数传递（dst-app [FILES...]），工具启动后
    GUI 窗口打开，后续操作通过 lua_run 注入脚本。
    """
    exe_path = _resolve_exe(exe)

    cmd = [exe_path]
    if file_path:
        cmd.append(file_path)

    print(f"启动工具: {' '.join(cmd)}")
    # 工具是 GUI 应用，不等待输出
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # 等待窗口出现
    time.sleep(3)
    return proc


def run_lua(
    script_text: str,
    exe: str | None = None,
    timeout: int = 30,
    label: str | None = None,
) -> LuaResult:
    """
    执行 Lua 脚本。

    参数:
      script_text: Lua 源码
      exe: 工具可执行文件路径
      timeout: 超时时间（秒）
      label: 操作标签（注入到脚本开头）

    返回: LuaResult

    示例:
      >>> result = run_lua("print(tool.document_revision)")
      >>> print(result.ok)         # True
      >>> print(result.output)     # ["4"]
      >>> print(result.changed)    # False
    """
    if label:
        script_text = f"doc:set_label('{label}');\n" + script_text

    return lua_run(script_text, exe=exe, timeout=timeout)


def run_lua_file(
    file_path: str,
    exe: str | None = None,
    timeout: int = 30,
) -> LuaResult:
    """从文件执行 Lua 脚本"""
    script_dir = os.path.join(SCRIPT_DIR, "..", "lua")
    full_path = os.path.join(script_dir, file_path) if not os.path.isabs(file_path) else file_path

    if not os.path.exists(full_path):
        return LuaResult(
            ok=False,
            output=[],
            error={"message": f"Lua 脚本不存在: {full_path}"}
        )

    with open(full_path, "r", encoding="utf-8") as f:
        script_text = f.read()

    return lua_run(script_text, exe=exe, timeout=timeout)


def verify_operation(
    operation_name: str,
    lua_script: str,
    exe: str | None = None,
    capture_before: bool = True,
    capture_after: bool = True,
    pixel_threshold: int = 30,
    workdir: str | None = None,
) -> dict:
    """
    执行 Lua 操作 + 截图验证。

    完整工作流:
      1. 操作前截图（可选）
      2. 执行 Lua 脚本
      3. 操作后截图（可选）
      4. 像素 diff 定位变化
      5. 返回结构化结果

    参数:
      operation_name: 操作名称（用于报告）
      lua_script: Lua 源码
      exe: 工具路径
      capture_before: 是否截操作前截图
      capture_after: 是否截操作后截图
      pixel_threshold: 像素差异阈值
      workdir: 临时文件工作目录

    返回:
      {
          "operation": str,
          "lua": {"ok": bool, "output": [...], "changed": bool},
          "diff": {
              "captured": bool,
              "changed": bool | None,
              "bbox": tuple | None,
              "diff_ratio": float | None,
              "changed_pixels": int | None,
              "description": str | None
          }
      }
    """
    result = {
        "operation": operation_name,
        "lua": {},
        "diff": {"captured": False}
    }

    before_img = None
    if capture_before:
        hwnd = find_window()
        if hwnd:
            before_img = capture(hwnd)
            result["diff"]["captured"] = True

    # 执行 Lua 脚本
    lua_result = lua_run(lua_script, exe=exe)
    result["lua"] = {
        "ok": lua_result.ok,
        "output": lua_result.output,
        "changed": lua_result.changed,
        "error": lua_result.error,
    }

    if lua_result.error:
        return result

    # 操作后截图
    after_img = None
    if capture_after and before_img is not None:
        time.sleep(0.3)  # 等待渲染
        hwnd = find_window()
        if hwnd:
            after_img = capture(hwnd)

    # 像素 diff
    if before_img and after_img:
        diff = pixel_diff(before_img, after_img, threshold=pixel_threshold)
        result["diff"].update({
            "changed": diff["changed"],
            "bbox": diff["bbox"],
            "diff_ratio": diff["diff_ratio"],
            "changed_pixels": diff["changed_pixels"],
        })

        if not diff["changed"]:
            result["diff"]["description"] = "无变化"
        elif workdir:
            os.makedirs(workdir, exist_ok=True)
            try:
                desc = full_diff(before_img, after_img, workdir, verify=True)["description"]
                result["diff"]["description"] = desc
            except Exception as e:
                result["diff"]["description"] = f"识图失败: {e}"

    return result


def click_ui_button(title: str, exe: str | None = None) -> dict:
    """
    通过 UIA 点击工具界面按钮。

    用于 Lua API 无法覆盖的操作（如文件对话框、弹窗确认）。

    参数:
      title: 按钮标题文本
      exe: 工具路径（用于窗口查找）

    返回:
      {"ok": bool, "message": str}
    """
    window = uia_connect()
    if window is None:
        return {"ok": False, "message": "未找到 DST Mod Tool 窗口"}

    try:
        control = get_control(window, title=title)
        if control is None:
            return {"ok": False, "message": f"未找到标题为 '{title}' 的控件"}

        click_control(control)
        return {"ok": True, "message": f"已点击: {title}"}
    except Exception as e:
        return {"ok": False, "message": f"点击失败: {e}"}


def inspect_doc(exe: str | None = None) -> LuaResult:
    """查看当前文档完整状态"""
    return run_lua_file("inspect_doc.lua", exe=exe)


def import_resources(paths: list[str], exe: str | None = None, label: str | None = None) -> LuaResult:
    """
    导入资源文件。

    参数:
      paths: 资源文件路径列表
      exe: 工具路径
      label: 操作标签

    返回: LuaResult
    """
    label_env = label or f"导入资源: {len(paths)} 个文件"
    # 将路径列表直接内联为 Lua 表（DST Mod Tool 沙箱无 os.setenv）
    # Windows 路径含反斜杠，用 Lua 长字符串 [[...]] 避免 \t / \n 转义
    paths_lua = "{ " + ", ".join(f'[[{p}]]' for p in paths) + " }"
    script = f"""
        doc:set_label({label_env!r})
        local paths = {paths_lua}
        print("导入资源:", #paths, "个文件")
        for _, p in ipairs(paths) do
            print("  -", p)
        end
        doc:import_resources(paths)
        print("导入完成")
    """
    return lua_run(script, exe=exe)


def select_animation(name: str, bank_name: str | None = None, exe: str | None = None) -> LuaResult:
    """
    选择动画。

    参数:
      name: 动画名称
      bank_name: 可选，Bank 名称（不指定则遍历所有 Bank）
      exe: 工具路径
    """
    old_anim = os.environ.get("DST_ANIMATION_NAME")
    old_bank = os.environ.get("DST_BANK_NAME")
    os.environ["DST_ANIMATION_NAME"] = name
    try:
        if bank_name is not None:
            os.environ["DST_BANK_NAME"] = bank_name
        return run_lua_file("select_animation.lua", exe=exe)
    finally:
        if old_anim is None:
            os.environ.pop("DST_ANIMATION_NAME", None)
        else:
            os.environ["DST_ANIMATION_NAME"] = old_anim
        if old_bank is None and bank_name is not None:
            os.environ.pop("DST_BANK_NAME", None)
        elif old_bank is not None:
            os.environ["DST_BANK_NAME"] = old_bank
        elif bank_name is None:
            os.environ.pop("DST_BANK_NAME", None)


def select_frame(idx: int, animation_name: str | None = None, bank_name: str | None = None, exe: str | None = None) -> LuaResult:
    """
    选择帧（0-based）。

    参数:
      idx: 帧索引（0-based）
      animation_name: 动画名称（必需，用于定位帧所属动画）
      bank_name: 可选，Bank 名称
      exe: 工具路径

    注意: 选择帧需要先确定动画上下文，animation_name 不能为 None。
    """
    old_frame = os.environ.get("DST_FRAME_INDEX")
    old_anim = os.environ.get("DST_ANIMATION_NAME")
    old_bank = os.environ.get("DST_BANK_NAME")

    os.environ["DST_FRAME_INDEX"] = str(idx)
    try:
        if animation_name is not None:
            os.environ["DST_ANIMATION_NAME"] = animation_name
        if bank_name is not None:
            os.environ["DST_BANK_NAME"] = bank_name
        return run_lua_file("select_frame.lua", exe=exe)
    finally:
        if old_frame is None:
            os.environ.pop("DST_FRAME_INDEX", None)
        else:
            os.environ["DST_FRAME_INDEX"] = old_frame
        if old_anim is None:
            os.environ.pop("DST_ANIMATION_NAME", None)
        else:
            os.environ["DST_ANIMATION_NAME"] = old_anim
        if old_bank is None:
            os.environ.pop("DST_BANK_NAME", None)
        else:
            os.environ["DST_BANK_NAME"] = old_bank


def export_build(out_path: str, animation_name: str, bank_name: str | None = None,
                 frame_index: int | None = None, max_dim: int = 1024,
                 build_name: str | None = None, exe: str | None = None) -> LuaResult:
    """
    导出动画帧序列为 PNG。

    参数:
      out_path:        导出目录（必须不存在，工具原子创建）
      animation_name:  动画名称
      bank_name:       可选，Bank 名称
      frame_index:     可选，定位到指定帧（0-based）
      max_dim:         导出图片最大边长（默认 1024）
      build_name:      可选，指定 Build 名称
      exe:             工具路径
    """
    old_export_path = os.environ.get("DST_EXPORT_PATH")
    old_anim = os.environ.get("DST_ANIMATION_NAME")
    old_bank = os.environ.get("DST_BANK_NAME")
    old_frame = os.environ.get("DST_FRAME_INDEX")
    old_max_dim = os.environ.get("DST_EXPORT_MAX_DIM")
    old_build = os.environ.get("DST_EXPORT_BUILD")

    os.environ["DST_EXPORT_PATH"] = out_path
    os.environ["DST_ANIMATION_NAME"] = animation_name
    try:
        if bank_name is not None:
            os.environ["DST_BANK_NAME"] = bank_name
        if frame_index is not None:
            os.environ["DST_FRAME_INDEX"] = str(frame_index)
        os.environ["DST_EXPORT_MAX_DIM"] = str(max_dim)
        if build_name is not None:
            os.environ["DST_EXPORT_BUILD"] = build_name
        return run_lua_file("export_build.lua", exe=exe)
    finally:
        if old_export_path is None:
            os.environ.pop("DST_EXPORT_PATH", None)
        else:
            os.environ["DST_EXPORT_PATH"] = old_export_path
        if old_anim is None:
            os.environ.pop("DST_ANIMATION_NAME", None)
        else:
            os.environ["DST_ANIMATION_NAME"] = old_anim
        if old_bank is None:
            os.environ.pop("DST_BANK_NAME", None)
        else:
            os.environ["DST_BANK_NAME"] = old_bank
        if old_frame is None:
            os.environ.pop("DST_FRAME_INDEX", None)
        else:
            os.environ["DST_FRAME_INDEX"] = old_frame
        if old_max_dim is None:
            os.environ.pop("DST_EXPORT_MAX_DIM", None)
        else:
            os.environ["DST_EXPORT_MAX_DIM"] = old_max_dim
        if old_build is None:
            os.environ.pop("DST_EXPORT_BUILD", None)
        else:
            os.environ["DST_EXPORT_BUILD"] = old_build


def undo(n: int = 1, exe: str | None = None) -> LuaResult:
    """撤销操作"""
    old = os.environ.get("DST_UNDO_STEPS")
    os.environ["DST_UNDO_STEPS"] = str(n)
    try:
        return run_lua_file("undo.lua", exe=exe)
    finally:
        if old is None:
            os.environ.pop("DST_UNDO_STEPS", None)
        else:
            os.environ["DST_UNDO_STEPS"] = old


def redo(n: int = 1, exe: str | None = None) -> LuaResult:
    """重做操作"""
    old = os.environ.get("DST_REDO_STEPS")
    os.environ["DST_REDO_STEPS"] = str(n)
    try:
        return run_lua_file("redo.lua", exe=exe)
    finally:
        if old is None:
            os.environ.pop("DST_REDO_STEPS", None)
        else:
            os.environ["DST_REDO_STEPS"] = old


def full_report(result: dict) -> str:
    """
    生成人类可读的操作报告。

    参数:
      result: verify_operation() 返回的字典

    返回: str，格式化的报告文本
    """
    lines = []
    lines.append(f"=== 操作: {result['operation']} ===")

    lua = result["lua"]
    if lua.get("ok"):
        lines.append("✅ Lua 执行成功")
        if lua.get("changed"):
            lines.append("📝 文档已修改")
        output = lua.get("output", [])
        if output:
            lines.append("📤 输出:")
            for line in output:
                lines.append(f"  {line}")
    else:
        lines.append(f"❌ Lua 执行失败: {lua.get('error', {}).get('message', '未知错误')}")

    diff = result.get("diff", {})
    if diff.get("captured"):
        if diff.get("description"):
            lines.append(f"🖼️  视觉变化: {diff['description']}")
            if diff.get("bbox"):
                x1, y1, x2, y2 = diff["bbox"]
                lines.append(f"   变化区域: ({x1},{y1})-({x2},{y2})")
                lines.append(f"   变化比例: {diff.get('diff_ratio', 0):.2%}")
    elif not lua.get("ok"):
        lines.append("🖼️  未截图（操作失败）")
    else:
        lines.append("🖼️  未截图（跳过验证）")

    return "\n".join(lines)


# CLI 入口
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "run":
        script_text = sys.argv[2] if len(sys.argv) > 2 else ""
        if not script_text:
            script_text = sys.stdin.read()
        result = run_lua(script_text)
        print(json.dumps({
            "ok": result.ok,
            "output": result.output,
            "error": result.error,
            "changed": result.changed,
            "before_revision": result.before_revision,
            "after_revision": result.after_revision,
        }, ensure_ascii=False, indent=2))

    elif cmd == "inspect":
        result = inspect_doc()
        print(json.dumps({
            "ok": result.ok,
            "output": result.output,
            "error": result.error,
        }, ensure_ascii=False, indent=2))

    elif cmd == "click":
        if len(sys.argv) < 3:
            print("用法: workflow.py click <button_title>", file=sys.stderr)
            sys.exit(1)
        result = click_ui_button(sys.argv[2])
        print(json.dumps(result, ensure_ascii=False, indent=2))

    elif cmd == "report":
        result = json.loads(sys.stdin.read())
        print(full_report(result))

    else:
        print(f"未知命令: {cmd}", file=sys.stderr)
        print("可用命令: run, inspect, click, report", file=sys.stderr)
        sys.exit(1)

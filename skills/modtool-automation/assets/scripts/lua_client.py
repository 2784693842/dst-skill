#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""DST Mod Tool Lua 脚本客户端

调用方式:
  方式1: lua_client run "print(1+1)"
  方式2: lua_client run-file script.lua
  方式3: lua_client run-stdin  (从 stdin 读取 Lua 源码)

返回: 结构化 LuaResult，包含:
  - ok: bool
  - output: list[str]   # print() 的输出行
  - error: dict | None  # 错误信息
  - document: dict      # changed/before_revision/after_revision
  - stats: dict         # elapsed_micros 等
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass, field, asdict

# 重新配置 stdout 编码，确保中文输出不乱码
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ---------------------------------------------------------------------------
# 路径解析
# __file__ 所在目录:  assets/scripts/
# 上一级:             assets/
# 再上一级:          skill 根目录 (modtool-automation/)
# 再上一级:          skills/
# 再上一级:          项目根目录
# ---------------------------------------------------------------------------
_SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))          # assets/scripts/
_SKILL_DIR = os.path.dirname(_SCRIPTS_DIR)                          # modtool-automation/
_SKILLS_DIR = os.path.dirname(_SKILL_DIR)                           # skills/
_PROJECT_DIR = os.path.dirname(_SKILLS_DIR)                         # 项目根

# Mod Tool 默认路径，可通过环境变量 DST_MOD_TOOL_EXE 覆盖
_DEFAULT_MOD_TOOL_EXE = os.path.join("D:\\", "starve", "DST Mod Tool.exe")


def _resolve_exe(exe: str | None) -> str:
    """解析 Mod Tool exe 路径。

    优先级: 显式传入 > 环境变量 DST_MOD_TOOL_EXE > 默认路径
    """
    if exe is not None:
        return exe
    env_exe = os.environ.get("DST_MOD_TOOL_EXE")
    if env_exe:
        return env_exe
    return _DEFAULT_MOD_TOOL_EXE


# ===================================================================
# LuaResult 数据类
# ===================================================================
@dataclass
class LuaResult:
    """DST Mod Tool 执行 Lua 脚本后的结构化结果。"""

    ok: bool
    output: list[str]
    error: dict | None = None
    document: dict = field(default_factory=dict)
    stats: dict = field(default_factory=dict)
    raw: dict = field(default_factory=dict)  # 原始 JSON 响应，调试用

    # ------------------------------------------------------------------
    # 便捷方法
    # ------------------------------------------------------------------
    def print_output(self) -> str:
        """将所有 print() 输出行合并为字符串。"""
        return "\n".join(self.output)

    @property
    def changed(self) -> bool:
        """文档是否发生变更。"""
        return self.document.get("changed", False)

    @property
    def before_revision(self) -> int:
        """变更前的文档修订号。"""
        return self.document.get("before_revision", 0)

    @property
    def after_revision(self) -> int:
        """变更后的文档修订号。"""
        return self.document.get("after_revision", 0)

    def to_dict(self) -> dict:
        """序列化为字典（方便 JSON 输出）。"""
        return asdict(self)


# ===================================================================
# 核心函数
# ===================================================================
def _parse_response(stdout: str, stderr: str = "", returncode: int = 0) -> LuaResult:
    """解析 Mod Tool 的 JSON 响应。

    如果 stdout 不是合法 JSON，返回一个 ok=False 的错误结果。
    """
    try:
        data = json.loads(stdout)
    except (json.JSONDecodeError, TypeError):
        return LuaResult(
            ok=False,
            output=[],
            error={
                "message": f"subprocess exited with code {returncode}, stderr: {stderr}"
            },
        )

    # 提取 response.report
    report = data.get("response", {}).get("report", {})
    ok = bool(report.get("ok", False))

    # output: 可能是 list[str] 也可能是 str
    raw_output = report.get("output", [])
    if isinstance(raw_output, str):
        output_lines: list[str] = [raw_output]
    elif isinstance(raw_output, list):
        output_lines = [str(line) for line in raw_output]
    else:
        output_lines = []

    error = report.get("error", None)
    if error is not None and not isinstance(error, dict):
        error = {"message": str(error)}

    document = report.get("document", {})
    stats = report.get("stats", {})

    return LuaResult(
        ok=ok,
        output=output_lines,
        error=error,
        document=document,
        stats=stats,
        raw=data,
    )


def run(script_text: str, exe: str | None = None, timeout: int = 30) -> LuaResult:
    """通过 subprocess 调用 DST Mod Tool 执行一段 Lua 脚本。

    Args:
        script_text: Lua 源码字符串
        exe: Mod Tool 可执行文件路径，None 时使用默认路径
        timeout: 超时时间（秒）

    Returns:
        LuaResult 结构化结果
    """
    resolved_exe = _resolve_exe(exe)
    stdin_bytes = script_text.encode("utf-8")

    try:
        proc = subprocess.run(
            [resolved_exe, "script", "--stdin"],
            input=stdin_bytes,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return LuaResult(
            ok=False,
            output=[],
            error={"message": "timeout", "code": timeout},
        )

    stdout = proc.stdout or ""
    stderr = proc.stderr or ""
    return _parse_response(stdout, stderr=stderr, returncode=proc.returncode)


def run_file(file_path: str, exe: str | None = None, timeout: int = 30) -> LuaResult:
    """从文件读取 Lua 脚本并执行。

    Args:
        file_path: Lua 脚本文件路径
        exe: Mod Tool 可执行文件路径
        timeout: 超时时间（秒）

    Returns:
        LuaResult 结构化结果

    Raises:
        FileNotFoundError: 脚本文件不存在
    """
    with open(file_path, "r", encoding="utf-8") as f:
        script_text = f.read()
    return run(script_text, exe=exe, timeout=timeout)


def run_stdin(exe: str | None = None, timeout: int = 120) -> LuaResult:
    """从标准输入读取 Lua 脚本并执行。

    Args:
        exe: Mod Tool 可执行文件路径
        timeout: 超时时间（秒）

    Returns:
        LuaResult 结构化结果
    """
    script_text = sys.stdin.read()
    return run(script_text, exe=exe, timeout=timeout)


# ===================================================================
# CLI 入口
# ===================================================================
def _print_result(result: LuaResult, as_json: bool = False) -> None:
    """打印执行结果。

    Args:
        result: LuaResult 结果对象
        as_json: True 时输出 JSON，False 时输出纯文本
    """
    if as_json:
        print(json.dumps(result.to_dict(), ensure_ascii=False, indent=2))
    else:
        # 纯文本模式：打印 output 行，如有错误则追加
        if result.output:
            sys.stdout.write(result.print_output())
            if not result.output[-1].endswith("\n"):
                sys.stdout.write("\n")
        if result.error:
            sys.stderr.write(
                f"ERROR: {json.dumps(result.error, ensure_ascii=False)}\n"
            )
        if not result.ok:
            sys.exit(1)


def main(argv: list[str] | None = None) -> None:
    """CLI 主入口。

    支持的子命令:
        run <script_text>         直接执行 Lua 源码字符串
        run-file <file_path>      从文件读取并执行
        run-stdin                 从 stdin 读取并执行

    全局选项:
        --json                    以 JSON 格式输出结果
    """
    if argv is None:
        argv = sys.argv[1:]

    if not argv:
        sys.stderr.write("用法: lua_client {run|run-file|run-stdin} [选项]\n")
        sys.exit(1)

    # 解析 --json 选项
    as_json = "--json" in argv
    argv = [arg for arg in argv if arg != "--json"]

    subcommand = argv[0]

    try:
        if subcommand == "run":
            if len(argv) < 2:
                sys.stderr.write("用法: lua_client run <script_text> [--json]\n")
                sys.exit(1)
            script_text = argv[1]
            result = run(script_text)

        elif subcommand == "run-file":
            if len(argv) < 2:
                sys.stderr.write("用法: lua_client run-file <file_path> [--json]\n")
                sys.exit(1)
            file_path = argv[1]
            result = run_file(file_path)

        elif subcommand == "run-stdin":
            result = run_stdin()

        else:
            sys.stderr.write(f"未知子命令: {subcommand}\n")
            sys.stderr.write("支持的子命令: run, run-file, run-stdin\n")
            sys.exit(1)

        _print_result(result, as_json=as_json)

    except FileNotFoundError as e:
        sys.stderr.write(f"文件未找到: {e}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"未预期错误: {e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()

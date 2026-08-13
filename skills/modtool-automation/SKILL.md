---
name: modtool-automation
description: Use when automating DST Mod Tool via Lua script injection, screenshot diff-detection, UIA-based GUI control, or visual verification of animation import/edit/export operations. 中文触发：DST Mod Tool 自动化、Lua 脚本执行、截图差异对比、动画导入/导出自动化、视觉验证。信号：script --stdin、lua_client、screenshot、diff_detector、UIA、animation import、Mod Tool。
---

# DST Mod Tool 自动化

通过 Lua 脚本注入 + 截图差异检测 + UIA 精确控件操控，自动化控制 DST Mod Tool（Spine/DST 动画编辑器）。

**当前版本**：1.1.13（2026-08-13 更新，SHA256: `42db01835931a7d7b24def4b5813c8f29cc26ad4c2c48bd5c8a50dc568ccae83`）

## 核心设计原则：Lua 优先，截图验证兜底

DST Mod Tool 实测支持 `script --stdin` 子命令，从 stdin 读取 Lua 源码后执行，向 stdout 输出结构化 JSON。这是 **唯一可靠的自动化入口**。1.1.13 起新增 `--help` / `-h`（顶层）和 `script --help [--lang en|zh-CN]`（脚本 API 参考）子命令。所有其他 `--flag` 参数（`--version`、`--batch`、`--headless`、`--run` 等）均无效，会直接启动 GUI。

**1.1.13 关键变化**：
- 新增 `--help`/`-h`（顶层帮助）、`script --help [--lang en|zh-CN]`（50KB Lua API 参考）
- 新增 `tool:save_document` / `tool:save_document_as` / `tool:open_document` — **可直接通过 Lua 命令打开/保存 .dmt 文件**，无需再依赖 GUI 文件对话框
- 新增完整的 Build/Bank 树 API（Build/Symbol/SymbolFrame/Bank/Animation/AnimFrame/Element 全生命周期）
- 新增裁剪 `animation:crop`、对比 `utils.compare_anim_frames`、仿射工具 `utils.affine`
- 新增 Anti-Follow / Follow Symbol / 搜索替换 Elements / 碰撞重算
- 新增 DMT 工作区命令：`save_document_as` 原子保存，`open_document` 为终端命令
- 安全限额明确：Lua 内存 64 MiB、指令 1000 万、执行时间 5 秒

| 能力 | 入口 | 精确度 | 成本 |
|------|------|--------|------|
| 文档操作（导入/选择/播放/撤销/导出/开存 .dmt） | `script --stdin` (Lua API) | ✅ 事务级 | ~340μs/次 |
| 动画编辑（裁剪/对比/仿射/跟随符号） | `script --text/--file` | ✅ 事务级 | ~340μs/次 |
| 精确点击 UI 控件 | UIA `click_input()` | ✅ 1px | ~50ms |
| 截图验证操作结果 | ImageGrab + 像素 diff | ✅ 亚像素 | ~50ms |
| 语义描述变化 | caption-vision.ps1 | ✅ 语义级 | ~2s |
| 文件对话框 / 弹窗确认 | 无 Lua API | ⚠️ 需 UIA + 截图 | 依赖 UIA |

**Lua 是主路径，截图识别和模拟操作只在 Lua 无法表达的场景才启用。**

## 能力范围

- 通过 Lua API 执行任意文档操作（导入资源、选择动画/帧、播放、撤销/重做、导出）
- 操作前后截图对比，自动定位变化区域（像素级 diff）
- 语义级变化描述（调用 sensenova-vision 识图）
- UIA 控件精确操控（点击、选择、滚动）
- DPI-aware 坐标系转换（client ↔ screen ↔ logical）

## 工作流

### 主路径：Lua 脚本执行

```
① 启动/连接工具
   命令: DST Mod Tool.exe <动画文件.zip>
   或:   通过 Lua 命令 tool:open_document("/abs/path.dmt") 打开已有 .dmt
   或:   python uia_client.py info  (连接已运行的实例)

② 执行 Lua 脚本
   命令: python lua_client.py run "doc:set_label('test'); print(document_revision)"
   返回: {"ok": true, "output": ["4"], "document": {"changed": false}}

③ 操作 .dmt 工作区（1.1.13 新增）
   保存:  tool:save_document()          -- 保存到已绑定的 .dmt
   另存:  tool:save_document_as("/abs")  -- 原子保存并绑定新路径
   打开:  tool:open_document("/abs")    -- 终端命令，替换工作区（不能与编辑混用）

④ 验证操作结果（可选）
   python diff_detector.py full before.png after.png

⑤ 报告
   整合 Lua output + diff 描述 → 自然语言报告
```

### 截图差异检测（三级递进）

```
L1: pixel_diff(before, after, threshold=30)
    → 纯本地 PIL 操作，~50ms
    → 返回 {changed: bool, bbox: tuple, diff_ratio: float}
    → 判断：变了还是没变

L2: capture_region(after, bbox)
    → 只截取变化区域
    → 降低全屏噪声（gpui 是 GPU 渲染，动画播放时每帧都有像素变化）

L3: semantic_diff(before, after)
    → 两张图同时传给 caption-vision.ps1
    → prompt: "对比图A和图B，A是操作前，B是操作后，描述B的具体变化"
    → 返回语义描述文本
```

**实际工作流**：L1 → 有变化才走 L2+L3，无变化直接跳过识图（省一次 API 调用）。

### UIA 控件操控（Lua 无法覆盖的场景）

```
① connect()  → 获取 pywinauto WindowSpecification
② get_control(w, title="Play") → 精确定位控件
③ click_control(btn) → SendInput 模拟点击（pywinauto 自动处理坐标转换）
```

gpui/Zed 框架通过 UIA 暴露完整控件树（47 Buttons + 1 Slider + 1 MenuBar），每个控件都有精确边界矩形。

## 接口锚点

### 顶层 CLI

```bash
# 1.1.13 新增：--help / -h 正常工作，打印帮助文本后退出（不启动 GUI）
"D:\starve\DST Mod Tool.exe" --help

# 1.1.13 新增：script --help [--lang en|zh-CN] 打印完整 Lua API 参考（~50KB）
"D:\starve\DST Mod Tool.exe" script --help
"D:\starve\DST Mod Tool.exe" script --help --lang zh-CN

# 打开动画资源或 .dmt 工作区（仍会启动 GUI）
"D:\starve\DST Mod Tool.exe" <动画文件.zip>

# 无效参数（启动 GUI，不输出）：--version、/?、help
```

### Lua 脚本接口（实测验证）

```bash
# 方式1：内联脚本
"D:\starve\DST Mod Tool.exe" script --text "print(1+1)"

# 方式2：从文件读取（必须为绝对路径）
"D:\starve\DST Mod Tool.exe" script --file "C:\abs\path\script.lua"

# 方式3：从 stdin 读取（lua_client.py 使用此方式）
printf 'print(document_revision)' | "D:\starve\DST Mod Tool.exe" script --stdin
```

**响应格式**（JSON，stdout）：
```json
{
  "version": 1,
  "request_id": "...",
  "response": {
    "type": "script",
    "report": {
      "ok": true,
      "output": ["print 输出行"],
      "error": null,
      "document": {"changed": false, "before_revision": 4, "after_revision": 4},
      "stats": {"elapsed_micros": 340, "lua_memory_bytes": 26080}
    }
  }
}
```

### 环境变量接口（Lua 脚本内获取参数）

**机制**：Python 侧 `subprocess.run()` 继承调用进程的 `os.environ`，Lua 脚本用 `os.getenv()` 读取。Lua 5.1 本身**没有** `os.setenv`。

| 变量 | 设置方 | 用途 |
|------|--------|------|
| `DST_RESOURCE_PATHS` | Python | 导入资源路径（分号分隔） |
| `DST_ANIMATION_NAME` | Python | 要选择的动画名称 |
| `DST_FRAME_INDEX` | Python | 要选择的帧索引（0-based） |
| `DST_UNDO_STEPS` / `DST_REDO_STEPS` | Python | 撤销/重做步数 |
| `DST_EXPORT_PATH` | Python | 导出目录路径 |
| `DST_OPERATION_LABEL` | Python | 操作历史标签 |

> **注意**：`import_resources` 因路径较多，workflow.py 直接内联进 Lua 源码，不经过环境变量。

### UIA 接口（pywinauto）

- 窗口类名：`Zed::Window`
- 标题：`DST Mod Tool`
- 后端：必须 `backend='uia'`（Win32 后端不支持 gpui 自定义控件）
- 坐标：UIA 控件坐标 = client 坐标（相对客户区）
- DPI：`GetDpiForWindow(hwnd)` / 96.0

## 环境变量

| 变量 | 用途 |
|------|------|
| `DST_MOD_TOOL_EXE` | DST Mod Tool 可执行文件路径（默认 `D:\starve\DST Mod Tool.exe`） |

## 不变量

- **Lua 优先**：凡 Lua API 能做的事，不启用 GUI 模拟
- **diff 先于识图**：先像素 diff 定位变化，再截取变化区域识图，避免全屏噪声
- **UIA 坐标优先于模板匹配**：能 UIA 定位的控件不依赖截图识别坐标
- **DPI-aware 贯穿**：所有坐标转换必须经 `client_to_screen()` 或手动 DPI 缩放
- **截图只用于验证**：操作结果优先用 Lua 的 `document.changed`/`output` 验证，截图只做视觉确认
- **图片字节永不进入主模型上下文**：所有图片处理在外部脚本内完成

## 验证

- `lua_client.py run "print(1+1)"` → 返回 `{"ok": true, "output": ["2"]}`
- `screenshot.py info` → 打印窗口 hwnd、rect、dpi
- `screenshot.py capture "0,0,500,500"` → 截取前 500×500 区域
- `diff_detector.py compare a.png b.png` → 输出 diff_ratio 和 bbox
- `uia_client.py list` → 列出所有控件
- `uia_client.py click --title "Play"` → 点击 Play 按钮

## 按需资源

- Lua API 完整参考（从二进制提取）：`references/lua-api.md`
- JSON 响应协议：`references/json-envelope.md`
- 三套坐标系转换：`references/coordinate-systems.md`
- Lua 脚本模板：`assets/lua/`

# 审核背景：modtool-automation 及全技能体系审查

## 一、已发现的问题清单（来自 4 个审核 Agent）

### 🔴 阻断（5 个）

**B1** `inspect_doc.lua` 使用全局变量名而非 `tool.X`
- 文件：`skills/modtool-automation/assets/lua/inspect_doc.lua` 第 6-50 行
- 现状代码：
```lua
print("revision:", document_revision)         -- 错误：全局变量，不存在
print("is_empty:", document_is_empty)         -- 错误
if selection then ...                          -- 错误
if playback then ...                           -- 错误
if history then ...                            -- 错误
if hide_layers and #hide_layers > 0 then ...   -- 错误
if override_symbols and next(override_symbols) then ... -- 错误
```
- 正确做法（lua-api.md 第 88-95 行）：字段通过 `tool` 访问，如 `tool.document_revision`
- 证据：`references/lua-api.md` 第 501 行示例 `print("revision", tool.document_revision)`
- 后果：所有 7 个字段输出 nil，文档状态完全不可见
- 调用方：`workflow.py` 第 248 行 `inspect_doc()`

**B2** `select_animation.lua` 向 `tool:select_animation()` 传递字符串
- 文件：`skills/modtool-automation/assets/lua/select_animation.lua` 第 11 行
- 现状：`tool:select_animation(name)` — name 是 `os.getenv("DST_ANIMATION_NAME")` 返回的字符串
- 正确：应传 Animation handle（通过 `bank.animations:find("idle")` 获取）
- 证据：`lua-api.md` 第 74 行："参数为 Animation handle"；`script-help-1.1.13.md` 第 156 行示例用 handle
- 后果：Lua 运行时类型错误，脚本回滚
- 调用方：`workflow.py` 第 283 行、`export_build.lua` 第 15 行

**B3** `select_frame.lua` 向 `tool:select_frame()` 传递数值索引
- 文件：`skills/modtool-automation/assets/lua/select_frame.lua` 第 13 行
- 现状：`tool:select_frame(idx)` — idx 是 `tonumber(...)` 返回的数字
- 正确：应传 AnimFrame handle（通过 `animation.frames[1]` 获取）
- 证据：`lua-api.md` 第 75 行："参数为 AnimFrame handle，非数值索引"；`script-help-1.1.13.md` 第 162 行明确说明
- 后果：Lua 运行时类型错误，脚本回滚
- 调用方：`workflow.py` 第 296 行、`export_build.lua` 第 17 行

**B4** `export_build.lua` 是非功能占位符
- 文件：`skills/modtool-automation/assets/lua/export_build.lua` 第 21-26 行
- 现状：只 print，不执行任何导出 API
- 可用的导出 API（lua-api.md 第 191-192 行）：`animation:export_png_sequence()`、`animation:export_gif()`、`animation:export_apng()`
- 同时存在 B2/B3 的相同问题（第 15/17 行）
- SKILL.md 第 38 行将"导出"列为 Lua API 能力，但实际模板无法执行

**B5** `workflow.py` `open_file()` 使用不存在的 `--open` 参数
- 文件：`skills/modtool-automation/assets/scripts/workflow.py` 第 51、58 行
- 现状：
```python
cmd.append("--open")
cmd.append(file_path)
```
- 正确（cli-probe-1.1.13.txt 第 18-21 行）：`dst-app [FILES...]`，文件直接作为位置参数
- 后果：`--open` 被忽略，文件路径也被忽略，工具启动后不打开任何文件

### 🟡 警告（9 个）

**W1** `dst-shader-authoring` 章节结构不一致
- 用了 `## 执行流程`/`## 编写规则`/`## 验证清单` 而非标准 `## 工作流`/`## 不变量`/`## 验证`
- H1 为全英文 `# DST Shader Authoring`，其他均为中英混合

**W2** 45 个 dst-* 技能正文中零交叉引用
- creature-boss 声明涉及 prefab+brain+SG+combat，但正文未引用任何相关技能
- character-authoring 涉及台词/技能树，未引用 localization-speech/skilltree-authoring
- modtool-automation 与 dst-assets-animation-atlas 互不知晓

**W3** `skill-resources/` 未同步 modtool-automation
- modtool-automation 整个目录（19 个文件）缺失
- 另有 2 个旧文件缺失：`combat-contract.md`、`networking-prefab-template.lua`

**W4** `json-envelope.md` stats 字段表缺 `mutation_stages`

**W5** `lua-api.md` Element 字段表写 `frame_num`，主字段名应为 `frame`

**W6** `diff_detector.py` 硬编码依赖 sensenova-vision 但未声明，静默降级

**W7** `import_resource.lua` 模板与 workflow.py 导入方式矛盾（env var vs 内联）

**W8** 不变量部分不可验证

**W9** `/dst.md` 硬性要求第 5 条（DST 源码路径）不适用于 modtool-automation

### 🔴 路由问题

**R1** `/dst` 命令完全未路由 modtool-automation
- 48 个技能中 3 个未被路由：modtool-automation、sensenova-image、sensenova-vision
- 输入"DST Mod Tool 自动化"/"截图差异"/"UIA 控件"均错误回退到 dst-source-research

**R2** 编辑→编译→接入模组的完整链路无人覆盖
- modtool 编辑完后，如何把 anim zip 接入 DST 模组（声明 Asset、SetBank/SetBuild）？两个技能都没覆盖这条链路

---

## 二、涉及的文件与上下文

### 2.1 modtool-automation 技能结构
```
skills/modtool-automation/
├── SKILL.md                      # 主文档（201 行）
├── assets/
│   ├── lua/
│   │   ├── export_build.lua      # 占位符（B4）
│   │   ├── import_resource.lua   # env var 方式（W7）
│   │   ├── inspect_doc.lua       # 全局变量 bug（B1）
│   │   ├── redo.lua
│   │   ├── select_animation.lua  # 字符串参数 bug（B2）
│   │   ├── select_frame.lua      # 数字参数 bug（B3）
│   │   └── undo.lua
│   └── scripts/
│       ├── diff_detector.py      # 硬编码 sensenova-vision（W6）
│       ├── lua_client.py
│       ├── screenshot.py
│       ├── uia_client.py
│       └── workflow.py           # --open bug（B5）
└── references/
    ├── cli-probe-1.1.13.txt      # CLI 探测原始数据
    ├── coordinate-systems.md
    ├── json-envelope.md          # 缺 mutation_stages（W4）
    ├── lua-api.md                # frame_num 歧义（W5）
    └── script-help-1.1.13.md     # 原始 50KB 帮助文本
```

### 2.2 Lua API 关键字段（lua-api.md 第 70-95 行）
```
tool 只读字段（通过 tool.X 访问）：
- tool.document_revision
- tool.document_is_empty
- tool.document_path
- tool.selection
- tool.playback
- tool.history
- tool.hide_layers
- tool.override_symbols

tool 方法：
- tool:select_animation(animation)  — Animation handle
- tool:select_frame(frame)          — AnimFrame handle
- tool:play()/pause()/undo()/redo()
- tool:save_document()/save_document_as()/open_document()
```

### 2.3 DST Mod Tool CLI 用法（cli-probe-1.1.13.txt）
```
dst-app [FILES...]                              -- 位置参数打开文件
dst-app script (--file PATH | --text LUA | --stdin)
dst-app --help / -h                             -- 顶层帮助
dst-app script --help [--lang en|zh-CN]         -- API 参考
```
无 `--open` 子命令。

### 2.4 /dst 命令结构（.claude/commands/dst.md）
- 硬性要求 7 条（第 5 条是 DST 源码路径）
- 技能目录：45 个 dst-* 技能，分 4 组（核心基础/玩法/世界·UI·资源/工程化）
- 易混淆配对速查：7 对 dst-* 配对
- **未收录**：modtool-automation、sensenova-image、sensenova-vision

### 2.5 skill-resources/ 结构
- 47 个目录（与 skills/ 的 48 个差 1 个：modtool-automation）
- 是 skills/ 的发布镜像，供其他项目引用
- 历史上同步过：commit `1a2a7d9 chore: 同步 KTEX 工具修复到 skill-resources 镜像`

### 2.6 dst-shader-authoring 章节名对照
| 实际 | 标准 |
|------|------|
| `## 执行流程` | `## 工作流` |
| `## 选择管线` | (正文小节) |
| `## 编写规则` | `## 不变量` |
| `## 编译与部署` | (正文小节) |
| `## 后处理的特殊顺序` | (正文小节) |
| `## 验证清单` | `## 验证` |
| H1: `# DST Shader Authoring` | `# DST Shader 编写` |

### 2.7 全技能清单（48 个）
45 个 dst-* + 3 个非 dst-*（modtool-automation、sensenova-image、sensenova-vision）

---

## 三、修复约束

1. **最小改动原则**：每个修复应是最小可独立验证的变更
2. **兼容性**：Lua 模板修复后不能破坏现有调用方（workflow.py）
3. **一致性**：dst-shader-authoring 修复后应与 44 个其他 dst-* 技能的章节名一致
4. **可回退**：skill-resources/ 同步前应确认是否需要
5. **提交粒度**：按优先级分批提交，不要把所有修复混在一个 commit

---

## 四、需要审核的修复方案

以下方案需要多视角评估：

### 方案 A：修复 B1-B5（Lua 模板 + workflow.py）
- B1: `inspect_doc.lua` 全局变量 → `tool.X`
- B2: `select_animation.lua` 改为先 `doc.banks:find()` → `bank.animations:find()` 获取 handle
- B3: `select_frame.lua` 改为先获取 Animation handle → `animation.frames[idx+1]` 获取 frame handle
- B4: `export_build.lua` 实现真实 `animation:export_png_sequence()` 调用
- B5: `workflow.py` 去掉 `--open`，直接传位置参数

### 方案 B：修复 /dst 路由
- 新增 modtool-automation 条目（建议放在"世界 / UI / 资源"组末尾）
- 可选新增 sensenova-vision 条目
- 易混淆配对新增：Mod Tool 自动化 vs 动画资源
- 硬性要求第 5 条增加 modtool-automation 豁免

### 方案 C：修复 dst-shader-authoring 章节
- 重命名章节为标准名
- H1 改为中英混合

### 方案 D：同步 skill-resources/
- 复制 modtool-automation 到 skill-resources/
- 补回 combat-contract.md 和 networking-prefab-template.lua

### 方案 E：跨技能引用
- 在 atlas 侧引用 modtool-automation（编辑动画时）
- 在 modtool 侧引用 atlas（导出后接入模组）
- 可选：在 orchestrator 技能（creature-boss/character）中引用子技能
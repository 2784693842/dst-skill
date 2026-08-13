# Lua API 完整参考

以下 API 从 `DST Mod Tool.exe` 1.1.13 的 `script --help` 输出提取，已通过 `script --text` 实测验证。

---

## 执行规则

- 从应用内编辑器运行的脚本会先保存脚本文件；外部 `--file`/`--text`/`--stdin` 只执行提供的源码，不重写源文件
- 一次成功运行中的全部 `doc`/节点 API 编辑**在 undo 历史中合并为一条操作**
- 前面语句的变更立即可被后续语句观察到
- 语法错误 / 运行时错误 / 资源超限 → **整次运行回滚**
- 只读脚本（无工具方法调用）不产生撤销条目
- `tool` 命令排队，在 Lua + 文档提交成功后按调用顺序执行
- **延迟 `tool` 操作失败 → 后续延迟操作不执行，但已提交的文档变更不回滚**
- 调用方必须检查 `ok`、`error`、`tool_results`，不能只看文档 revision

## 基本约定

### 集合

- 所有集合为 **1-based 有序序列**，支持 `ipairs` 和长度运算符
- 集合为**只读视图**，禁止 `collection[i] = value`，用 `add`/`remove`/`move_to`/`move_to_parent`
- 文档集合不支持 `pairs`，必须用 `ipairs` 保持文档顺序
- 修改集合时逆序遍历
- `find(name)` 大小写不敏感；`SymbolFrame` 用 `find(num)` 精确查找

### 字段与方法

- 每个节点暴露**只读 `id`**（十进制字符串），文档内唯一且跨编辑/保存/撤销稳定
- 可写字段支持直接赋值和显式 setter（`set_frame_rate`/`set_pivot`/`set_bounds`/`set_reference`/`set_transform`）
- 显式 setter 返回 `true`/`false` 表示是否真正改变
- `clone()` 返回新副本，`add()` 返回新创建的节点
- `move_to(index)` 是 1-based，不环绕

### 文档层次结构

```
doc
├── builds               Build 集合
│   └── Build            └── symbols       Symbol 集合
│       └── Symbol       └── frames        SymbolFrame 集合
│           └── SymbolFrame
└── banks                Bank 集合
    └── Bank             └── animations    Animation 集合
        └── Animation    └── frames        AnimFrame 集合
            └── AnimFrame └── elements     Element 集合
                └── Element
```

---

## 全局对象

### `doc`

| 方法 | 说明 |
|------|------|
| `doc:set_label(label)` | 设置操作历史名称（最后调用生效） |
| `doc:import_resources(paths, options?)` | 导入资源（ZIP/DYN/BIN/SCML/GIF/PNG/Spine JSON/PSD），返回 `{builds: Build[], banks: Bank[]}` |
| `doc:search_replace_elements(scope, rule)` | 批量查找/替换/移除 Element |
| `doc:recalculate_collision(scope, options)` | 重算 AnimFrame 碰撞边界 |

**`import_resources` 约束**：
- 路径必须绝对，不接受目录和 `.dmt`
- 多个 PNG 按正常动画导入规则合并为一个图像序列
- Spine 色彩处理：`spine_colors = "bake"` 或 `"ignore"`；`spine_color_tolerance = 0.0..1.0`
- 返回的 handle 可立即编辑（同一事务内）

### `tool`

| 方法 | 说明 |
|------|------|
| `tool:select_animation(animation)` | 选择动画（参数为 Animation handle） |
| `tool:select_frame(frame)` | 选择帧并 seek（参数为 AnimFrame handle，非数值索引） |
| `tool:play()` | 播放 |
| `tool:pause()` | 暂停 |
| `tool:undo(steps?)` | 撤销（默认 1，0 为 no-op，超出静默 clamp） |
| `tool:redo(steps?)` | 重做（同上） |
| `tool:set_hide_layer(layer, enabled)` | 显示/隐藏图层 |
| `tool:set_override_symbol(source, target?)` | 符号覆盖（`target=nil` 清除） |
| `tool:save_document()` | 保存到已绑定的 .dmt |
| `tool:save_document_as(abs)` | 原子保存并绑定到新 .dmt 路径 |
| `tool:open_document(abs)` | **终端命令**：替换工作区（不能与编辑/撤销/导出混用） |

| 只读字段 | 类型 | 说明 |
|----------|------|------|
| `document_revision` | integer | 文档版本号 |
| `document_is_empty` | boolean | 文档是否为空 |
| `document_path` | string\|nil | 当前绑定的 .dmt 绝对路径 |
| `selection` | table | 选中状态（bank/animation/frame/element，nil 表示未选） |
| `playback` | table | 播放状态（playing/looping/frame_index/frame_count/fps） |
| `history` | table | 历史状态（entries/cursor/can_undo/can_redo） |
| `hide_layers` | string[] | 隐藏图层名列表（按名排序） |
| `override_symbols` | table | 符号覆盖映射 |

> `tool` 字段从脚本开始时的快照起步，选择/播放/历史/预览命令排队后在投影中即时更新。`open_document` 之后不能输出或执行其他命令。

---

## Build 树 API

### Build 集合

| API | 返回 | 说明 |
|-----|------|------|
| `#doc.builds` | integer | Build 数量 |
| `doc.builds[i]` | Build\|nil | 按顺序读取 |
| `doc.builds:find(name)` | Build\|nil | 大小写不敏感 |
| `doc.builds:add(name)` | Build | 追加（含默认 Symbol + SymbolFrame） |

### Build

| 字段 | 可写 | 说明 |
|------|------|------|
| `name` | ✅ | 名称 |
| `version` | ❌ | 版本号 |
| `hidden` | ✅ | 隐藏状态 |
| `symbols` | ❌ | Symbol 集合 |

| 方法 | 说明 |
|------|------|
| `build:set_name(name)` | 改名称 |
| `build:set_hidden(bool)` | 改隐藏 |
| `build:clone()` | 复制 |
| `build:move_to(i)` | 移动到位置 |
| `build:remove_unused_symbols()` | 移除未使用 Symbol |
| `build:remove()` | 删除 |

### Symbol

| 字段 | 可写 | 说明 |
|------|------|------|
| `name` | ✅ | 名称 |
| `hidden` | ✅ | 隐藏 |
| `frames` | ❌ | SymbolFrame 集合 |

| 方法 | 说明 |
|------|------|
| `symbol:set_name`/`set_hidden`/`clone`/`remove` | — |
| `symbol:move_to_parent(build)` | 移到另一个 Build 末尾 |
| `symbol:remove_unused_frames()` | 移除未使用帧 |

### SymbolFrame

| 字段 | 可写 | 说明 |
|------|------|------|
| `num` | ✅ | 帧号 |
| `duration` | ✅ | 持续帧数（≥1） |
| `pivot_x`/`pivot_y` | ✅ | 轴心 |
| `width`/`height` | ❌ | 图像尺寸（仅替换图像时改变） |
| `hidden` | ✅ | 隐藏 |

| 方法 | 说明 |
|------|------|
| `frame:set_num`/`set_duration`/`set_pivot`/`set_hidden` | — |
| `frame:replace_image(abs)` | 替换图像 |
| `frame:export_png(abs)` | 导出为 PNG |
| `frame:clone()`/`move_to_parent(symbol)`/`remove()` | — |

---

## Bank 树 API

### Bank 集合 / Bank

| API | 返回 |
|-----|------|
| `#doc.banks` | integer |
| `doc.banks:find(name)` | Bank\|nil |
| `doc.banks:add(name)` | Bank |

| 方法 | 说明 |
|------|------|
| `bank:set_name`/`clone`/`move_to`/`remove` | — |
| `bank:transform(t)` | 对所有动画应用变换 |
| `bank:anti_follow(opts)` | 对 Bank 中所有动画运行 Anti-Follow Symbol |

### Animation 集合 / Animation

| 方法 | 说明 |
|------|------|
| `animation:set_name`/`set_frame_rate`/`clone`/`move_to`/`move_to_parent`/`remove` | — |
| `animation:reverse()` | 反转帧序 |
| `animation:append(source)` | 追加帧副本 |
| `animation:transform(t)` | 变换 |
| `animation:anti_follow(opts)` | Anti-Follow |
| `animation:follow_symbol(child, opts)` | 跟随符号 |
| `animation:crop(points)` | 分割为 2-4 段（1-3 个零-based 边界点） |
| `animation:compare_transition(other, opts?)` | 对比过渡帧 |
| `animation:export_png_sequence(dir, opts?)` | 导出 PNG 序列 |
| `animation:export_gif(abs, opts?)` | 导出 GIF |
| `animation:export_apng(abs, opts?)` | 导出 APNG |

**导出选项**：
- `builds`：有序唯一 Build handle 数组
- `hide_layers`：字符串数组
- `override_symbols`：{源→目标} 映射
- `background`：`{r=0..255, g=0..255, b=0..255}`（省略=透明）
- `canvas`：`{center_x, center_y, width, height}`（1..4096）
- `scale` 或 `max_dimension`（二选一）

### AnimFrame

| 字段 | 可写 | 说明 |
|------|------|------|
| `x`/`y`/`width`/`height` | ✅ | 碰撞边界 |
| `elements` | ❌ | Element 集合 |

| 方法 | 说明 |
|------|------|
| `frame:set_bounds(x,y,w,h)` | 设置碰撞 |
| `frame:export_png(abs, opts?)` | 导出 |
| `frame:clone`/`move_to`/`move_to_parent`/`transform`/`remove` | — |

### Element

| 字段 | 可写 | 说明 |
|------|------|------|
| `symbol`/`frame_num` | ✅ | 符号名 + 帧号 |
| `layer` | ✅ | 图层 |
| `a`/`b`/`c`/`d`/`tx`/`ty` | ✅ | 仿射变换 |
| `draw_index` | ❌ | 1-based 绘制顺序（1=最前） |

| 方法 | 说明 |
|------|------|
| `element:set_reference(symbol, frame)` | 设置引用 |
| `element:set_layer(layer)` | 改图层 |
| `element:set_transform(a,b,c,d,tx,ty)` | 设置变换 |
| `element:place_above`/`place_below`/`bring_to_front`/`send_to_back` | 绘制顺序 |
| `element:clone`/`move_to`/`move_to_parent`/`transform`/`remove` | — |

> `element.frame` 是 Symbol Frame 的 `num`，不是 `symbol.frames` 的索引。

### Element 集合批量操作

```lua
anim_frame.elements:add({ symbol="body", frame=0, layer="body", tx=12, ty=-4 })

anim_frame.elements:update_many({
    { element = ..., tx = 10 },
    { element = ..., symbol = "hand", frame_num = 3, transform = {1,0,0,1,4,8} },
})
anim_frame.elements:transform_all({ type = "translate", x = 2, y = 0 })
```

---

## Animation 裁剪与对比

### `animation:crop(points)`

```lua
local pre, loop, pst = animation:crop({34, 112})[1], animation:crop({34,112})[2], animation:crop({34,112})[3]
```

- `points`：1-3 个**严格递增**的整数边界，零-based
- 边界 `N` 有效范围：`1..N-1`
- 每段至少 1 帧，最后一段包含末帧

### `utils.compare_anim_frames(left, right, opts?)`

```lua
local report = utils.compare_anim_frames(left, right, {
    tolerance = 0.00001,
    compare_bounds = true,
    compare_events = true,
    compare_references = true,
    compare_draw_order = true,
})
```

对比文档值（非渲染像素），忽略 Element ID。`compare_draw_order=false` 时按多重集匹配。

---

## Affine 工具

`utils.affine` 使用严格 `{a,b,c,d,tx,ty}` 表，提供：

| 方法 | 说明 |
|------|------|
| `utils.affine.multiply` | 矩阵乘法 |
| `utils.affine.compose` | 复合 |
| `utils.affine.inverse` | 逆矩阵 |
| `utils.affine.apply_point` | 应用到点 |
| `utils.affine.rotate_about` | 绕点旋转 |
| `utils.affine.decompose` | 分解 |
| `utils.affine.from_element` | 从 Element 获取 |

---

## 常用 Transform

Bank / Animation / AnimFrame / Element 的 `transform` 方法接受：

```lua
{ type = "translate", x = 10, y = -5 }
{ type = "rotate", degrees = 15 }
{ type = "scale", x = 1.2, y = 0.8 }
{ type = "affine", a = 1, b = 0, c = 0, d = 1, tx = 10, ty = -5 }
```

- `scale` 分量绝对值 ≥ 0.001，`affine` 线性部分必须可逆
- `translate`/`scale` 在 Bank/Animation/AnimFrame 上会同步更新碰撞中心；`rotate`/`affine` 不会 → 需手动调用 `doc:recalculate_collision`

---

## Anti-Follow Symbol

将非锚点 Element 转换为锚点的局部坐标系。

```lua
animation:anti_follow({
    symbol = "body",           -- 必需：锚点 Symbol 名
    frame_pattern = [[^0$]],   -- 可选：匹配 Element Frame 号的正则
    maintain_scale = false,    -- 可选：保留缩放
})
```

## Follow Symbol

将 `child` 动画的内容附加到 `target` 的匹配 Element 上。

```lua
local target = doc.banks:find("main").animations:find("idle")
local child  = doc.banks:find("effects").animations:find("glow")

target:follow_symbol(child, {
    symbol = "body",
    local_x = 0, local_y = 8,
    local_scale_x = 1, local_scale_y = 1,
    local_rotation_degrees = 0,
    inherit_position_x = true, inherit_position_y = true,
    inherit_scale = true, inherit_rotation = true,
    average_rotation = false,
    z_index_offset = 1,
    alignment = "unaligned",   -- "unaligned" | "relength_child" | "relength_target"
})
```

---

## 搜索替换 Elements

```lua
-- 精确替换
doc:search_replace_elements({animation}, {
    type = "reference",
    field = "symbol",          -- "symbol" | "layer"
    search = "old_body",
    replacement = "new_body",  -- nil 表示删除
})

-- 正则替换
doc:search_replace_elements({animation}, {
    type = "regex",
    query = {
        symbol = [[^(.*)_old$]],
        frame = [[^(\d+)$]],
        layer = [[^(.*)$]],
    },
    action = "replace",       -- "replace" | "remove" | "keep"
    replacement = {
        symbol = "$s1_new",
        frame = "$n1",
        layer = "$l1",
    },
})
```

- 三字段均需匹配（大小写不敏感，不 trim）
- 替换文本支持 `$sN`/`$nN`/`$lN`（Group 0 = 完整匹配）
- 结果 Frame 必须为非负整数

---

## 重算碰撞

```lua
doc:recalculate_collision({animation}, {
    builds = {build},          -- 必需
    hide_layers = {"shadow"},
    override_symbols = {swap_body = "body"},
    include_hidden = false,
})
```

`scope` 可为 Bank/Animation/AnimFrame，不接受 Element。

---

## 沙箱限制与安全限额

**可用的标准库**：`table`、`string`、`math`、`utf8`、基本 Lua 函数
**不可用的模块**：`io`、`os`（除 `os.getenv`）、`package`、`debug`
**文件访问**：仅限 `doc:import_resources`（输入）、`replace_image`（输入）、图像导出 API（输出）、`tool:save_document_as`/`open_document`

| 资源 | 默认上限 |
|------|----------|
| 源码大小 | 1 MiB |
| Lua 内存 | 64 MiB |
| 指令数 | 10,000,000 |
| 执行时间 | 5 秒 |
| 变更操作 | 10,000 |
| 输出行数 | 1,000 |
| 输出行长度 | 4 KiB |
| 单次解码图像 | 4 GiB |

超出任一限制 → 停止脚本，整次回滚。

---

## 常见错误

| 错误 | 正确做法 |
|------|----------|
| 用 `.` 调用方法（如 `build.set_name`） | 用冒号 `build:set_name("x")` |
| 给只读字段/集合赋值 | 用 setter 方法 |
| 混淆 Frame `num` 与集合索引 | `symbol.frames[1]` 是第一个元素；`symbol.frames:find(1)` 是 `num=1` 的帧 |
| 删除后访问对象 | 删除后不要再用 |
| 正向迭代时修改顺序 | 逆序遍历或先保存目标对象 |
| 假设新建父节点为空 | 新建 Build/Symbol/Bank 含默认子树 |
| 使用相对路径 | 全部必须绝对路径，Windows 用 `[[...]]` |

---

## IPC 协议 v1（命令行入口不可用时）

### 请求

```json
{
  "version": 1,
  "request_id": 42,
  "command": {
    "type": "run_lua",
    "source": { "type": "text", "value": "print(1+1)" }
    // 或 { "type": "file", "path": "/abs/path.lua" }
  }
}
```

### 响应

```json
{
  "version": 1,
  "request_id": 42,
  "response": {
    "type": "script",
    "report": {
      "ok": true,
      "origin": "external_ipc",
      "output": ["2"],
      "error": null,
      "document": { "changed": false, "before_revision": 7, "after_revision": 7, "history_label": null },
      "tool_results": [],
      "stats": { "elapsed_micros": 120, "instructions": 8, "mutation_stages": 0, "lua_memory_bytes": 24576 }
    }
  }
}
```

### 错误码

| Code | 说明 |
|------|------|
| `busy` | 另一脚本或互斥任务正在运行 |
| `invalid_source`/`read_source` | 源参数无效或文件读取失败 |
| `lua_syntax`/`lua_runtime` | Lua 语法/运行时错误 |
| `document_edit` | 文档编辑验证失败 |
| `resource` | 资源加载失败 |
| `limit_exceeded` | 超出资源限额 |
| `commit_failed` | 文档事务提交失败 |
| `tool_command_failed` | 延迟命令失败 |
| `cancelled` | 请求被取消 |
| `internal` | 内部执行服务错误 |

### 关键行为

- 服务端等待最多 60 秒，命令行客户端最多 65 秒
- 超时发出协作取消信号，**不会回滚已完成的文档提交**
- 同一时间只能运行一个脚本，与打开/保存/重置互斥
- 遇到 `busy` 应等待重试，不要并发重放

---

## AI Agent 工作流指南

1. **先读**：只读脚本建立 revision、Builds、Banks、当前选中状态
2. **精确解析目标**：用 `find` + `assert`，不猜名字/索引/帧号
3. **聚焦编辑**：设 History 名称，每次请求只做一个相关变更组
4. **分离 History 命令**：`undo`/`redo` 单独发请求，不与编辑混用
5. **检查报告**：`report.ok`、`report.error`、`report.document`、每个 `tool_results`
6. **必要时检查最终状态**：有延迟命令时用 `report.final_tool_state`（仅当脚本排队了选择/播放/预览/历史/开文档/存文档命令时出现）
7. **视觉验证**：导出尺寸受限的 PNG 后用视觉工具确认，不能仅靠退出码

```lua
-- 推荐：简洁的带标签摘要
print("revision", tool.document_revision)
print("builds", #doc.builds)
print("banks", #doc.banks)

-- 编辑动画
doc:set_label("Rename idle animation")
local bank = assert(doc.banks:find("wilson"), "Bank not found")
local anim = assert(bank.animations:find("idle"), "Animation not found")
anim.name = "idle_loop"

-- 渲染预览
local frame = assert(anim.frames[1], "No frames")
frame:export_png([[/tmp/preview.png]], { max_dimension = 1024 })
```

### Agent Checklist

- ✅ 全部使用绝对路径，Windows 用 `[[...]]`
- ✅ 编辑前解析目标，编辑后用只读请求验证
- ✅ 给用户可见的编辑设清晰的 History label
- ✅ 延迟命令后检查 `report.final_tool_state`（如存在）
- ✅ 不把文档 revision 不变当作 tool 命令成功的依据
- ✅ 不忽略 `tool_results`
- ✅ 不将 undo/redo 与文档编辑混在一个请求
- ✅ 不重复使用已有的 PNG 序列输出目录
- ✅ 不凭 IPC 输出推断图像内容，必须打开检查
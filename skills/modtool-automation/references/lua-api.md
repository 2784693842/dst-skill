# Lua API 完整参考

以下 API 从 `DST Mod Tool.exe`（版本 1.1.13）的 `script --help` 输出提取。1.1.12 的实测验证结论仍适用，1.1.13 新增了完整的文档层次结构和工具对象参考。

## 全局对象

### `doc` — LuaDocument userdata

代表当前动画文档。不可直接遍历，通过方法访问。

| 方法 | 参数 | 用途 |
|------|------|------|
| `doc:set_label(label)` | `string` | 设置操作历史名称（undo 时显示） |
| `doc:import_resources(paths, options?)` | `string[]`, `table?` | 导入资源（ZIP/DYN/BIN/SCML/GIF/PNG/Spine JSON/PSD） |
| `doc:replace_image(...)` | — | 替换图像 |
| 导出 API | — | 图像/动画导出 |

**约束**：
- 路径必须为绝对路径
- 导出目录必须不存在（工具原子写入）
- `doc:import_resources` 是唯一的文件输入入口

### `tool` — 工具命令对象

提交脚本后执行的延迟命令。

| 方法 | 参数 | 用途 |
|------|------|------|
| `tool:select_animation(name)` | `string` | 选择动画 |
| `tool:select_frame(idx)` | `integer` | 选择帧（0-based） |
| `tool:play()` | — | 播放当前动画 |
| `tool:pause()` | — | 暂停 |
| `tool:undo(n?)` | `integer?` | 撤销（默认 1 步） |
| `tool:redo(n?)` | `integer?` | 重做（默认 1 步） |
| `tool:set_hide_layer(layer, enabled)` | `string, boolean` | 隐藏图层 |
| `tool:set_override_symbol(source, target?)` | `string, string?` | 符号覆盖 |

## 只读字段

| 字段 | 类型 | 用途 |
|------|------|------|
| `document_revision` | `integer` | 文档版本号，每次修改递增 |
| `document_is_empty` | `boolean` | 文档是否为空 |
| `selection` | `table` | 当前选中状态（bank/animation/frame/element） |
| `playback` | `table` | 播放状态（playing/looping/frame_index/frame_count/fps） |
| `history` | `table` | 历史状态（entries/cursor/can_undo/can_redo） |
| `hide_layers` | `string[]` | 隐藏图层列表 |
| `override_symbols` | `table` | 符号覆盖映射 |

## 标准函数

| 函数 | 用途 |
|------|------|
| `print(...)` | 输出到 stdout JSON 的 `report.output` 数组，参数用制表符连接 |
| `os.getenv(name)` | 获取环境变量（参数由 Python 侧 `os.environ` 设置，Lua 5.1 无 `os.setenv`） |
| `pairs()` / `ipairs()` | 遍历 table |
| `tonumber()` / `tostring()` | 类型转换 |

## 沙箱限制

- ❌ `package` 模块不可用
- ❌ `debug` 模块不可用
- ❌ 不能自由访问文件系统
- ❌ 不能启动外部进程
- ✅ `os.getenv()` 可用
- ✅ `print()` 可用（输出到 JSON 响应）
- ✅ `string` / `table` / `math` 标准库可用

**文件访问仅限**：`doc:import_resources`（输入）、`replace_image` 和图像导出 API（输出）。

## 事务性保证

- 语法/运行时错误 → 整次运行回滚，不产生任何变更
- 只读脚本（无工具方法调用）不产生撤销条目
- `undo`/`redo` 不能与文档修改混用在同一脚本中
- 资源限制：指令数、内存超限则整次回滚
- 延迟工具操作失败 → 后续延迟操作不执行，但已提交的文档变更不回滚
- 调用方必须检查 `ok`、`error`、`tool_results` 三个字段，不能只看文档 revision

## 文档层次结构（1.1.13 新增）

```
doc
├── builds                # Build 集合
│   └── Build
│       └── symbols       # Symbol 集合
│           └── Symbol
│               └── frames    # SymbolFrame 集合
│                   └── SymbolFrame
└── banks                 # Bank 集合
    └── Bank
        └── animations    # Animation 集合
            └── Animation
                └── frames      # AnimFrame 集合
                    └── AnimFrame
                        └── elements  # Element 集合
                            └── Element
```

## 集合约定

- 所有集合为 **1-based 有序序列**，支持 `ipairs` 和长度运算符
- 集合为**只读视图**，禁止 `collection[i] = value`，用 `add`/`remove`/`move_to`/`move_to_parent` 替代
- 文档集合不支持 `pairs`，必须用 `ipairs` 保持文档顺序
- 修改集合时逆序遍历：`for i = #collection, 1, -1 do collection[i]:remove() end`
- `find(name)` 大小写不敏感；`SymbolFrame` 用 `find(num)` 精确查找

## 字段与方法约定

- 每个节点暴露**只读 `id` 字段**（十进制字符串），文档内唯一且跨编辑/保存/撤销稳定
- 可写字段支持直接赋值和显式 setter（`set_frame_rate`/`set_pivot`/`set_bounds`/`set_reference`/`set_transform`）
- 显式 setter 返回值表示是否真正改变（`true`/`false`）
- 只读字段、子集合、文档结构不可直接赋值
- `clone()` 返回新副本，`add()` 返回新创建的节点

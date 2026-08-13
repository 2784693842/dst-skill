# DST Mod Tool 1.1.13 Lua 脚本接口痛点反馈

**版本**: DST Mod Tool 1.1.13
**报告日期**: 2026-08-14
**场景**: 程序化修改 bearger 角色动画（79 个动画，每帧 ~33 个元素），实现"克隆缩小熊绑定到右手"功能

---

## 一、硬限制

### 1. 5 秒 Lua 执行超时（严重）

`frame.elements:add()` 每秒只能调用约 370 次。单个动画（37 帧 × 33 元素 = 1221 次）就已超时。无任何分批/异步/后台处理接口。

- **唯一绕过**: `animation:follow_symbol()`（内部原生实现）
- **建议**: 增加超时时间选项，或提供批量 add 接口

### 2. 无碰撞重算 API

`build` 对象上没有 `recalc_collision` 或 `recalculate` 方法。碰撞计算仅限 GUI 操作。

- **建议**: 暴露 `build:recalc_collision()` 给 Lua 脚本

### 3. 批量 add 格式不可用

`frame.elements:add({spec1, spec2})` 报错 `"error converting Lua nil to String"`。仅支持逐元素单 add。spec 表 key 为 `frame`（非 `frame_num`），命名不一致且无文档。

- **建议**: 支持 `frame.elements:add({spec_array})` 批量格式，并统一 spec 表 key 命名

---

## 二、API 设计缺陷

### 4. follow_symbol 符号匹配无唯一性（严重）

同名符号有多个实例时（如 `bearger_hand` 有两只手），`follow_symbol` 匹配全部实例。无参数可指定"只匹配某一个"。

- **当前 workaround**: 先手动 remove 不需要的实例 → follow_symbol → 再加回。极其脆弱。
- **建议**: 增加 `instance_index` 或 `predicate` 参数，支持按条件筛选

### 5. local_y 坐标方向反直觉

DST 内部坐标系 y 轴向下为负。`local_y` 正值使 mini 向下移（ty 更负），负值才向上。无文档说明。

- **建议**: 文档中明确坐标系统方向，或增加示例

### 6. transform(scale) 语义不明

`transform({type="scale", x=0.5, y=1})` 中 y=1 是否真的保持元素 sy 不变，需要额外验证。mini 的 ty 是绝对坐标，与 transform 后的缩放关系不直观。

- **建议**: 文档说明 transform 对各元素 a/b/c/d/tx/ty 的具体计算公式

---

## 三、状态管理

### 7. 工作区状态跨调用持久化

每次脚本调用之间，`doc.banks` / `doc.builds` 状态不重置。必须手动 `for i=#doc.banks,1,-1 do doc.banks[i]:remove() end` 清理。

- **建议**: 提供 `tool:new_document()` 或 `tool:reset()`

### 8. tool:open_document() 不能重置到空

空文件不存在时报错，不能用于"清空工作区"。

- **建议**: 支持传入 `nil` 或特殊标记创建空文档

### 9. Bank 同名合并静默发生

`bearger_actions.zip` 和 `bearger_basic.zip` 的 bank 名都是 "bearger"，import 时自动合并。第一次只 import build+basic 得到 29 个动画，直到显式 import 三个文件才凑齐 79 个。

- **建议**: import 时返回每个文件的 bank 数量，或支持重命名

---

## 四、调试困难

### 10. 无运行时断点/分步执行

5 秒超时硬切断，`print` 仅最终一次性输出。无法知道超时在哪一行。

- **建议**: 增加 `print` 实时输出或超时前 dump 最后一条 print

### 11. 输出截断

脚本 print 过多时，runner 可能截断 stdout。

- **建议**: 增加输出长度限制说明，或提供日志文件输出

### 12. API 版本无迁移说明

0.5.1 → 1.1.13 的 API 变更无 changelog。

- **建议**: 提供版本 changelog

---

## 五、核心矛盾

| 问题 | 影响 | 当前 workaround |
|------|------|----------------|
| 5秒超时 | 无法逐元素编程 | 只能依赖 follow_symbol |
| follow_symbol 多匹配 | mini 出现在两只手 | 先 remove 后 add 回 |
| local_y 方向不明 | 定位靠猜 | 反复试错 + 识图 |
| 无碰撞重算 | 碰撞框可能不对 | 无，需 GUI 手动 |
| 状态跨调用持久 | 清理复杂 | 手动 remove 循环 |
| Bank 同名合并 | 漏加载动画 | 显式 import 所有文件 |

---

## 六、建议优先级

1. **P0**: `follow_symbol` 增加实例选择参数（`instance_index` 或 `predicate`）
2. **P0**: 碰撞重算暴露为 Lua API
3. **P1**: `frame.elements:add()` 支持批量输入
4. **P1**: 提供 `tool:new_document()` 重置工作区
5. **P2**: 超时时间可配置（当前硬编码 5 秒）
6. **P2**: 增加 API changelog
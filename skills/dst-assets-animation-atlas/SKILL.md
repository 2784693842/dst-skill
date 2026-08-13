---
name: dst-assets-animation-atlas
description: Use when preparing DST animation and texture assets — ANIM/ATLAS/IMAGE Asset declarations, compiling SCML with Mod Tools, SetBank/SetBuild/PlayAnimation, OverrideSymbol/ClearOverrideSymbol, inventory icons, portraits, minimap atlases, or diagnosing missing animation/atlas resources. 中文触发：动画、图集、Build、Bank、纹理、Mod Tools 编译、图标、立绘、资源缺失。信号：Asset、AnimState、SetBuild、OverrideSymbol、atlas、SCML。
---

# DST 动画、Build 与图集资源

从资源源文件、编译产物、Asset 声明到 Lua 使用逐层核对名称和路径。

## 工作流

1. 列出每项资源的源文件、编译产物、Asset 类型、相对路径、bank、build、animation、symbol 和消费位置。
2. 从相同用途原版资源调用点确认管线；世界 AnimState、UIAnim、Image、库存图标和 Minimap 使用不同契约。
3. 用 DST Mod Tools 编译 SCML、纹理和图集，保留可再生成的源文件，不手工伪造二进制产物。
4. 在 Prefab 或入口的 Assets 中声明实际使用资源；图集 XML、TEX 和 Lua 路径大小写保持一致。
5. 设置 AnimState bank/build/animation 前确认名称存在；OverrideSymbol 与 ClearOverrideSymbol 成对管理。
6. 库存、配方、角色肖像和 Minimap 图标分别注册正确 Atlas，不用世界动画资源替代 UI 图集。
7. 在干净启动中检查资源加载日志、所有动画状态、皮肤或 Build 切换和远端客户端。

## 源码锚点

- prefabs/ 中 Asset、SetBank、SetBuild、PlayAnimation 和 OverrideSymbol 调用。
- prefabs.lua、prefabutil.lua、modutil.lua 的资源注册 API。
- widgets/image.lua、uianim.lua、itemimage.lua。
- anim 与 atlas 相关 Mod Tools 输出约定。

## 不变量

- Asset 声明路径使用模组相对路径，运行时解析路径按具体 API 契约处理。
- bank、build、animation 和 symbol 是不同命名空间。
- 不要把未实际运行编译器的文件描述为已编译可用。
- 资源替换要清理旧 Override，避免影响后续装备或皮肤。

## 验证

- 启动日志无缺失 Asset、Atlas、Animation 或 Symbol。
- 所有目标动画和 UI 图标在不同客户端可见。
- 源资源可通过记录的工具链重新生成相同类别产物。

## 按需资源

- 需要资源类型与消费 API 对照时读取 references/asset-pipelines.md。

## 辅助工具（Python 脚本）

`assets/scripts/` 下提供一组 DST 贴图/动画资源分析工具，**纯 Python 编写，不依赖游戏运行**。统一外部依赖仅为 **Pillow**（`ktex_decode` / `dst_tex_analyze` / `scml_analyze` 不依赖任何第三方库，手动实现 PNG 写出和 DXT 解码）。

### KTEX 解码系列

DST 的 `.tex` 文件为 KTEX 格式：`magic(4) + fmt(4) + N × (w(2) + h(2) + size(4)) + 数据区`，支持 RGBA8（无压缩）、DXT1（BC1，8 字节/4×4 块）、DXT5（BC3，16 字节/4×4 块，占 DST 贴图约 95.7%）。

| 脚本 | 用途 | 依赖 |
|---|---|---|
| `ktex_decode.py` | 单文件解码：`ktex_decode.py <file.tex> [out.png]`，输出 PNG + 像素统计 | 无 |
| `ktex_batch.py` | 批量扫描目录：`ktex_batch.py <tex根目录>`，统计格式/尺寸/分类分布 + 抽样像素分析 | 无 |
| `ktex_ascii.py` | 终端字符画预览：`ktex_ascii.py <file.tex> [--cols 80] [--rows 36] [--xml xxx.xml] [--element name]` | 无 |
| `dst_tex_analyze.py` | 目录级分析 + 抽样解码 PNG：`dst_tex_analyze.py <tex根目录> [--stat] [--out <目录>] [--limit N]` | 无 |

**用法示例**：

```bash
# 解码单个贴图看内容
python assets/scripts/ktex_decode.py mod/images/player.tex player.png

# 批量统计模组贴图格式分布（验证是否全为 DXT5）
python assets/scripts/ktex_batch.py "C:/DST/mods/mymod"

# 终端快速预览（不用打开图片）
python assets/scripts/ktex_ascii.py mod/images/player.tex

# 目录级分析 + 抽样出 PNG 到 output/
python assets/scripts/dst_tex_analyze.py "C:/DST/mods/mymod" --out output/tex_samples --limit 30
```

### SCML / 人物贴图系列

| 脚本 | 用途 | 依赖 |
|---|---|---|
| `scml_analyze.py` | 解析 Spriter SCML 工程：`scml_analyze.py <file.scml> [-j out.json] [--json-only]`，输出部位规范表 + 动画统计 + sdbm 哈希 | 无 |
| `char_sheet_gen.py` | 生成 1024×512 动画贴图模板 / 校验 png 尺寸：`char_sheet_gen.py --parts-json <parts.json> [-o out.png] [--font <path.ttf>]` 或 `--check <png目录>` | Pillow |

**用法示例**：

```bash
# 分析 SCML → JSON
python assets/scripts/scml_analyze.py character.scml -j parts.json --json-only

# 生成动画贴图模板（分区网格 + 部位名标注）
python assets/scripts/char_sheet_gen.py --parts-json parts.json -o template.png

# 校验已绘制的 png 尺寸是否符合 SCML 标准
python assets/scripts/char_sheet_gen.py --parts-json parts.json --check "C:/DST/mods/mymod/images"
```

### 来源

上述工具改编自开源项目 [zxiyx/dst-mod-creater](https://github.com/zxiyx/dst-mod-creater) 的 `tools/` 目录，经静态审查后修复了以下问题：

- `ktex_decode.py`：原格式判断依赖 `size == w*h*1/2` 等启发式规则，DXT5 贴图（占 95.7%）会走错解码分支输出乱码；改为 per-block 字节数精确判定，DXT1/DXT5 解码核心与 `dst_tex_analyze.py` 统一。
- `ktex_batch.py`：移除原作者硬编码路径和道诡异仙 mod 专属样本列表，改为命令行参数。
- `ktex_ascii.py`：修复 CLI 参数边界 bug；去掉对 PIL 的硬性依赖，字符画缩略用纯字节操作实现。
- `char_sheet_gen.py`：移除硬编码字体路径 `consola.ttf`，改为可选 `--font` 参数 + 默认字体 fallback。
- 统一编码声明、CLI 参数处理、跨平台兼容（Windows 控制台 UTF-8 输出）。


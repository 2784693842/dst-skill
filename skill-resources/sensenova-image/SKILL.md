---
name: sensenova-image
description: Use when generating images via SenseNova text-to-image API from a text-only (non-multimodal) orchestrator model — single image, multi-variant, aspect-ratio selection, style control, batch/series generation, iterative refinement, and image display to the user. 中文触发：文生图、生图、绘图、画图、出图、生成图片、图像生成、比例选择、多图变体、风格化。信号：sensenova-u1-fast、/images/generations、SENSENOVA_API_KEY。
---

# SenseNova 文生图

让一个**无图像态**的主控模型，通过编排 SenseNova 的文生图 HTTP API 生成图片，并把结果以"用户能直接看到"的方式回显。主控模型全程只做文本编排——视觉生成完全交给 SenseNova，不依赖自身视觉能力。

## 能力范围（仅限文生图）

- 单图生成
- 多图变体（`n>1`）
- 11 种比例 × 2 种档次（1K / 2K）= **22 种精确像素规格**
- 风格化（套用风格后缀模板）
- 骨架保留 / 风格迁移（同一主体快速换风格）
- 批量生成（多个 prompt）
- 系列一致生成（复用角色 / 风格锚定段）
- 迭代精修（按用户反馈改 prompt 重新生成）

## 工作流

1. **校验配置**：读取 `SENSENOVA_API_KEY`（来自环境变量或项目 `.env`），缺失或空值立即报错并给出获取指引，不继续。
2. **解析意图**：从用户自然语言提取——主提示词、目标比例、数量、风格倾向、是否系列生成。
3. **组装提示词**：
   - **自动组装**：`compose-prompt.ps1 -Subject <主体> -Scene <场景> -Style <风格键> -Mood <氛围> [-AspectRatio 16:9] [-Negative]`
     - 内置 11 个风格键：default/photoreal/anime/oil/watercolor/pixel/d3/cyberpunk/minimal/vintage/concept
     - `-AspectRatio` 自动在 prompt 开头插入构图前缀（如 `Composition: 16:9 landscape, ...`）
   - **骨架保留 / 风格迁移**：先写骨架 prompt（不含风格）验证构图，再用 `genimage-variants.ps1 -Styles a,b,c` 批量换风格
   - 手写模板：`assets/prompt-templates.md`
   - 系列生成：复用已确认的锚定段
4. **选 size**：
   - **推荐方式**：用 `resolve-size.ps1 -AspectRatio <比例> [-Tier 1k|2k]` 自动解析（如 `-AspectRatio 16:9 -Tier 2k` → `2752x1536`）
   - 用户未指定比例时给出建议而非擅自猜测；未指定档次默认 2K
   - 精确像素值见 `references/sensenova-contract.md` 的 BUCKETS 规格表（22 种）
5. **调用 API**（按场景选入口）：
   - **单图/多图**：`call-genimage.ps1 -Prompt <prompt> -Size <size> -N <n>`
     - 或 `call-genimage.ps1 -Prompt <prompt> -AspectRatio 16:9 -Tier 2k -N 1`（自动解析 size）
     - API Key 自动从环境变量链获取：`SN_KEY` → `SENSENOVA_KEY` → `SENSENOVA_API_KEY` → `SENSENOVA_SECRET_KEY` → `.env` 文件
   - **风格变体**：`genimage-variants.ps1 -Subject <主体> -Styles <键1,键2,...> [-Scene] [-Mood] [-Negative] [-AspectRatio] [-Tier] [-DryRun]`
   - **批量**：`batch-genimage.ps1 -PromptFile <prompts.txt> [-Compose] [-AspectRatio] [-Tier] [-DryRun]`
6. **落地图片**：`image-save.ps1` 把返回的 **URL（主路径）** 或 **base64（回退）** 解码为本地 PNG，写入**工作区临时目录**（`<工作区>/output/`，由 `-OutputDir` 指定；不写 `.claude/`）；URL 下载带 User-Agent + 超时 + 2 次重试 + Content-Length 头校验（±1% 容差）；大图自动产出一份回显用缩放图（宽 ≤ 1200px）；落地后校验 PNG/JPEG/WebP 魔数，非图像字节直接报错。
7. **回显**：**严禁用 `Read` 读取图片文件**（含 PNG/JPG/WebP）。回显方式：打印每张图的**绝对路径** + 生成参数 + 提示词摘要，让用户自行打开；多图/变体时附 `manifest.json` 路径方便追溯。
8. **多图/批量**：打印所有图片路径列表；批量/变体模式自动写 `manifest.json`（含 seq/prompt/status/error/images）。
9. **拼合对比**：多图时用 `make-contact-sheet.ps1 -ImagePaths <path1,path2,...> -Cols <N> -CellW <W> -CellH <H> [-NoLabel] -OutName <name>.png` 拼成网格 PNG，每格标序号+文件名，方便横向对比。
10. **失败处理**：API 错误（鉴权失败 / 限流 / 内容违规 / 超时）映射为可读错误并给重试 / 调整建议，绝不吞错。

## 接口锚点

- 端点：`POST https://token.sensenova.cn/v1/images/generations`
- 模型：`sensenova-u1-fast`（固定，图像生成专用，`model` 字段必须为 `sensenova-u1-fast`）
- 鉴权：`Authorization: Bearer $SENSENOVA_API_KEY`
- 完整契约快照见 `references/sensenova-contract.md`（离线执行依据，不依赖在线文档）。

## 水印控制（重要）

SenseNova 服务端默认在所有生成图片右下角叠加"日日新 sensenova"水印。

- **`watermark` 参数**：请求体中传入 `watermark: false` 可关闭水印，**当前免费公测中**，后续将转为付费功能。
- **强制显式传入**：为避免未来默认值变更影响线上业务，**所有调用必须显式传入 `watermark` 参数**（默认 `false`），不得依赖服务端默认值。
- `compose-prompt.ps1 -NoWatermark` 开关会在 prompt 中加入反水印术语，**不再作为主要手段**（prompt 层面无法阻止服务端 post-processing 水印），仅作为补充提示保留。
- 编排脚本（`genimage-variants.ps1` / `batch-genimage.ps1`）通过 `-Watermark $false` 透传到底层 API，无需手工修改调用体。

## 不变量

- `SENSENOVA_API_KEY` 绝不出现在终端输出、日志或产物文件中。
- **严禁用 `Read` 工具读取图片文件**（PNG/JPG/WebP/BMP 等）。回显方式仅限打印路径 + 参数摘要，让用户自行打开。
- 生成图片写入**工作区临时目录**（默认 `<工作区>/output/`），不写 `.claude/`，不写项目源码目录。
- 大图回显用缩放副本（`*-small.png`），原图保留在磁盘。
- 落地后必须校验图像魔数，非图像字节直接报错并丢弃，避免把错误 JSON 或乱码当成图片保存。
- 模型名、端点、size 规格全部以 contract 快照为准，不硬编码易变项。
- 用户未指定比例时给出建议，不擅自猜测。
- 系列生成时锚定段一旦确认就复用，不每轮重写导致角色 / 风格漂移。
- 批量 / 变体生成必须写 `manifest.json`，保证每个 prompt 的成功/失败/产物路径可追踪。
- `compose-prompt.ps1` 是纯 prompt 组装（不调用 API），编排脚本通过 `&` 调用它，不回链写死。
- contact sheet 用 GDI+ 渲染，无外部依赖；网格图片只用于对比，不替代原图。

## 验证

- 单图：给定 prompt → 用户看到一张图 + 拿到原图路径。
- 多图：`n=4` → 4 张都展示。
- 各 size 规格至少抽 1:1、16:9、9:16 各生成一次确认可用。
- `SENSENOVA_API_KEY` 缺失 → 清晰报错 + 获取指引。
- `SENSENOVA_API_KEY` 无效 / 过期 → 清晰报错（非 401 乱码）。
- prompt 为空 → 报错。
- 内容违规被拒 → 映射为可读错误，不崩溃。
- `compose-prompt.ps1` 传入未知风格键 → Warning + 回退 default。
- `genimage-variants.ps1 -DryRun` → 只打印计划不调 API。
- `batch-genimage.ps1 -DryRun` → 只打印计划不调 API。
- `make-contact-sheet.ps1` 输入 0 张图 → 报错。
- `make-contact-sheet.ps1 -Cols 0` → 自动 sqrt 列数。

## 按需资源

- size 规格表 / 参数细则：`references/sensenova-contract.md`
- 提示词模板（风格 / 质量 / 系列锚定 / 骨架保留 / 构图比例）：`assets/prompt-templates.md`
- 配置模板：`assets/templates/.env.example`
- 环境诊断脚本（doctor）：`assets/scripts/api-probe.ps1`
- 尺寸解析器（比例+档次 → 精确像素）：`assets/scripts/resolve-size.ps1`
- JSON 恢复器（markdown 代码块 → 有效 JSON）：`assets/scripts/recover-json.ps1`
- Prompt 组装器（11 种风格后缀 + 负向 + 质量 + 构图前缀）：`assets/scripts/compose-prompt.ps1`
- 单图调用（含 env fallback 链 + Content-Length 校验）：`assets/scripts/call-genimage.ps1`
- 图片落地（URL/base64 → PNG，含 UA/超时/重试/魔数校验）：`assets/scripts/image-save.ps1`
- 批量生成编排：`assets/scripts/batch-genimage.ps1`
- 风格变体编排：`assets/scripts/genimage-variants.ps1`
- 多图拼合（GDI+ 网格 PNG + 标签）：`assets/scripts/make-contact-sheet.ps1`
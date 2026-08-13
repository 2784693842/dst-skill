---
name: sensenova-image
description: Use when generating images via SenseNova text-to-image API from a text-only (non-multimodal) orchestrator model — single image, multi-variant, aspect-ratio selection, style control, batch/series generation, iterative refinement, and image display to the user. 中文触发：文生图、生图、绘图、画图、出图、生成图片、图像生成、比例选择、多图变体、风格化。信号：sensenova-u1-fast、/images/generations、SENSENOVA_API_KEY。
---

# SenseNova 文生图

让一个**无图像态**的主控模型，通过编排 SenseNova 的文生图 HTTP API 生成图片，并把结果以"用户能直接看到"的方式回显。主控模型全程只做文本编排——视觉生成完全交给 SenseNova，不依赖自身视觉能力。

## 能力范围（仅限文生图）

- 单图生成
- 多图变体（`n>1`）
- 11 种 2K 分辨率 / 比例选择
- 风格化（套用风格后缀模板）
- 批量生成（多个 prompt）
- 系列一致生成（复用角色 / 风格锚定段）
- 迭代精修（按用户反馈改 prompt 重新生成）

## 工作流

1. **校验配置**：读取 `SENSENOVA_API_KEY`（来自环境变量或项目 `.env`），缺失或空值立即报错并给出获取指引，不继续。
2. **解析意图**：从用户自然语言提取——主提示词、目标比例、数量、风格倾向、是否系列生成。
3. **组装提示词**：套用 `assets/prompt-templates.md` 的风格 / 质量后缀模板，必要时加负向约束；系列生成时复用已确认的角色 / 风格锚定段。
4. **选 size**：按目标比例从 `references/sensenova-contract.md` 的规格表匹配；用户未指定比例时给出建议而非擅自猜测，默认 `2048x2048`（1:1）。
5. **调用 API**：`call-genimage.ps1 -Prompt <prompt> -Size <size> -N <n>`，返回 JSON。
6. **落地图片**：`image-save.ps1` 把返回的 **URL（主路径）** 或 **base64（回退）** 解码为本地 PNG，写 scratchpad 目录（`<项目>/.claude/sensenova-images/`）；URL 下载带 User-Agent + 超时 + 2 次重试；大图自动产出一份回显用缩放图（宽 ≤ 1200px）；落地后校验 PNG/JPEG/WebP 魔数，非图像字节直接报错（防把错误 JSON 当图存）。
7. **回显**：用 `Read(file_path)` 逐张呈现给用户（Claude 视觉能力），同时打印每张的**原图绝对路径**（方便用户直接打开）。
8. **多图**：`n>1` 或批量 prompt 时依次 `Read`，每张附编号、生成参数和提示词摘要。
9. **失败处理**：API 错误（鉴权失败 / 限流 / 内容违规 / 超时）映射为可读错误并给重试 / 调整建议，绝不吞错。

## 接口锚点

- 端点：`POST https://token.sensenova.cn/v1/images/generations`
- 模型：`sensenova-u1-fast`（固定，图像生成专用，`model` 字段必须为 `sensenova-u1-fast`）
- 鉴权：`Authorization: Bearer $SENSENOVA_API_KEY`
- 完整契约快照见 `references/sensenova-contract.md`（离线执行依据，不依赖在线文档）。

## 不变量

- `SENSENOVA_API_KEY` 绝不出现在终端输出、日志或产物文件中。
- 生成图片只写入 scratchpad（`.claude/sensenova-images/`），不写入项目源码目录。
- 回显前图片必须先落地为本地文件（`Read` 只接受本地路径），不直接展示 base64 内联。
- 大图回显用缩放副本（`*-small.png`），原图保留在磁盘。
- 落地后必须校验图像魔数，非图像字节直接报错并丢弃，避免把错误 JSON 或乱码当成图片保存。
- 模型名、端点、size 规格全部以 contract 快照为准，不硬编码易变项。
- 用户未指定比例时给出建议，不擅自猜测。
- 系列生成时锚定段一旦确认就复用，不每轮重写导致角色 / 风格漂移。

## 验证

- 单图：给定 prompt → 用户看到一张图 + 拿到原图路径。
- 多图：`n=4` → 4 张都展示。
- 各 size 规格至少抽 1:1、16:9、9:16 各生成一次确认可用。
- `SENSENOVA_API_KEY` 缺失 → 清晰报错 + 获取指引。
- `SENSENOVA_API_KEY` 无效 / 过期 → 清晰报错（非 401 乱码）。
- prompt 为空 → 报错。
- 内容违规被拒 → 映射为可读错误，不崩溃。

## 按需资源

- size 规格表 / 参数细则：`references/sensenova-contract.md`
- 提示词模板（风格 / 质量 / 系列锚定）：`assets/prompt-templates.md`
- 配置模板：`assets/templates/.env.example`
- 探活脚本（验证 KEY + 连通性）：`assets/scripts/api-probe.ps1`
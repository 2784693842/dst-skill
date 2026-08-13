---
name: sensenova-vision
description: Use when a text-only (non-multimodal) orchestrator model needs to understand, extract data from, or analyze image files via SenseNova vision API — charts, tables, UI screenshots, diagrams, photos. Avoids context overflow by never loading image bytes into model context; all encoding and API calls happen in external scripts. 中文触发：识图、图片分析、图表提取、表格识别、OCR、图片描述、截图分析、图片转表格、识别图片、图像理解、image caption、chart analysis、table OCR。信号：sensenova-6.7-flash-lite、image_url、vision。
---

# SenseNova 识图

让一个**无图像态**的主控模型，通过编排 SenseNova 的视觉 API（`/chat/completions` 多模态消息）理解、描述或从图片中提取结构化数据。

## 核心设计原则：永不触碰图片字节

**问题**：用 `Read` 工具直接读取图片文件 → base64 编码后的图片数据（通常 50–500KB 文本）直接进入主模型上下文 → 快速耗尽 token 预算，尤其在批量处理或多轮对话中。

**方案**：图片加载、压缩、base64 编码、API 调用**全部在外部 PowerShell 脚本进程内完成**，主模型只接收纯文本 caption 结果（通常 <2000 token），context 开销可控。

```
用户图片路径
    ↓
caption-vision.ps1 (进程外执行)
    ├── 读取图片字节
    ├── 压缩（>5MB 或 >2048px）
    ├── base64 编码
    ├── 调视觉 API
    └── 返回纯文本 caption
    ↓
主模型收到纯文本（context 安全）
```

## 能力范围（仅限识图/图像理解）

- 单图描述（general）
- 图表数据提取（chart → Markdown 表格）
- 表格截图识别（table → Markdown 表格）
- 界面截图分析（UI → 组件/布局/文字）
- 流程图/架构图分析（diagram → 节点关系）
- 批量识图（目录扫描 + 结果汇总）
- 自定义 prompt 引导提取
- MD5 缓存（同图同 prompt 不重复调用）

## 工作流

1. **接收图片路径**：从用户消息或文件列表获取 `.png/.jpg/.jpeg/.gif/.webp/.bmp` 文件路径。
2. **类型检测**：按文件名关键词自动匹配类型（chart/table/UI/diagram/general），也可用 `-Type` 手动指定。
3. **组装 prompt**：根据类型选取内置 prompt 模板（见 `references/vision-contract.md`），或用 `-Prompt` 自定义。
4. **调用识图脚本**：

   ```powershell
   # 基础 — 自动检测类型
   & .\assets\scripts\caption-vision.ps1 -Image "output\chart.png"

   # 指定类型 + 自定义 prompt
   & .\assets\scripts\caption-vision.ps1 -Image "output\table.png" -Type table `
     -Prompt "提取表格所有内容，Markdown 表格格式，保持行列结构"

   # JSON 输出（含 type/usage/cached 等元信息）
   & .\assets\scripts\caption-vision.ps1 -Image "output\ui.png" -AsJson

   # 批量处理目录
   & .\assets\scripts\caption-vision.ps1 -ImageDir "output\screenshots/" -AsJson -OutputFile captions.json
   ```

5. **处理结果**：
   - 单图：纯文本 caption 直接纳入回复
   - Markdown 表格：直接嵌入回复或进一步提取数据
   - 批量：读取 `captions.json` 汇总所有结果
6. **回显**：将 caption 文本整合为自然语言回复，**绝不**用 `Read` 读取图片文件。

## 接口锚点

- 端点：`POST https://token.sensenova.cn/v1/chat/completions`
- 模型：`sensenova-6.7-flash-lite`（视觉多模态，固定）
- 鉴权：`Authorization: Bearer $SN_API_KEY`
- 消息格式：OpenAI 兼容多模态消息（text + image_url data URL）
- 完整契约快照见 `references/vision-contract.md`

## 环境变量回落链

API Key 按以下优先级自动解析（首个非空值生效）：

| 优先级 | 来源 |
|---|---|
| 1 | `SN_VISION_API_KEY` |
| 2 | `SN_CHAT_API_KEY` |
| 3 | `SN_API_KEY` |
| 4 | `SENSENOVA_API_KEY`（与 sensenova-image 共用） |
| 5 | `.env` 文件中的同名键 |

模型和 base URL 也支持 `SN_VISION_MODEL` / `SN_VISION_BASE_URL` / `SN_CHAT_MODEL` / `SN_CHAT_BASE_URL` 覆盖。

## 图片压缩规则

脚本自动压缩，用户无需关心：

| 条件 | 动作 |
|---|---|
| 文件 > 5MB | 压缩为 JPEG (quality=75) |
| 最长边 > 2048px | 等比缩放至 2048px |
| RGBA/P/LA 模式 | 转为 RGB + 白色背景 |
| 不满足条件 | 原样使用 |

## 缓存

- 缓存键 = `image MD5 + prompt MD5`
- 缓存位置：`<script dir>/.caption_cache/`
- 命中缓存：返回 `cached: true`，不消耗 API 调用
- 跳过缓存：`-NoCache`

## 不变量

- **严禁用 `Read` 工具读取图片文件**（PNG/JPG/WEBP/GIF/BMP）。所有图片处理必须在 `caption-vision.ps1` 等外部脚本中完成。
- `SN_API_KEY` 绝不出现在终端输出、日志或产物文件中。
- 脚本返回的 caption 文本是主模型的唯一信息通道。
- 图片压缩仅在脚本进程内完成，不产生磁盘中间文件（内存处理）。
- 批量模式必须写 `captions.json`（含 file/type/description/usage/cached/status/error）。
- 自定义 prompt 必须用 `-Prompt` 参数传入，不硬编码到脚本。

## 验证

- 给定有效 `.png` → 返回描述文本
- 给定图表截图 + `-Type chart` → 返回 Markdown 表格
- 给定表格截图 + `-Type table` → 返回结构化 Markdown
- 给定 UI 截图 + `-Type ui` → 返回组件描述
- `-AsJson` → 返回含 usage/cached 的 JSON
- 同图同 prompt 第二次 → `cached: true`，无 API 调用
- `SN_API_KEY` 缺失 → 清晰报错
- `SN_API_KEY` 无效 → 401 映射为可读错误
- 图片文件不存在 → 清晰报错
- 非图片字节 → 清晰报错
- `-Type unknown` → 回退 `general`
- 批量 0 张图 → 报错

## 按需资源

- API 契约快照（消息格式、prompt 模板、env 回落链）：`references/vision-contract.md`
- 识图核心脚本（加载/压缩/编码/API/缓存/批量）：`assets/scripts/caption-vision.ps1`
- 环境变量模板：`assets/templates/.env.example`
- 配套文生图 skill（识图 → 再生成流程）：`../sensenova-image/`
# SenseNova 识图 Skill

让无图像态（纯文本）的主控模型通过 SenseNova 视觉 API（`/chat/completions` 多模态消息）理解、描述或从图片中提取结构化数据。

**核心设计原则**：所有图片字节处理（加载、压缩、base64 编码、API 调用）在外部 `caption-vision.ps1` 脚本中完成，主模型只接收纯文本 caption，**彻底避免用 `Read` 工具读取图片导致的上下文溢出**。

## 与 sensenova-image 的关系

| Skill | 用途 | 端点 | 模型 |
|---|---|---|---|
| `sensenova-image` | 文生图 | `/images/generations` | `sensenova-u1-fast` |
| `sensenova-vision` | 识图/图像理解 | `/chat/completions` | `sensenova-6.7-flash-lite` |

## 快速上手

```powershell
# 1. 配置 API Key（与 sensenova-image 共用，SN_API_KEY 或 SENSENOVA_API_KEY）
# 2. 单图识图
& .\assets\scripts\caption-vision.ps1 -Image "output\chart.png"

# 3. 指定类型 + JSON 输出
& .\assets\scripts\caption-vision.ps1 -Image "output\table.png" -Type table -AsJson

# 4. 批量处理
& .\assets\scripts\caption-vision.ps1 -ImageDir "output/screenshots/" -AsJson -OutputFile captions.json
```

## 能力

- **图表数据提取**（chart → Markdown 表格，精确数值）
- **表格截图识别**（table → Markdown 表格，保持行列结构）
- **UI 截图分析**（ui → 组件/布局/文字/颜色描述）
- **流程图/架构图分析**（diagram → 节点关系 + 连接）
- **通用描述**（general → 主体/背景/文字/颜色）
- **自定义 prompt**（`-Prompt` 覆盖内置模板）
- **自动类型检测**（按文件名关键词命中）
- **MD5 缓存**（同图同 prompt 不重复调用）

## 目录

```
assets/
├── scripts/
│   └── caption-vision.ps1   # 核心脚本：加载/压缩/编码/API/缓存/批量
└── templates/.env.example
references/
└── vision-contract.md        # API 契约快照：消息格式/prompt 模板/env 回落链/错误映射
SKILL.md
README.md
```

## 脚本速查

### 单图（自动检测类型）

```powershell
& .\assets\scripts\caption-vision.ps1 -Image "output\photo.png"
```

### 指定类型 + 自定义 prompt

```powershell
& .\assets\scripts\caption-vision.ps1 `
  -Image "output\table.png" `
  -Type table `
  -Prompt "提取所有数值，Markdown 表格格式"
```

### JSON 输出（含 usage/cached/type 元信息）

```powershell
& .\assets\scripts\caption-vision.ps1 `
  -Image "output\chart.png" `
  -Type chart `
  -AsJson
```

### 批量处理

```powershell
& .\assets\scripts\caption-vision.ps1 `
  -ImageDir "output/screenshots/" `
  -AsJson `
  -OutputFile captions.json
```

### 跳过缓存

```powershell
& .\assets\scripts\caption-vision.ps1 -Image "output\new.png" -NoCache
```

## 关键约定

- **严禁用 `Read` 工具读取图片文件**（PNG/JPG/WEBP/GIF/BMP）——所有图片处理在 `caption-vision.ps1` 内完成
- 环境变量回落链：`SN_VISION_API_KEY` → `SN_CHAT_API_KEY` → `SN_API_KEY` → `SENSENOVA_API_KEY` → `.env`
- 图片自动压缩：>5MB 或 >2048px 最长边 → JPEG quality=75
- 缓存键 = `image MD5 + prompt MD5`，缓存位置 `<script dir>/.caption_cache/`
- 与 `sensenova-image` 共用 API Key（`SN_API_KEY` 或 `SENSENOVA_API_KEY` 通用）

## API 契约

- 端点：`POST https://token.sensenova.cn/v1/chat/completions`
- 模型：`sensenova-6.7-flash-lite`（视觉多模态）
- 完整消息格式、prompt 模板、压缩规则、错误映射见 `references/vision-contract.md`

## 验证

- 给定有效 `.png` → 返回纯文本描述
- 给定图表截图 + `-Type chart` → 返回 Markdown 表格
- 给定表格截图 + `-Type table` → 返回结构化 Markdown
- 给定 UI 截图 + `-Type ui` → 返回组件描述
- `-AsJson` → 返回含 `usage`/`cached`/`type` 的 JSON
- 同图同 prompt 第二次 → `cached: true`，不消耗 API 调用
- `SN_API_KEY` 缺失 → 清晰报错
- 图片不存在 → 清晰报错
- 批量 0 张图 → 报错
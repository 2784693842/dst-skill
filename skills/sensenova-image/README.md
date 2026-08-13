# SenseNova 文生图 Skill

让无图像态的主控模型通过 SenseNova `/images/generations` 生成图片，并以"用户能直接看到"的方式回显。

## 快速上手（3 步）

1. 把 `assets/templates/.env.example` 复制到你项目的 `.env`，填好 `SENSENOVA_API_KEY`
2. 跑 `.\assets\scripts\api-probe.ps1` 诊断环境（不落地图片）
3. 跑 `.\assets\scripts\api-probe.ps1 -LiveCheck` 验证真实 API 连通性
4. 按 `SKILL.md` 工作流编排：解析意图 → 装提示词 → 调 API → 落地 → 回显

## 目录

```
assets/
├── prompt-templates.md
├── templates/.env.example
└── scripts/
    ├── api-probe.ps1         # 环境诊断（doctor）：PS/.NET/Key/端点/依赖
    ├── call-genimage.ps1     # 调用 API，返回原始 JSON（含 env fallback 链）
    ├── resolve-size.ps1      # 比例+档次 → 精确像素（22 种规格）
    ├── recover-json.ps1      # markdown 围栏 → 有效 JSON 提取
    ├── image-save.ps1        # URL/base64 落地 PNG（含 UA/超时/重试/魔数/Content-Length 校验）
    ├── compose-prompt.ps1    # 结构化参数 → 最终 prompt（11 风格+负向+质量+构图前缀）
    ├── batch-genimage.ps1    # 批量生成：读 prompt 文件 → 调 API → 落地 → 写 manifest
    ├── genimage-variants.ps1 # 风格变体：主体 + 多风格 → 出图 → 拼 contact sheet
    └── make-contact-sheet.ps1 # 多图拼成网格 PNG（GDI+，含标签）
references/
└── sensenova-contract.md
SKILL.md
README.md
```

## 关键约定

- 图片只写 `<工作区>/output/`（由 `-OutputDir` 指定），不进源码目录，不进 git（`.gitignore` 已排除）
- 大图自动产出一份回显用缩放副本（宽 ≤ 1200px，`*-small.png`）
- API 响应**主路径是 URL**，base64 只是回退
- 环境变量回落链：`SN_KEY` → `SENSENOVA_KEY` → `SENSENOVA_API_KEY` → `SENSENOVA_SECRET_KEY` → `.env`
- 探活脚本不落地图片，可用于 CI 校验
- 批量/变体生成必写 `manifest.json`（含 seq/prompt/status/error/images）
- **严禁用 `Read` 工具读取图片文件**，回显方式仅限打印路径

## 脚本速查

### 单图/多图（推荐：用 -AspectRatio 代替硬编码 -Size）

```powershell
# 方式 A：用比例自动解析像素
$size = & .\assets\scripts\resolve-size.ps1 -AspectRatio 16:9 -Tier 2k
# => 2752x1536

# 组装 prompt（-AspectRatio 自动注入构图前缀）
$prompt = & .\assets\scripts\compose-prompt.ps1 `
  -Subject "a dragon" -Scene "soaring over a castle" `
  -Style d3 -AspectRatio 16:9

# 调 API（自动从环境变量链获取 Key）
.\assets\scripts\call-genimage.ps1 -Prompt $prompt -Size $size -N 2
# 或直接传入比例
.\assets\scripts\call-genimage.ps1 -Prompt $prompt -AspectRatio 16:9 -Tier 2k -N 1

# 落地
.\assets\scripts\image-save.ps1 -Url "<返回 URL>" -Seq 1 -OutputDir <目标目录>
```

### 风格变体（自动拼 prompt + 出图 + contact sheet）

```powershell
# 同一主体出 4 种风格，自动拼合对比
.\assets\scripts\genimage-variants.ps1 `
  -Subject "a young woman with silver short hair" `
  -Scene "standing on a rainy neon-lit city street at night" `
  -Styles anime, oil, photoreal, d3 `
  -AspectRatio 9:16 -Tier 2k `
  -DryRun   # 去掉 -DryRun 真正出图
```

### 批量生成

```powershell
# prompts.txt 每行一个 prompt
.\assets\scripts\batch-genimage.ps1 -PromptFile prompts.txt -AspectRatio 16:9 -Tier 2k -N 1

# Compose 模式：每行 `主体|场景|风格`
# a dragon|over a castle|d3
# a castle|in a field|oil
.\assets\scripts\batch-genimage.ps1 -PromptFile prompts.txt -Compose -AspectRatio 3:4 -Tier 1k -DryRun
```

### 拼合对比

```powershell
# 把多张图拼成网格 PNG
.\assets\scripts\make-contact-sheet.ps1 `
  -ImagePaths "a.png","b.png","c.png","d.png" `
  -Cols 2 -CellW 400 -CellH 400 `
  -OutName comparison.png
```

## 生成图不入库

`.gitignore` 排除了 `*.png` / `*.jpg` / `*.webp` / `manifest.json` / `summary.json` / `contact_sheet_*.png`，保证生成图不进版本控制。
# dst-character-parts

**DST 人物拆件** — 把角色立绘、三视图或已有角色图拆分为 DST Spriter/SCML 人物动画可用的透明 PNG 部件，并完成完整性审计。

## 触发场景

- 用户给一张角色三视图，要求拆成 DST 动画部件
- 用户要给已有角色替换 Build 贴图
- 用户要求"按 SCML 模板出零件"
- 用户要求检查拆件完整性（缺图 / 尺寸 / 透明通道）

## 与上下游 skill 的关系

```
sensenova-image             (AI 生成角色立绘 / 三视图 / 单部位 sprite)
        ↓
dst-character-parts         ← 拆件、对齐、审计（本 skill）
        ↓
dst-assets-animation-atlas  (SCML 编译 / KTEX 打包 / char_sheet_gen.py 模板)
```

## 目录结构

```
dst-character-parts/
├── SKILL.md                     # 工作流、不变量、验证清单
├── references/
│   └── dst-parts-spec.md        # DST 人物部位规范（常见部件族、复杂服装、透明边缘）
└── scripts/
    ├── scml_parts_plan.py       # 从 SCML 生成部件计划 JSON
    └── audit_parts.py           # 拆件完整性审计（缺图/尺寸/Alpha/重复/边缘）
```

## 快速使用

### 1. 生成部件计划

```powershell
# cwd = skill 根目录
python scripts/scml_parts_plan.py "exported\wilson\wilson.scml" --output "parts_plan.json"
```

### 2. 逐件拆分

按 `parts_plan.json` 的 folder 和 file 清单，逐件制作透明 PNG，保持像素尺寸与 pivot 与 SCML 一致。

### 3. 自动审计

```powershell
python scripts/audit_parts.py "parts/" `
  --plan "parts_plan.json" `
  --report "audit.json" `
  --contact-sheet "contact_sheet.png" `
  --strict `
  --columns 6
```

审计输出：

| 状态 | 含义 |
|---|---|
| `ok` | 通过 |
| `missing` | 缺图（错误） |
| `size_mismatch` | 像素尺寸不符（错误） |
| `no_alpha` | 无透明通道（错误） |
| `empty_alpha` | Alpha 全空且非模板占位帧（错误） |
| `template_blank` | 模板原本就是全透明占位帧（警告） |
| `edge_touches` | 像素触碰画布边缘（警告） |

`--strict` 模式下有任何错误则退出码为 1。

## 依赖

| 依赖 | 状态 |
|---|---|
| Python 3.8+ | 系统自带 |
| Pillow | `pip install Pillow`；本仓库已含 |
| `xml.etree.ElementTree` | Python 标准库 |

## ⚠️ 图片读取约束（强制）

**禁止用 `Read` 工具直接读取图片文件**（PNG/JPG/WEBP/GIF/BMP）。所有识图/图像分析必须通过 `sensenova-vision` skill 的 `caption-vision.ps1` 脚本完成。

## 质量底线

- 原图永不原地修改
- 透明 PNG 必须带 Alpha 通道，背景 Alpha 必须为 0
- 像素尺寸和 pivot 必须与 SCML 一致
- AI 生成图必须经人工检查
- 不交付未通过 `audit_parts.py --strict` 的结果
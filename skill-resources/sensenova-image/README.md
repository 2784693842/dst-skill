# SenseNova 文生图 Skill

让无图像态的主控模型通过 SenseNova `/images/generations` 生成图片，并以"用户能直接看到"的方式回显。

## 快速上手（3 步）

1. 把 `assets/templates/.env.example` 复制到你项目的 `.env`，填好 `SENSENOVA_API_KEY`
2. 跑 `.\assets\scripts\api-probe.ps1` 验证连通性（**不会落地图片**）
3. 按 `SKILL.md` 工作流编排：解析意图 → 装提示词 → 调 `call-genimage.ps1` → `image-save.ps1` 落地 → `Read` 回显

## 目录

```
assets/
├── prompt-templates.md      # 风格/质量/负向/系列锚定模板
├── templates/.env.example
└── scripts/
    ├── api-probe.ps1        # 探活（只验 KEY + 端点，不落地）
    ├── call-genimage.ps1    # 调用 API，返回原始 JSON
    └── image-save.ps1       # 把 URL/base64 落地为本地 PNG
references/
└── sensenova-contract.md    # API 契约快照（11 种 size 规格、错误码）
SKILL.md                     # 编排流程、不变量、验证
```

## 关键约定

- 图片只写 `.claude/sensenova-images/`（scratchpad），不进源码目录
- 大图自动产出一份回显用缩放副本（宽 ≤ 1200px，`*-small.png`）
- API 响应**主路径是 URL**，base64 只是回退
- 探活脚本不落地图片，可用于 CI 校验
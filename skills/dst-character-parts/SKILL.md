---
name: dst-character-parts
description: 将人物立绘、三视图或已有角色图拆分为《饥荒联机版》Spriter/SCML人物动画可用的透明PNG部件，并保持画风、比例、方向、遮挡层级、画布、pivot和文件命名一致。用于制作或更新DST人物Mod美术，尤其是用户要求"人物拆件""角色拆分""把三视图做成动画部件""替换人物Build贴图""按SCML模板出零件"或检查拆件完整性时。
---

# DST 人物拆件

把角色设定图转换为可装配、可转动、可编译的 DST 人物部件。优先复用目标人物的 SCML 结构，不把设定图简单切成互相粘连的矩形。

## 输出目标

- 与目标 SCML 相同路径、尺寸和命名的透明 PNG 部件。
- 一份从 SCML 生成的部件计划 JSON（`parts_plan.json`）。
- 一张拆件预览图和一份完整性检查报告（`audit.json` + `contact_sheet.png`）。
- 必要时提供正面、背面、侧面重组预览；不要未经验证直接覆盖正式 Build。

## 工具链与依赖

| 依赖 | 用途 | 状态 |
|---|---|---|
| Python 3.8+ | 运行配套脚本 | 系统自带 |
| Pillow (`PIL`) | PNG 读写 / alpha 通道检查 / contact sheet 渲染 | 需 `pip install Pillow`；本项目 `skill-resources` 已含 |
| `scripts/scml_parts_plan.py` | 从 SCML 生成部件计划 JSON | skill 自带 |
| `scripts/audit_parts.py` | 拆件完整性审计 | skill 自带 |

**脚本调用约定**：以下 `python scripts/...` 命令均假定**当前工作目录为该 skill 根目录**（即 `D:\dst-skills-skillsh\skills\dst-character-parts\` 或 `D:\dst-skills-skillsh\skill-resources\dst-character-parts\`）。若从其他目录调用，用 `-c <skill-dir>` 或在脚本路径前加相对路径。

### 与上下游 skill 的关系

```
sensenova-image        (AI 生成角色立绘 / 三视图 / 单部位 sprite)
        ↓
dst-character-parts    ← 本 skill：拆件、对齐、审计
        ↓
dst-assets-animation-atlas  (SCML 编译 / KTEX 打包 / char_sheet_gen.py 模板)
```

- **上游 `sensenova-image`**：若角色设定图是 AI 生成，先用 `sensenova-image` 出图并显式传 `watermark=false`；生成的三视图/立绘作为本 skill 的输入。
- **下游 `dst-assets-animation-atlas`**：拆件通过后，把部件放入 DST SCML 工程，用 `char_sheet_gen.py --check` 校验像素尺寸，再用 Mod Tools / SCML 编译成 DST Build。

## 工作流程

### 1. 检查输入

1. **查看原图**：用 `Read` 工具打开每张立绘或三视图（PNG/JPG/WEBP），**不要用 base64 手动解码**；图片会以视觉方式呈现，可看清尺寸和细节。若需要批量识图分析，调用 `sensenova-vision` skill 的 `caption-vision.ps1`（`-Type general`）。
2. **查找目标人物的 `exported/<character>/<character>.scml`**。若已有 SCML，必须以它的 folder、file、尺寸和 pivot 为准。
3. 若没有 SCML，先询问或选择最接近的官方/既有人物骨架作为模板，并明确这项假设（可参照 `dst-assets-animation-atlas` 的 `references/character-esc.md` 部位规范）。
4. **保留原图，不在唯一原件上修改**；新内容写入独立工作目录。

输入只有一个方向且其他方向不可可靠推断时，先制作方向设定图（可调用 `sensenova-image` 基于已有视图做 AI 推断生成）并让用户确认，再拆件。不要把正面五官直接旋转成侧脸。

### 2. 生成部件计划

运行（**cwd = skill 根目录**）：

```powershell
python scripts/scml_parts_plan.py <角色.scml> --output <parts_plan.json>
```

读取生成的 JSON，按实际 folder 逐项制作。不要凭通用清单删减目标 SCML 已有部件。

需要判断头发、裙摆、披风、蝴蝶结或饰品如何分层时，读取 `references/dst-parts-spec.md`。

### 3. 锁定角色设计

在拆件前固定以下内容：

- 头身比、头部宽高、身体总高和脚底线。
- 正面、背面、侧面的发型轮廓与饰品所在一侧。
- 服装的袖口、腰线、裙长、鞋高和左右不对称细节。
- 描边粗细、阴影方向、颜色和纹理密度。

若这些内容在不同视图间冲突，先做一张修正版三视图（可调用 `sensenova-image` 出图），不要让不同零件分别"自行理解"角色设计。

### 4. 逐件拆分

对具有语义或被遮挡区域的零件，使用以下手段逐件处理；**先看原图，再以原图作为编辑参考**。一次只处理一个部件族，例如头部、头发、躯干或一条手臂。

| 手段 | 适用场景 |
|---|---|
| 手动图像编辑（本地软件 / GIMP / Photoshop） | 精确控制透明通道、描边和关节补全 |
| `sensenova-image` 局部重绘 / 局部生成 | 缺失的方向视图、需要补全的隐藏区域 |
| `sensenova-image -AspectRatio` + 固定尺寸 | 单部位 sprite 生成，prompt 中强制 `transparent background, no shadow` |
| `sensenova-vision` 识图分析 | 判断原图哪些区域属于哪个部件 |

遵守以下规则：

- 输出透明背景 PNG，不带白底、棋盘格、环境阴影或其他身体部位。
- 保留原画风和原颜色，不擅自美化五官、改服装或改变头身比。
- 在关节和遮挡边缘补全必要的隐藏区域，使骨骼转动时不会露洞；补全区域延伸到可见接缝之外约部件长度的 10%～15%。
- 头发至少按模板区分前发、后发及帽子遮挡版本；长发不要和躯干、手臂或裙子烘焙在一起。
- 上臂、下臂、手掌分别独立；沿袖口或关节的自然结构拆分。
- 裙摆、上衣和腿部保持独立；长裙按模板需要拆出前层、后层或左右摆片。
- 不把眼睛、嘴、腮红等表情烘焙进头部，除非目标 SCML 本来就是这种结构。
- 侧面通常由游戏镜像生成另一侧；角色存在明显左右不对称设计时，记录镜像会造成的错误，并准备独立素材或运行时覆盖方案。

### 5. 对齐画布与 pivot

替换既有部件时：

1. 保持目标 PNG 的像素尺寸不变。
2. 保持 SCML 中的 `pivot_x/pivot_y` 不变。
3. 让关节锚点落在原模板相同位置，而不是把图像视觉居中。
4. 需要放大或缩小时围绕关节锚点变换，不围绕画布中心变换。
5. 保留透明留白；不要为了节省空间紧裁导致 pivot 漂移。

新增部件时，先确定 pivot 和父骨骼，再写入 SCML。不要靠反复修改动画关键帧弥补错误的部件原点。

### 6. 重组验证

至少检查：

- 中立站立的正面、背面和侧面轮廓。
- `idle`、`run`、`attack`、`item_out/item_in`、受击和死亡动作。
- 戴帽子后的头发遮挡。
- 手持物品时双手与 `swap_object` 的层级。
- 长发、裙摆和手臂交叉时是否穿帮。
- 游戏镜像后的饰品方向。

先生成静态重组预览，再编译动画。发现比例或接缝错误时回到源部件修正，不在编译产物上累计变换。

### 7. 自动检查

运行（**cwd = skill 根目录**）：

```powershell
python scripts/audit_parts.py <parts目录> `
  --plan <parts_plan.json> `
  --report <audit.json> `
  --contact-sheet <contact_sheet.png> `
  --strict `
  --columns 6
```

处理所有错误：缺图、尺寸不符、非模板占位帧的空 Alpha、无透明通道。目标模板原本就是全透明的占位帧只记为警告；边缘触碰和重复图片也属于警告，结合模板判断是否合理。

### 8. 交付与覆盖规则

- 明确列出已完成、尚待人工确认和无法从原图可靠恢复的部件。
- 只有重组预览和检查均通过后，才替换目标 `exported/<character>` 中的对应 PNG。
- **编译前备份 SCML 和人物源工程**；不要直接修改唯一的 `anim/<character>.zip`。
- 若用户要求正式更新，再调用 `dst-assets-animation-atlas` skill 的编译流程（`char_sheet_gen.py --check` → Mod Tools 编译 SCML → KTEX 打包），并按该项目交接说明同步游戏目录或发布包。

## 质量底线

不得交付以下结果：

- 只是把整个人物矩形裁成几块，部件仍带其他身体区域。
- 透明边缘带白边、黑边或棋盘纹。
- 三个方向的服装、发饰或身体比例互相矛盾。
- 手臂旋转后出现断口，长发与身体无法分层。
- 文件名看似正确，但像素尺寸或 pivot 与 SCML 不一致。
- 未经实测就声称动画 Build 已经可用。

## 不变量

- **原图永不原地修改**；所有新内容写入独立工作目录。
- **透明 PNG 必须带 Alpha 通道**，背景 Alpha 必须为 0，不得有白色/灰色/棋盘格毛边。
- **像素尺寸和 pivot 必须与 SCML 一致**，不接受"视觉看起来差不多"。
- **AI 生成图必须经人工检查**；AI 擅长填充但容易引入不存在的装饰或改变画风，发现偏差必须回到源部件修正。
- **下游编译由 `dst-assets-animation-atlas` 负责**，本 skill 只交付符合 SCML 规格的部件和审计报告。
- **不交付未通过 `audit_parts.py --strict` 的结果**（模板占位帧的警告除外）。

## 验证

- 给定一张角色三视图 + 已有 SCML → 输出完整部件 PNG + `parts_plan.json` + `audit.json`，`audit_parts.py --strict` 返回 0。
- `scml_parts_plan.py` 对有效 SCML → 正确提取 folders/files/width/height/pivot。
- `audit_parts.py` 对缺图 → `status: missing` + 错误计数 + `--strict` 退出 1。
- `audit_parts.py` 对尺寸不符 → `status: size_mismatch` + 错误计数。
- `audit_parts.py` 对非透明 PNG → `status: no_alpha` + 错误计数。
- `audit_parts.py` 对全透明占位帧 → `status: template_blank` + 警告（非错误）。
- 三个方向重组预览 + `idle/run/attack` 动作检查通过后，才替换正式 PNG。
- `sensenova-image` 生成图 → 经本 skill 拆件 → `dst-assets-animation-atlas` 编译，端到端可跑通。
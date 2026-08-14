---
name: dst-asset-reskin
description: DST 动画资源换皮/重制复合 skill。把一个已有 DST 动画 zip（Build+Atlas+Bin）整体替换材质纹理并维持原画风与原动画结构，端到端串联 modtool-automation（dmt 工程操作）、sensenova-image（AI 生成新材质）、dst-assets-animation-atlas（KTEX/SCML 编译打包）、sensenova-vision（识图校验）。触发：换皮、换材质、重制纹理、retex、reskin、血肉化、腐蚀化、石头化、换贴图不换动画、dmt 换皮。信号：boat_ancient.zip、anim zip 换皮、.dmt、SetBuild 换纹理、保持原画风。
---

# DST 动画资源换皮（Asset Reskin）

把一个已编译的 DST 动画包（`anim/<x>.zip` 内含 Build + Atlas + Bin）的**材质纹理**整体替换为新纹理，同时**保持原动画结构、原符号层级、原 pivot、原画风笔触**。这是一个**编排型复合 skill**，本身不含新逻辑，只负责把 4 个原子 skill 正确串联成一条流水线。

## 必读：本 skill 是编排层，必须并行加载下面 4 个原子 skill

本 skill 单独加载不足以执行任务。**接到换皮任务后，必须并行加载以下全部 4 个 skill**（一个都不能少）：

| 原子 skill | 在换皮流水线中的职责 |
|---|---|
| `modtool-automation` | 用 `.dmt` 工程导入原 zip → 解出 Build/Symbol/帧 → 导出每帧 PNG → 处理后回填 → 另存新 zip。**唯一能程序化操作 DST Mod Tool 的入口** |
| `sensenova-image` | AI 生成新材质纹理（如血肉、石头、金属、腐蚀）。显式传 `watermark=false`，prompt 锁定原画风 |
| `sensenova-vision` | 识图校验：读原帧 PNG 分析画风/配色/结构；读生成的新纹理判断是否保持原画风；读导出结果验证换皮成功。**禁止用 Read 直接读图片** |
| `dst-assets-animation-atlas` | KTEX 解码/编码、SCML/Anim 编译、`char_sheet_gen.py` 尺寸校验。当 modtool-automation 的 zip 回填失败或需要手工补编时介入 |

**缺少任何一个都会导致流水线断裂**：
- 缺 modtool-automation → 无法程序化操作 zip，只能 GUI 手工（不可接受）
- 缺 sensenova-image → 无法生成新材质，只能用现成贴图
- 缺 sensenova-vision → 无法识图校验，盲改
- 缺 dst-assets-animation-atlas → KTEX/编译兜底缺失

## 流水线总览

```
原 anim zip (D:\...\boat_ancient.zip)
    │
    ▼ [modtool-automation]
    ① tool:open_document / import_resources 导入原 zip
    ② 遍历 build.symbols → 逐符号导出原帧 PNG 到工作目录
    │
    ▼ [sensenova-vision]
    ③ caption-vision.ps1 识读原帧：画风、配色、笔触、明暗、描边
    ④ 组装"画风锚定段"（见下）
    │
    ▼ [sensenova-image]
    ⑤ 基于锚定段 + "换成血肉纹理" 主体词 → 生成新材质 PNG
       -Watermark $false -AspectRatio 与原帧一致
    ⑥ 多帧/多符号时复用锚定段保证风格一致
    │
    ▼ [sensenova-vision]
    ⑦ caption-vision.ps1 识读生成的新纹理，校验是否保持原画风
    ⑧ 偏差过大 → 回 ⑤ 调 prompt 重生成
    │
    ▼ [modtool-automation]
    ⑨ 把新纹理 PNG 按原符号路径/尺寸/pivot 回填到 .dmt 工程
    ⑩ tool:save_document_as 另存为新 zip（不覆盖原 zip）
    │
    ▼ [sensenova-vision / dst-assets-animation-atlas]
    ⑪ 导出若干关键帧 PNG，识图校验换皮后动画外观
    ⑫ 若回填尺寸不符 → dst-assets-animation-atlas 的 KTEX/char_sheet_gen.py 修补
```

## 画风锚定段（跨步骤复用，避免风格漂移）

换皮最容易翻车的地方：AI 生成的新纹理画风与原 zip 不一致。**必须先识读原帧，固定锚定段，后续每张新纹理生成都原样复用**。

锚定段至少包含：
- **画风类型**：如 DST 官方 2D 手绘、厚涂、像素、写实
- **配色基调**：主色、辅色、阴影色、高光色（从原帧识图提取）
- **笔触特征**：描边粗细、是否有抖动线条、纹理密度
- **明暗方向**：光源方向、阴影投射
- **画布尺寸**：原帧像素尺寸（回填时必须一致）

**多符号合并规则**：原 zip 通常有多个符号（如 boat_ancient 的 3+ 符号）。多符号时**先分别识读每个符号的配色，再合并成锚定段**：
- 取各符号的**共同画风描述**（画风类型、笔触、明暗方向在各符号间应一致）
- 为每个符号列出**各自的配色分支清单**（`#PALETTE_符号名#`），生成该符号的新纹理时用其分支，而不是一刀切用一个色板

示例（血肉化 boat_ancient）：

```
#STYLE#：DST 官方 2D 手绘风格，粗描边，平涂色块 + 轻微纹理噪点
#PALETTE#：暗红主色 #6b1f1f，亮红高光 #b03030，深红阴影 #2a0808，骨白点缀 #d4c4a0
#LIGHTING#：左上光源，柔和明暗过渡
#CANVAS#：保持原帧像素尺寸（如 256x256）
#TARGET#：把原有木纹/金属/石头材质整体替换为血肉纹理，保留原符号轮廓与结构，不增减部件
```

## 关键不变量

- **原 zip 永不覆盖**：所有产物写入独立工作目录，另存为新 zip
- **像素尺寸与 pivot 必须与原 Build 一致**：modtool-automation 导出时记录每帧 width/height/pivot，回填时严格匹配
- **画风必须先识图锁定再生成**：不允许跳过 sensenova-vision 直接让 AI "自由发挥"
- **新纹理必须经识图校验**：生成后用 sensenova-vision 识读，画风偏差大则重生成
- **禁止用 Read 工具读图片**：所有识图走 sensenova-vision 的 caption-vision.ps1
- **AI 生成图必须显式传 watermark=false**：避免水印污染纹理
- **dmt 工程是唯一可靠操作入口**：不依赖 GUI 手工

## 与 dmt 的关系

用户提到"dmt 辅助"时，指的就是用 DST Mod Tool 的 `.dmt` 工程文件作为程序化操作载体（`modtool-automation` skill 的 `tool:open_document` / `tool:save_document_as`）。本 skill 全程围绕 `.dmt` 工程展开：导入原 zip → 在工程内替换纹理 → 另存新 zip。

**版本前置检查（必做）**：`tool:open_document` / `tool:save_document_as` / `import_resources` 是 Mod Tool **1.1.13** 才有的能力。流水线开始前必须先确认：
1. 运行 `DST Mod Tool.exe --help`，确认能输出顶层帮助（老版本会直接弹 GUI）
2. 运行 `DST Mod Tool.exe script --help`，确认参考文档里出现 `save_document_as` / `open_document`
3. 两者缺一 → **停止流水线**，回退到 ⑫ 路径（atlas skill 的 KTEX 手工补编）或提示用户升级 Mod Tool，不得在旧版本上硬跑 ⑨→⑩

## 常见换皮语义映射

| 用户说法 | 主体 prompt 词 | 配色锚定 |
|---|---|---|
| 血肉化 / flesh / 肉 | raw flesh texture, organic, sinew, exposed muscle | 暗红主，亮红高光，骨白点缀 |
| 腐蚀化 / corruption | corrupted, decayed, necrotic, oozing | 紫黑主，毒绿高光 |
| 石头化 / petrified | petrified stone, cracked rock, mossy | 灰褐主，苔绿点缀 |
| 金属化 / metallic | brushed metal, riveted iron, rusty | 铁灰主，锈橙点缀 |
| 冰霜化 / frozen | frozen ice, frost, crystalline | 冰蓝主，白高光 |

## 验证

- 原 zip 与新 zip 的 Build/Symbol/帧数完全一致（只换纹理，不改结构）
- 新纹理经 sensenova-vision 识读，画风判定与原帧一致
- **新纹理识读确认右下角无水印文本**（watermark=false 是否真的生效）
- 导出关键帧（idle/run/attack 若有）识图校验外观符合预期
- 新 zip 能被 DST 正常加载（用 modtool-automation 或 atlas skill 的 KTEX 校验）
- **原 zip 文件不落盘修改**：所有回填写入新 zip；`tool:save_document_as` 另存本身就保证新文件，**不做**"原 zip 字节 sha256 对比"（Mod Tool 回填必然重写字节，该断言不可执行）

## 按需资源

- modtool-automation 的 lua_client.py / uia_client.py / diff_detector.py
- sensenova-image 的 call-genimage.ps1（带 -Watermark $false）
- sensenova-vision 的 caption-vision.ps1
- dst-assets-animation-atlas 的 ktex_decode.py / char_sheet_gen.py
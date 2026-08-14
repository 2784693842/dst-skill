# SenseNova 文生图 · 提示词模板

主控模型按这些模板组装最终 `prompt`，再交给 API。模板是可复用片段，按场景拼接。

## 质量增强后缀（默认追加）

```
highly detailed, sharp focus, professional, best quality
```

偏写实时可换成：

```
photorealistic, 8k uhd, dslr, soft lighting, high quality, film grain, Fujifilm XT3
```

## 风格后缀（按需追加其一）

| 风格 | 后缀 |
|---|---|
| 二次元 / 动漫 | `anime style, cel shading, vibrant colors, manga` |
| 油画 | `oil painting, impasto, rich textures, classical` |
| 水彩 | `watercolor, soft edges, wash, paper texture` |
| 像素艺术 | `pixel art, 16-bit, retro game, dithering` |
| 3D 渲染 | `3d render, octane render, cinematic, volumetric lighting` |
| 赛博朋克 | `cyberpunk, neon lights, futuristic, dark moody` |
| 极简 | `minimalist, clean, negative space, flat` |
| 复古胶片 | `vintage film, 35mm, grainy, warm tones, retro` |
| 概念艺术 | `concept art, artstation trending, detailed, epic` |

## 负向约束（需要时追加在末尾）

```
low quality, worst quality, blurry, deformed, distorted, bad anatomy, extra limbs, watermark, text, signature, out of frame
```

> ⚠️ SenseNova `/v1/images/generations` API **没有独立的 negative-prompt 字段**，负向约束只是作为提示词文本拼在末尾，效果有限。

---

## 水印处理 (Watermark)

**事实**：SenseNova 服务端默认在所有生成图片右下角叠加"日日新 sensenova"水印。

### 官方 API 参数（推荐）

请求体传入 `watermark: false` 可关闭水印，**当前免费公测中**，后续将转为付费功能。

```json
{
  "model": "sensenova-u1-fast",
  "prompt": "A cat on a windowsill",
  "size": "2048x2048",
  "n": 1,
  "watermark": false
}
```

**强制显式传入**：为避免未来默认值变更影响线上业务，**所有调用必须显式传入 `watermark` 参数**（默认 `false`），不得依赖服务端默认值。

编排脚本通过 `-Watermark $false` 自动透传，无需手工修改请求体：

```powershell
& .\assets\scripts\call-genimage.ps1 -Prompt "A cat" -Size 2048x2048 -Watermark $false
```

### 提示词层（`-NoWatermark` 开关，仅补充）

`compose-prompt.ps1 -NoWatermark` 会在 prompt 中加入反水印术语（**效果不可靠**，服务端水印是 post-processing 叠加，prompt 层面无法阻止）：

```
no watermark, no logo, no text, no signature, clean image, unbranded, without watermark
```

### 后处理裁剪（付费后的兜底）

如付费后无法关闭水印，可裁剪底部 5–10%：

生成后用 PowerShell 裁剪右下角：

```powershell
# 裁剪底部 8%，移除水印
$src = "output\image.png"
$img = [System.Drawing.Bitmap]::FromFile($src)
$w = $img.Width
$h = [int]($img.Height * 0.92)
$clip = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($clip)
$g.DrawImage($img, 0, 0, 0, 0, $w, $h, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$img.Dispose()
$clip.Save($src)
$clip.Dispose()
```

---

## 系列锚定段（跨轮复用，保证一致）

系列生成时，把"角色 / 场景 / 风格"的锚定描述固定下来，**每轮都原样复用**，只改变动部分：

```
#CHARACTER#：a young woman with silver short hair, green eyes, wearing a navy coat
#SCENE#：standing on a rainy neon-lit city street at night
#STYLE#：anime style, cel shading, cinematic composition
```

组装规则：`#STYLE#，#CHARACTER# #SCENE#，<本轮变动描述>`。
- 变动描述只写"这轮要变的"（如 `holding an umbrella, looking back`）。
- 锚定段一旦用户确认就写入会话记忆，后续轮次直接引用，不重写、不扩写。

## 提示词组装顺序

```
[主描述]，[风格后缀]，[质量后缀]，[负向约束]
```

系列场景则：

```
[风格锚定]，[角色锚定] [场景锚定]，[变动描述]，[质量后缀]，[负向约束]
```

## 多语言注意

`sensenova-u1-fast` 对中文 prompt 支持良好；混排时把视觉主体描述放在最前，风格/质量后缀放最后。

---

## 骨架保留 / 风格迁移 (Skeleton Preservation / Style Translation)

官方 sn-image-base 推荐的核心范式：将提示词拆为三段，中间主体部分作为"骨架"，前后风格段独立替换，从而实现"换风格不换构图"。

```
<构图/场景锚定> + <主体骨架> + <风格后缀>
```

| 段 | 作用 | 替换时 |
|---|---|---|
| 构图/场景锚定 | 确定视角、空间、光影基调 | 换风格时保留 |
| 主体骨架 | 人物/物体的身份、姿态、配色 | 换风格时保留 |
| 风格后缀 | 渲染引擎、笔触、调色 | **自由替换** |

**示例：**

```
# 骨架（固定，不含风格）
A young woman with silver short hair, standing on a rainy neon-lit city street at night, cinematic lighting, shallow depth of field

# 风格 A — 3D 卡通
[骨架] + 3d render, c4d, octane render, vivid colors, glossy finish

# 风格 B — 油画
[骨架] + oil painting, impasto texture, museum quality, rich pigments

# 风格 C — 摄影
[骨架] + photograph, fujifilm xe3, iso 400, natural skin tones
```

**操作步骤：**

1. 先写骨架 prompt（不含风格），单独生成一张验证构图和主体
2. 在骨架末尾追加风格后缀，批量生成变体
3. 对比变体，选出最优风格
4. 如需调整构图/主体，只改骨架段，重跑风格列表

> 工具支持：`genimage-variants.ps1 -Styles a,b,c` 自动将多风格后缀拼到同一骨架后，批量出图。

---

## 构图与比例 (Composition Ratio Guidelines)

不同长宽比对应不同的画面用途，选择时需考虑最终展示场景。官方 sn-infographic 推荐按以下维度决策：

| 比例 | 像素 (2K) | 像素 (1K) | 推荐用途 | 构图要点 |
|---|---|---|---|---|
| 16:9 | 2752×1536 | 1376×768 | 宽屏展示、横幅、壁纸 | 横向留白，主体偏侧 |
| 9:16 | 1536×2752 | 768×1376 | 短视频封面、手机海报 | 竖向主体居中，上下留白 |
| 1:1 | 2048×2048 | 1024×1024 | 社交头像、Instagram | 主体居中对称 |
| 21:9 | 3072×1376 | 1536×688 | 电影宽幅、游戏概念图 | 极宽留白，叙事横向展开 |
| 4:5 | 1824×2272 | 912×1136 | 小红书/竖排社交 | 主体偏上，底部留文案空间 |
| 3:4 | 1760×2368 | 880×1184 | 海报、竖版展示 | 纵向节奏，主体由下至上引导 |
| 9:21 | 1344×3136 | 672×1568 | 超长海报、手机锁屏 | 极端竖构图，分层叙事 |

**构图关键词注入（`-AspectRatio` 自动添加前缀）：**

| 比例 | 自动注入的 Composition 前缀 |
|---|---|
| 16:9 | `Composition: 16:9 landscape, wide cinematic framing, horizontal composition` |
| 9:16 | `Composition: 9:16 portrait, vertical framing, tall composition` |
| 1:1 | `Composition: 1:1 square, centered composition, balanced framing` |
| 21:9 | `Composition: 21:9 ultra-wide, panoramic cinematic framing, extreme horizontal` |
| 其余 | `Composition: <ratio> <orientation>, balanced framing` |

> `compose-prompt.ps1` 的 `-AspectRatio` 参数会自动在 prompt 开头插入对应的前缀，无需手动编写。

---

## 提示词长度与 Token 估算

- 模型最大接受 **4096 token** 的 prompt
- 经验值：100 个英文词 ≈ 130 token，中文需估算为英文 2 倍
- 建议长度：**150–400 英文词**（覆盖构图、主体、风格、质量四个层次）
- 超过 600 词时注意精简，过多细节反而降低生成质量
- 负向约束不计入主 prompt token 上限（追加在末尾）
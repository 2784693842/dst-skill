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
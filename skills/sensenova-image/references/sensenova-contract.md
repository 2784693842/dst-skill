# SenseNova 文生图 API 契约快照

> 来源：`platform.sensenova.cn/docs`（MHT 存档）。Skill 离线执行以此为准，不依赖在线文档。
> 端点与模型名若与在线文档不一致，以在线文档为准并更新本快照。

## 基础

- Base URL：`https://token.sensenova.cn/v1`
- 端点：`POST /images/generations`
- 完整 URL：`https://token.sensenova.cn/v1/images/generations`
- 鉴权：Header `Authorization: Bearer <API_KEY>`
- Content-Type：`application/json`

> 注意：Claude Code SDK 对接时 `ANTHROPIC_BASE_URL` 不带 `/v1`（SDK 自加 `/messages`）；本 skill 直连 `/images/generations`，因此 base 取 `https://token.sensenova.cn/v1`。

## 请求体

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `model` | string | 是 | — | 固定为 `sensenova-u1-fast` |
| `prompt` | string | 是 | — | 图像描述文本，最大 4096 token |
| `size` | string | 否 | `2752x1536` | 图像尺寸，11 种 2K 规格 |
| `n` | integer | 否 | `1` | 生成图片数量 |
| `watermark` | boolean | 否 | `true` | 是否叠加"日日新 sensenova"水印；**必须显式传 `false` 关闭**（当前免费公测，后续转为付费） |

## size 规格表（11 种比例 × 2 种档次 = 22 种精确像素）

官方 BUCKETS 映射表。**推荐使用 `resolve-size.ps1 -AspectRatio <比例> -Tier <1k|2k>` 自动解析**，无需记忆像素值。

| 比例 | 1K 档次 | 2K 档次 | 用途 |
|---|---|---|---|
| `2:3` | `832x1248` | `1664x2496` | 竖，手机海报 |
| `3:2` | `1248x832` | `2496x1664` | 横，经典照片 |
| `3:4` | `880x1184` | `1760x2368` | 竖 |
| `4:3` | `1184x880` | `2368x1760` | 横，屏保 |
| `4:5` | `912x1136` | `1824x2272` | 竖，社交 |
| `5:4` | `1136x912` | `2272x1824` | 横 |
| `1:1` | `1024x1024` | `2048x2048` | 方 |
| `16:9` | `1376x768` | `2752x1536` | 横，宽屏（文档默认） |
| `9:16` | `768x1376` | `1536x2752` | 竖，短视频封面 |
| `21:9` | `1536x688` | `3072x1376` | 超宽 |
| `9:21` | `672x1568` | `1344x3136` | 超长竖 |

> 档次说明：**1K** 总像素约 100 万，适合快速预览和小尺寸展示；**2K** 总像素约 400 万，适合高清出图。未指定档次默认 2K。

## 响应体

OpenAI 兼容形态。**响应主路径是 `url`**，MHT 官方示例未包含 base64 字段：

```json
{
  "created": 1713167890,
  "data": [
    { "url": "https://cdn.sensenova.dev/gen/..." }
  ]
}
```

字段优先级（按官方文档 + OpenAI 兼容惯例）：

1. **`data[].url`**（主路径，官方示例使用）— 图片托管 URL，可下载
2. **`data[].b64_json`**（回退，OpenAI 惯例）— base64 编码字节
3. **`data[].b64` / `data[].image` / `data[].b64_image` / `data[].data`**（兼容更多变体）

## 错误形态

HTTP 非 200 时返回错误 JSON，常见：

| HTTP | 场景 |
|---|---|
| 401 | API_KEY 无效 / 过期 |
| 429 | 触发限流 |
| 400 | 参数非法（如 size 不在规格表）/ 内容违规 |
| 5xx | 服务端错误，可重试 |

## 环境变量回落链

API Key 按以下优先级自动解析（首个非空值生效）：

| 优先级 | 来源 |
|---|---|
| 1 | 环境变量 `SN_KEY` |
| 2 | 环境变量 `SENSENOVA_KEY` |
| 3 | 环境变量 `SENSENOVA_API_KEY` |
| 4 | 环境变量 `SENSENOVA_SECRET_KEY` |
| 5 | 工作目录 `.env` 文件中的同名键 |

默认 base URL 可从 `SENSENOVA_BASE_URL` 环境变量覆盖，未设定时使用 `https://token.sensenova.cn/v1`。

---

## JSON 响应恢复

API 返回的 JSON 可能被包裹在 markdown 代码块中（三反引号或行内反引号），`recover-json.ps1` 负责提取并解析：

1. 先尝试直接 `ConvertFrom-Json`
2. 若失败，去掉 markdown 围栏后再试
3. 扫描平衡的 `{}` / `[]` 括号对，逐个尝试 `ConvertFrom-Json`
4. 首个解析成功即退出；全部失败则报错

---

## Content-Length 校验

`image-save.ps1 -ContentLength <n>` 对下载字节数做 ±1% 容差的校验，防止服务端返回截断或错误内容。

---

## 示例请求

```bash
curl -X POST https://token.sensenova.cn/v1/images/generations \
  -H "Authorization: Bearer $SENSENOVA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "sensenova-u1-fast",
    "prompt": "A serene mountain lake at dawn, misty, cinematic lighting, 4k",
    "size": "2752x1536",
    "n": 1,
    "watermark": false
  }'
```
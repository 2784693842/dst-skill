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

## size 规格表（11 种）

| size | 比例 | 用途 |
|---|---|---|
| `1664x2496` | 2:3 | 竖，手机海报 |
| `2496x1664` | 3:2 | 横，经典照片 |
| `1760x2368` | 3:4 | 竖 |
| `2368x1760` | 4:3 | 横，屏保 |
| `1824x2272` | 4:5 | 竖，社交 |
| `2272x1824` | 5:4 | 横 |
| `2048x2048` | 1:1 | 方 |
| `2752x1536` | 16:9 | 横，宽屏（文档默认） |
| `1536x2752` | 9:16 | 竖，短视频封面 |
| `3072x1376` | 21:9 | 超宽 |
| `1344x3136` | 9:21 | 超长竖 |

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

## 示例请求

```bash
curl -X POST https://token.sensenova.cn/v1/images/generations \
  -H "Authorization: Bearer $SENSENOVA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "sensenova-u1-fast",
    "prompt": "A serene mountain lake at dawn, misty, cinematic lighting, 4k",
    "size": "2752x1536",
    "n": 1
  }'
```
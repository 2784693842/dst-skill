# SenseNova 视觉 API 契约快照

> 来源：`sn-da-image-caption` 官方 skill 分析。Skill 离线执行以此为准。

## 基础

- Base URL：`https://token.sensenova.cn/v1`
- 端点：`POST /chat/completions`（多模态消息）
- 完整 URL：`https://token.sensenova.cn/v1/chat/completions`
- 鉴权：Header `Authorization: Bearer <API_KEY>`
- Content-Type：`application/json`
- 模型：`sensenova-6.7-flash-lite`（视觉多模态专用）

## 请求体

```json
{
  "model": "sensenova-6.7-flash-lite",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "text", "text": "<prompt>"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,<base64>"}}
      ]
    }
  ],
  "max_tokens": 4096
}
```

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `model` | string | 是 | — | 固定 `sensenova-6.7-flash-lite` |
| `messages[].content` | array | 是 | — | 多模态消息数组 |
| `content[0].type` | string | 是 | — | `"text"` |
| `content[0].text` | string | 是 | — | 提示词 |
| `content[1].type` | string | 是 | — | `"image_url"` |
| `content[1].image_url.url` | string | 是 | — | `data:<mime>;base64,<b64>` |
| `max_tokens` | int | 否 | 4096 | 最大输出 token |

## 响应体

标准 OpenAI chat 响应形态：

```json
{
  "choices": [
    {
      "message": { "content": "<caption text>" }
    }
  ],
  "usage": {
    "prompt_tokens": 1100,
    "completion_tokens": 400
  }
}
```

主路径：`choices[0].message.content`（纯文本 caption）

## 环境变量回落链

### API Key

`SN_VISION_API_KEY` → `SN_CHAT_API_KEY` → `SN_API_KEY` → `SENSENOVA_API_KEY` → `.env`

### Base URL

`SN_VISION_BASE_URL` → `SN_CHAT_BASE_URL` → `SN_BASE_URL` → `SENSENOVA_BASE_URL` → `https://token.sensenova.cn/v1`

### 模型

`SN_VISION_MODEL` → `SN_CHAT_MODEL` → `sensenova-6.7-flash-lite`

## 图片类型 Prompt 模板

### chart（图表数据提取）

```
这是一张数据图表。请精确提取以下信息：
1. 图表标题
2. X轴标签（所有类别/时间点）及单位
3. Y轴标签及单位
4. 每个数据点/柱/扇区的具体数值（保留原始精度）
5. 图例名称（如有多系列）
6. 整体趋势或关键发现
请以 Markdown 表格格式输出数值数据。
```

### table（表格截图识别）

```
请精确提取图片中表格的所有内容。要求：
1. 输出为 Markdown 表格格式
2. 保持原始行列结构不变
3. 数值保持原样，不四舍五入、不省略
4. 如有合并单元格，展开并在每行重复填充
5. 表头如有多级，用 / 分隔
```

### ui（界面截图分析）

```
请以前端开发者视角详细描述这个界面截图：
1. 页面整体布局（header/sidebar/content/footer）
2. 每个UI组件（按钮/表单/表格/导航/卡片）的位置和内容
3. 文字内容（完整提取）
4. 颜色主题和字体样式
5. 间距和对齐关系
```

### diagram（流程图/架构图）

```
请描述这张图的完整结构：
1. 图的类型（流程图/架构图/思维导图/ER图/其他）
2. 所有节点的名称和内容
3. 节点之间的连接关系（A → B）和方向
4. 分支条件（如有）
5. 层级或分组关系
6. 整体含义描述
```

### general（通用描述）

```
请详细描述这张图片的内容，包括：主体对象、背景、文字信息、颜色和布局。如果包含文字请完整提取。
```

## 类型检测关键词

| 类型 | 关键词 |
|---|---|
| chart | chart, 图表, 趋势, 柱状, 折线, 饼图, 散点, bar, line, pie, histogram, 可视化, visualization, plot, graph |
| table | table, 表格, excel, 整理, 提取, data, 列表, sheet |
| ui | ui, 截图, screenshot, 界面, 页面, 网页, app, vue, react, html, css, 前端, layout, 设计稿 |
| diagram | 流程, 架构, diagram, flow, 架构图, 思维导图, mindmap, topology, 拓扑, 关系图, er图 |

检测逻辑：文件名 + context 拼接后按关键词命中数计分，最高分类型生效，0 命中回退 `general`。

## 图片压缩规则

| 条件 | 动作 |
|---|---|
| 文件 > 5MB | 压缩为 JPEG (quality=75) |
| 最长边 > 2048px | 等比缩放至 2048px |
| RGBA/P/LA 模式 | 转 RGB + 白色背景 |

压缩参数：`MAX_IMAGE_SIZE_BYTES = 5 * 1024 * 1024`，`MAX_IMAGE_DIMENSION = 2048`，`JPEG_QUALITY = 75`

## 错误映射

| HTTP | 场景 |
|---|---|
| 401 | API_KEY 无效/过期 |
| 429 | 触发限流 |
| 400 | 参数非法/内容违规 |
| 5xx | 服务端错误，可重试 |
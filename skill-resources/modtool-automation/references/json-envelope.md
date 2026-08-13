# JSON 响应协议

`DST Mod Tool.exe script` 子命令的 stdout 输出格式。

## 成功响应

```json
{
  "version": 1,
  "request_id": "唯一请求标识符",
  "response": {
    "type": "script",
    "report": {
      "ok": true,
      "origin": "external_ipc",
      "output": ["print 输出行 1", "print 输出行 2"],
      "error": null,
      "document": {
        "changed": false,
        "before_revision": 4,
        "after_revision": 4,
        "history_label": null
      },
      "tool_results": [],
      "stats": {
        "elapsed_micros": 340,
        "instructions": 0,
        "lua_memory_bytes": 26080,
        "loaded_image_bytes": 0
      }
    }
  }
}
```

## 字段说明

### `version` (integer)
协议版本号，当前为 1。

### `request_id` (string)
唯一请求标识符，用于调试。

### `response.type` (string)
响应类型，当前固定为 `"script"`。

### `response.report`

| 字段 | 类型 | 说明 |
|------|------|------|
| `ok` | `boolean` | 脚本是否成功执行 |
| `origin` | `string` | 执行来源，外部调用时为 `"external_ipc"` |
| `output` | `string[]` | `print()` 的所有输出行 |
| `error` | `object \| null` | 错误信息（成功时为 null） |
| `document` | `object` | 文档变更状态 |
| `tool_results` | `array` | 工具方法执行结果 |
| `stats` | `object` | 执行统计 |

### `document` 子字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `changed` | `boolean` | 本次脚本是否修改了文档 |
| `before_revision` | `integer` | 执行前的版本号 |
| `after_revision` | `integer` | 执行后的版本号 |
| `history_label` | `string \| null` | `set_label` 设置的历史标签 |

### `stats` 子字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `elapsed_micros` | `integer` | 执行耗时（微秒） |
| `instructions` | `integer` | Lua 指令数 |
| `lua_memory_bytes` | `integer` | Lua 内存使用（字节） |
| `loaded_image_bytes` | `integer` | 加载的图像数据（字节） |
| `mutation_stages` | `string[]` | 本次操作执行的事务阶段名称列表 |

## 错误响应

```json
{
  "version": 1,
  "request_id": "...",
  "response": {
    "type": "script",
    "report": {
      "ok": false,
      "origin": "external_ipc",
      "output": [],
      "error": {
        "stage": "parse | execute | serialize",
        "code": "错误代码",
        "message": "人类可读错误信息",
        "traceback": "Lua traceback 字符串"
      },
      "document": {
        "changed": false,
        "before_revision": 4,
        "after_revision": 4,
        "history_label": null
      },
      "tool_results": [],
      "stats": {
        "elapsed_micros": 340,
        "instructions": 0,
        "lua_memory_bytes": 26080,
        "loaded_image_bytes": 0,
        "mutation_stages": []
      }
    }
  }
}
```

**错误时退出码为 1，成功时退出码为 0。**

## 非 JSON 输出（工具启动失败）

当工具无法启动时，stdout 可能为空或非 JSON。`lua_client.py` 应检测这种情况并返回：

```python
LuaResult(
    ok=False,
    error={
        "message": f"subprocess exited with code {code}, stderr: {stderr}",
    }
)
```

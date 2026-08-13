# 三套坐标系转换

DST Mod Tool 自动化涉及三套坐标系，必须精确对齐才能确保点击和截图的准确性。

## 三套坐标系

| 坐标系 | 描述 | 来源 |
|--------|------|------|
| **UIA client 坐标** | 相对窗口客户区（不含标题栏和边框） | `pywinauto` 控件 `rectangle()` |
| **屏幕物理像素坐标** | 相对屏幕左上角（显示器实际像素） | `GetWindowRect()`、`ImageGrab.grab(bbox)` |
| **逻辑坐标** | DPI 缩放后的坐标 | `SendInput`、某些 API |

## 坐标转换公式

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  屏幕物理像素 (ImageGrab / GetWindowRect)                   │
│       ↑                                                    │
│       │ client_to_screen()                                 │
│       │ win_rect.left + client_x                           │
│       │ win_rect.top  + client_y                           │
│       │                                                    │
│       ↓                                                    │
│  UIA client 坐标 (pywinauto 控件 rectangle())               │
│       ↑                                                    │
│       │ / scale                                            │
│       │ scale = GetDpiForWindow() / 96.0                   │
│       ↓                                                    │
│  逻辑坐标 (SendInput)                                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 转换函数

### UIA client → 屏幕物理像素

```python
def client_to_screen(hwnd, client_x, client_y):
    """UIA client 坐标 → 屏幕物理像素坐标"""
    from ctypes import wintypes
    import ctypes
    user32 = ctypes.windll.user32

    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    # rect.left/top 是窗口左上角的屏幕坐标
    screen_x = rect.left + client_x
    screen_y = rect.top + client_y
    return screen_x, screen_y
```

### 屏幕物理像素 → 逻辑坐标

```python
def screen_to_logical(hwnd, screen_x, screen_y):
    """屏幕物理像素坐标 → SendInput 逻辑坐标"""
    import ctypes
    user32 = ctypes.windll.user32

    dpi = user32.GetDpiForWindow(hwnd)
    scale = dpi / 96.0
    return screen_x / scale, screen_y / scale
```

### pywinauto 自动转换（推荐）

```python
from pywinauto import Desktop

desktop = Desktop(backend='uia')
window = desktop.windows(title_re='.*Mod Tool.*')[-1]

# 方法1：直接用控件 click_input()，pywinauto 自动处理所有转换
control = window.child_window(title="Play")
control.click_input()  # ✅ 最可靠

# 方法2：手动 client_to_screen
rect = control.rectangle()
screen_rect = window.client_to_screen(
    (rect.left, rect.top),
    (rect.right, rect.bottom)
)
```

## 实测数据

| 项 | 值 |
|----|-----|
| 窗口类名 | `Zed::Window` |
| DPI | 96 (1.0x，当前环境无缩放) |
| 窗口坐标偏移 | `win_rect.left = -12`, `win_rect.top = -12`（标题栏和边框） |
| `ClientToScreen` API | 对 `Zed::Window` 返回错误结果（直接回传输入值），不可用 |
| pywinauto `client_to_screen()` | 内部用 `GetWindowRect` 正确计算，可用 |

## 注意事项

1. **DPI 缩放**：当前环境 DPI=96（100%），`scale=1.0`，三套坐标完全一致。但在 125% DPI 下，`scale=1.25`，`GetWindowRect` 返回物理像素，`SendInput` 用逻辑坐标，差 25%。

2. **gpui 是 DPI-aware**：gpui 框架（Zed/DST Mod Tool）内部用物理像素渲染，UIA 控件坐标也是物理像素。因此 `GetWindowRect` + UIA 坐标直接对齐，无需 DPI 缩放。

3. **SendInput 的坐标系**：`SendInput` 使用逻辑坐标。如果 `scale ≠ 1.0`，必须手动除以 `scale`。

4. **pywinauto 推荐**：直接用 `control.click_input()`，pywinauto 内部处理所有坐标转换，无需手动计算。

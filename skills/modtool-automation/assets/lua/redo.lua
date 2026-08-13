-- redo.lua: 重做操作
-- 用法: 设置环境变量 DST_REDO_STEPS 后执行（可选，默认 1）

local steps_str = os.getenv("DST_REDO_STEPS") or "1"
local steps = tonumber(steps_str) or 1

doc:set_label("重做 " .. steps .. " 步")
tool:redo(steps)
print("已重做", steps, "步")

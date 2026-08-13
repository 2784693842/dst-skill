-- undo.lua: 撤销操作
-- 用法: 设置环境变量 DST_UNDO_STEPS 后执行（可选，默认 1）

local steps_str = os.getenv("DST_UNDO_STEPS") or "1"
local steps = tonumber(steps_str) or 1

doc:set_label("撤销 " .. steps .. " 步")
tool:undo(steps)
print("已撤销", steps, "步")

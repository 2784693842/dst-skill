-- select_frame.lua: 选择帧（0-based）
-- 用法: 设置环境变量 DST_FRAME_INDEX 后执行

local idx_str = os.getenv("DST_FRAME_INDEX") or "0"
local idx = tonumber(idx_str)

if not idx then
    print("ERROR: DST_FRAME_INDEX 不是有效数字:", idx_str)
    return
end

doc:set_label("选择帧: " .. idx)
tool:select_frame(idx)
print("已选择第", idx, "帧 (0-based)")

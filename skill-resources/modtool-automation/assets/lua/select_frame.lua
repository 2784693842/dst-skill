-- select_frame.lua: 选择帧（0-based）
-- 用法: 设置 DST_FRAME_INDEX (0-based) 和 DST_ANIMATION_NAME 后执行
--       可选: 设置 DST_BANK_NAME 指定 Bank 名

local idx_str = os.getenv("DST_FRAME_INDEX") or "0"
local idx = tonumber(idx_str)

if not idx then
    print("ERROR: DST_FRAME_INDEX 不是有效数字:", idx_str)
    return
end

-- 需要动画上下文才能定位帧
local anim_name = os.getenv("DST_ANIMATION_NAME")
if not anim_name or anim_name == "" then
    print("ERROR: 未设置 DST_ANIMATION_NAME（选择帧需要指定动画）")
    return
end

local bank_name = os.getenv("DST_BANK_NAME") or ""

-- 查找动画 handle
local animation = nil

if bank_name ~= "" then
    local bank = doc.banks:find(bank_name)
    if not bank then
        print("ERROR: Bank 未找到:", bank_name)
        return
    end
    animation = bank.animations:find(anim_name)
else
    for _, bank in ipairs(doc.banks) do
        local a = bank.animations:find(anim_name)
        if a then
            animation = a
            break
        end
    end
end

if animation == nil then
    print("ERROR: 未找到动画:", anim_name)
    return
end

local frame_count = #animation.frames

if idx < 0 or idx >= frame_count then
    print("ERROR: 帧索引越界:", idx, "(动画共有", frame_count, "帧, 有效范围 0.." .. (frame_count - 1) .. ")")
    return
end

-- DST_FRAME_INDEX 是 0-based，animation.frames 是 1-based
local frame = animation.frames[idx + 1]

if frame == nil then
    print("ERROR: 无法获取帧 handle (idx=" .. idx .. ")")
    return
end

doc:set_label("选择帧: " .. anim_name .. "[" .. idx .. "]")
tool:select_frame(frame)
print("已选择帧:", idx, "(0-based) | 动画:", anim_name, "| 总帧数:", frame_count)
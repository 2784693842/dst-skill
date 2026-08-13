-- select_animation.lua: 选择动画
-- 用法: 设置环境变量 DST_ANIMATION_NAME 后执行
--       可选: 设置 DST_BANK_NAME 指定 Bank 名（不指定则遍历所有 Bank）

local anim_name = os.getenv("DST_ANIMATION_NAME")
if not anim_name or anim_name == "" then
    print("ERROR: 未设置 DST_ANIMATION_NAME")
    return
end

local bank_name = os.getenv("DST_BANK_NAME") or ""

local animation = nil
local found_bank = nil
local matches = 0

if bank_name ~= "" then
    -- 指定了 Bank，只在该 Bank 中查找
    local bank = doc.banks:find(bank_name)
    if not bank then
        print("ERROR: Bank 未找到:", bank_name)
        return
    end
    animation = bank.animations:find(anim_name)
    if animation then
        found_bank = bank
        matches = 1
    end
else
    -- 未指定 Bank，遍历所有 Bank 查找
    for _, bank in ipairs(doc.banks) do
        local a = bank.animations:find(anim_name)
        if a then
            if matches == 0 then
                animation = a
                found_bank = bank
            end
            matches = matches + 1
        end
    end
end

if animation == nil then
    print("ERROR: 未找到动画:", anim_name)
    return
end

if matches > 1 then
    print("WARN: 动画名 '" .. anim_name .. "' 在 " .. matches .. " 个 Bank 中存在，使用第一个: " .. found_bank.name)
end

doc:set_label("选择动画: " .. anim_name)
tool:select_animation(animation)
print("已选择动画:", anim_name, "| Bank:", found_bank.name, "| 帧数:", #animation.frames)
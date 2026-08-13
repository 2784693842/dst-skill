-- select_animation.lua: 选择动画
-- 用法: 设置环境变量 DST_ANIMATION_NAME 后执行

local name = os.getenv("DST_ANIMATION_NAME")
if not name or name == "" then
    print("ERROR: 未设置 DST_ANIMATION_NAME")
    return
end

doc:set_label("选择动画: " .. name)
tool:select_animation(name)
print("已选择动画:", name)

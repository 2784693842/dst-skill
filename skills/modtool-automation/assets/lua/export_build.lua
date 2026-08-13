-- export_build.lua: 导出 build 数据
-- 用法: 设置环境变量 DST_EXPORT_PATH 后执行

local out_path = os.getenv("DST_EXPORT_PATH")
if not out_path or out_path == "" then
    print("ERROR: 未设置 DST_EXPORT_PATH（导出目录，必须不存在）")
    print("注意: 输出目录必须不存在，工具会原子写入")
    return
end

local anim_name = os.getenv("DST_ANIMATION_NAME") or ""
local frame_idx = tonumber(os.getenv("DST_FRAME_INDEX") or "0")

if anim_name ~= "" then
    tool:select_animation(anim_name)
end
tool:select_frame(frame_idx)

doc:set_label("导出 build: " .. out_path)

-- 导出当前选中的 build
-- 注意: 具体导出 API 需根据 doc 对象的实际方法调整
print("导出目录:", out_path)
print("动画:", anim_name or "(当前)")
print("帧:", frame_idx)
print("导出设置完成（等待工具执行导出）")

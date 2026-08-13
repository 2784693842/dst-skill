-- export_build.lua: 导出动画帧序列为 PNG
-- 用法: 设置环境变量 DST_EXPORT_PATH（目录，必须不存在）和 DST_ANIMATION_NAME 后执行
--       可选: DST_BANK_NAME、DST_FRAME_INDEX（0-based）、DST_EXPORT_MAX_DIM（默认 1024）、DST_EXPORT_BUILD

local out_path = os.getenv("DST_EXPORT_PATH")
if not out_path or out_path == "" then
    print("ERROR: 未设置 DST_EXPORT_PATH（导出目录，必须不存在）")
    print("注意: 输出目录必须不存在，工具会原子创建并写入编号 PNG")
    return
end

local anim_name = os.getenv("DST_ANIMATION_NAME")
if not anim_name or anim_name == "" then
    print("ERROR: 未设置 DST_ANIMATION_NAME（导出需要指定动画）")
    return
end

local bank_name = os.getenv("DST_BANK_NAME") or ""
local frame_idx_str = os.getenv("DST_FRAME_INDEX") or ""
local max_dim_str = os.getenv("DST_EXPORT_MAX_DIM") or "1024"
local max_dim = tonumber(max_dim_str)
if not max_dim or max_dim <= 0 then
    max_dim = 1024
end

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
if frame_count == 0 then
    print("ERROR: 动画无帧:", anim_name)
    return
end

-- 可选: 选择指定帧（仅影响 UI 定位，不影响导出内容）
if frame_idx_str ~= "" then
    local frame_idx = tonumber(frame_idx_str)
    if frame_idx and frame_idx >= 0 and frame_idx < frame_count then
        local frame = animation.frames[frame_idx + 1]
        if frame then
            tool:select_frame(frame)
            print("已定位到帧:", frame_idx, "(0-based)")
        end
    end
end

-- 构建导出选项
local options = {
    max_dimension = max_dim,
}

-- 可选: 指定 Build（通过环境变量 DST_EXPORT_BUILD）
local build_name = os.getenv("DST_EXPORT_BUILD") or ""
if build_name ~= "" then
    local build = doc.builds:find(build_name)
    if build then
        options.builds = { build }
    else
        print("WARN: Build 未找到:", build_name, "，使用默认 Build")
    end
end

doc:set_label("导出动画帧序列: " .. anim_name)
print("导出动画:", anim_name)
print("帧数:", frame_count)
print("输出目录:", out_path)
print("最大尺寸:", max_dim)

animation:export_png_sequence(out_path, options)

print("导出已提交，等待工具执行")
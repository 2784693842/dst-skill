-- inspect_doc.lua: 打印当前文档的完整状态
-- 用法: DST Mod Tool.exe script --text "$(cat inspect_doc.lua)"
-- 或:   DST Mod Tool.exe script --file inspect_doc.lua

print("=== 文档状态 ===")
print("revision:", tool.document_revision)
print("is_empty:", tool.document_is_empty)
print("path:", tool.document_path or "(未绑定)")

print("\n=== 选中状态 ===")
if tool.selection then
    local sel = tool.selection
    local found = false
    if sel.bank then
        print("bank:", sel.bank.name)
        found = true
    end
    if sel.animation then
        print("animation:", sel.animation.name)
        found = true
    end
    if sel.frame then
        print("frame: (AnimFrame handle)")
        found = true
    end
    if sel.element then
        print("element: (Element handle)")
        found = true
    end
    if not found then
        print("(无选中项)")
    end
else
    print("(无选中项)")
end

print("\n=== 播放状态 ===")
if tool.playback then
    local pb = tool.playback
    print("playing:", pb.playing)
    print("looping:", pb.looping)
    print("frame_index:", pb.frame_index)
    print("frame_count:", pb.frame_count)
    print("fps:", pb.fps)
else
    print("(无播放状态)")
end

print("\n=== 历史状态 ===")
if tool.history then
    local h = tool.history
    print("entries:", h.entries)
    print("cursor:", h.cursor)
    print("can_undo:", h.can_undo)
    print("can_redo:", h.can_redo)
else
    print("(无历史状态)")
end

print("\n=== 隐藏图层 ===")
if tool.hide_layers and #tool.hide_layers > 0 then
    for _, layer in ipairs(tool.hide_layers) do
        print("  -", layer)
    end
else
    print("(无隐藏图层)")
end

print("\n=== 符号覆盖 ===")
if tool.override_symbols and next(tool.override_symbols) then
    for k, v in pairs(tool.override_symbols) do
        print(k .. " -> " .. tostring(v))
    end
else
    print("(无符号覆盖)")
end

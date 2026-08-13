-- inspect_doc.lua: 打印当前文档的完整状态
-- 用法: DST Mod Tool.exe script --text "$(cat inspect_doc.lua)"
-- 或:   DST Mod Tool.exe script --file inspect_doc.lua

print("=== 文档状态 ===")
print("revision:", document_revision)
print("is_empty:", document_is_empty)

print("\n=== 选中状态 ===")
if selection then
    for k, v in pairs(selection) do
        print(k .. ": " .. tostring(v))
    end
else
    print("(未选中)")
end

print("\n=== 播放状态 ===")
if playback then
    for k, v in pairs(playback) do
        print(k .. ": " .. tostring(v))
    end
else
    print("(未播放)")
end

print("\n=== 历史状态 ===")
if history then
    print("entries:", history.entries)
    print("cursor:", history.cursor)
    print("can_undo:", history.can_undo)
    print("can_redo:", history.can_redo)
end

print("\n=== 隐藏图层 ===")
if hide_layers and #hide_layers > 0 then
    for _, layer in ipairs(hide_layers) do
        print("  -", layer)
    end
else
    print("(无隐藏图层)")
end

print("\n=== 符号覆盖 ===")
if override_symbols and next(override_symbols) then
    for k, v in pairs(override_symbols) do
        print(k .. " -> " .. tostring(v))
    end
else
    print("(无符号覆盖)")
end

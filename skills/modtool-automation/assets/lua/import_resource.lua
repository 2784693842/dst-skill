-- import_resource.lua: 导入资源文件
-- 参数通过 os.getenv 获取（工具环境变量接口）
-- 用法: 设置环境变量 DST_RESOURCE_PATH 后执行
-- 或:   直接修改下面的路径

local paths_str = os.getenv("DST_RESOURCE_PATHS") or ""
if paths_str == "" then
    print("ERROR: 未设置资源路径")
    print("请通过环境变量 DST_RESOURCE_PATHS 传入路径（多个路径用分号分隔）")
    return
end

-- 解析路径列表（分号分隔）
local paths = {}
for p in paths_str:gmatch("([^;]+)") do
    paths[#paths + 1] = p:gsub("^%s*(.-)%s*$", "%1")
end

if #paths == 0 then
    print("ERROR: 路径列表为空")
    return
end

-- 设置操作标签
local label = os.getenv("DST_OPERATION_LABEL") or ("导入资源: " .. #paths .. " 个文件")
doc:set_label(label)

print("导入资源:", #paths, "个文件")
for _, p in ipairs(paths) do
    print("  -", p)
end

doc:import_resources(paths)

print("导入完成")

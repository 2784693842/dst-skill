-- 带 netvar 的最小网络 Prefab 骨架（对照原版 prefabs/firepit.lua 结构）
-- 所有网络字段必须在 SetPristine() 之前声明；非主机分支在 SetPristine 后立即返回。
-- net_bool / net_byte / net_uint / net_entity / net_string 均为全局函数（见 netvars.lua），无需 require。

local function OnActiveDirty(inst)
    -- dirty 回调：只更新表现/缓存，绝不在这里做权威逻辑
    inst.active = inst._active:value() ~= 0
    if inst.components.mymod_visual then
        inst.components.mymod_visual:Refresh()
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()   -- 1. 先 AddNetwork

    inst:AddTag("mymod")
    inst:AddTag("structure")

    -- 2. 在 SetPristine 前声明直接挂在实体上的 netvar（net_bool / net_byte / net_uint / net_entity / net_string 等）
    inst._active = net_bool(inst.GUID, "mymod.active", "activedirty")
    inst._count = net_byte(inst.GUID, "mymod.count", "countdirty")

    -- 3. 非主机端（客户端）监听 dirty 事件，只更新表现
    if not TheWorld.ismastersim then
        inst:ListenForEvent("activedirty", OnActiveDirty)
    end

    inst.entity:SetPristine()   -- 4. SetPristine

    if not TheWorld.ismastersim then
        return inst             -- 5. 非主机立即返回
    end

    -- 6. 主机端才加 Component / 权威逻辑 / 保存
    inst:AddComponent("mymodlogic")
    inst:AddComponent("inspectable")

    return inst
end

return Prefab("mymod_prefab", fn)

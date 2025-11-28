local _G = GLOBAL

-- ========== 导入模块 ==========

-- 导入组件 Hook（需要在符文实现之前加载）
modimport("scripts/hooks/component_hooks.lua")

-- 导入符文实现
modimport("scripts/runes/silver_runes.lua")
modimport("scripts/runes/gold_runes.lua")
modimport("scripts/runes/prismatic_runes.lua")

-- 导入核心系统（需要在所有符文实现之后加载）
modimport("scripts/runes/rune_core.lua")

-- ========== RPC 处理 ==========

AddModRPCHandler("Augment", "SelectRune", function(inst)
    if inst and inst:IsValid() and inst:HasTag("player") then
        SelectRandomRune(inst)
    end
end)

-- ========== 按键监听 ==========

_G.TheInput:AddKeyDownHandler(_G.KEY_Z, function()
    if _G.ThePlayer and _G.ThePlayer:IsValid() then
        _G.SendModRPCToServer(_G.GetModRPC("Augment", "SelectRune"))
    end
end)

-- ========== 玩家初始化 ==========

AddPlayerPostInit(function(inst)
    -- 初始化符文相关变量
    inst._current_rune = nil
    
    if _G.TheWorld.ismastersim then
        -- 确保玩家有必要的组件
        if not inst.components.talker then
            inst:AddComponent("talker")
        end
    end
end)

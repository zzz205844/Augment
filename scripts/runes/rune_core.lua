local _G = GLOBAL

-- ========== 符文定义 ==========

-- 银色符文池
SILVER_RUNES = {
    "炼狱龙魂",  -- 攻击附带42点aoe伤害，范围2，冷却8秒
    "海洋龙魂",  -- 攻击恢复4点生命和4点san，冷却8秒
    "云端龙魂",  -- 脱离战斗8秒后获得15%移速，持续到下次进入战斗
}

-- 金色符文池
GOLD_RUNES = {
    "超级加倍",  -- 被你杀死的生物立即复活一次，死亡时双倍掉落
    "超越死亡",  -- 死亡时回满生命值，但3秒内持续降低为0。如果3秒内击杀任意生物则停止并将生命值调整为10点
    "无休恢复",  -- 移动和传送回复生命值，每移动10m恢复1点生命
}

-- 棱彩符文池
PRISMATIC_RUNES = {
    "连锁闪电",  -- 对敌人造成伤害时，对附近另一敌人造成50%连锁伤害；砍树挖矿时对附近同类目标造成50%效果
    "禁字诀",    -- 不能穿戴服装和护甲，根据损失的生命值获得最多30%移速、30%伤害加成和30%吸血
    "双刀流",    -- 拥有副武器槽，每次攻击副武器造成40%伤害并附加全额特殊效果，副武器每次攻击消耗全额
}

-- ========== 符文应用映射 ==========

RUNE_HANDLERS = {
    ["炼狱龙魂"] = ApplyInfernoDragon,
    ["海洋龙魂"] = ApplyOceanDragon,
    ["云端龙魂"] = ApplyCloudDragon,
    ["超级加倍"] = ApplyDoubleUp,
    ["超越死亡"] = ApplyBeyondDeath,
    ["无休恢复"] = ApplyEndlessRecovery,
    ["连锁闪电"] = ApplyChainLightning,
    ["禁字诀"] = ApplyForbiddenSeal,
    ["双刀流"] = ApplyDualWield,
}

-- ========== 符文应用函数 ==========

function ApplyRune(inst, rune_name)
    if not _G.TheWorld.ismastersim then return end
    
    -- 移除旧符文效果（如果有）
    if inst._current_rune then
        -- 清理旧的符文效果
        local old_rune = inst._current_rune
        if old_rune == "炼狱龙魂" then
            if inst._inferno_listener then
                inst:RemoveEventCallback("onattackother", inst._inferno_listener)
                inst._inferno_listener = nil
            end
            -- 取消周期性任务
            if inst._inferno_cooldown_task then
                inst._inferno_cooldown_task:Cancel()
                inst._inferno_cooldown_task = nil
            end
            -- 清理冷却时间变量
            inst._inferno_cooldown = nil
        elseif old_rune == "海洋龙魂" then
            if inst._ocean_listener then
                inst:RemoveEventCallback("onattackother", inst._ocean_listener)
                inst._ocean_listener = nil
            end
            -- 取消周期性任务
            if inst._ocean_cooldown_task then
                inst._ocean_cooldown_task:Cancel()
                inst._ocean_cooldown_task = nil
            end
            -- 清理冷却时间变量
            inst._ocean_cooldown = nil
        elseif old_rune == "云端龙魂" then
            inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "cloud_dragon")
            if inst._cloud_combat_listener then
                inst:RemoveEventCallback("onattackother", inst._cloud_combat_listener)
                inst:RemoveEventCallback("attacked", inst._cloud_combat_listener)
                inst._cloud_combat_listener = nil
            end
            -- 取消周期性任务
            if inst._cloud_update_task then
                inst._cloud_update_task:Cancel()
                inst._cloud_update_task = nil
            end
        elseif old_rune == "超级加倍" then
            -- 先移除事件监听器
            if inst._doubleup_listener then
                inst:RemoveEventCallback("onattackother", inst._doubleup_listener)
                inst._doubleup_listener = nil
            end
            
            -- 先清除标记，防止 Hook 函数中的检查通过
            DOUBLE_UP_KILLERS[inst] = nil
            
            -- 清理所有被 Hook 的 health 组件
            if inst._doubleup_victims then
                for victim, has_died in pairs(inst._doubleup_victims) do
                    if victim and victim:IsValid() and victim.components.health then
                        -- 如果 health 组件的 SetVal 被 Hook 了，恢复原始方法
                        if victim.components.health._doubleup_oldSetVal then
                            victim.components.health.SetVal = victim.components.health._doubleup_oldSetVal
                            victim.components.health._doubleup_oldSetVal = nil
                        end
                    end
                end
                inst._doubleup_victims = nil
            end
        elseif old_rune == "超越死亡" then
            if inst._beyond_death_listener then
                inst:RemoveEventCallback("death", inst._beyond_death_listener)
                inst._beyond_death_listener = nil
            end
            if inst._beyond_death_task then
                inst._beyond_death_task:Cancel()
                inst._beyond_death_task = nil
            end
            if inst._beyond_death_killed_listener then
                inst:RemoveEventCallback("killed", inst._beyond_death_killed_listener)
                inst._beyond_death_killed_listener = nil
            end
        elseif old_rune == "连锁闪电" then
            if inst._chain_listener then
                inst:RemoveEventCallback("onattackother", inst._chain_listener)
                inst._chain_listener = nil
            end
            CHAIN_LIGHTNING_WORKERS[inst] = nil
        elseif old_rune == "禁字诀" then
            -- 恢复原始的Equip函数
            if inst._forbidden_old_equip then
                inst.components.inventory.Equip = inst._forbidden_old_equip
                inst._forbidden_old_equip = nil
            end
            -- 移除其他效果
            inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "forbidden_seal")
            inst.components.combat.damagemultiplier = 1
            inst._forbidden_lifesteal = 0
        elseif old_rune == "无休恢复" then
            -- 取消周期性任务
            if inst._endless_recovery_task then
                inst._endless_recovery_task:Cancel()
                inst._endless_recovery_task = nil
            end
            -- 移除传送事件监听器
            if inst._endless_teleported_listener then
                inst:RemoveEventCallback("teleported", inst._endless_teleported_listener)
                inst._endless_teleported_listener = nil
            end
            -- 清理变量
            inst._endless_distance = nil
            inst._endless_last_pos = nil
        elseif old_rune == "双刀流" then
            -- 移除攻击事件监听器
            if inst._dual_wield_attack_listener then
                inst:RemoveEventCallback("onattackother", inst._dual_wield_attack_listener)
                inst._dual_wield_attack_listener = nil
            end
            -- 移除tag
            if inst:HasTag("dual_wielder") then
                inst:RemoveTag("dual_wielder")
            end
            -- 清理副武器引用
            if inst._dual_wield_offhand then
                local old_item = inst._dual_wield_offhand
                if old_item:IsValid() then
                    old_item:RemoveTag("dual_wield_offhand")
                end
                inst._dual_wield_offhand = nil
            end
        end
    end
    
    -- 应用新符文
    inst._current_rune = rune_name
    
    local handler = RUNE_HANDLERS[rune_name]
    if handler then
        handler(inst)
    end
    
    -- 显示消息
    local message = "应用符文: " .. rune_name
    print(message)
    if inst.components.talker then
        inst.components.talker:Say(message)
    end
end

-- ========== 随机选择符文 ==========

function SelectRandomRune(inst)
    if not _G.TheWorld.ismastersim then return end
    
    -- 测试模式：只从金色符文池中随机选择一个符文
    local selected_rune = GOLD_RUNES[_G.math.random(1, #GOLD_RUNES)]
    
    --[[ 原逻辑：随机选择一个符文池
    -- 随机选择一个符文池
    local pool_type = _G.math.random(1, 3)
    local rune_pool = nil
    local pool_name = ""
    
    if pool_type == 1 then
        rune_pool = SILVER_RUNES
        pool_name = "银色符文池"
    elseif pool_type == 2 then
        rune_pool = GOLD_RUNES
        pool_name = "金色符文池"
    else
        rune_pool = PRISMATIC_RUNES
        pool_name = "棱彩符文池"
    end
    
    -- 从选择的池子中随机选择一个符文
    local selected_rune = rune_pool[_G.math.random(1, #rune_pool)]
    --]]
    
    -- 应用符文
    ApplyRune(inst, selected_rune)
end


local _G = GLOBAL

-- ========== 银色符文实现 ==========

-- 炼狱龙魂：攻击附带AOE伤害
function ApplyInfernoDragon(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst._inferno_cooldown = 0  -- 冷却时间计时器
    
    -- 监听攻击事件以触发AOE
    local function OnAttack(inst, data)
        if data and data.target and inst._inferno_cooldown <= 0 then
            local x, y, z = data.target.Transform:GetWorldPosition()
            local ents = _G.TheSim:FindEntities(x, y, z, 2, nil, {"INLIMBO", "player", "companion", "abigail"})
            
            for _, ent in ipairs(ents) do
                if ent.components.combat then
                    ent.components.combat:GetAttacked(inst, 42, nil)
                end
            end
            
            inst._inferno_cooldown = 8  -- 设置8秒冷却
        end
    end
    
    -- 冷却时间递减（保存任务引用以便清理）
    inst._inferno_cooldown_task = inst:DoPeriodicTask(0.1, function(inst)
        if inst._inferno_cooldown and inst._inferno_cooldown > 0 then
            inst._inferno_cooldown = inst._inferno_cooldown - 0.1
            if inst._inferno_cooldown <= 0 then
                inst._inferno_cooldown = 0
            end
        end
    end)
    
    inst:ListenForEvent("onattackother", OnAttack)
    inst._inferno_listener = OnAttack
end

-- 海洋龙魂：攻击恢复生命和san
function ApplyOceanDragon(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst._ocean_cooldown = 0
    
    -- 监听攻击事件以触发治疗效果
    local function OnAttack(inst, data)
        if data and data.target and inst._ocean_cooldown <= 0 then
            if inst.components.health then
                inst.components.health:DoDelta(4)
            end
            if inst.components.sanity then
                inst.components.sanity:DoDelta(4)
            end
            
            inst._ocean_cooldown = 8
        end
    end
    
    -- 冷却时间递减（保存任务引用以便清理）
    inst._ocean_cooldown_task = inst:DoPeriodicTask(0.1, function(inst)
        if inst._ocean_cooldown and inst._ocean_cooldown > 0 then
            inst._ocean_cooldown = inst._ocean_cooldown - 0.1
            if inst._ocean_cooldown <= 0 then
                inst._ocean_cooldown = 0
            end
        end
    end)
    
    inst:ListenForEvent("onattackother", OnAttack)
    inst._ocean_listener = OnAttack
end

-- 云端龙魂：脱离战斗8秒后获得额外移速
function ApplyCloudDragon(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst._cloud_last_combat = _G.GetTime()
    inst._cloud_speed_active = false
    
    -- 记录最近一次战斗相关事件
    local function OnCombatEvent()
        inst._cloud_last_combat = _G.GetTime()
    end
    
    -- 根据战斗状态控制移速增益
    local function UpdateCloudSpeed(inst)
        local current_time = _G.GetTime()
        
        -- 检测是否在战斗中
        local in_combat = false
        if inst.components.combat and inst.components.combat.target then
            in_combat = true
            inst._cloud_last_combat = current_time
        elseif inst.sg and inst.sg:HasStateTag("attack") then
            in_combat = true
            inst._cloud_last_combat = current_time
        end
        
        if not in_combat and current_time - inst._cloud_last_combat >= 8 then
            -- 脱离战斗8秒，激活移速加成
            if not inst._cloud_speed_active then
                inst.components.locomotor:SetExternalSpeedMultiplier(inst, "cloud_dragon", 1.5)
                inst._cloud_speed_active = true
            end
        else
            -- 进入战斗，移除移速加成
            if inst._cloud_speed_active then
                inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "cloud_dragon")
                inst._cloud_speed_active = false
            end
        end
    end
    
    inst:ListenForEvent("onattackother", OnCombatEvent)
    inst:ListenForEvent("attacked", OnCombatEvent)
    inst._cloud_combat_listener = OnCombatEvent
    
    inst._cloud_update_task = inst:DoPeriodicTask(0.5, UpdateCloudSpeed)
end


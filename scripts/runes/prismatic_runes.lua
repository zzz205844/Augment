local _G = GLOBAL

-- ========== 棱彩符文实现 ==========

-- 连锁闪电：伤害连锁，工作连锁
function ApplyChainLightning(inst)
    if not _G.TheWorld.ismastersim then return end
    
    CHAIN_LIGHTNING_WORKERS[inst] = true
    
    local function OnAttack(inst, data)
        if data and data.target then
            local x, y, z = data.target.Transform:GetWorldPosition()
            local ents = _G.TheSim:FindEntities(x, y, z, 5, {"_combat"}, {"INLIMBO", "player", "companion", "abigail"})
            
            for _, ent in ipairs(ents) do
                if ent ~= data.target and ent.components.combat and ent.components.combat:CanBeAttacked(inst) then
                    local damage = data.damage or (inst.components.combat and inst.components.combat.defaultdamage or 34)
                    ent.components.combat:GetAttacked(inst, damage * 0.5, nil)
                    break  -- 只连锁一个
                end
            end
        end
    end
    
    inst:ListenForEvent("onattackother", OnAttack)
    inst._chain_listener = OnAttack
end

-- 禁字诀：不能穿戴装备，根据生命值损失获得加成
function ApplyForbiddenSeal(inst)
    if not _G.TheWorld.ismastersim then return end
    
    -- 禁用装备（保存原始函数以便之后恢复）
    if not inst._forbidden_old_equip then
        inst._forbidden_old_equip = inst.components.inventory.Equip
    end
    function inst.components.inventory:Equip(item, old_to_active)
        if item and (item:HasTag("armor") or item:HasTag("clothing")) then
            if inst.components.talker then
                inst.components.talker:Say("禁字诀：无法装备护甲和服装")
            end
            return false
        end
        return inst._forbidden_old_equip(self, item, old_to_active)
    end
    
    -- 根据生命值损失更新加成
    local function UpdateForbiddenBonus(inst)
        if inst.components.health then
            local health_percent = inst.components.health:GetPercent()
            local lost_percent = 1 - health_percent
            local bonus_multiplier = math.min(lost_percent * 0.33, 0.30)  -- 最多30%
            
            -- 移速加成
            inst.components.locomotor:SetExternalSpeedMultiplier(inst, "forbidden_seal", 1 + bonus_multiplier)
            
            -- 伤害加成
            inst.components.combat.damagemultiplier = 1 + bonus_multiplier
            
            -- 吸血效果（需要hook攻击事件）
            inst._forbidden_lifesteal = bonus_multiplier
        end
    end
    
    -- 实现吸血
    local function OnAttack(inst, data)
        if data and data.target and inst._forbidden_lifesteal and inst._forbidden_lifesteal > 0 then
            local damage = data.damage or (inst.components.combat and inst.components.combat.defaultdamage or 34)
            local heal = damage * inst._forbidden_lifesteal
            if inst.components.health then
                inst.components.health:DoDelta(heal)
            end
        end
    end
    
    inst:ListenForEvent("onattackother", OnAttack)
    inst:ListenForEvent("healthdelta", UpdateForbiddenBonus)
    inst:DoPeriodicTask(0.1, UpdateForbiddenBonus)
end

-- 双刀流：副武器槽
function ApplyDualWield(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst._dual_wield_offhand = nil
    
    -- 添加副武器槽（使用一个tag来标记）
    inst:AddTag("dual_wielder")
    
    local function OnAttack(inst, data)
        if data and data.target and inst._dual_wield_offhand then
            local offhand = inst._dual_wield_offhand
            if offhand and offhand:IsValid() and offhand.components.weapon then
                local damage = offhand.components.weapon.damage * 0.4
                data.target.components.combat:GetAttacked(inst, damage, offhand)
                
                -- 触发副武器的特殊效果
                if offhand.components.weapon.onattack then
                    offhand.components.weapon.onattack(offhand, inst, data.target)
                end
                
                -- 消耗耐久（全额）
                if offhand.components.finiteuses then
                    offhand.components.finiteuses:Use(1)
                end
            end
        end
    end
    
    inst:ListenForEvent("onattackother", OnAttack)
    inst._dual_wield_attack_listener = OnAttack  -- 保存引用以便清理
    
    -- 添加RPC来设置副武器
    AddModRPCHandler("Augment", "SetOffhand", function(player, item)
        if player._dual_wield_offhand then
            -- 移除旧副武器
            local old_item = player._dual_wield_offhand
            if old_item:IsValid() then
                old_item:RemoveTag("dual_wield_offhand")
            end
        end
        
        if item and item:IsValid() and item.components.weapon then
            item:AddTag("dual_wield_offhand")
            player._dual_wield_offhand = item
        else
            player._dual_wield_offhand = nil
        end
    end)
end


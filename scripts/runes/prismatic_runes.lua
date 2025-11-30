local _G = GLOBAL

-- ========== 棱彩符文实现 ==========

-- 连锁闪电：伤害连锁，工作连锁
-- 处理连锁闪电符文的主效果（攻击与工作连锁）
function ApplyChainLightning(inst)
    if not _G.TheWorld.ismastersim then return end
    
    CHAIN_LIGHTNING_WORKERS[inst] = true
    
    -- 监听攻击事件以执行连锁伤害
    local function OnAttack(inst, data)
        if data and data.target then
            local x, y, z = data.target.Transform:GetWorldPosition()
            local ents = _G.TheSim:FindEntities(x, y, z, 5, nil, {"INLIMBO", "player", "companion", "abigail"})
            
            for _, ent in ipairs(ents) do
                if ent ~= data.target and ent ~= inst and ent.components.combat and ent.components.combat:CanBeAttacked(inst) then
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
    if not inst.components.inventory then return end
    
    local inventory = inst.components.inventory
    local EQUIPSLOTS = _G.EQUIPSLOTS
    
    -- 判断物品是否属于禁字诀禁止装备的类别
    local function IsForbiddenItem(item)
        if not item or not item.components or not item.components.equippable then
            return false
        end
        local slot = item.components.equippable.equipslot
        return slot == EQUIPSLOTS.HEAD
            or slot == EQUIPSLOTS.BODY
            or item:HasTag("armor")
            or item:HasTag("clothing")
    end
    
    -- 提示玩家当前无法装备护甲或服装
    local function RejectEquip()
        if inst.components.talker then
            inst.components.talker:Say("禁字诀：无法装备护甲和服装")
        end
    end
    
    local function GiveItemToBackpack(item)
        if not item then
            return true
        end
        local success = inventory:GiveItem(item, nil, inst:GetPosition())
        return success and item.components.inventoryitem and item.components.inventoryitem.owner == inst
    end
    
    -- 将指定槽位中的物品移回背包，失败时返回 false
    local function StoreSlotItem(slot, stored_items)
        local equipped = inventory:GetEquippedItem(slot)
        if not equipped or not IsForbiddenItem(equipped) then
            return true
        end
        local removed = inventory:Unequip(slot)
        if not removed then
            return true
        end
        if GiveItemToBackpack(removed) then
            if stored_items then
                table.insert(stored_items, removed)
            end
            return true
        end
        -- 背包没有空间，尝试重新装备回原位
        if removed:IsValid() then
            inventory:Equip(removed)
        end
        return false
    end
    
    -- 先尝试把现有的护甲/服装移回背包，确保空间充足
    local stored_items = {}
    for _, slot in ipairs({EQUIPSLOTS.HEAD, EQUIPSLOTS.BODY}) do
        if not StoreSlotItem(slot, stored_items) then
            for _, item in ipairs(stored_items) do
                if item and item:IsValid() then
                    inventory:Equip(item)
                end
            end
            if inst.components.talker then
                inst.components.talker:Say("背包空间不足，无法应用禁字诀")
            end
            return
        end
    end
    
    -- 禁用装备（保存原始函数以便之后恢复）
    if not inst._forbidden_old_equip then
        inst._forbidden_old_equip = inventory.Equip
    end
    if inst._forbidden_old_equip then
        -- 覆写 Equip 函数来拒绝护甲/服装
        inventory.Equip = function(self, item, ...)
            if IsForbiddenItem(item) then
                RejectEquip()
                return false
            end
            return inst._forbidden_old_equip(self, item, ...)
        end
    end
    
    -- 监听装备事件，阻止其它系统重新穿戴护甲
    local function OnEquip(inst, data)
        if data and data.item and IsForbiddenItem(data.item) then
            inst:DoTaskInTime(0, function()
                if inst.components.inventory then
                    local slot = data.eslot or (data.item.components.equippable and data.item.components.equippable.equipslot)
                    if slot then
                        local removed = inst.components.inventory:Unequip(slot)
                        if removed then
                            if not GiveItemToBackpack(removed) then
                                inst.components.inventory:DropItem(removed, true, true)
                            end
                        end
                    end
                end
                RejectEquip()
            end)
        end
    end
    
    -- 根据生命值损失更新加成
    local function UpdateForbiddenBonus(inst)
        if inst.components.health then
            local health_percent = inst.components.health:GetPercent()
            local lost_percent = 1 - health_percent
            local bonus_multiplier = _G.math.min(lost_percent * 0.33, 0.30)  -- 最多30%
            
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
    inst._forbidden_attack_listener = OnAttack
    
    inst:ListenForEvent("healthdelta", UpdateForbiddenBonus)
    inst._forbidden_health_listener = UpdateForbiddenBonus
    
    inst:ListenForEvent("equip", OnEquip)
    inst._forbidden_equip_listener = OnEquip
    
    inst._forbidden_bonus_task = inst:DoPeriodicTask(0.1, UpdateForbiddenBonus)
    UpdateForbiddenBonus(inst)
end

-- 双刀流：副武器槽
function ApplyDualWield(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst._dual_wield_offhand = nil
    
    -- 添加副武器槽（使用一个tag来标记）
    inst:AddTag("dual_wielder")
    
    -- 监听攻击事件以触发副武器的额外打击
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


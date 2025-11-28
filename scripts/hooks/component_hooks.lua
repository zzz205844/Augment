local _G = GLOBAL

-- ========== 组件 Hook ==========

-- 用于超级加倍的双倍掉落
DOUBLE_UP_KILLERS = DOUBLE_UP_KILLERS or {}

-- Hook lootdropper组件实现双倍掉落
AddComponentPostInit("lootdropper", function(LootDropper, lootdropper_inst)
    local oldGenerateLoot = LootDropper.GenerateLoot
    
    function LootDropper:GenerateLoot()
        local loot = oldGenerateLoot(self)
        
        -- 检查是否被超级加倍玩家杀死
        -- 通过 combat 组件的 lastattacker 获取击杀者
        local killer = nil
        if self.inst.components.combat and self.inst.components.combat.lastattacker then
            killer = self.inst.components.combat.lastattacker
        end
        
        if killer and killer:IsValid() and DOUBLE_UP_KILLERS[killer] then
            -- 双倍掉落
            local doubled_loot = {}
            for _, item_prefab in ipairs(loot) do
                table.insert(doubled_loot, item_prefab)
                table.insert(doubled_loot, item_prefab)
            end
            loot = doubled_loot
        end
        
        return loot
    end
end)

-- 用于连锁闪电的工作连锁
CHAIN_LIGHTNING_WORKERS = CHAIN_LIGHTNING_WORKERS or {}

-- Hook workable组件实现工作连锁
AddComponentPostInit("workable", function(Workable, workable_inst)
    local oldWorkedBy = Workable.WorkedBy
    
    function Workable:WorkedBy(worker, numworks, ...)
        local result = oldWorkedBy(self, worker, numworks, ...)
        
        -- 检查是否是连锁闪电玩家
        if worker and worker:IsValid() and CHAIN_LIGHTNING_WORKERS[worker] and numworks and numworks > 0 then
            local x, y, z = workable_inst.Transform:GetWorldPosition()
            local ents = _G.TheSim:FindEntities(x, y, z, 5, nil, {"INLIMBO"})
            
            for _, ent in ipairs(ents) do
                if ent ~= workable_inst and ent.components.workable and ent.prefab == workable_inst.prefab and ent.components.workable:CanBeWorked() then
                    ent.components.workable:WorkedBy(worker, numworks * 0.5)
                    break  -- 只连锁一个
                end
            end
        end
        
        return result
    end
end)


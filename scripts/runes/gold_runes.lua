local _G = GLOBAL

-- ========== 金色符文实现 ==========

-- 超级加倍：生物复活并双倍掉落
function ApplyDoubleUp(inst)
    if not _G.TheWorld.ismastersim then return end
    
    DOUBLE_UP_KILLERS[inst] = true
    
    -- 跟踪所有被标记的生物，记录是否已经"死过一次"
    -- 值为 false 表示还没死过，true 表示已经死过一次
    inst._doubleup_victims = inst._doubleup_victims or {}
    
    -- 在攻击时 Hook 目标的 health 组件
    local function OnAttackOther(inst, data)
        if data and data.target and data.target.components.health then
            local victim = data.target
            
            -- 如果这个生物还没有被 Hook，说明是第一次被这个玩家攻击
            if not inst._doubleup_victims[victim] then
                -- 标记这个生物，false 表示还没死过
                inst._doubleup_victims[victim] = false
                
                -- 保存原始的 SetVal 方法（如果还没有保存）
                if not victim.components.health._doubleup_oldSetVal then
                    victim.components.health._doubleup_oldSetVal = victim.components.health.SetVal
                    
                    -- Hook SetVal 方法，在第一次死亡时立即恢复生命值
                    victim.components.health.SetVal = function(self, val, cause, afflicter)
                        local old_health = self.currenthealth
                        
                        -- 先调用原始方法
                        local result = self._doubleup_oldSetVal(self, val, cause, afflicter)
                        
                        -- 检查是否是第一次死亡（生命值从正数降到0或以下）
                        if old_health > 0 and self.currenthealth <= 0 then
                            -- 检查是否是被超级加倍玩家杀死，且还没死过
                            if inst._doubleup_victims and 
                               not inst._doubleup_victims[victim] and 
                               DOUBLE_UP_KILLERS[inst] then
                                
                                -- 标记为已经死过一次
                                inst._doubleup_victims[victim] = true
                                
                                -- 立即恢复满血，阻止死亡流程
                                self.currenthealth = self.maxhealth
                                if self.inst.replica and self.inst.replica.health then
                                    self.inst.replica.health:SetIsDead(false)
                                end
                                
                                -- 触发复活事件（如果有复活动画）
                                self.inst:PushEvent("respawn")
                                
                                -- 恢复原始的 SetVal 方法（只复活一次）
                                self.SetVal = self._doubleup_oldSetVal
                                self._doubleup_oldSetVal = nil
                                
                                return result
                            end
                        end
                        
                        return result
                    end
                end
            end
        end
    end
    
    inst:ListenForEvent("onattackother", OnAttackOther)
    inst._doubleup_listener = OnAttackOther
end

-- 超越死亡：死亡时回满生命，3秒内降低为0，击杀生物可停止
function ApplyBeyondDeath(inst)
    if not _G.TheWorld.ismastersim then return end
    
    local function OnDeath(inst)
        if inst.components.health and inst.components.health:IsDead() then
            local max_health = inst.components.health.maxhealth
            inst.components.health:SetCurrentHealth(max_health)
            inst:PushEvent("respawnfromghost")
            
            local time_left = 3.0
            local saved = false
            
            local function DeathCountdown()
                if not saved and inst and inst:IsValid() and inst.components.health then
                    if time_left > 0 then
                        time_left = time_left - 0.1
                        local health_per_tick = max_health / 30.0  -- 3秒内总共降低max_health
                        inst.components.health:DoDelta(-health_per_tick)
                    else
                        -- 3秒到，如果还活着则设为10，否则死亡
                        if inst.components.health.currenthealth > 0 then
                            inst.components.health:SetCurrentHealth(10)
                        end
                        inst._beyond_death_task = nil
                        if inst._beyond_death_killed_listener then
                            inst:RemoveEventCallback("killed", inst._beyond_death_killed_listener)
                            inst._beyond_death_killed_listener = nil
                        end
                    end
                end
            end
            
            local function OnKilledWhileDying(inst, data)
                if data and data.victim and not saved then
                    saved = true
                    -- 停止死亡倒计时，设置生命为10
                    if inst._beyond_death_task then
                        inst._beyond_death_task:Cancel()
                        inst._beyond_death_task = nil
                    end
                    if inst and inst:IsValid() and inst.components.health then
                        inst.components.health:SetCurrentHealth(10)
                    end
                    inst:RemoveEventCallback("killed", inst._beyond_death_killed_listener)
                    inst._beyond_death_killed_listener = nil
                end
            end
            
            inst._beyond_death_killed_listener = OnKilledWhileDying
            inst:ListenForEvent("killed", OnKilledWhileDying)
            inst._beyond_death_task = inst:DoPeriodicTask(0.1, DeathCountdown)
        end
    end
    
    inst:ListenForEvent("death", OnDeath)
    inst._beyond_death_listener = OnDeath
end

-- 无休恢复：移动回复生命
function ApplyEndlessRecovery(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst._endless_distance = 0
    inst._endless_last_pos = nil
    
    -- 保存周期性任务的引用以便清理
    inst._endless_recovery_task = inst:DoPeriodicTask(0.1, function(inst)
        local x, y, z = inst.Transform:GetWorldPosition()
        
        if inst._endless_last_pos then
            local dx = x - inst._endless_last_pos.x
            local dz = z - inst._endless_last_pos.z
            local distance = math.sqrt(dx * dx + dz * dz)
            inst._endless_distance = inst._endless_distance + distance
            
            -- 每移动10米恢复1点生命
            if inst._endless_distance >= 10 then
                local health_gain = math.floor(inst._endless_distance / 10)
                if inst.components.health then
                    inst.components.health:DoDelta(health_gain)
                end
                inst._endless_distance = inst._endless_distance - health_gain * 10
            end
        end
        
        inst._endless_last_pos = {x = x, y = y, z = z}
    end)
    
    -- 监听传送事件（保存引用以便清理）
    local function OnTeleported()
        if inst.components.health then
            inst.components.health:DoDelta(1)  -- 传送时恢复1点生命
        end
    end
    inst:ListenForEvent("teleported", OnTeleported)
    inst._endless_teleported_listener = OnTeleported
end


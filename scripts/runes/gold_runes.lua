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
    -- 负责在第一次命中时登记目标并注入复活逻辑
    -- 监听攻击事件以对受害者注入复活逻辑
    local function OnAttackOther(inst, data)
        if data and data.target and data.target.components.health then
            local victim = data.target
            
            -- 如果这个生物还没有被 Hook，说明是第一次被这个玩家攻击
            if not inst._doubleup_victims[victim] then
                -- 标记这个生物，false 表示还没死过
                inst._doubleup_victims[victim] = false
                
                local health = victim.components.health
                
                -- 保存原始的 SetVal 方法（如果还没有保存）
                if health and not health._doubleup_oldSetVal then
                    health._doubleup_oldSetVal = health.SetVal
                    
                    -- Hook SetVal 方法，在第一次死亡时立即恢复生命值
                    health.SetVal = function(self, val, cause, afflicter)
                        local original = self._doubleup_oldSetVal
                        local previous = self.currenthealth or 0
                        local lethal_hit = val ~= nil and previous > 0 and val <= 0
                        local already_revived = inst._doubleup_victims and inst._doubleup_victims[victim]
                        
                        if lethal_hit and DOUBLE_UP_KILLERS[inst] and not already_revived then
                            -- 标记为已经死过一次
                            inst._doubleup_victims[victim] = true
                            victim._doubleup_revived = true
                            
                            -- 立即恢复满血，阻止死亡流程
                            self.SetVal = original
                            self._doubleup_oldSetVal = nil
                            if original then
                                original(self, self.maxhealth, cause, afflicter)
                            else
                                self.currenthealth = self.maxhealth
                            end
                            
                            self.isdead = false
                            if self.inst.replica and self.inst.replica.health then
                                if self.inst.replica.health.SetIsDead then
                                    self.inst.replica.health:SetIsDead(false)
                                end
                                if self.inst.replica.health.SetCurrentHealth then
                                    self.inst.replica.health:SetCurrentHealth(self.currenthealth)
                                end
                            end
                            
                            -- 触发复活事件（如果有复活动画）
                            self.inst:PushEvent("respawn")
                            self.inst:PushEvent("doubleup_revived", { killer = inst })
                            
                            return
                        end
                        
                        if original then
                            return original(self, val, cause, afflicter)
                        end
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
    if not inst.components.health then return end
    
    inst._beyond_death_active = true
    local health = inst.components.health
    
    -- 倒计时触发时恢复玩家控制、点击等状态
    -- 在倒计时期间恢复玩家的控制权与交互
    local function RestoreBeyondState()
        if inst.components.playercontroller then
            inst.components.playercontroller:Enable(true)
            if inst.components.playercontroller.RemoteResumePrediction then
                inst.components.playercontroller:RemoteResumePrediction()
            end
        end
        if inst.sg and inst.sg:HasStateTag("dead") then
            inst.sg:GoToState("idle")
        end
        if inst.components.health then
            inst.components.health:SetInvincible(false)
        end
        inst:RemoveTag("NOCLICK")
        if inst.replica and inst.replica.health then
            if inst.replica.health.SetIsDead then
                inst.replica.health:SetIsDead(false)
            end
            if inst.components.health and inst.replica.health.SetCurrentHealth then
                inst.replica.health:SetCurrentHealth(inst.components.health.currenthealth)
            end
        end
        if inst.erode_task then
            inst.erode_task:Cancel()
            inst.erode_task = nil
        end
    end
    
    -- 以一致方式修改生命值并同步 HUD/replica
    -- 统一设置生命值并同步 UI 显示
    local function SetHealthSafely(amount, cause)
        if not inst.components.health then
            return
        end
        local health = inst.components.health
        local max_with_penalty = health:GetMaxWithPenalty() or health.maxhealth or amount
        local target = amount
        if max_with_penalty and max_with_penalty > 0 then
            if target > max_with_penalty then
                target = max_with_penalty
            elseif target < 0 then
                target = 0
            end
        end
        health:SetVal(target, cause or "beyond_death_saved", inst)
        health:ForceUpdateHUD(true)
        if inst.replica and inst.replica.health and inst.replica.health.SetCurrentHealth then
            inst.replica.health:SetCurrentHealth(health.currenthealth)
        end
    end
    
    -- 取消 Health.redirect 的自定义拦截
    -- 停用自定义的伤害重定向
    local function DisableBeyondRedirect()
        if not inst.components.health then
            return
        end
        if inst._beyond_redirect_active then
            inst.components.health.redirect = inst._beyond_old_redirect
            inst._beyond_old_redirect = nil
            inst._beyond_redirect_active = nil
        end
    end
    
    -- 在倒计时期间 Hook Health.redirect 以防重复触发
    -- 启用自定义的伤害重定向
    local function EnableBeyondRedirect()
        if not inst.components.health or inst._beyond_redirect_active then
            return
        end
        
        inst._beyond_redirect_active = true
        local health = inst.components.health
        local old_redirect = health.redirect
        inst._beyond_old_redirect = old_redirect
        
        health.redirect = function(inst_health, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
            if inst._beyond_dying and cause ~= "beyond_death" then
                return true
            end
            if old_redirect then
                return old_redirect(inst_health, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
            end
        end
    end
    
    -- 统一清理倒计时任务与击杀事件
    -- 取消倒计时与击杀监听任务
    local function ClearBeyondDeathTasks()
        if inst._beyond_death_task then
            inst._beyond_death_task:Cancel()
            inst._beyond_death_task = nil
        end
        if inst._beyond_death_killed_listener then
            inst:RemoveEventCallback("killed", inst._beyond_death_killed_listener)
            inst._beyond_death_killed_listener = nil
        end
    end
    
    -- 结束倒计时并撤销 redirect/状态标记
    -- 完整结束倒计时状态并清理标记
    local function StopBeyondCountdown()
        ClearBeyondDeathTasks()
        DisableBeyondRedirect()
        inst._beyond_dying = false
    end
    
    -- 启动 3 秒倒计时并安排周期扣血
    -- 启动倒计时并注册相关监听
    local function StartBeyondCountdown()
        if inst._beyond_dying then
            return
        end
        
        ClearBeyondDeathTasks()
        RestoreBeyondState()
        EnableBeyondRedirect()
        
        local time_left = 3.0
        inst._beyond_saved = false
        inst._beyond_dying = true
        
        -- 监听倒计时期间的击杀事件
        -- 倒计时时击杀生物即可终止死亡
        local function OnKilledWhileDying(inst, data)
            if inst._beyond_dying and data and data.victim then
                inst._beyond_saved = true
                StopBeyondCountdown()
                SetHealthSafely(10, "beyond_death_saved")
                RestoreBeyondState()
            end
        end
        
        inst._beyond_death_killed_listener = OnKilledWhileDying
        inst:ListenForEvent("killed", OnKilledWhileDying)
        
        inst._beyond_death_task = inst:DoPeriodicTask(0.1, function()
            if not inst:IsValid() or not inst.components.health then
                StopBeyondCountdown()
                return
            end
            
            if inst._beyond_saved then
                StopBeyondCountdown()
                return
            end
            
            if time_left > 0 then
                time_left = time_left - 0.1
                local per_tick = inst.components.health.maxhealth / 30.0
                inst.components.health:DoDelta(-per_tick, true, "beyond_death", true, inst, true)
            else
                StopBeyondCountdown()
                inst._beyond_force_death = true
                inst.components.health:SetVal(0, "beyond_death_fail", inst)
                inst._beyond_force_death = nil
            end
        end)
    end
    
    if not health._beyond_oldSetVal then
        health._beyond_oldSetVal = health.SetVal
        
        -- Hook Health:SetVal 以拦截首次致命打击
        health.SetVal = function(self, val, cause, afflicter)
            local inst = self.inst
            local lethal_hit = val ~= nil and self.currenthealth and self.currenthealth > 0 and val <= 0
            
            if inst._beyond_dying and lethal_hit and not inst._beyond_force_death then
                return self._beyond_oldSetVal(self, val, cause, afflicter)
            end
            
            if inst._beyond_death_active and lethal_hit and not inst._beyond_dying and not inst._beyond_force_death then
                StartBeyondCountdown()
                return self._beyond_oldSetVal(self, self.maxhealth, cause, afflicter)
            end
            
            return self._beyond_oldSetVal(self, val, cause, afflicter)
        end
    end
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
    -- 传送事件触发时额外恢复 1 点生命
    local function OnTeleported()
        if inst.components.health then
            inst.components.health:DoDelta(1)  -- 传送时恢复1点生命
        end
    end
    inst:ListenForEvent("teleported", OnTeleported)
    inst._endless_teleported_listener = OnTeleported
end


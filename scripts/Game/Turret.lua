------------------------------------------------------------------------
-- Turret.lua  —— 炮塔系统 v4
-- 数据定义 + 槽位 + 自动索敌 + 6种专属攻击动画
------------------------------------------------------------------------
local C = require "Game.Config"
local E = require "Game.Entities"
local T = {}

-- 飙血颜色
local BLOOD_COLOR = {180, 30, 20}

------------------------------------------------------------------------
-- 炮塔类型定义
------------------------------------------------------------------------
T.TYPES = {
    arrow    = { name = "弓箭炮塔",   imgKey = "arrow",    range = 380, damage = 30, cooldown = 1.0,  color = {180, 140, 80},  projType = "arrow",    activeDuration = 6,  restDuration = 3 },
    sniper   = { name = "狙击炮塔",   imgKey = "sniper",   range = 380, damage = 50, cooldown = 5.0,  color = {255, 60, 40},   projType = "sniper",   activeDuration = 10, restDuration = 5,  offsetY = 25, turnSpeed = 1.8 },
    flame    = { name = "喷火炮塔",   imgKey = "flame",    range = 280, damage = 5,  cooldown = 0.12, color = {255, 120, 30},  projType = "flame",    activeDuration = 4,  restDuration = 3 },
    electric = { name = "电能炮塔",   imgKey = "electric", range = 380, damage = 15, cooldown = 0.7,  color = {60, 160, 255},  projType = "electric", activeDuration = 5,  restDuration = 3 },
    rocket   = { name = "火箭炮塔",   imgKey = "rocket",   range = 380, damage = 40, cooldown = 8.0,  color = {80, 120, 60},   projType = "rocket",   activeDuration = 24,  restDuration = 5 },
    minigun  = { name = "机关枪炮塔", imgKey = "minigun",  range = 380, damage = 10, cooldown = 0.1,  color = {255, 230, 80},  projType = "minigun",  activeDuration = 5,  restDuration = 4 },
}

T.TYPE_LIST = { "arrow", "sniper", "flame", "electric", "rocket", "minigun" }

--- 获取炮台加成后伤害
local function getTurretDamage(typeKey, baseDmg, G)
    local bonus = 0
    if G.turretDmgBonus then
        bonus = G.turretDmgBonus[typeKey] or 0
    end
    -- 天赋通用炮塔伤害加成
    local generalPct = G.turretDmgPct or 0
    return math.floor(baseDmg * (1 + bonus / 100) * (1 + generalPct / 100))
end

--- 获取炮台加成后射程
local function getTurretRange(typeKey, baseRange, G)
    local bonus = 0
    if G.turretRangeBonus then
        bonus = G.turretRangeBonus[typeKey] or 0
    end
    return baseRange * (1 + bonus / 100)
end

--- 获取炮台加成后冷却（加成越高冷却越短）
local function getTurretCooldown(typeKey, baseCool, G)
    local bonus = 0
    if G.turretCoolBonus then
        bonus = G.turretCoolBonus[typeKey] or 0
    end
    -- 天赋通用冷却加速
    local cdMul = G.cooldownMul or 1.0
    return baseCool / ((1 + bonus / 100) * cdMul)
end

------------------------------------------------------------------------
-- 渲染尺寸
------------------------------------------------------------------------
local TURRET_H = 48
local TURRET_W = 36

------------------------------------------------------------------------
-- 4 个炮塔槽位（像素偏移）
------------------------------------------------------------------------
T.SLOTS = {
    { id = 1, label = "左上", pxOffX = -22, pxOffY = -42 },
    { id = 2, label = "右上", pxOffX =  22, pxOffY = -42 },
    { id = 3, label = "左下", pxOffX = -22, pxOffY =  28 },
    { id = 4, label = "右下", pxOffX =  22, pxOffY =  28 },
}

------------------------------------------------------------------------
-- 初始化（不带炮塔，通过肉鸽升级解锁）
------------------------------------------------------------------------
function T.InitTurrets(G)
    G.turrets = {}
    G.turretProjectiles = {}
    G.turretUpgrades = {}    -- 机制升级 flag 表，key: "typeKey_flagName" = true/数值
    G.burnZones = {}         -- 持续燃烧区域列表
end

-- 检查某炮塔是否拥有某机制升级
function T.HasUpgrade(G, typeKey, flagName)
    if not G.turretUpgrades then return false end
    return G.turretUpgrades[typeKey .. "_" .. flagName] ~= nil and
           G.turretUpgrades[typeKey .. "_" .. flagName] ~= false
end

-- 获取某炮塔机制升级的数值（无则返回 0）
function T.GetUpgradeVal(G, typeKey, flagName)
    if not G.turretUpgrades then return 0 end
    local v = G.turretUpgrades[typeKey .. "_" .. flagName]
    if type(v) == "number" then return v end
    if v == true then return 1 end
    return 0
end

-- 设置机制升级 flag
function T.SetUpgrade(G, typeKey, flagName, value)
    if not G.turretUpgrades then G.turretUpgrades = {} end
    G.turretUpgrades[typeKey .. "_" .. flagName] = value
end

------------------------------------------------------------------------
-- 解锁炮塔（添加到下一个空槽位）
-- 返回 true 表示解锁成功，false 表示槽位已满
------------------------------------------------------------------------
function T.UnlockTurret(G, typeKey)
    if not T.TYPES[typeKey] then return false end
    if not G.turrets then G.turrets = {} end

    -- 找到已占用的槽位
    local usedSlots = {}
    for _, t in ipairs(G.turrets) do
        usedSlots[t.slotId] = true
    end

    -- 找第一个空槽位
    for _, slot in ipairs(T.SLOTS) do
        if not usedSlots[slot.id] then
            local tDef = T.TYPES[typeKey]
            table.insert(G.turrets, {
                slotId = slot.id,
                typeKey = typeKey,
                coolTimer = 0,
                angle = math.pi / 2,
                recoil = 0,
                phase = "active",                          -- "active" 攻击中 / "resting" 冷却中
                phaseTimer = tDef.activeDuration or 6,     -- 当前阶段剩余时间
            })
            print("[Turret] Unlocked " .. typeKey .. " at slot " .. slot.id)
            return true
        end
    end

    print("[Turret] No empty slot for " .. typeKey)
    return false
end

------------------------------------------------------------------------
-- 获取已解锁炮塔数量
------------------------------------------------------------------------
function T.GetUnlockedCount(G)
    return G.turrets and #G.turrets or 0
end

function T.SetTurrets(G, selections)
    G.turrets = {}
    for i, typeKey in ipairs(selections) do
        local tDef = T.TYPES[typeKey]
        if i <= #T.SLOTS and tDef then
            table.insert(G.turrets, {
                slotId = i, typeKey = typeKey, coolTimer = 0,
                angle = math.pi / 2, recoil = 0,
                phase = "active",
                phaseTimer = tDef.activeDuration or 6,
            })
        end
    end
    G.turretProjectiles = {}
end

------------------------------------------------------------------------
-- 火车精灵中心
------------------------------------------------------------------------
local function getTrainSpriteCenter(G)
    local cx = G.cartCenterX
    local topY = G.cartTopY
    local ch = G.cartH
    local t = G.gameTime or 0
    local drawH = ch + 20
    local vibeX = math.sin(t * 25) * 0.4
    local vibeY = math.sin(t * 30) * 0.3
    return cx + vibeX, topY - 5 + drawH / 2 + vibeY
end

function T.GetSlotWorldPos(G, slotId)
    local slot = T.SLOTS[slotId]
    if not slot then return 0, 0 end
    local scx, scy = getTrainSpriteCenter(G)
    return scx + slot.pxOffX, scy + slot.pxOffY
end

------------------------------------------------------------------------
-- 生成投射物
------------------------------------------------------------------------
local function spawnProjectile(G, projType, sx, sy, tx, ty, angle, targetEnemy, damage, maxRange)
    if not G.turretProjectiles then G.turretProjectiles = {} end

    if projType == "sniper" then
        -- 狙击：射线 + 命中爆裂
        table.insert(G.turretProjectiles, {
            type = "sniper",
            sx = sx, sy = sy, tx = tx, ty = ty,
            life = 0.35, maxLife = 0.35,
        })
        -- 命中点爆裂粒子
        for _ = 1, 6 do
            local a = math.random() * math.pi * 2
            local spd = 40 + math.random() * 60
            table.insert(G.turretProjectiles, {
                type = "spark",
                x = tx, y = ty,
                vx = math.cos(a) * spd,
                vy = math.sin(a) * spd,
                life = 0.2 + math.random() * 0.15,
                maxLife = 0.35,
                r = 255, g = 80, b = 40,
            })
        end
    elseif projType == "electric" then
        -- 闪电弧
        local dx = tx - sx
        local dy = ty - sy
        local dist = math.sqrt(dx * dx + dy * dy)
        local segments = math.max(5, math.floor(dist / 10))
        local points = {}
        for i = 0, segments do
            local t2 = i / segments
            local px = sx + dx * t2
            local py = sy + dy * t2
            if i > 0 and i < segments then
                local nx = -dy / dist
                local ny = dx / dist
                local offset = (math.random() - 0.5) * 22
                px = px + nx * offset
                py = py + ny * offset
            end
            table.insert(points, { x = px, y = py })
        end
        table.insert(G.turretProjectiles, {
            type = "electric",
            points = points,
            life = 0.3, maxLife = 0.3,
        })
        -- 命中点电火花
        for _ = 1, 4 do
            local a = math.random() * math.pi * 2
            local spd = 30 + math.random() * 50
            table.insert(G.turretProjectiles, {
                type = "spark",
                x = tx, y = ty,
                vx = math.cos(a) * spd,
                vy = math.sin(a) * spd,
                life = 0.15 + math.random() * 0.15,
                maxLife = 0.3,
                r = 100, g = 180, b = 255,
            })
        end
    elseif projType == "minigun" then
        -- 机关枪曳光弹（追踪目标，到达后造成伤害）
        local spd = 500
        local spread = (math.random() - 0.5) * 0.12
        local a = angle + spread
        local life = maxRange and (maxRange / spd) or 0.8
        table.insert(G.turretProjectiles, {
            type = "minigun",
            x = sx, y = sy,
            vx = math.cos(a) * spd,
            vy = math.sin(a) * spd,
            speed = spd,
            life = life, maxLife = life,
            target = targetEnemy,
            damage = damage or 3,
            tx = tx, ty = ty,
        })
    elseif projType == "rocket" then
        -- 火箭弹（追踪目标，到达后AOE爆炸）
        local spd = 150
        local life = maxRange and (maxRange / spd) or 3.0
        table.insert(G.turretProjectiles, {
            type = "rocket",
            x = sx, y = sy,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            speed = spd,
            angle = angle,
            life = life, maxLife = life,
            trailTimer = 0,
            target = targetEnemy,
            tx = tx, ty = ty,
            exploded = false,
        })
    elseif projType == "arrow" then
        -- 弓箭（追踪目标，到达后造成伤害）
        local spd = 280
        local life = maxRange and (maxRange / spd) or 1.5
        table.insert(G.turretProjectiles, {
            type = "arrow",
            x = sx, y = sy,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            speed = spd,
            angle = angle,
            life = life, maxLife = life,
            target = targetEnemy,
            damage = damage or 8,
            tx = tx, ty = ty,
        })
    elseif projType == "poison_arrow" then
        -- 毒箭（追踪，命中后持续中毒）
        local spd = 280
        local life = maxRange and (maxRange / spd) or 1.5
        table.insert(G.turretProjectiles, {
            type = "poison_arrow",
            x = sx, y = sy,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            speed = spd,
            angle = angle,
            life = life, maxLife = life,
            target = targetEnemy,
            damage = damage or 8,
            tx = tx, ty = ty,
        })
    elseif projType == "ball_lightning" then
        -- 闪电球（缓速追踪，接近时范围链式伤害）
        local spd = 180
        local life = maxRange and (maxRange / spd) or 2.5
        table.insert(G.turretProjectiles, {
            type = "ball_lightning",
            x = sx, y = sy,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            speed = spd,
            angle = angle,
            life = life, maxLife = life,
            target = targetEnemy,
            damage = damage or 15,
            tx = tx, ty = ty,
            pulseTimer = 0,
        })
    end
end

------------------------------------------------------------------------
-- 丧尸 DoT / 减速 / 眩晕 tick
------------------------------------------------------------------------
function T.UpdateZombieEffects(G, dt)
    if not G.zombies then return end
    for _, z in ipairs(G.zombies) do
        if not z.dead then
            -- 燃烧
            if z.burnTimer and z.burnTimer > 0 then
                z.burnTimer = z.burnTimer - dt
                z.burnTickTimer = (z.burnTickTimer or 0) + dt
                if z.burnTickTimer >= 0.5 then
                    z.burnTickTimer = 0
                    local bdmg = z.burnDmg or 5
                    z.hp = z.hp - bdmg
                    z.hitAnim = 0.2
                    E.SpawnParticles(G, z.x, z.y, {255, 120, 30}, 2)
                    E.SpawnFloatText(G, z.x, z.y - 10, tostring(bdmg), "damage")
                    if z.hp <= 0 then
                        z.dead = true
                        G.killCount = (G.killCount or 0) + 1
                        E.SpawnGoldFly(G, z.x, z.y, 1)
                        E.SpawnZombieDeath(G, z.x, z.y)
                    end
                end
            end
            -- 中毒
            if z.poisonTimer and z.poisonTimer > 0 then
                z.poisonTimer = z.poisonTimer - dt
                z.poisonTickTimer = (z.poisonTickTimer or 0) + dt
                if z.poisonTickTimer >= 0.4 then
                    z.poisonTickTimer = 0
                    local pdmg = z.poisonDmg or 4
                    z.hp = z.hp - pdmg
                    z.hitAnim = 0.15
                    E.SpawnParticles(G, z.x, z.y, {60, 200, 60}, 2)
                    E.SpawnFloatText(G, z.x, z.y - 10, tostring(pdmg), "damage")
                    if z.hp <= 0 then
                        z.dead = true
                        G.killCount = (G.killCount or 0) + 1
                        E.SpawnGoldFly(G, z.x, z.y, 1)
                        E.SpawnZombieDeath(G, z.x, z.y)
                    end
                end
            end
            -- 眩晕/冻结（冻结期间 hitAnim 持续）
            if z.stunTimer and z.stunTimer > 0 then
                z.stunTimer = z.stunTimer - dt
                z.stunned = true
            else
                z.stunned = false
            end
        end
    end

    -- 更新燃烧区域
    if G.burnZones then
        local scrollDelta = G.lastScrollDelta or 0
        local keepZones = {}
        for _, bz in ipairs(G.burnZones) do
            bz.life = bz.life - dt
            -- 随场景滚动向上移动（与僵尸保持同步）
            bz.y = bz.y - scrollDelta
            if bz.life > 0 then
                -- 对区域内的丧尸造成持续燃烧效果
                bz.tickTimer = (bz.tickTimer or 0) + dt
                if bz.tickTimer >= 0.5 then
                    bz.tickTimer = 0
                    local r2 = bz.radius * bz.radius
                    for _, z in ipairs(G.zombies or {}) do
                        if not z.dead then
                            local ddx = z.x - bz.x
                            local ddy = z.y - bz.y
                            if ddx * ddx + ddy * ddy < r2 then
                                -- 强制燃烧
                                z.burnTimer = math.max(z.burnTimer or 0, 2.0)
                                z.burnDmg = bz.damage or 8
                                z.burnTickTimer = 0
                            end
                        end
                    end
                end
                table.insert(keepZones, bz)
            end
        end
        G.burnZones = keepZones
    end
end

------------------------------------------------------------------------
-- 更新炮塔（索敌 + 开火）
------------------------------------------------------------------------
function T.Update(G, dt)
    if not G.turrets then return end

    -- 丧尸 DoT/状态效果 tick
    T.UpdateZombieEffects(G, dt)

    for _, turret in ipairs(G.turrets) do
        local def = T.TYPES[turret.typeKey]
        if not def then goto continue end

        if turret.coolTimer > 0 then
            turret.coolTimer = turret.coolTimer - dt
        end

        -- 后坐力恢复
        if turret.recoil and turret.recoil > 0 then
            turret.recoil = turret.recoil - dt * 10
            if turret.recoil < 0 then turret.recoil = 0 end
        end

        -- ===== 攻击/冷却双阶段计时 =====
        if not turret.phase then turret.phase = "active" end
        if not turret.phaseTimer then turret.phaseTimer = def.activeDuration or 6 end

        -- 只有 active 阶段在有目标时才消耗 phaseTimer
        -- resting 阶段一直倒计时
        if turret.phase == "resting" then
            turret.phaseTimer = turret.phaseTimer - dt
            if turret.phaseTimer <= 0 then
                turret.phase = "active"
                turret.phaseTimer = def.activeDuration or 6
                turret.coolTimer = 0  -- 恢复后立刻可射击
            end

            -- 冷却阶段：喷火停止
            if turret.typeKey == "flame" then
                turret.flaming = false
                turret.flameTime = 0
            end

            -- 冷却阶段：炮管回正，不索敌不攻击
            local target = math.pi / 2
            local diff = target - turret.angle
            while diff > math.pi do diff = diff - 2 * math.pi end
            while diff < -math.pi do diff = diff + 2 * math.pi end
            if math.abs(diff) > 0.02 then
                turret.angle = turret.angle + diff * dt * 3.0
            else
                turret.angle = target
            end
            turret.targeting = false

            if turret.fireFlash and turret.fireFlash > 0 then
                turret.fireFlash = turret.fireFlash - dt
            end
            goto continue
        end

        local tx, ty = T.GetSlotWorldPos(G, turret.slotId)

        -- 索敌（只攻击屏幕可见范围内的敌人）
        local effectiveRange = getTurretRange(turret.typeKey, def.range, G)
        local nearDistSq = effectiveRange * effectiveRange
        local nearEnemy = nil
        if G.zombies then
            for _, z in ipairs(G.zombies) do
                if not z.dead and z.y > (G.hudH or 48) and z.y < (G.screenH or 800) then
                    local dx = z.x - tx
                    local dy = z.y - ty
                    local distSq = dx * dx + dy * dy
                    if distSq < nearDistSq then
                        nearDistSq = distSq
                        nearEnemy = z
                    end
                end
            end
        end

        if nearEnemy then
            local dx = nearEnemy.x - tx
            local dy = nearEnemy.y - ty
            local targetAngle = math.atan(dy, dx)

            -- 平滑转向（有 turnSpeed 的炮台）
            local turnSpeed = def.turnSpeed
            if turnSpeed then
                local diff = targetAngle - turret.angle
                while diff > math.pi  do diff = diff - 2 * math.pi end
                while diff < -math.pi do diff = diff + 2 * math.pi end
                local step = turnSpeed * dt
                if math.abs(diff) <= step then
                    turret.angle = targetAngle
                else
                    turret.angle = turret.angle + (diff > 0 and step or -step)
                end
                -- 对准程度：角度误差小于 0.12 rad（~7°）才视为"已对准"
                turret.aimed = math.abs(diff) <= 0.12
            else
                turret.angle = targetAngle
                turret.aimed = true
            end
            turret.targeting = true

            -- 攻击阶段倒计时（仅在有目标时消耗）
            turret.phaseTimer = turret.phaseTimer - dt
            if turret.phaseTimer <= 0 then
                turret.phase = "resting"
                turret.phaseTimer = def.restDuration or 3
                -- 立即停止喷火
                if turret.typeKey == "flame" then
                    turret.flaming = false
                    turret.flameTime = 0
                end
                goto continue
            end

            -- 弓箭炮塔：场上已有箭矢飞行中则不发射
            if turret.typeKey == "arrow" and G.turretProjectiles then
                local hasArrow = false
                for _, proj in ipairs(G.turretProjectiles) do
                    if proj.type == "arrow" and proj.life > 0 then
                        hasArrow = true
                        break
                    end
                end
                if hasArrow then goto continue end
            end

            if turret.coolTimer <= 0 then
                turret.coolTimer = getTurretCooldown(turret.typeKey, def.cooldown, G)

                -- ============================================================
                -- 各炮塔专属开火逻辑（含升级机制）
                -- ============================================================

                local muzzleDist = TURRET_H * 0.45
                local mx = tx + math.cos(turret.angle) * muzzleDist
                local my = ty + math.sin(turret.angle) * muzzleDist

                if turret.typeKey == "flame" then
                    -- ---- 喷火炮台 ----
                    local flameLen = effectiveRange
                    local halfSpread = 0.45
                    local cosA = math.cos(turret.angle)
                    local sinA = math.sin(turret.angle)
                    local flameLenSq = flameLen * flameLen
                    -- 旋转火焰：逐帧偏转角度
                    if T.HasUpgrade(G, "flame", "rotating") then
                        local rotSpd = T.HasUpgrade(G, "flame", "rotating_plus") and 3.2 or 1.8
                        turret.rotatingAngleOffset = (turret.rotatingAngleOffset or 0) + dt * rotSpd
                        cosA = math.cos(turret.angle + turret.rotatingAngleOffset)
                        sinA = math.sin(turret.angle + turret.rotatingAngleOffset)
                    end
                    for _, z in ipairs(G.zombies) do
                        if not z.dead then
                            local fdx = z.x - tx
                            local fdy = z.y - ty
                            local distSq = fdx * fdx + fdy * fdy
                            if distSq < flameLenSq and distSq > 0 then
                                local dist = math.sqrt(distSq)
                                local dot = (fdx * cosA + fdy * sinA) / dist
                                if dot > math.cos(halfSpread) then
                                    local flameDmg = getTurretDamage(turret.typeKey, def.damage, G)
                                    z.hp = z.hp - flameDmg
                                    z.hitAnim = 0.3
                                    E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 3)
                                    E.SpawnFloatText(G, z.x, z.y - 10, tostring(flameDmg), "damage")
                                    -- 粘性火焰：离开范围后继续燃烧
                                    if T.HasUpgrade(G, "flame", "sticky") then
                                        local stickyDur = T.HasUpgrade(G, "flame", "sticky_plus") and 5.0 or 3.0
                                        local stickyDmg = T.HasUpgrade(G, "flame", "sticky_plus") and math.floor(flameDmg * 0.68) or math.floor(flameDmg * 0.5)
                                        z.burnTimer = math.max(z.burnTimer or 0, stickyDur)
                                        z.burnDmg = stickyDmg
                                        z.burnTickTimer = 0
                                    end
                                    -- 凝固汽油：减速
                                    if T.HasUpgrade(G, "flame", "napalm") then
                                        local napalmSlowDur = T.HasUpgrade(G, "flame", "napalm_plus") and 3.0 or 2.0
                                        local napalmSlowMul = T.HasUpgrade(G, "flame", "napalm_plus") and 0.25 or 0.4
                                        z.slowTimer = napalmSlowDur
                                        z.slowMul = napalmSlowMul
                                    end
                                    if z.hp <= 0 then
                                        z.dead = true
                                        G.killCount = (G.killCount or 0) + 1
                                        E.SpawnZombieDeath(G, z.x, z.y)
                                        E.SpawnGoldFly(G, z.x, z.y, 1)
                                    end
                                end
                            end
                        end
                    end
                    -- 地面燃烧区域（喷火炮台升级）
                    if T.HasUpgrade(G, "flame", "burnzone") then
                        turret.burnzoneTimer = (turret.burnzoneTimer or 0) + def.cooldown
                        if turret.burnzoneTimer >= 1.5 then
                            turret.burnzoneTimer = 0
                            if not G.burnZones then G.burnZones = {} end
                            local bzRadius = T.HasUpgrade(G, "flame", "burnzone_plus") and 70 or 50
                            local bzLife   = T.HasUpgrade(G, "flame", "burnzone_plus") and 8.0 or 5.0
                            table.insert(G.burnZones, {
                                x = nearEnemy.x + (math.random() - 0.5) * 40,
                                y = nearEnemy.y + (math.random() - 0.5) * 40,
                                radius = bzRadius, life = bzLife, damage = 10,
                                tickTimer = 0,
                            })
                        end
                    end

                elseif turret.typeKey == "arrow" then
                    -- ---- 弓箭炮台 ----
                    turret.recoil = 1.0
                    turret.fireFlash = 0.12
                    local projDmg = getTurretDamage(turret.typeKey, def.damage, G)
                    local projType = T.HasUpgrade(G, "arrow", "poison") and "poison_arrow" or "arrow"

                    -- 爆炸箭标记（在命中逻辑中处理AOE）
                    local arrowExplosive = T.HasUpgrade(G, "arrow", "explosive")
                    local arrowExplosiveBig = T.HasUpgrade(G, "arrow", "explosive_big")
                    if arrowExplosive then
                        projType = "arrow"
                        projDmg = math.floor(projDmg * 1.3)
                    end
                    -- 贯穿层数
                    local arrowPierce = T.GetUpgradeVal(G, "arrow", "pierce")
                    -- 穿链层数
                    local arrowChain = T.GetUpgradeVal(G, "arrow", "chain")
                    -- 毒素强化
                    local arrowPoisonExtra = T.HasUpgrade(G, "arrow", "poison_extra")

                    -- 扇形三连射
                    local function fireArrow(tx2, ty2, angle2, tEnemy)
                        local idx = #G.turretProjectiles + 1
                        spawnProjectile(G, projType, mx, my, tx2, ty2, angle2, tEnemy, projDmg, effectiveRange)
                        local proj = G.turretProjectiles[idx]
                        if proj then
                            if arrowExplosive then proj.explosive = true end
                            if arrowExplosiveBig then proj.explosive_big = true end
                            if arrowPierce > 0 then proj.pierceLeft = arrowPierce end
                            if arrowChain > 0 then proj.chainLeft = arrowChain end
                            if arrowPoisonExtra then proj.poison_extra = true end
                        end
                    end
                    if T.HasUpgrade(G, "arrow", "triple") then
                        local spreads = { -0.22, 0, 0.22 }
                        for _, sp in ipairs(spreads) do
                            local sa = turret.angle + sp
                            local ex2 = nearEnemy.x + math.cos(sa) * 60
                            local ey2 = nearEnemy.y + math.sin(sa) * 60
                            fireArrow(ex2, ey2, sa, nearEnemy)
                        end
                    else
                        fireArrow(nearEnemy.x, nearEnemy.y, turret.angle, nearEnemy)
                    end

                elseif turret.typeKey == "sniper" then
                    -- ---- 狙击炮台（需对准后才开火）----
                    if not turret.aimed then goto continue end
                    turret.recoil = 1.0
                    turret.fireFlash = 0.15
                    local projDmg = getTurretDamage(turret.typeKey, def.damage, G)

                    -- 暴击计算
                    local critChance = T.GetUpgradeVal(G, "sniper", "crit")
                    local isCrit = (critChance > 0) and (math.random(100) <= critChance)
                    local critMul = T.HasUpgrade(G, "sniper", "crit_plus") and 2.5 or 2.0
                    if isCrit then projDmg = math.floor(projDmg * critMul) end

                    -- 激光光束：不发射投射物，直接持续光束伤害
                    if T.HasUpgrade(G, "sniper", "laser") then
                        turret.laserActive = true
                        local laserCooldown = T.HasUpgrade(G, "sniper", "laser_plus") and 8.0 or 12.0
                        turret.laserTimer = (turret.laserTimer or 0) + def.cooldown
                        -- 当前是否已有激活的持续光束（避免重复创建）
                        local hasBeam = false
                        for _, p2 in ipairs(G.turretProjectiles) do
                            if p2.type == "laser_beam" and p2.turretRef == turret then
                                hasBeam = true; break
                            end
                        end
                        if not hasBeam and turret.laserTimer >= laserCooldown then
                            turret.laserTimer = 0
                            local laserDmgMul  = T.HasUpgrade(G, "sniper", "laser_plus") and 3.0 or 2.0
                            local beamDuration = T.HasUpgrade(G, "sniper", "laser_plus") and 5.0 or 3.0
                            local dmgInterval  = 0.15   -- 每0.15秒造一次伤害
                            local lx2 = mx + math.cos(turret.angle) * effectiveRange * 1.5
                            local ly2 = my + math.sin(turret.angle) * effectiveRange * 1.5
                            table.insert(G.turretProjectiles, {
                                type         = "laser_beam",
                                sx = mx, sy = my, ex = lx2, ey = ly2,
                                life         = beamDuration,
                                maxLife      = beamDuration,
                                wide         = T.HasUpgrade(G, "sniper", "laser_plus"),
                                turretRef    = turret,   -- 每帧跟随炮台角度
                                laserDmgMul  = laserDmgMul,
                                laserBaseDmg = projDmg,
                                laserRange   = effectiveRange,
                                dmgInterval  = dmgInterval,
                                dmgTimer     = 0,        -- 立即开始第一次伤害
                                -- 帧动画
                                laserPhase    = "open",
                                laserFrameIdx = 1,
                                laserFrameT   = 0,
                            })
                        end
                    else
                        -- 普通狙击
                        local projType = "sniper"
                        local instant_dmg = projDmg
                        -- 爆炸弹：狙击命中后小AOE
                        if T.HasUpgrade(G, "sniper", "explosive") then
                            instant_dmg = math.floor(projDmg * 1.5)
                            nearEnemy.sniper_explosive = true
                        end
                        nearEnemy.hp = nearEnemy.hp - instant_dmg
                        nearEnemy.hitAnim = 1.0
                        -- 暴击特效
                        if isCrit then
                            E.SpawnParticles(G, nearEnemy.x, nearEnemy.y, {255, 220, 0}, 8)
                            E.SpawnFloatText(G, nearEnemy.x, nearEnemy.y - 10, tostring(instant_dmg), "crit")
                        else
                            E.SpawnParticles(G, nearEnemy.x, nearEnemy.y, BLOOD_COLOR, 4)
                            E.SpawnFloatText(G, nearEnemy.x, nearEnemy.y - 10, tostring(instant_dmg), "damage")
                        end
                        -- 命中冻结
                        if T.HasUpgrade(G, "sniper", "freeze") then
                            local stunDur = T.HasUpgrade(G, "sniper", "freeze_plus") and 2.8 or 1.8
                            nearEnemy.stunTimer = stunDur
                            nearEnemy.stunned = true
                            -- freeze_plus：回复少量列车HP
                            if T.HasUpgrade(G, "sniper", "freeze_plus") and G.trainHP then
                                G.trainHP = math.min(G.trainMaxHP or 100, G.trainHP + 2)
                            end
                        end
                        -- 爆炸弹 AOE（explosive_big用更大半径）
                        if T.HasUpgrade(G, "sniper", "explosive") then
                            if T.HasUpgrade(G, "sniper", "explosive_big") then
                                -- 使用更大AOE半径（RocketAOE基础×1.5倍）
                                if not G.zombies then return end
                                local bigR = 80 * 1.5
                                for _, z in ipairs(G.zombies) do
                                    if not z.dead then
                                        local exdx = z.x - nearEnemy.x; local exdy = z.y - nearEnemy.y
                                        local exd2 = exdx * exdx + exdy * exdy
                                        if exd2 < bigR * bigR then
                                            local bigDmg = math.floor(projDmg * 0.8 * (1.0 - 0.5 * math.sqrt(exd2) / bigR))
                                            z.hp = z.hp - bigDmg
                                            z.hitAnim = 1.0
                                            E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 4)
                                            E.SpawnFloatText(G, z.x, z.y - 10, tostring(bigDmg), "damage")
                                            if z.hp <= 0 then z.dead = true; G.killCount = (G.killCount or 0) + 1; E.SpawnZombieDeath(G, z.x, z.y); E.SpawnGoldFly(G, z.x, z.y, 1) end
                                        end
                                    end
                                end
                            else
                                T.RocketAOE(G, nearEnemy.x, nearEnemy.y)
                            end
                            T.SpawnExplosion(G, nearEnemy.x, nearEnemy.y)
                        end
                        if nearEnemy.hp <= 0 then
                            nearEnemy.dead = true
                            E.SpawnZombieDeath(G, nearEnemy.x, nearEnemy.y)
                            E.SpawnGoldFly(G, nearEnemy.x, nearEnemy.y, 1)
                        end
                        spawnProjectile(G, projType, mx, my, nearEnemy.x, nearEnemy.y, turret.angle, nearEnemy, 0)
                    end

                elseif turret.typeKey == "electric" then
                    -- ---- 电能炮台 ----
                    turret.recoil = 1.0
                    turret.fireFlash = 0.12
                    local projDmg = getTurretDamage(turret.typeKey, def.damage, G)

                    -- 全场闪电：全屏随机攻击所有敌人
                    if T.HasUpgrade(G, "electric", "fullfield") then
                        for _, z in ipairs(G.zombies or {}) do
                            if not z.dead then
                                -- 全场闪电：每次有 50% 概率击中
                                if math.random() < 0.5 then
                                    local fDmg = math.floor(projDmg * 0.6)
                                    z.hp = z.hp - fDmg
                                    z.hitAnim = 0.3
                                    E.SpawnParticles(G, z.x, z.y, {100, 180, 255}, 3)
                                    E.SpawnFloatText(G, z.x, z.y - 10, tostring(fDmg), "damage")
                                    if z.hp <= 0 then
                                        z.dead = true
                                        G.killCount = (G.killCount or 0) + 1
                                        E.SpawnZombieDeath(G, z.x, z.y)
                                        E.SpawnGoldFly(G, z.x, z.y, 1)
                                    end
                                    -- 全场闪电视觉
                                    table.insert(G.turretProjectiles, {
                                        type = "electric",
                                        points = {{ x = mx, y = my }, { x = z.x, y = z.y }},
                                        life = 0.2, maxLife = 0.2,
                                    })
                                end
                            end
                        end
                    else
                        -- 闪电球
                        if T.HasUpgrade(G, "electric", "ball_lightning") then
                            spawnProjectile(G, "ball_lightning", mx, my, nearEnemy.x, nearEnemy.y, turret.angle, nearEnemy, projDmg, effectiveRange)
                        else
                            -- 普通闪电 + 链式跳跃
                            local chainCount = 1 + T.GetUpgradeVal(G, "electric", "chain")
                            local hitTargets = { nearEnemy }
                            nearEnemy.hp = nearEnemy.hp - projDmg
                            nearEnemy.hitAnim = 1.0
                            -- 眩晕
                            if T.HasUpgrade(G, "electric", "stun") and math.random() < 0.4 then
                                nearEnemy.stunTimer = 1.5
                                nearEnemy.stunned = true
                            end
                            E.SpawnParticles(G, nearEnemy.x, nearEnemy.y, {100, 180, 255}, 4)
                            E.SpawnFloatText(G, nearEnemy.x, nearEnemy.y - 10, tostring(projDmg), "damage")
                            spawnProjectile(G, "electric", mx, my, nearEnemy.x, nearEnemy.y, turret.angle, nearEnemy, projDmg)
                            if nearEnemy.hp <= 0 then
                                nearEnemy.dead = true
                                E.SpawnZombieDeath(G, nearEnemy.x, nearEnemy.y)
                                E.SpawnGoldFly(G, nearEnemy.x, nearEnemy.y, 1)
                            end
                            -- 链式跳跃额外目标
                            if chainCount > 1 then
                                local lastX, lastY = nearEnemy.x, nearEnemy.y
                                for ci = 2, chainCount do
                                    local best, bestDist = nil, 120 * 120
                                    for _, z in ipairs(G.zombies or {}) do
                                        local inHit = false
                                        for _, ht in ipairs(hitTargets) do
                                            if ht == z then inHit = true; break end
                                        end
                                        if not z.dead and not inHit then
                                            local cdx = z.x - lastX
                                            local cdy = z.y - lastY
                                            local cd2 = cdx * cdx + cdy * cdy
                                            if cd2 < bestDist then
                                                bestDist = cd2
                                                best = z
                                            end
                                        end
                                    end
                                    if best then
                                        table.insert(hitTargets, best)
                                        local chainDmg = math.floor(projDmg * 0.7)
                                        best.hp = best.hp - chainDmg
                                        best.hitAnim = 0.8
                                        if T.HasUpgrade(G, "electric", "stun") and math.random() < 0.4 then
                                            best.stunTimer = 1.5
                                            best.stunned = true
                                        end
                                        E.SpawnParticles(G, best.x, best.y, {100, 180, 255}, 3)
                                        E.SpawnFloatText(G, best.x, best.y - 10, tostring(chainDmg), "damage")
                                        spawnProjectile(G, "electric", lastX, lastY, best.x, best.y, 0, nil, 0)
                                        if best.hp <= 0 then
                                            best.dead = true
                                            E.SpawnZombieDeath(G, best.x, best.y)
                                            E.SpawnGoldFly(G, best.x, best.y, 1)
                                        end
                                        lastX, lastY = best.x, best.y
                                    end
                                end
                            end
                        end
                    end

                elseif turret.typeKey == "rocket" then
                    -- ---- 火箭炮台 ----
                    turret.recoil = 1.0
                    turret.fireFlash = 0.15
                    local projDmg = getTurretDamage(turret.typeKey, def.damage, G)

                    -- 导弹雨：从天而降12枚
                    if T.HasUpgrade(G, "rocket", "missile_rain") then
                        local centerX = nearEnemy.x
                        local centerY = nearEnemy.y
                        for ri = 1, 12 do
                            local rainAngle = (ri / 12) * math.pi * 2
                            local rainDist = 20 + math.random() * 60
                            local rTargetX = centerX + math.cos(rainAngle) * rainDist
                            local rTargetY = centerY + math.sin(rainAngle) * rainDist
                            -- 从目标上方生成
                            local rSX = rTargetX + (math.random() - 0.5) * 40
                            local rSY = rTargetY - 200 - math.random() * 100
                            table.insert(G.turretProjectiles, {
                                type = "rocket",
                                x = rSX, y = rSY,
                                vx = (rTargetX - rSX) * 0.8,
                                vy = (rTargetY - rSY) * 0.8,
                                speed = 200,
                                angle = math.atan(rTargetY - rSY, rTargetX - rSX),
                                life = 1.5, maxLife = 1.5,
                                trailTimer = 0,
                                target = nil,
                                tx = rTargetX, ty = rTargetY,
                                exploded = false,
                            })
                        end
                    end

                    -- 温压弹：超大AOE+减速
                    if T.HasUpgrade(G, "rocket", "thermobaric") then
                        projDmg = math.floor(projDmg * 0.7)
                        -- 标记弹头为温压型（命中时大AOE）
                    end

                    -- 5联火箭（带散射，不重叠）
                    local volleyCount = T.HasUpgrade(G, "rocket", "volley5") and 5 or 1
                    if volleyCount > 1 then
                        local spreadAngles = { -0.35, -0.18, 0, 0.18, 0.35 }
                        local rktLife = effectiveRange / 150
                        for vi, sp in ipairs(spreadAngles) do
                            local va = turret.angle + sp
                            -- 发射点也略微分开，避免视觉重叠
                            local vox = math.cos(va + math.pi / 2) * (vi - 3) * 5
                            local voy = math.sin(va + math.pi / 2) * (vi - 3) * 5
                            local targetX = nearEnemy.x + math.cos(va) * 80
                            local targetY = nearEnemy.y + math.sin(va) * 80
                            table.insert(G.turretProjectiles, {
                                type = "rocket",
                                x = mx + vox, y = my + voy,
                                vx = math.cos(va) * 150,
                                vy = math.sin(va) * 150,
                                speed = 150,
                                angle = va,
                                life = rktLife, maxLife = rktLife,
                                trailTimer = 0,
                                target = nearEnemy,
                                tx = targetX, ty = targetY,
                                exploded = false,
                                thermobaric = T.HasUpgrade(G, "rocket", "thermobaric"),
                            })
                        end
                    else
                        -- 单发火箭
                        local rktLife = effectiveRange / 150
                        local rp = {
                            type = "rocket",
                            x = mx, y = my,
                            vx = math.cos(turret.angle) * 150,
                            vy = math.sin(turret.angle) * 150,
                            speed = 150,
                            angle = turret.angle,
                            life = rktLife, maxLife = rktLife,
                            trailTimer = 0,
                            target = nearEnemy,
                            tx = nearEnemy.x, ty = nearEnemy.y,
                            exploded = false,
                            thermobaric = T.HasUpgrade(G, "rocket", "thermobaric"),
                            burnzone = T.HasUpgrade(G, "rocket", "burnzone"),
                        }
                        table.insert(G.turretProjectiles, rp)
                    end

                elseif turret.typeKey == "minigun" then
                    -- ---- 机关枪炮台 ----
                    turret.recoil = 0.5
                    turret.fireFlash = 0.06
                    local projDmg = getTurretDamage(turret.typeKey, def.damage, G)

                    -- 360°弹幕风暴（触发型，有冷却）
                    if T.HasUpgrade(G, "minigun", "storm360") then
                        local stormCooldown = T.HasUpgrade(G, "minigun", "storm360_plus") and 3.0 or 4.0
                        turret.stormTimer = (turret.stormTimer or 0) + def.cooldown
                        if turret.stormTimer >= stormCooldown then
                            turret.stormTimer = 0
                            local stormDmgMul = T.HasUpgrade(G, "minigun", "storm360_plus") and 1.05 or 0.7
                            -- 180°朝下扇形发射24发（-π/2 ~ π/2 以π/2为中轴，即正下方半圆）
                            for si = 0, 23 do
                                local sa = (si / 23) * math.pi  -- 0 ~ π（朝右→朝下→朝左）
                                local spd = 400 + math.random() * 100
                                local stormLife = effectiveRange / spd
                                table.insert(G.turretProjectiles, {
                                    type = "minigun",
                                    x = mx, y = my,
                                    vx = math.cos(sa) * spd,
                                    vy = math.sin(sa) * spd,
                                    speed = spd,
                                    life = stormLife, maxLife = stormLife,
                                    target = nil,
                                    damage = math.floor(projDmg * stormDmgMul),
                                    tx = mx + math.cos(sa) * 300,
                                    ty = my + math.sin(sa) * 300,
                                    stormShot = true,
                                })
                            end
                        end
                    end

                    -- 燃烧弹：命中后燃烧
                    local mgLife = effectiveRange / 500
                    local mg_proj = {
                        type = "minigun",
                        x = mx, y = my,
                        vx = math.cos(turret.angle) * 500,
                        vy = math.sin(turret.angle) * 500,
                        speed = 500,
                        life = mgLife, maxLife = mgLife,
                        target = nearEnemy,
                        damage = projDmg,
                        tx = nearEnemy.x, ty = nearEnemy.y,
                        incendiary = T.HasUpgrade(G, "minigun", "incendiary"),
                        incendiary_plus = T.HasUpgrade(G, "minigun", "incendiary_plus"),
                        ricochetLeft = T.GetUpgradeVal(G, "minigun", "ricochet"),
                    }
                    local spread = (math.random() - 0.5) * 0.12
                    mg_proj.vx = math.cos(turret.angle + spread) * 500
                    mg_proj.vy = math.sin(turret.angle + spread) * 500
                    table.insert(G.turretProjectiles, mg_proj)

                    -- 多目标锁定：同时打两个额外目标
                    if T.HasUpgrade(G, "minigun", "multilock") then
                        local hitCount = 0
                        for _, z in ipairs(G.zombies or {}) do
                            if not z.dead and z ~= nearEnemy and hitCount < 2 then
                                local ddx = z.x - tx
                                local ddy = z.y - ty
                                if ddx * ddx + ddy * ddy < effectiveRange * effectiveRange then
                                    hitCount = hitCount + 1
                                    local mangle = math.atan(z.y - my, z.x - mx)
                                    table.insert(G.turretProjectiles, {
                                        type = "minigun",
                                        x = mx, y = my,
                                        vx = math.cos(mangle) * 500,
                                        vy = math.sin(mangle) * 500,
                                        speed = 500,
                                        life = mgLife, maxLife = mgLife,
                                        target = z,
                                        damage = math.floor(projDmg * 0.6),
                                        tx = z.x, ty = z.y,
                                    })
                                end
                            end
                        end
                    end

                else
                    -- 其他未处理的炮台类型（fallback）
                    local isProjectile = (turret.typeKey == "arrow" or turret.typeKey == "minigun" or turret.typeKey == "rocket")
                    if not isProjectile then
                        local tDmg = getTurretDamage(turret.typeKey, def.damage, G)
                        nearEnemy.hp = nearEnemy.hp - tDmg
                        nearEnemy.hitAnim = 1.0
                        E.SpawnParticles(G, nearEnemy.x, nearEnemy.y, BLOOD_COLOR, 4)
                        E.SpawnFloatText(G, nearEnemy.x, nearEnemy.y - 10, tostring(tDmg), "damage")
                        if nearEnemy.hp <= 0 then
                            nearEnemy.dead = true
                            E.SpawnZombieDeath(G, nearEnemy.x, nearEnemy.y)
                            E.SpawnGoldFly(G, nearEnemy.x, nearEnemy.y, 1)
                        end
                    end
                    turret.recoil = 1.0
                    turret.fireFlash = 0.12
                    spawnProjectile(G, def.projType, mx, my, nearEnemy.x, nearEnemy.y, turret.angle, nearEnemy,
                        getTurretDamage(turret.typeKey, def.damage, G), effectiveRange)
                end
            end

            -- 喷火炮台：有目标时持续播放火焰动画
            if turret.typeKey == "flame" then
                turret.flaming = true
                turret.flameTime = (turret.flameTime or 0) + dt
            end
        else
            turret.targeting = false
            -- 喷火炮台：无目标时停止喷火
            if turret.typeKey == "flame" then
                turret.flaming = false
                turret.flameTime = 0
            end
            local target = math.pi / 2
            local diff = target - turret.angle
            while diff > math.pi do diff = diff - 2 * math.pi end
            while diff < -math.pi do diff = diff + 2 * math.pi end
            if math.abs(diff) > 0.02 then
                turret.angle = turret.angle + diff * dt * 3.0
            else
                turret.angle = target
            end
        end

        if turret.fireFlash and turret.fireFlash > 0 then
            turret.fireFlash = turret.fireFlash - dt
        end
        ::continue::
    end

    -- 更新投射物
    T.UpdateProjectiles(G, dt)
end

------------------------------------------------------------------------
-- 更新投射物
------------------------------------------------------------------------
function T.UpdateProjectiles(G, dt)
    if not G.turretProjectiles then return end
    local list = G.turretProjectiles
    local total = #list
    local writeIdx = 0
    for readIdx = 1, total do
        local p = list[readIdx]
        p.life = p.life - dt
        if p.life > 0 then

            ----------------------------------------------------------------
            -- 弹道类(arrow/minigun/rocket)：追踪目标 + 命中判定
            ----------------------------------------------------------------
            local isTracking = (p.type == "arrow" or p.type == "minigun" or p.type == "rocket" or p.type == "mounted_bullet")

            if isTracking and p.target then
                -- 目标已死 → 子弹失去追踪
                if p.target.dead then
                    -- 火箭保留最后目标坐标，飞到那里照样爆炸
                    if p.type ~= "rocket" then
                        p.tx = nil
                        p.ty = nil
                    end
                    p.target = nil
                else
                    -- 目标还活着则实时更新目标坐标
                    p.tx = p.target.x
                    p.ty = p.target.y
                    -- 重新计算朝目标方向的速度
                    if p.tx and p.ty and p.speed then
                        local dx = p.tx - p.x
                        local dy = p.ty - p.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist > 1 then
                            p.vx = dx / dist * p.speed
                            p.vy = dy / dist * p.speed
                            p.angle = math.atan(dy, dx)
                        end
                    end
                end
            end

            -- 移动
            if p.vx then
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
            end

            -- 序列帧计时器更新
            if p.frameTime then
                p.frameTime = p.frameTime + dt
            end

            -- 激光束：位置跟随炮台 + DPS伤害tick + 帧动画推进
            if p.type == "laser_beam" then
                -- 1. 跟随炮台位置和角度
                local tr = p.turretRef
                if tr then
                    local tdef = T.TYPES[tr.typeKey]
                    local bx, by = T.GetSlotWorldPos(G, tr.slotId)
                    local tmx  = bx + (tdef and tdef.offsetX or 0)
                    local tmy  = by + (tdef and tdef.offsetY or 0)
                    local rng  = (p.laserRange or 300) * 1.5
                    -- 裁剪激光终点到屏幕范围内
                    local dirX = math.cos(tr.angle)
                    local dirY = math.sin(tr.angle)
                    local maxRng = rng
                    local scrW = G.screenW or 480
                    local scrH = G.screenH or 800
                    if dirY > 0.001 then
                        maxRng = math.min(maxRng, (scrH - tmy) / dirY)
                    elseif dirY < -0.001 then
                        maxRng = math.min(maxRng, (0 - tmy) / dirY)
                    end
                    if dirX > 0.001 then
                        maxRng = math.min(maxRng, (scrW - tmx) / dirX)
                    elseif dirX < -0.001 then
                        maxRng = math.min(maxRng, (0 - tmx) / dirX)
                    end
                    maxRng = math.max(0, maxRng)
                    p.sx = tmx
                    p.sy = tmy
                    p.ex = tmx + dirX * maxRng
                    p.ey = tmy + dirY * maxRng
                end

                -- 2. DPS伤害 tick
                p.dmgTimer = (p.dmgTimer or 0) + dt
                if p.dmgTimer >= (p.dmgInterval or 0.15) then
                    p.dmgTimer = p.dmgTimer - (p.dmgInterval or 0.15)
                    local lx1, ly1, lx2, ly2 = p.sx, p.sy, p.ex, p.ey
                    local ldx   = lx2 - lx1
                    local ldy   = ly2 - ly1
                    local llen2 = ldx * ldx + ldy * ldy
                    if llen2 > 0 then
                        for _, z in ipairs(G.zombies or {}) do
                            if not z.dead then
                                local t2 = ((z.x - lx1)*ldx + (z.y - ly1)*ldy) / llen2
                                t2 = math.max(0, math.min(1, t2))
                                local perpDx = z.x - (lx1 + t2*ldx)
                                local perpDy = z.y - (ly1 + t2*ldy)
                                if perpDx*perpDx + perpDy*perpDy < 14*14 then
                                    local laserDmg = math.floor((p.laserBaseDmg or 30) * (p.laserDmgMul or 2.0) * (p.dmgInterval or 0.15))
                                    z.hp = z.hp - laserDmg
                                    z.hitAnim = 0.4
                                    E.SpawnParticles(G, z.x, z.y, {100, 180, 255}, 3)
                                    E.SpawnFloatText(G, z.x, z.y - 10, tostring(laserDmg), "damage")
                                    if z.hp <= 0 then
                                        z.dead = true
                                        G.killCount = (G.killCount or 0) + 1
                                        E.SpawnZombieDeath(G, z.x, z.y)
                                        E.SpawnGoldFly(G, z.x, z.y, 1)
                                    end
                                end
                            end
                        end
                    end
                end

                -- 3. 帧动画推进
                if p.laserPhase then
                    local FPS  = 12
                    local FSPD = 1.0 / FPS
                    p.laserFrameT = (p.laserFrameT or 0) + dt
                    if p.laserFrameT >= FSPD then
                        p.laserFrameT = p.laserFrameT - FSPD
                        p.laserFrameIdx = (p.laserFrameIdx or 1) + 1
                        if p.laserPhase == "open" then
                            if p.laserFrameIdx > 4 then
                                p.laserPhase    = "loop"
                                p.laserFrameIdx = 1
                            end
                        elseif p.laserPhase == "loop" then
                            -- 剩余时长不足关闭动画时切换
                            if p.life <= 4 * FSPD then
                                p.laserPhase    = "close"
                                p.laserFrameIdx = 1
                            elseif p.laserFrameIdx > 10 then
                                p.laserFrameIdx = 1
                            end
                        elseif p.laserPhase == "close" then
                            if p.laserFrameIdx > 4 then
                                p.laserFrameIdx = 4
                            end
                        end
                    end
                    -- 炮口帧独立循环（4帧，12fps，open+loop阶段使用）
                    p.laserMuzzleT = (p.laserMuzzleT or 0) + dt
                    if p.laserMuzzleT >= FSPD then
                        p.laserMuzzleT = p.laserMuzzleT - FSPD
                        p.laserMuzzleIdx = ((p.laserMuzzleIdx or 0) % 4) + 1
                    end
                end
            end

            ----------------------------------------------------------------
            -- 弓箭：到达目标 → 单体伤害 + 命中火花
            ----------------------------------------------------------------
            if p.type == "arrow" and p.tx and p.ty then
                local dx = p.x - p.tx
                local dy = p.y - p.ty
                local distSq = dx * dx + dy * dy
                if distSq < 144 then
                    -- 贯穿：pierce剩余次数大于0则不销毁
                    local pierceLeft = p.pierceLeft or 0
                    local willKill = (pierceLeft <= 0)
                    if willKill then p.life = 0 end
                    -- 造成伤害
                    if p.target and not p.target.dead then
                        local arrowDmg = p.damage or 8
                        p.target.hp = p.target.hp - arrowDmg
                        p.target.hitAnim = 1.0
                        E.SpawnParticles(G, p.target.x, p.target.y, BLOOD_COLOR, 5)
                        E.SpawnFloatText(G, p.target.x, p.target.y - 10, tostring(arrowDmg), "damage")
                        if p.target.hp <= 0 then
                            p.target.dead = true
                            E.SpawnGoldFly(G, p.target.x, p.target.y, 1)
                            E.SpawnZombieDeath(G, p.target.x, p.target.y)
                        end
                        -- 爆炸箭：命中后AOE
                        if p.explosive then
                            local aoeR = p.explosive_big and 140 or 90
                            for _, z in ipairs(G.zombies or {}) do
                                if not z.dead and z ~= p.target then
                                    local adx = z.x - p.x
                                    local ady = z.y - p.y
                                    if adx * adx + ady * ady < aoeR * aoeR then
                                        local aoeDmg = math.floor(arrowDmg * 0.6)
                                        z.hp = z.hp - aoeDmg
                                        z.hitAnim = 0.6
                                        E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 3)
                                        E.SpawnFloatText(G, z.x, z.y - 10, tostring(aoeDmg), "damage")
                                        if z.hp <= 0 then z.dead = true; G.killCount = (G.killCount or 0) + 1; E.SpawnZombieDeath(G, z.x, z.y); E.SpawnGoldFly(G, z.x, z.y, 1) end
                                    end
                                end
                            end
                            T.SpawnExplosion(G, p.x, p.y)
                        end
                        -- 穿链弹：命中后弹射至最近另一目标
                        if p.chainLeft and p.chainLeft > 0 then
                            local best, bestDist = nil, 160 * 160
                            for _, z in ipairs(G.zombies or {}) do
                                if not z.dead and z ~= p.target then
                                    local cdx = z.x - p.x; local cdy = z.y - p.y
                                    local cd2 = cdx * cdx + cdy * cdy
                                    if cd2 < bestDist then bestDist = cd2; best = z end
                                end
                            end
                            if best then
                                local ca = math.atan(best.y - p.y, best.x - p.x)
                                local spd = 320
                                table.insert(G.turretProjectiles, {
                                    type = "arrow",
                                    x = p.x, y = p.y,
                                    vx = math.cos(ca) * spd, vy = math.sin(ca) * spd,
                                    speed = spd, angle = ca, life = 1.2, maxLife = 1.2,
                                    target = best, damage = math.floor(arrowDmg * 0.7),
                                    tx = best.x, ty = best.y,
                                    chainLeft = p.chainLeft - 1,
                                    isChain = true,
                                })
                                -- 弹射连线特效
                                table.insert(G.turretProjectiles, {
                                    type = "electric",
                                    points = {{ x = p.x, y = p.y }, { x = best.x, y = best.y }},
                                    life = 0.2, maxLife = 0.2,
                                    r = 255, g = 220, b = 80,
                                })
                            end
                        end
                        -- 贯穿：更新目标为下一个
                        if not willKill then
                            p.pierceLeft = pierceLeft - 1
                            -- 寻找穿透方向上下一个敌人
                            local best2, bestDot = nil, 0.8
                            for _, z in ipairs(G.zombies or {}) do
                                if not z.dead and z ~= p.target then
                                    local ndx = z.x - p.x; local ndy = z.y - p.y
                                    local nd = math.sqrt(ndx * ndx + ndy * ndy)
                                    if nd > 1 then
                                        local pvx, pvy = p.vx, p.vy
                                        local plen = math.sqrt(pvx * pvx + pvy * pvy)
                                        local dot2 = (ndx / nd) * (pvx / plen) + (ndy / nd) * (pvy / plen)
                                        if dot2 > bestDot and nd < 300 then bestDot = dot2; best2 = z end
                                    end
                                end
                            end
                            if best2 then
                                p.target = best2; p.tx = best2.x; p.ty = best2.y
                            else
                                p.life = 0  -- 找不到下一目标则消失
                            end
                        end
                    end
                    -- 命中火花
                    for _ = 1, 3 do
                        local a = math.random() * math.pi * 2
                        local spd = 30 + math.random() * 40
                        table.insert(G.turretProjectiles, {
                            type = "spark", x = p.x, y = p.y,
                            vx = math.cos(a) * spd, vy = math.sin(a) * spd,
                            life = 0.2, maxLife = 0.2,
                            r = 200, g = 160, b = 80,
                        })
                    end
                end
            end

            ----------------------------------------------------------------
            -- 机关枪：穿透弹 — 沿路径命中所有敌人
            ----------------------------------------------------------------
            if p.type == "minigun" then
                if not p.hitSet then p.hitSet = {} end
                local hitR = 14  -- 命中半径
                for _, z in ipairs(G.zombies or {}) do
                    if not z.dead and not p.hitSet[z] then
                        local dx = p.x - z.x
                        local dy = p.y - z.y
                        if dx * dx + dy * dy < hitR * hitR then
                            p.hitSet[z] = true
                            local mgDmg = p.damage or 10
                            z.hp = z.hp - mgDmg
                            z.hitAnim = 1.0
                            E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 2)
                            E.SpawnFloatText(G, z.x, z.y - 10, tostring(mgDmg), "damage")
                            if z.hp <= 0 then
                                z.dead = true
                                G.killCount = (G.killCount or 0) + 1
                                E.SpawnGoldFly(G, z.x, z.y, 1)
                                E.SpawnZombieDeath(G, z.x, z.y)
                            end
                            -- 命中火花
                            table.insert(G.turretProjectiles, {
                                type = "spark", x = p.x, y = p.y,
                                vx = (math.random() - 0.5) * 30,
                                vy = (math.random() - 0.5) * 30,
                                life = 0.12, maxLife = 0.12,
                                r = 255, g = 230, b = 100,
                            })
                        end
                    end
                end
            end

            ----------------------------------------------------------------
            -- 火箭：烟尾 + 到达目标 → AOE伤害 + 爆炸特效
            ----------------------------------------------------------------
            if p.type == "rocket" then
                p.trailTimer = (p.trailTimer or 0) + dt
                if p.trailTimer > 0.03 then
                    p.trailTimer = 0
                    table.insert(G.turretProjectiles, {
                        type = "smoke", x = p.x, y = p.y,
                        vx = (math.random() - 0.5) * 15,
                        vy = (math.random() - 0.5) * 15,
                        life = 0.4, maxLife = 0.4,
                        size = 3 + math.random() * 3,
                    })
                end
                if p.tx and p.ty and not p.exploded then
                    local dx = p.x - p.tx
                    local dy = p.y - p.ty
                    local distSq = dx * dx + dy * dy
                    if distSq < 225 then
                        p.exploded = true
                        p.life = 0
                        -- 温压弹：超大范围 AOE + 减速
                        if p.thermobaric then
                            -- 临时扩大 AOE，通过直接计算（基础爆炸半径80px）
                            local tbDmg = getTurretDamage("rocket", T.TYPES.rocket.damage, G)
                            local tbRadius = 80 * 2.2
                            local tbR2 = tbRadius * tbRadius
                            for _, z in ipairs(G.zombies or {}) do
                                if not z.dead then
                                    local tdx = z.x - p.x
                                    local tdy = z.y - p.y
                                    local td2 = tdx * tdx + tdy * tdy
                                    if td2 < tbR2 then
                                        local dist = math.sqrt(td2)
                                        local falloff = 1.0 - 0.6 * (dist / tbRadius)
                                        local finalDmg = math.floor(tbDmg * falloff)
                                        z.hp = z.hp - finalDmg
                                        z.hitAnim = 1.0
                                        z.slowTimer = 3.0
                                        z.slowMul = 0.3
                                        E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 4)
                                        E.SpawnFloatText(G, z.x, z.y - 10, tostring(finalDmg), "damage")
                                        if z.hp <= 0 then
                                            z.dead = true
                                            G.killCount = (G.killCount or 0) + 1
                                            E.SpawnGoldFly(G, z.x, z.y, 1)
                                            E.SpawnZombieDeath(G, z.x, z.y)
                                        end
                                    end
                                end
                            end
                            -- 大爆炸特效（两重）
                            T.SpawnExplosion(G, p.x, p.y)
                            T.SpawnExplosion(G, p.x + (math.random() - 0.5) * 30, p.y + (math.random() - 0.5) * 30)
                        else
                            T.RocketAOE(G, p.x, p.y)
                            T.SpawnExplosion(G, p.x, p.y)
                        end
                        -- 燃烧区域
                        if p.burnzone then
                            if not G.burnZones then G.burnZones = {} end
                            table.insert(G.burnZones, {
                                x = p.x, y = p.y,
                                radius = 60, life = 6.0, damage = 12,
                                tickTimer = 0,
                            })
                        end
                    end
                end
            end

            ----------------------------------------------------------------
            -- 毒箭：到达目标 → 单体伤害 + 中毒
            ----------------------------------------------------------------
            if p.type == "poison_arrow" and p.tx and p.ty then
                local dx = p.x - p.tx
                local dy = p.y - p.ty
                local distSq = dx * dx + dy * dy
                if distSq < 144 then
                    p.life = 0
                    if p.target and not p.target.dead then
                        local arrowDmg = p.damage or 8
                        p.target.hp = p.target.hp - arrowDmg
                        p.target.hitAnim = 1.0
                        local poisonDur = p.poison_extra and 6.0 or 4.0
                        local poisonDmgMul = p.poison_extra and 0.39 or 0.3
                        p.target.poisonTimer = poisonDur
                        p.target.poisonDmg = math.floor(arrowDmg * poisonDmgMul)
                        p.target.poisonTickTimer = 0
                        E.SpawnParticles(G, p.target.x, p.target.y, {60, 200, 60}, 5)
                        E.SpawnFloatText(G, p.target.x, p.target.y - 10, tostring(arrowDmg), "damage")
                        if p.target.hp <= 0 then
                            p.target.dead = true
                            E.SpawnGoldFly(G, p.target.x, p.target.y, 1)
                            E.SpawnZombieDeath(G, p.target.x, p.target.y)
                        end
                    end
                    for _ = 1, 4 do
                        local a = math.random() * math.pi * 2
                        local spd = 25 + math.random() * 35
                        table.insert(G.turretProjectiles, {
                            type = "spark", x = p.x, y = p.y,
                            vx = math.cos(a) * spd, vy = math.sin(a) * spd,
                            life = 0.25, maxLife = 0.25,
                            r = 60, g = 200, b = 60,
                        })
                    end
                end
            end

            ----------------------------------------------------------------
            -- 闪电球：接近目标时链式爆炸
            ----------------------------------------------------------------
            if p.type == "ball_lightning" and p.tx and p.ty then
                -- 脉冲持续放电（每隔0.3s）
                p.pulseTimer = (p.pulseTimer or 0) + dt
                if p.pulseTimer >= 0.3 then
                    p.pulseTimer = 0
                    -- 附近敌人链式伤害
                    local blR = 80
                    for _, z in ipairs(G.zombies or {}) do
                        if not z.dead then
                            local bdx = p.x - z.x
                            local bdy = p.y - z.y
                            if bdx * bdx + bdy * bdy < blR * blR then
                                local blDmg = p.damage or 15
                                z.hp = z.hp - blDmg
                                z.hitAnim = 0.4
                                z.stunTimer = 0.8
                                z.stunned = true
                                E.SpawnParticles(G, z.x, z.y, {100, 180, 255}, 3)
                                E.SpawnFloatText(G, z.x, z.y - 10, tostring(blDmg), "damage")
                                -- 闪电放电特效
                                local lPoints = {{ x = p.x, y = p.y }, { x = z.x, y = z.y }}
                                table.insert(G.turretProjectiles, {
                                    type = "electric",
                                    points = lPoints,
                                    life = 0.15, maxLife = 0.15,
                                })
                                if z.hp <= 0 then
                                    z.dead = true
                                    G.killCount = (G.killCount or 0) + 1
                                    E.SpawnZombieDeath(G, z.x, z.y)
                                    E.SpawnGoldFly(G, z.x, z.y, 1)
                                end
                            end
                        end
                    end
                end
                -- 到达主目标时爆炸消失
                local dx = p.x - p.tx
                local dy = p.y - p.ty
                if dx * dx + dy * dy < 200 then
                    p.life = 0
                    -- 最终大爆炸
                    local blR = 100
                    for _, z in ipairs(G.zombies or {}) do
                        if not z.dead then
                            local bdx = p.x - z.x
                            local bdy = p.y - z.y
                            if bdx * bdx + bdy * bdy < blR * blR then
                                local blDmg = math.floor((p.damage or 15) * 1.5)
                                z.hp = z.hp - blDmg
                                z.hitAnim = 0.5
                                E.SpawnParticles(G, z.x, z.y, {100, 180, 255}, 5)
                                E.SpawnFloatText(G, z.x, z.y - 10, tostring(blDmg), "damage")
                                if z.hp <= 0 then
                                    z.dead = true
                                    G.killCount = (G.killCount or 0) + 1
                                    E.SpawnZombieDeath(G, z.x, z.y)
                                    E.SpawnGoldFly(G, z.x, z.y, 1)
                                end
                            end
                        end
                    end
                    for _ = 1, 8 do
                        local a = math.random() * math.pi * 2
                        local spd = 60 + math.random() * 80
                        table.insert(G.turretProjectiles, {
                            type = "spark", x = p.x, y = p.y,
                            vx = math.cos(a) * spd, vy = math.sin(a) * spd,
                            life = 0.3, maxLife = 0.3,
                            r = 100, g = 180, b = 255,
                        })
                    end
                end
            end

            ----------------------------------------------------------------
            -- 火箭特殊标记：温压弹、燃烧区域
            ----------------------------------------------------------------
            if p.type == "rocket" and p.exploded then
                -- 已在标准 rocket 逻辑中处理，这里只处理额外标记
            end

            ----------------------------------------------------------------
            -- 机关枪燃烧弹：命中时施加燃烧；跳弹：命中后弹射
            ----------------------------------------------------------------
            if p.type == "minigun" and not p.stormShot then
                if not p.hitSet then p.hitSet = {} end
                local hitR = 14
                for _, z in ipairs(G.zombies or {}) do
                    if not z.dead and not p.hitSet[z] then
                        local dx = p.x - z.x
                        local dy = p.y - z.y
                        if dx * dx + dy * dy < hitR * hitR then
                            p.hitSet[z] = true
                            -- 燃烧弹
                            if p.incendiary then
                                local burnDur = p.incendiary_plus and 4.0 or 2.5
                                local burnDmgV = p.incendiary_plus and 9 or 6
                                z.burnTimer = math.max(z.burnTimer or 0, burnDur)
                                z.burnDmg = burnDmgV
                                z.burnTickTimer = 0
                            end
                            -- 跳弹：命中后弹射至附近另一敌人（最多ricochetLeft次）
                            if p.ricochetLeft and p.ricochetLeft > 0 and not p.isRicochet then
                                local best, bestDist = nil, 180 * 180
                                for _, z2 in ipairs(G.zombies or {}) do
                                    if not z2.dead and z2 ~= z then
                                        local rdx = z2.x - p.x; local rdy = z2.y - p.y
                                        local rd2 = rdx * rdx + rdy * rdy
                                        if rd2 < bestDist then bestDist = rd2; best = z2 end
                                    end
                                end
                                if best then
                                    local ra = math.atan(best.y - p.y, best.x - p.x)
                                    local rspd = 480
                                    table.insert(G.turretProjectiles, {
                                        type = "minigun",
                                        x = p.x, y = p.y,
                                        vx = math.cos(ra) * rspd, vy = math.sin(ra) * rspd,
                                        speed = rspd, life = 0.6, maxLife = 0.6,
                                        target = best, damage = math.floor((p.damage or 10) * 0.65),
                                        tx = best.x, ty = best.y,
                                        ricochetLeft = p.ricochetLeft - 1,
                                        isRicochet = true,
                                        incendiary = p.incendiary,
                                        incendiary_plus = p.incendiary_plus,
                                    })
                                    -- 跳弹火花特效
                                    for _ = 1, 5 do
                                        local ra2 = math.random() * math.pi * 2
                                        table.insert(G.turretProjectiles, {
                                            type = "spark", x = p.x, y = p.y,
                                            vx = math.cos(ra2) * (50 + math.random() * 60),
                                            vy = math.sin(ra2) * (50 + math.random() * 60),
                                            life = 0.15, maxLife = 0.15,
                                            r = 255, g = 200, b = 80,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end

            ----------------------------------------------------------------
            -- 上车子弹：直线飞行 → 碰到丧尸造成伤害
            ----------------------------------------------------------------
            if p.type == "mounted_bullet" then
                local hitRadius = 12
                if not p.hitSet then p.hitSet = {} end
                for _, z in ipairs(G.zombies or {}) do
                    if not z.dead and not p.hitSet[z] then
                        local dx2 = p.x - z.x
                        local dy2 = p.y - z.y
                        if dx2 * dx2 + dy2 * dy2 < hitRadius * hitRadius then
                            p.hitSet[z] = true  -- 穿透：记录已命中，不消亡
                            local mDmg = p.damage or 30
                            z.hp = z.hp - mDmg
                            z.hitAnim = 0.2
                            E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 3)
                            E.SpawnFloatText(G, z.x, z.y - 10, tostring(mDmg), "damage")
                            if z.hp <= 0 then
                                z.dead = true
                                G.killCount = (G.killCount or 0) + 1
                                E.SpawnGoldFly(G, z.x, z.y, 1)
                                E.SpawnZombieDeath(G, z.x, z.y)
                            end
                        end
                    end
                end
            end

            writeIdx = writeIdx + 1
            list[writeIdx] = p
        end
    end
    -- 清除尾部死亡射弹（新增的射弹在 total 之后，保留）
    local newTotal = #list
    for i = total, writeIdx + 1, -1 do
        table.remove(list, i)
    end
end

------------------------------------------------------------------------
-- 绘制（炮塔 + 投射物）
------------------------------------------------------------------------
function T.Draw(vg, G)
    if not G.turrets or not G.turretImgs then return end

    -- 0) 地面燃烧区域（最底层）
    T.DrawBurnZones(vg, G)

    -- 1) 炮塔本体（第三层）
    for _, turret in ipairs(G.turrets) do
        local def = T.TYPES[turret.typeKey]
        if not def then goto continue end

        local tx, ty = T.GetSlotWorldPos(G, turret.slotId)
        local img = G.turretImgs[def.imgKey]
        if not img or img == 0 then goto continue end

        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgRotate(vg, turret.angle - math.pi / 2)

        -- 后坐力
        local recoilOff = 0
        if turret.recoil and turret.recoil > 0 then
            recoilOff = -turret.recoil * 5
        end

        local halfW = TURRET_W / 2
        local halfH = TURRET_H / 2

        local imgPaint = nvgImagePattern(vg, -halfW, -halfH + recoilOff, TURRET_W, TURRET_H, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -halfW, -halfH + recoilOff, TURRET_W, TURRET_H)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)

        -- 炮口闪光（双层，喷火/弓箭炮台不用）
        if turret.typeKey ~= "flame" and turret.typeKey ~= "arrow" and turret.fireFlash and turret.fireFlash > 0 then
            local ratio = turret.fireFlash / 0.12
            local fa = math.floor(ratio * 240)
            local fSize = 6 + ratio * 6

            -- 外层光晕
            nvgBeginPath(vg)
            nvgCircle(vg, 0, halfH + 4, fSize)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, fa))
            nvgFill(vg)

            -- 内核
            nvgBeginPath(vg)
            nvgCircle(vg, 0, halfH + 4, fSize * 0.35)
            nvgFillColor(vg, nvgRGBA(255, 255, 220, fa))
            nvgFill(vg)
        end

        -- 喷火炮台：炮口循环播放火焰序列帧
        if turret.typeKey == "flame" and turret.flaming and G.flameFrames then
            local frameCount = G.FLAME_FRAME_COUNT or 21
            local fps = 24
            local frameIdx = math.floor((turret.flameTime or 0) * fps) % frameCount + 1
            local fImg = G.flameFrames[frameIdx]
            if fImg and fImg ~= 0 then
                local drawH = 130
                local drawW = drawH * (101 / 235)
                -- 翻转火焰图片，让火焰尖端朝外喷射
                nvgSave(vg)
                nvgTranslate(vg, 0, halfH - 4)
                nvgScale(vg, 1, -1)
                local paint = nvgImagePattern(vg, -drawW / 2, -drawH, drawW, drawH, 0, fImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, -drawW / 2, -drawH, drawW, drawH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
                nvgRestore(vg)
            end
        end

        nvgRestore(vg)
        ::continue::
    end

    -- 2) 投射物（第二层，在炮台上方）
    T.DrawProjectiles(vg, G)

    -- 3) 炮口特效（最顶层）
    T.DrawMuzzleFlashes(vg, G)
end

------------------------------------------------------------------------
-- 炮口特效（最顶层，仅 laser_beam open/loop 阶段）
------------------------------------------------------------------------
function T.DrawMuzzleFlashes(vg, G)
    if not G.turretProjectiles or not G.laserMuzzleFrames then return end
    for _, p in ipairs(G.turretProjectiles) do
        if p.type == "laser_beam" then
            local phase = p.laserPhase or "loop"
            if (phase == "open" or phase == "loop") then
                local idx = p.laserMuzzleIdx or 1
                local mHandle = G.laserMuzzleFrames[idx]
                if mHandle and mHandle ~= 0 then
                    local dx  = p.ex - p.sx
                    local dy  = p.ey - p.sy
                    local angle = math.atan(dy, dx)
                    local mW, mH = 100, 62
                    nvgSave(vg)
                    nvgTranslate(vg, p.sx, p.sy)
                    nvgRotate(vg, angle + math.pi * 0.5)
                    local paint = nvgImagePattern(vg, -mW * 0.5, -mH * 0.5, mW, mH, 0, mHandle, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, -mW * 0.5, -mH * 0.5, mW, mH)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                    nvgRestore(vg)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- 绘制投射物
------------------------------------------------------------------------
function T.DrawProjectiles(vg, G)
    if not G.turretProjectiles then return end

    for _, p in ipairs(G.turretProjectiles) do
        if p.type == "arrow" then
            T.DrawArrow(vg, p, G)
        elseif p.type == "sniper" then
            T.DrawSniper(vg, p)
        elseif p.type == "electric" then
            T.DrawElectric(vg, p)
        elseif p.type == "rocket" then
            T.DrawRocket(vg, p, G)
        elseif p.type == "minigun" then
            T.DrawMinigun(vg, p)
        elseif p.type == "spark" then
            T.DrawSpark(vg, p)
        elseif p.type == "smoke" then
            T.DrawSmoke(vg, p)
        elseif p.type == "explosion" then
            T.DrawExplosion(vg, p)
        elseif p.type == "mounted_bullet" then
            T.DrawMountedBullet(vg, p, G)
        elseif p.type == "poison_arrow" then
            T.DrawPoisonArrow(vg, p, G)
        elseif p.type == "ball_lightning" then
            T.DrawBallLightning(vg, p)
        elseif p.type == "laser_beam" then
            T.DrawLaserBeam(vg, p, G)
        end
    end
end

------------------------------------------------------------------------
-- 弓箭：使用箭矢图片渲染
------------------------------------------------------------------------
function T.DrawArrow(vg, p, G)
    local alpha = math.min(1.0, p.life / 0.2)
    local img = G and G.arrowProjImg
    if not img or img == 0 then
        -- fallback: 简单三角形
        local a = math.floor(alpha * 255)
        nvgSave(vg)
        nvgTranslate(vg, p.x, p.y)
        nvgRotate(vg, p.angle)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 10, 0)
        nvgLineTo(vg, -6, -3)
        nvgLineTo(vg, -6, 3)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(180, 140, 80, a))
        nvgFill(vg)
        nvgRestore(vg)
        return
    end

    -- 原图 658x658 正方形，箭头朝下
    local drawSize = 30
    local drawW = drawSize
    local drawH = drawSize

    nvgSave(vg)
    nvgTranslate(vg, p.x, p.y)
    -- 原图箭头朝下(+Y)，p.angle=0 朝右，π/2 朝下，所以减 π/2
    nvgRotate(vg, p.angle - math.pi / 2)
    nvgGlobalAlpha(vg, alpha)

    local paint = nvgImagePattern(vg, -drawW / 2, -drawH / 2, drawW, drawH, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, -drawW / 2, -drawH / 2, drawW, drawH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)
end

------------------------------------------------------------------------
-- 狙击：粗激光射线 + 渐隐
------------------------------------------------------------------------
function T.DrawSniper(vg, p)
    local ratio = p.life / p.maxLife
    local a = math.floor(ratio * 255)

    -- 外层红色光柱（粗）
    nvgBeginPath(vg)
    nvgMoveTo(vg, p.sx, p.sy)
    nvgLineTo(vg, p.tx, p.ty)
    nvgStrokeColor(vg, nvgRGBA(255, 40, 30, math.floor(a * 0.6)))
    nvgStrokeWidth(vg, 5 * ratio)
    nvgStroke(vg)

    -- 中层亮红
    nvgBeginPath(vg)
    nvgMoveTo(vg, p.sx, p.sy)
    nvgLineTo(vg, p.tx, p.ty)
    nvgStrokeColor(vg, nvgRGBA(255, 120, 80, a))
    nvgStrokeWidth(vg, 2.5 * ratio + 0.5)
    nvgStroke(vg)

    -- 核心白线
    nvgBeginPath(vg)
    nvgMoveTo(vg, p.sx, p.sy)
    nvgLineTo(vg, p.tx, p.ty)
    nvgStrokeColor(vg, nvgRGBA(255, 240, 220, a))
    nvgStrokeWidth(vg, 1.0 * ratio + 0.3)
    nvgStroke(vg)

    -- 命中点大闪光
    local flashR = 10 * ratio
    nvgBeginPath(vg)
    nvgCircle(vg, p.tx, p.ty, flashR)
    nvgFillColor(vg, nvgRGBA(255, 120, 60, math.floor(a * 0.6)))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, p.tx, p.ty, flashR * 0.4)
    nvgFillColor(vg, nvgRGBA(255, 255, 200, a))
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 电能：粗闪电弧（蓝白色锯齿线）
------------------------------------------------------------------------
function T.DrawElectric(vg, p)
    if not p.points or #p.points < 2 then return end
    local ratio = p.life / p.maxLife
    local a = math.floor(ratio * 255)

    -- 外层光晕（蓝色，很粗）
    nvgBeginPath(vg)
    nvgMoveTo(vg, p.points[1].x, p.points[1].y)
    for i = 2, #p.points do
        nvgLineTo(vg, p.points[i].x, p.points[i].y)
    end
    nvgStrokeColor(vg, nvgRGBA(40, 120, 255, math.floor(a * 0.35)))
    nvgStrokeWidth(vg, 7 * ratio)
    nvgStroke(vg)

    -- 中间层
    nvgBeginPath(vg)
    nvgMoveTo(vg, p.points[1].x, p.points[1].y)
    for i = 2, #p.points do
        nvgLineTo(vg, p.points[i].x, p.points[i].y)
    end
    nvgStrokeColor(vg, nvgRGBA(120, 180, 255, a))
    nvgStrokeWidth(vg, 3 * ratio + 1)
    nvgStroke(vg)

    -- 核心白线
    nvgBeginPath(vg)
    nvgMoveTo(vg, p.points[1].x, p.points[1].y)
    for i = 2, #p.points do
        nvgLineTo(vg, p.points[i].x, p.points[i].y)
    end
    nvgStrokeColor(vg, nvgRGBA(220, 240, 255, a))
    nvgStrokeWidth(vg, 1.5 * ratio + 0.5)
    nvgStroke(vg)

    -- 节点火花
    for i = 1, #p.points do
        nvgBeginPath(vg)
        nvgCircle(vg, p.points[i].x, p.points[i].y, 3 * ratio)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, math.floor(a * 0.7)))
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 火箭：大弹头 + 尾焰
------------------------------------------------------------------------
function T.DrawRocket(vg, p, G)
    local alpha = math.min(1.0, p.life / 0.3)
    local img = G and G.rocketProjImg
    if not img or img == 0 then
        -- fallback: 简单圆点
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, 5)
        nvgFillColor(vg, nvgRGBA(80, 120, 60, math.floor(alpha * 255)))
        nvgFill(vg)
        return
    end

    local drawH = 38  -- 火箭弹绘制高度
    local drawW = drawH * (117 / 126)  -- 保持原图比例

    nvgSave(vg)
    nvgTranslate(vg, p.x, p.y)
    -- 原图火箭头朝上（-Y），旋转到飞行方向
    nvgRotate(vg, p.angle + math.pi / 2)
    nvgGlobalAlpha(vg, alpha)

    local paint = nvgImagePattern(vg, -drawW / 2, -drawH / 2, drawW, drawH, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, -drawW / 2, -drawH / 2, drawW, drawH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)
end

------------------------------------------------------------------------
-- 机关枪：曳光弹（亮黄短线 + 弹头光点）
------------------------------------------------------------------------
function T.DrawMinigun(vg, p)
    local a = math.floor(math.min(1.0, p.life / 0.1) * 255)
    local angle = math.atan(p.vy, p.vx)
    local len = 10
    local ex = p.x - math.cos(angle) * len
    local ey = p.y - math.sin(angle) * len

    -- 外层曳光（宽，半透明）
    nvgBeginPath(vg)
    nvgMoveTo(vg, ex, ey)
    nvgLineTo(vg, p.x, p.y)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 60, math.floor(a * 0.4)))
    nvgStrokeWidth(vg, 4)
    nvgStroke(vg)

    -- 核心曳光线
    nvgBeginPath(vg)
    nvgMoveTo(vg, ex, ey)
    nvgLineTo(vg, p.x, p.y)
    nvgStrokeColor(vg, nvgRGBA(255, 240, 120, a))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 弹头亮点
    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, 2.5)
    nvgFillColor(vg, nvgRGBA(255, 255, 200, a))
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 通用火花粒子（狙击/电能命中时使用）
------------------------------------------------------------------------
function T.DrawSpark(vg, p)
    local ratio = p.life / p.maxLife
    local a = math.floor(ratio * 255)
    local size = 2.5 * ratio + 0.5

    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, size)
    nvgFillColor(vg, nvgRGBA(p.r or 255, p.g or 200, p.b or 100, a))
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 烟雾粒子（火箭尾迹）
------------------------------------------------------------------------
function T.DrawSmoke(vg, p)
    local ratio = p.life / p.maxLife
    local a = math.floor(ratio * 100)
    local size = p.size * (1.0 + (1.0 - ratio) * 2)

    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, size)
    nvgFillColor(vg, nvgRGBA(140, 140, 140, a))
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 火箭AOE范围伤害
------------------------------------------------------------------------
local ROCKET_AOE_RADIUS = 80  -- 爆炸半径(像素)

function T.RocketAOE(G, ex, ey)
    if not G.zombies then return end
    local dmg = getTurretDamage("rocket", T.TYPES.rocket.damage, G)
    local radiusSq = ROCKET_AOE_RADIUS * ROCKET_AOE_RADIUS
    for _, z in ipairs(G.zombies) do
        if not z.dead then
            local dx = z.x - ex
            local dy = z.y - ey
            local distSq = dx * dx + dy * dy
            if distSq < radiusSq then
                -- 距离衰减：中心全额伤害，边缘50%
                local dist = math.sqrt(distSq)
                local falloff = 1.0 - 0.5 * (dist / ROCKET_AOE_RADIUS)
                local finalDmg = math.floor(dmg * falloff)
                z.hp = z.hp - finalDmg
                z.hitAnim = 1.0
                E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 4)
                E.SpawnFloatText(G, z.x, z.y - 10, tostring(finalDmg), "damage")
                if z.hp <= 0 then
                    z.dead = true
                    G.killCount = (G.killCount or 0) + 1
                    E.SpawnGoldFly(G, z.x, z.y, 1)
                    E.SpawnZombieDeath(G, z.x, z.y)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- 火箭爆炸效果 - 生成爆炸粒子群
------------------------------------------------------------------------
function T.SpawnExplosion(G, x, y)
    -- 中心火球（大的爆炸核心）
    table.insert(G.turretProjectiles, {
        type = "explosion", x = x, y = y,
        vx = 0, vy = 0,
        life = 0.5, maxLife = 0.5,
        size = 30, subType = "core",
    })

    -- 冲击波环
    table.insert(G.turretProjectiles, {
        type = "explosion", x = x, y = y,
        vx = 0, vy = 0,
        life = 0.4, maxLife = 0.4,
        size = 10, subType = "ring",
    })

    -- 火焰碎片（8-12个向外飞射的火星）
    local count = 8 + math.random(0, 4)
    for i = 1, count do
        local ang = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.5
        local spd = 60 + math.random() * 80
        table.insert(G.turretProjectiles, {
            type = "explosion", x = x, y = y,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd,
            life = 0.3 + math.random() * 0.3,
            maxLife = 0.6,
            size = 2 + math.random() * 3,
            subType = "debris",
        })
    end

    -- 烟雾（4-6个慢速扩散）
    for _ = 1, 4 + math.random(0, 2) do
        local ang = math.random() * math.pi * 2
        local spd = 15 + math.random() * 25
        table.insert(G.turretProjectiles, {
            type = "smoke", x = x, y = y,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd,
            life = 0.5 + math.random() * 0.3,
            maxLife = 0.8,
            size = 5 + math.random() * 5,
        })
    end
end

------------------------------------------------------------------------
-- 爆炸粒子渲染
------------------------------------------------------------------------
function T.DrawExplosion(vg, p)
    local ratio = p.life / p.maxLife
    local a = math.floor(ratio * 255)

    if p.subType == "core" then
        -- 中心火球：橙红色渐变，逐渐变大变淡
        local expand = 1.0 + (1.0 - ratio) * 1.5
        local sz = p.size * expand

        -- 外层光晕
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, sz * 1.3)
        nvgFillColor(vg, nvgRGBA(255, 100, 20, math.floor(a * 0.3)))
        nvgFill(vg)

        -- 中层火焰
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, sz)
        nvgFillColor(vg, nvgRGBA(255, 160, 40, math.floor(a * 0.7)))
        nvgFill(vg)

        -- 核心亮点
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, sz * 0.4)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, a))
        nvgFill(vg)

    elseif p.subType == "ring" then
        -- 冲击波环：快速扩大的圆环
        local expand = 1.0 + (1.0 - ratio) * 5.0
        local sz = p.size * expand
        local lineW = 3.0 * ratio

        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, sz)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 80, math.floor(a * 0.6)))
        nvgStrokeWidth(vg, lineW)
        nvgStroke(vg)

    elseif p.subType == "debris" then
        -- 飞散碎片：橙黄色小火星
        local sz = p.size * ratio
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, sz)
        local r = 255
        local g = math.floor(120 + 80 * ratio)
        local b = math.floor(30 * ratio)
        nvgFillColor(vg, nvgRGBA(r, g, b, a))
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 上车子弹绘制（小黄色圆点 + 拖尾）
------------------------------------------------------------------------
function T.DrawMountedBullet(vg, p, G)
    local alpha = math.min(1.0, p.life / 0.3)
    local a = math.floor(alpha * 255)
    local img = G and G.mountedBulletImg

    nvgSave(vg)
    nvgTranslate(vg, p.x, p.y)
    -- 图片朝上（-90°），旋转到飞行方向
    nvgRotate(vg, p.angle + math.pi * 0.5)

    if img and img ~= 0 then
        local iw, ih = nvgImageSize(vg, img)
        local scale = 40 / ih  -- 高度固定40px
        local dw, dh = iw * scale, ih * scale
        local paint = nvgImagePattern(vg, -dw / 2, -dh / 2, dw, dh, 0, img, alpha)
        nvgBeginPath(vg)
        nvgRect(vg, -dw / 2, -dh / 2, dw, dh)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- fallback 色块
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, -10)
        nvgLineTo(vg, -4, 6)
        nvgLineTo(vg, 4, 6)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(255, 160, 30, a))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

------------------------------------------------------------------------
-- 毒箭渲染（绿色箭矢）
------------------------------------------------------------------------
function T.DrawPoisonArrow(vg, p, G)
    local alpha = math.min(1.0, p.life / 0.2)
    local a = math.floor(alpha * 255)
    nvgSave(vg)
    nvgTranslate(vg, p.x, p.y)
    nvgRotate(vg, p.angle)
    -- 箭身（绿色）
    nvgBeginPath(vg)
    nvgMoveTo(vg, 10, 0)
    nvgLineTo(vg, -6, -3)
    nvgLineTo(vg, -6, 3)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(40, 200, 60, a))
    nvgFill(vg)
    -- 毒液光效
    nvgBeginPath(vg)
    nvgCircle(vg, 10, 0, 4)
    nvgFillColor(vg, nvgRGBA(120, 255, 80, math.floor(a * 0.6)))
    nvgFill(vg)
    nvgRestore(vg)
end

------------------------------------------------------------------------
-- 闪电球渲染
------------------------------------------------------------------------
function T.DrawBallLightning(vg, p)
    local alpha = math.min(1.0, p.life / 0.4)
    local a = math.floor(alpha * 255)
    local t = p.life * 5
    local pulse = 0.7 + 0.3 * math.sin(t)
    local sz = 10 * pulse

    -- 外层光晕
    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, sz * 2.0)
    nvgFillColor(vg, nvgRGBA(60, 120, 255, math.floor(a * 0.15)))
    nvgFill(vg)

    -- 中层
    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, sz * 1.3)
    nvgFillColor(vg, nvgRGBA(100, 180, 255, math.floor(a * 0.4)))
    nvgFill(vg)

    -- 核心
    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, sz)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, a))
    nvgFill(vg)

    -- 内核白点
    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, sz * 0.35)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, a))
    nvgFill(vg)

    -- 放电射线（4条随机）
    for i = 1, 4 do
        local ra = (i / 4) * math.pi * 2 + t * 0.7
        local rLen = sz * 1.5 + math.sin(t * 1.3 + i) * sz * 0.5
        nvgBeginPath(vg)
        nvgMoveTo(vg, p.x, p.y)
        nvgLineTo(vg, p.x + math.cos(ra) * rLen, p.y + math.sin(ra) * rLen)
        nvgStrokeColor(vg, nvgRGBA(150, 200, 255, math.floor(a * 0.7)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
end

------------------------------------------------------------------------
-- 激光光束渲染
------------------------------------------------------------------------
function T.DrawLaserBeam(vg, p, G)
    -- 取当前帧图片句柄
    local imgHandle = nil
    if G then
        local phase = p.laserPhase or "loop"
        local idx   = p.laserFrameIdx or 1
        if phase == "open" and G.laserOpenFrames then
            imgHandle = G.laserOpenFrames[idx]
        elseif phase == "close" and G.laserCloseFrames then
            imgHandle = G.laserCloseFrames[idx]
        elseif G.laserLoopFrames then
            imgHandle = G.laserLoopFrames[idx]
        end
    end

    local dx  = p.ex - p.sx
    local dy  = p.ey - p.sy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local angle   = math.atan(dy, dx)
    local mx      = (p.sx + p.ex) * 0.5
    local my      = (p.sy + p.ey) * 0.5
    local beamW   = p.wide and 90 or 64
    -- close 阶段让序列帧自己表达消失，不叠加透明度淡出
    local alpha   = 1.0

    if imgHandle and imgHandle ~= 0 then
        -- 用序列帧图片渲染光束
        -- 旋转坐标系：local +Y 沿光束方向，图片竖向自然对齐
        nvgSave(vg)
        nvgTranslate(vg, mx, my)
        nvgRotate(vg, angle + math.pi * 0.5)
        local hw = beamW * 0.5
        local hl = len   * 0.5
        local paint = nvgImagePattern(vg, -hw, -hl, beamW, len, 0, imgHandle, alpha)
        nvgBeginPath(vg)
        nvgRect(vg, -hw, -hl, beamW, len)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        nvgRestore(vg)
    else
        -- fallback：纯线段（无图片时）
        local a = math.floor(alpha * 255)
        nvgBeginPath(vg)
        nvgMoveTo(vg, p.sx, p.sy)
        nvgLineTo(vg, p.ex, p.ey)
        nvgStrokeColor(vg, nvgRGBA(255, 80, 40, math.floor(a * 0.25)))
        nvgStrokeWidth(vg, 18)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, p.sx, p.sy)
        nvgLineTo(vg, p.ex, p.ey)
        nvgStrokeColor(vg, nvgRGBA(255, 220, 180, a))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)
    end

end

------------------------------------------------------------------------
-- 绘制地面燃烧区域
------------------------------------------------------------------------
function T.DrawBurnZones(vg, G)
    if not G.burnZones then return end
    local t = G.gameTime or 0
    local frames = G.burnFlameFrames
    local frameCount = frames and #frames or 0

    for _, bz in ipairs(G.burnZones) do
        local ratio = math.min(1.0, bz.life / 5.0)   -- 1→0 随生命衰减
        local r     = bz.radius
        local cx, cy = bz.x, bz.y

        -- ---- 1. 地面焦黑（持久底色）----
        local scorch = math.floor(ratio * 100)
        local scorchPaint = nvgRadialGradient(vg, cx, cy, r * 0.15, r,
            nvgRGBA(30, 10, 0, scorch), nvgRGBA(10, 5, 0, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, cx, cy, r, r * 0.55)
        nvgFillPaint(vg, scorchPaint)
        nvgFill(vg)

        -- ---- 2. 帧动画火焰精灵填充区域 ----
        if frameCount > 0 then
            -- 在燃烧区域内散布多个火焰精灵，充分覆盖整个区域
            local flameCount = 16
            for fi = 0, flameCount - 1 do
                -- 伪随机分布，覆盖整个燃烧半径
                local seedA = math.sin(fi * 127.1 + bz.x * 0.013) * 0.5 + 0.5
                local seedR = math.sin(fi * 311.7 + bz.y * 0.017) * 0.5 + 0.5
                local baseAng = seedA * math.pi * 2
                -- 使用更大范围分布，覆盖整个圆
                local baseRad = math.sqrt(seedR) * r * 0.95
                local fx = cx + math.cos(baseAng) * baseRad
                local fy = cy + math.sin(baseAng) * baseRad * 0.55  -- 椭圆透视

                -- 每个火焰独立帧偏移，播放速率约10fps
                local frameOffset = fi * 2
                local frameIdx = math.floor(t * 10 + frameOffset) % frameCount + 1
                local img = frames[frameIdx]
                if img and img ~= 0 then
                    -- 火焰尺寸：中心稍大，边缘稍小，整体更小以填充更多
                    local distRatio = baseRad / (r * 0.95 + 0.01)
                    local sz = r * (0.55 - 0.15 * distRatio) * (0.85 + 0.15 * math.sin(t * 4.0 + fi * 2.1))
                    local halfSz = sz * 0.5

                    nvgSave(vg)
                    nvgTranslate(vg, fx, fy)
                    -- 旋转180°（图片倒转）
                    nvgRotate(vg, math.pi)
                    -- 绘制火焰精灵
                    local imgPaint = nvgImagePattern(vg, -halfSz, -halfSz, sz, sz, 0, img, ratio)
                    nvgBeginPath(vg)
                    nvgRect(vg, -halfSz, -halfSz, sz, sz)
                    nvgFillPaint(vg, imgPaint)
                    nvgFill(vg)
                    nvgRestore(vg)
                end
            end
        end

        -- ---- 3. 中心高光（增强火焰感） ----
        local corePulse = 0.5 + 0.5 * math.sin(t * 6.0)
        local coreA = math.floor(ratio * corePulse * 80)
        local coreR = r * 0.35
        local corePaint = nvgRadialGradient(vg, cx, cy, 0, coreR,
            nvgRGBA(255, 200, 50, coreA), nvgRGBA(255, 80, 0, 0))
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, coreR)
        nvgFillPaint(vg, corePaint)
        nvgFill(vg)
    end
end

return T

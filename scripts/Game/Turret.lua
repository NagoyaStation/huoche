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
    arrow    = { name = "弓箭炮塔",   imgKey = "arrow",    range = 220, damage = 8,  cooldown = 1.0,  color = {180, 140, 80},  projType = "arrow",    activeDuration = 6,  restDuration = 3 },
    sniper   = { name = "狙击炮塔",   imgKey = "sniper",   range = 350, damage = 35, cooldown = 5.0,  color = {255, 60, 40},   projType = "sniper",   activeDuration = 10, restDuration = 5 },
    flame    = { name = "喷火炮塔",   imgKey = "flame",    range = 200, damage = 5,  cooldown = 0.12, color = {255, 120, 30},  projType = "flame",    activeDuration = 4,  restDuration = 3 },
    electric = { name = "电能炮塔",   imgKey = "electric", range = 200, damage = 12, cooldown = 0.7,  color = {60, 160, 255},  projType = "electric", activeDuration = 5,  restDuration = 3 },
    rocket   = { name = "火箭炮塔",   imgKey = "rocket",   range = 280, damage = 40, cooldown = 8.0,  color = {80, 120, 60},   projType = "rocket",   activeDuration = 8,  restDuration = 5 },
    minigun  = { name = "机关枪炮塔", imgKey = "minigun",  range = 250, damage = 3,  cooldown = 0.1,  color = {255, 230, 80},  projType = "minigun",  activeDuration = 5,  restDuration = 4 },
}

T.TYPE_LIST = { "arrow", "sniper", "flame", "electric", "rocket", "minigun" }

--- 获取炮台加成后伤害
local function getTurretDamage(typeKey, baseDmg, G)
    local bonus = 0
    if G.turretDmgBonus then
        bonus = G.turretDmgBonus[typeKey] or 0
    end
    return math.floor(baseDmg * (1 + bonus / 100))
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
local function spawnProjectile(G, projType, sx, sy, tx, ty, angle, targetEnemy, damage)
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
        table.insert(G.turretProjectiles, {
            type = "minigun",
            x = sx, y = sy,
            vx = math.cos(a) * spd,
            vy = math.sin(a) * spd,
            speed = spd,
            life = 0.8, maxLife = 0.8,
            target = targetEnemy,
            damage = damage or 3,
            tx = tx, ty = ty,
        })
    elseif projType == "rocket" then
        -- 火箭弹（追踪目标，到达后AOE爆炸）
        local spd = 150
        table.insert(G.turretProjectiles, {
            type = "rocket",
            x = sx, y = sy,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            speed = spd,
            angle = angle,
            life = 3.0, maxLife = 3.0,
            trailTimer = 0,
            target = targetEnemy,
            tx = tx, ty = ty,
            exploded = false,
        })
    elseif projType == "arrow" then
        -- 弓箭（追踪目标，到达后造成伤害）
        local spd = 280
        table.insert(G.turretProjectiles, {
            type = "arrow",
            x = sx, y = sy,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            speed = spd,
            angle = angle,
            life = 1.5, maxLife = 1.5,
            target = targetEnemy,
            damage = damage or 8,
            tx = tx, ty = ty,
        })
    end
end

------------------------------------------------------------------------
-- 更新炮塔（索敌 + 开火）
------------------------------------------------------------------------
function T.Update(G, dt)
    if not G.turrets then return end

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
        local nearDistSq = def.range * def.range
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
            turret.angle = math.atan(dy, dx)
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
                turret.coolTimer = def.cooldown

                -- 喷火炮台：持续喷射，对火焰锥形范围内所有敌人造成伤害
                if turret.typeKey == "flame" then
                    local flameLen = def.range  -- 火焰长度与炮塔索敌范围一致
                    local halfSpread = 0.45   -- 火焰半扩散角（弧度，约50度锥形）
                    local cosA = math.cos(turret.angle)
                    local sinA = math.sin(turret.angle)
                    local flameLenSq = flameLen * flameLen
                    for _, z in ipairs(G.zombies) do
                        if not z.dead then
                            local fdx = z.x - tx
                            local fdy = z.y - ty
                            local distSq = fdx * fdx + fdy * fdy
                            if distSq < flameLenSq and distSq > 0 then
                                -- 检查是否在火焰锥形方向内
                                local dist = math.sqrt(distSq)
                                local dot = (fdx * cosA + fdy * sinA) / dist
                                if dot > math.cos(halfSpread) then
                                    local flameDmg = getTurretDamage(turret.typeKey, def.damage, G)
                                    z.hp = z.hp - flameDmg
                                    z.hitAnim = 0.3
                                    E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 3)
                                    if z.hp <= 0 then
                                        z.dead = true
                                        G.gold = (G.gold or 0) + (z.reward or 5)
                                        E.SpawnZombieDeath(G, z.x, z.y)
                                    end
                                end
                            end
                        end
                    end
                else
                    -- 弹道类武器不即时造成伤害，弹道到达后才扣血
                    local isProjectile = (turret.typeKey == "arrow" or turret.typeKey == "minigun" or turret.typeKey == "rocket")
                    if not isProjectile then
                        local tDmg = getTurretDamage(turret.typeKey, def.damage, G)
                        nearEnemy.hp = nearEnemy.hp - tDmg
                        nearEnemy.hitAnim = 1.0
                        E.SpawnParticles(G, nearEnemy.x, nearEnemy.y, BLOOD_COLOR, 4)
                        if nearEnemy.hp <= 0 then
                            nearEnemy.dead = true
                            G.gold = (G.gold or 0) + (nearEnemy.reward or 5)
                            E.SpawnZombieDeath(G, nearEnemy.x, nearEnemy.y)
                        end
                    end

                    turret.recoil = 1.0
                    turret.fireFlash = 0.12

                    -- 炮口发射投射物
                    local muzzleDist = TURRET_H * 0.45
                    local mx = tx + math.cos(turret.angle) * muzzleDist
                    local my = ty + math.sin(turret.angle) * muzzleDist
                    local projDmg = getTurretDamage(turret.typeKey, def.damage, G)
                    spawnProjectile(G, def.projType, mx, my, nearEnemy.x, nearEnemy.y, turret.angle, nearEnemy, projDmg)
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
    local alive = {}
    for _, p in ipairs(G.turretProjectiles) do
        p.life = p.life - dt
        if p.life > 0 then

            ----------------------------------------------------------------
            -- 弹道类(arrow/minigun/rocket)：追踪目标 + 命中判定
            ----------------------------------------------------------------
            local isTracking = (p.type == "arrow" or p.type == "minigun" or p.type == "rocket" or p.type == "mounted_bullet")

            if isTracking and p.target then
                -- 目标已死 → 子弹失去追踪，继续直线飞行直到 life 耗尽
                if p.target.dead then
                    p.target = nil
                    p.tx = nil
                    p.ty = nil
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

            ----------------------------------------------------------------
            -- 弓箭：到达目标 → 单体伤害 + 命中火花
            ----------------------------------------------------------------
            if p.type == "arrow" and p.tx and p.ty then
                local dx = p.x - p.tx
                local dy = p.y - p.ty
                local distSq = dx * dx + dy * dy
                if distSq < 144 then
                    p.life = 0
                    -- 造成伤害
                    if p.target and not p.target.dead then
                        p.target.hp = p.target.hp - (p.damage or 8)
                        p.target.hitAnim = 1.0
                        E.SpawnParticles(G, p.target.x, p.target.y, BLOOD_COLOR, 5)
                        if p.target.hp <= 0 then
                            p.target.dead = true
                            G.gold = (G.gold or 0) + (p.target.reward or 5)
                            E.SpawnZombieDeath(G, p.target.x, p.target.y)
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
            -- 机关枪：到达目标 → 单体伤害 + 小火花
            ----------------------------------------------------------------
            if p.type == "minigun" and p.tx and p.ty then
                local dx = p.x - p.tx
                local dy = p.y - p.ty
                local distSq = dx * dx + dy * dy
                if distSq < 144 then
                    p.life = 0
                    -- 造成伤害
                    if p.target and not p.target.dead then
                        p.target.hp = p.target.hp - (p.damage or 3)
                        p.target.hitAnim = 1.0
                        E.SpawnParticles(G, p.target.x, p.target.y, BLOOD_COLOR, 2)
                        if p.target.hp <= 0 then
                            p.target.dead = true
                            G.gold = (G.gold or 0) + (p.target.reward or 5)
                            E.SpawnZombieDeath(G, p.target.x, p.target.y)
                        end
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
                        T.RocketAOE(G, p.x, p.y)
                        T.SpawnExplosion(G, p.x, p.y)
                    end
                end
            end

            ----------------------------------------------------------------
            -- 上车子弹：直线飞行 → 碰到丧尸造成伤害
            ----------------------------------------------------------------
            if p.type == "mounted_bullet" then
                local hitRadius = 12
                for _, z in ipairs(G.zombies or {}) do
                    if not z.dead then
                        local dx2 = p.x - z.x
                        local dy2 = p.y - z.y
                        if dx2 * dx2 + dy2 * dy2 < hitRadius * hitRadius then
                            p.life = 0
                            z.hp = z.hp - (p.damage or 5)
                            z.hitAnim = 0.2
                            E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 3)
                            if z.hp <= 0 then
                                z.dead = true
                                G.killCount = (G.killCount or 0) + 1
                                G.gold = (G.gold or 0) + (z.reward or 5)
                                E.SpawnFloatText(G, z.x, z.y - 10, "击杀!", "gold")
                                E.SpawnZombieDeath(G, z.x, z.y)
                            else
                                E.SpawnFloatText(G, z.x, z.y - 15, tostring(p.damage or 5), "damage")
                            end
                            break
                        end
                    end
                end
            end

            table.insert(alive, p)
        end
    end
    G.turretProjectiles = alive
end

------------------------------------------------------------------------
-- 绘制（炮塔 + 投射物）
------------------------------------------------------------------------
function T.Draw(vg, G)
    if not G.turrets or not G.turretImgs then return end

    -- 1) 投射物（先画，在炮塔图层下面）
    T.DrawProjectiles(vg, G)

    -- 2) 炮塔本体
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
            T.DrawMountedBullet(vg, p)
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
    for _, z in ipairs(G.zombies) do
        if not z.dead then
            local dx = z.x - ex
            local dy = z.y - ey
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < ROCKET_AOE_RADIUS then
                -- 距离衰减：中心全额伤害，边缘50%
                local falloff = 1.0 - 0.5 * (dist / ROCKET_AOE_RADIUS)
                local finalDmg = math.floor(dmg * falloff)
                z.hp = z.hp - finalDmg
                z.hitAnim = 1.0
                E.SpawnParticles(G, z.x, z.y, BLOOD_COLOR, 4)
                if z.hp <= 0 then
                    z.dead = true
                    G.gold = (G.gold or 0) + (z.reward or 5)
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
function T.DrawMountedBullet(vg, p)
    local alpha = math.min(1.0, p.life / 0.3)
    local a = math.floor(alpha * 255)

    -- 拖尾
    local tailLen = 8
    local tx = p.x - math.cos(p.angle) * tailLen
    local ty = p.y - math.sin(p.angle) * tailLen
    nvgBeginPath(vg)
    nvgMoveTo(vg, tx, ty)
    nvgLineTo(vg, p.x, p.y)
    nvgStrokeWidth(vg, 2.5)
    nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(a * 0.6)))
    nvgStroke(vg)

    -- 弹头亮点
    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, 3)
    nvgFillColor(vg, nvgRGBA(255, 240, 150, a))
    nvgFill(vg)

    -- 发光
    nvgBeginPath(vg)
    nvgCircle(vg, p.x, p.y, 5)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, math.floor(a * 0.3)))
    nvgFill(vg)
end

return T

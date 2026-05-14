-- Game/Entities.lua - 实体逻辑：玩家、资源节点、丧尸(攻击列车)、浮岛物语风格自动攻击
local C = require "Game.Config"
local E = {}

--- 计算最终伤害（含攻击百分比加成和暴击）
--- @param baseDmg number 基础伤害
--- @param G table 全局状态
--- @return number dmg 最终伤害
--- @return boolean isCrit 是否暴击
function E.CalcDamage(baseDmg, G)
    local dmg = baseDmg * (G.atkPctMul or 1.0)
    local isCrit = false
    local critRate = G.critRate or 0
    if critRate > 0 and math.random(1, 100) <= critRate then
        isCrit = true
        dmg = dmg * (G.critDmg or 150) / 100
    end
    return math.floor(dmg), isCrit
end

--- 计算列车受到的伤害（含防御减伤）
--- @param rawDmg number 原始伤害
--- @param G table 全局状态
--- @return number 实际伤害
function E.CalcTrainDmgTaken(rawDmg, G)
    local def = G.defFlat or 0
    local reduced = math.max(1, rawDmg - def)
    return reduced
end

-- O(1) 删除：将末尾元素换到当前位置，再移除末尾
local function swapRemove(arr, i)
    local n = #arr
    if i < n then
        arr[i] = arr[n]
    end
    arr[n] = nil
end

------------------------------------------------------------------------
-- 路径噪声 (有机边缘)
------------------------------------------------------------------------
function E.PathNoise(y)
    return math.sin(y * 0.008) * 22
         + math.sin(y * 0.023 + 1.7) * 10
         + math.sin(y * 0.042 + 3.2) * 5
end

--- 获取路径中心和左右边界 (屏幕坐标)
function E.GetPathBounds(screenW, worldY)
    local centerX = screenW / 2 + E.PathNoise(worldY) * 0.5
    local halfW = screenW * C.PATH_WIDTH_RATIO / 2
    return centerX - halfW, centerX + halfW, centerX
end

------------------------------------------------------------------------
-- 玩家 (人类幸存者)
------------------------------------------------------------------------
function E.CreatePlayer(G)
    G.player = {
        x = G.screenW / 2,
        y = G.screenH * 0.55,
        vx = 0, vy = 0,
        facing = 1,
        carrying = 0,
        inv = { wood = 0, stone = 0, ore = 0, bush = 0, pebble = 0 },
        -- 动画
        walkAnim = 0,
        bobAnim = 0,
        collectAnim = 0,
        submitAnim = 0,
        -- 自动攻击
        atkTimer = 0,           -- 攻击冷却计时器
        atkTarget = nil,        -- 当前攻击目标 {type="res"/"zombie", ref=...}
        atkSwingAnim = 0,       -- 挥砍动画(0~1)
    }
end

function E.UpdatePlayer(G, dt, moveX, moveY)
    local p = G.player
    local speed = C.PLAYER_SPEED * G.speedMul

    -- 移动
    p.vx = moveX * speed
    p.vy = moveY * speed

    -- 随世界滚动向上移动（与资源、丧尸一致）
    local scrollSpeed = (C.BASE_SCROLL_SPEED + G.level * C.SCROLL_SPEED_PER_LEVEL) * G.scrollSpeedMul
    local scrollDelta = scrollSpeed * dt
    p.y = p.y - scrollDelta

    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt

    -- 朝向
    if math.abs(moveX) > 0.2 then
        p.facing = moveX > 0 and 1 or -1
    end

    -- 屏幕边界约束
    local margin = 16
    p.x = math.max(margin, math.min(G.screenW - margin, p.x))
    local topLimit = G.hudH + 10  -- 空气墙在顶部HUD下方
    local bottomLimit = G.screenH - margin
    p.y = math.max(topLimit, math.min(bottomLimit, p.y))

    -- 列车+车厢碰撞体积（取车厢和火车中更宽的宽度）
    -- 火车在屏幕顶部，碰撞区从屏幕上限一直延伸到车底，玩家只能被推向两侧或下方
    local collisionHalfW = math.max(G.cartW / 2, (G.carriageW or G.cartW) / 2) - 11
    local trainLeft = G.cartCenterX - collisionHalfW
    local trainRight = G.cartCenterX + collisionHalfW
    local trainTop = topLimit - 1  -- 略高于屏幕上限，确保覆盖整个顶部
    local trainBottom = G.cartBottomY + 8  -- 包含提交区域下沿
    if p.x > trainLeft and p.x < trainRight and p.y > trainTop and p.y < trainBottom then
        -- 火车贴屏幕顶部，不向上推（上方无空间），只推向左右或下方
        local pushLeft = p.x - trainLeft
        local pushRight = trainRight - p.x
        local pushBottom = trainBottom - p.y
        local minPush = math.min(pushLeft, pushRight, pushBottom)
        if minPush == pushLeft then
            p.x = trainLeft
        elseif minPush == pushRight then
            p.x = trainRight
        else
            p.y = trainBottom
        end
    end

    -- 行走动画
    if math.abs(moveX) > 0.1 or math.abs(moveY) > 0.1 then
        p.walkAnim = p.walkAnim + dt * 10
        p.isWalking = true
    else
        -- 停止移动时立即停止行走帧，walkAnim 仅用于补间弹跳衰减
        p.isWalking = false
        p.walkAnim = p.walkAnim * (1 - dt * 15)
        if p.walkAnim < 0.5 then p.walkAnim = 0 end
    end
    p.bobAnim = p.bobAnim + dt * 3
    p.collectAnim = math.max(0, p.collectAnim - dt)
    p.submitAnim = math.max(0, p.submitAnim - dt)
    p.atkSwingAnim = math.max(0, p.atkSwingAnim - dt * 4)

    -- 攻击冷却
    local atkInterval = C.AUTO_ATTACK_INTERVAL / (G.atkSpdMul or 1.0)
    p.atkTimer = math.max(0, p.atkTimer - dt)
end

------------------------------------------------------------------------
-- 自动攻击/采集 (浮岛物语风格: 靠近自动攻击)
------------------------------------------------------------------------
function E.AutoAttack(G, dt)
    local p = G.player
    if p.atkTimer > 0 then return end  -- 冷却中

    local range = C.AUTO_ATTACK_RANGE * (G.rangeMul or 1.0)
    local baseAtk = C.PLAYER_ATK + (G.meleeAtkBonus or 0)   -- 近战攻击力（含采集）
    local atkPower, _ = E.CalcDamage(baseAtk, G)  -- 资源节点不显示暴击

    -- 寻找最近的可攻击目标 (资源节点 或 丧尸)
    local rangeSq = range * range
    local bestDistSq = rangeSq + 1
    local bestTarget = nil
    local bestType = nil

    -- 检查资源节点
    for _, r in ipairs(G.resources) do
        if not r.dead and r.hp > 0 then
            local dx = r.x - p.x
            local dy = r.y - p.y
            local distSq = dx * dx + dy * dy
            if distSq < rangeSq and distSq < bestDistSq then
                bestDistSq = distSq
                bestTarget = r
                bestType = "res"
            end
        end
    end

    -- 检查丧尸 (也能自动攻击)
    for _, z in ipairs(G.zombies or {}) do
        if not z.dead then
            local dx = z.x - p.x
            local dy = z.y - p.y
            local distSq = dx * dx + dy * dy
            if distSq < rangeSq and distSq < bestDistSq then
                bestDistSq = distSq
                bestTarget = z
                bestType = "zombie"
            end
        end
    end

    if not bestTarget then
        p.atkTarget = nil
        return
    end

    -- 执行攻击
    p.atkTarget = { type = bestType, x = bestTarget.x, y = bestTarget.y }
    local atkInterval = C.AUTO_ATTACK_INTERVAL / (G.atkSpdMul or 1.0)
    p.atkTimer = atkInterval
    p.atkSwingAnim = 1.0

    -- 面向目标
    if bestTarget.x > p.x then p.facing = 1 else p.facing = -1 end

    if bestType == "res" then
        bestTarget.hp = bestTarget.hp - atkPower
        bestTarget.hitAnim = 0.2   -- 受击闪白

        -- 击碎粒子
        local rc = C.CLR.wood_color
        if bestTarget.rtype == "stone" then rc = C.CLR.stone_color
        elseif bestTarget.rtype == "ore" then rc = C.CLR.ore_color
        elseif bestTarget.rtype == "bush" then rc = C.CLR.bush_color
        elseif bestTarget.rtype == "pebble" then rc = C.CLR.pebble_color end
        E.SpawnParticles(G, bestTarget.x, bestTarget.y, rc, 3)

        if bestTarget.hp <= 0 then
            -- 节点被破坏，掉落资源
            bestTarget.dead = true
            local resInfo = C.RES[bestTarget.rtype]
            local amount = resInfo.drop or 1
            -- 双倍检测
            if (G.doubleMul or 0) > 0 and math.random() < G.doubleMul then
                amount = amount * 2
            end

            -- 直接获得资源(自动拾取)
            if p.carrying < G.maxCarry then
                local actual = math.min(amount, G.maxCarry - p.carrying)
                p.inv[bestTarget.rtype] = p.inv[bestTarget.rtype] + actual
                p.carrying = p.carrying + actual
                G.totalRes[bestTarget.rtype] = G.totalRes[bestTarget.rtype] + actual
                E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 10, "+" .. actual, bestTarget.rtype)
            else
                E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 10, "背包满", "damage")
            end

            p.collectAnim = 0.3
            E.SpawnParticles(G, bestTarget.x, bestTarget.y, rc, 6)
        else
            E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 15, "-" .. atkPower, "damage")
        end

    elseif bestType == "zombie" then
        local baseZDmg = C.PLAYER_ATK_ZOMBIE + (G.meleeAtkBonus or 0)  -- 近战攻击力
        local dmg, isCrit = E.CalcDamage(baseZDmg, G)
        bestTarget.hp = bestTarget.hp - dmg
        bestTarget.hitAnim = 0.2

        E.SpawnParticles(G, bestTarget.x, bestTarget.y, {220, 70, 60}, 3)

        if bestTarget.hp <= 0 then
            bestTarget.dead = true
            G.killCount = (G.killCount or 0) + 1
            E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 10, "击杀!", "gold")
            E.SpawnParticles(G, bestTarget.x, bestTarget.y, {220, 70, 60}, 6)
            -- 击杀奖励金币
            local goldReward = 2 + G.level
            G.gold = G.gold + goldReward
            E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 25, "+" .. goldReward, "gold")
        else
            if isCrit then
                E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 15, "暴击-" .. dmg, "crit")
            else
                E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 15, "-" .. dmg, "damage")
            end
        end
    end
end

------------------------------------------------------------------------
-- 提交检测 (走到列车下方提交区)
------------------------------------------------------------------------
function E.TrySubmit(G)
    local p = G.player
    if p.carrying <= 0 then return end

    local sx = G.submitBox.x
    local sy = G.submitBox.y
    local sw = C.SUBMIT_BOX_W
    local sh = C.SUBMIT_BOX_H

    local px = p.x
    local py = p.y
    if px > sx - sw / 2 - 12 and px < sx + sw / 2 + 12 and
       py > sy - sh / 2 - 12 and py < sy + sh / 2 + 12 then

        local submitted = p.carrying
        local goldEarned = math.floor(submitted * C.GOLD_PER_SUBMIT * G.goldMul)
        G.gold = G.gold + goldEarned

        -- 清空背包
        for rtype, _ in pairs(p.inv) do
            p.inv[rtype] = 0
        end
        p.carrying = 0

        G.levelProgress = G.levelProgress + submitted

        p.submitAnim = 0.4
        E.SpawnFloatText(G, sx, sy - 20, "+" .. goldEarned, "gold")
        E.SpawnParticles(G, sx, sy, {255, 220, 80}, 8)

        if G.levelProgress >= G.levelTarget then
            G.pendingLevelUp = true
        end
    end
end

------------------------------------------------------------------------
-- 资源节点生成 (有HP的可采集节点)
------------------------------------------------------------------------
function E.SpawnResources(G)
    local W = G.screenW

    local count = math.random(C.RES_PER_SPAWN_MIN, C.RES_PER_SPAWN_MAX)
    count = math.ceil(count * G.spawnMul)

    for ci = 1, count do
        local roll = math.random()
        local oreFreq = C.RES.ore.freq * G.oreLuckMul
        local totalFreq = C.RES.wood.freq + C.RES.stone.freq + oreFreq + C.RES.bush.freq + C.RES.pebble.freq
        local woodThresh = C.RES.wood.freq / totalFreq
        local stoneThresh = (C.RES.wood.freq + C.RES.stone.freq) / totalFreq
        local oreThresh = (C.RES.wood.freq + C.RES.stone.freq + oreFreq) / totalFreq
        local bushThresh = (C.RES.wood.freq + C.RES.stone.freq + oreFreq + C.RES.bush.freq) / totalFreq

        local rtype
        if roll < woodThresh then
            rtype = "wood"
        elseif roll < stoneThresh then
            rtype = "stone"
        elseif roll < oreThresh then
            rtype = "ore"
        elseif roll < bushThresh then
            rtype = "bush"
        else
            rtype = "pebble"
        end

        local pathL, pathR = E.GetPathBounds(W, G.scrollY)
        -- 交替左右两侧，保持均匀
        local side = (ci % 2 == 1) and 1 or 2
        local rx
        local margin = 20  -- 距屏幕边缘
        local resHalf = C.RES_SIZE / 2
        if side == 1 then
            local minX = margin + resHalf
            local maxX = math.max(minX + 1, math.floor(pathL - resHalf - 5))
            rx = math.random(math.floor(minX), math.floor(maxX))
        else
            local minX = math.min(math.floor(pathR + resHalf + 5), W - margin - resHalf)
            local maxX = W - margin - resHalf
            rx = math.random(math.floor(minX), math.floor(math.max(minX + 1, maxX)))
        end

        local ry = G.screenH + 10 + math.random(0, 40)
        local resInfo = C.RES[rtype]

        table.insert(G.resources, {
            x = rx, y = ry,
            rtype = rtype,
            hp = resInfo.hp,
            maxHp = resInfo.hp,
            dead = false,
            hitAnim = 0,
            bobPhase = math.random() * math.pi * 2,
            scale = 0.85 + math.random() * 0.3,  -- 随机大小变化
        })
    end
end

------------------------------------------------------------------------
-- 资源节点更新 (受击动画、清理)
------------------------------------------------------------------------
function E.UpdateResources(G, dt)
    for i = #G.resources, 1, -1 do
        local r = G.resources[i]
        r.hitAnim = math.max(0, (r.hitAnim or 0) - dt * 3)
        if r.dead then
            swapRemove(G.resources, i)
        end
    end
end

------------------------------------------------------------------------
-- 装饰物生成 (树、灌木)
------------------------------------------------------------------------
function E.SpawnDecorations(G)
    -- 装饰物已移除
end

------------------------------------------------------------------------
-- 滚动更新
------------------------------------------------------------------------
function E.UpdateScroll(G, dt)
    local speed = (C.BASE_SCROLL_SPEED + G.level * C.SCROLL_SPEED_PER_LEVEL) * G.scrollSpeedMul
    local scrollDelta = speed * dt
    G.scrollY = G.scrollY + scrollDelta
    G.distance = G.distance + scrollDelta
    G.lastScrollDelta = scrollDelta

    -- 资源向上滚动
    for i = #G.resources, 1, -1 do
        local r = G.resources[i]
        r.y = r.y - scrollDelta
        if r.y < G.hudH - 30 then
            swapRemove(G.resources, i)
        end
    end

    -- 装饰物已移除

    -- 浮动文字向上滚动
    for i = #G.floatTexts, 1, -1 do
        local ft = G.floatTexts[i]
        ft.y = ft.y - scrollDelta
    end
end

------------------------------------------------------------------------
-- 浮动文字
------------------------------------------------------------------------
function E.SpawnFloatText(G, x, y, text, rtype)
    table.insert(G.floatTexts, {
        x = x, y = y,
        text = text,
        rtype = rtype,
        life = 1.0,
        maxLife = 1.0,
    })
end

function E.UpdateFloatTexts(G, dt)
    for i = #G.floatTexts, 1, -1 do
        local ft = G.floatTexts[i]
        ft.y = ft.y - 40 * dt
        ft.life = ft.life - dt
        if ft.life <= 0 then
            swapRemove(G.floatTexts, i)
        end
    end
end

------------------------------------------------------------------------
-- 粒子
------------------------------------------------------------------------
function E.SpawnParticles(G, x, y, color, count)
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local spd = 50 + math.random() * 80
        table.insert(G.particles, {
            x = x, y = y,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd - 40,
            life = 0.5 + math.random() * 0.4,
            maxLife = 0.9,
            r = color[1], g = color[2], b = color[3],
            size = 2 + math.random() * 3,
        })
    end
end

function E.UpdateParticles(G, dt)
    for i = #G.particles, 1, -1 do
        local p = G.particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 120 * dt
        p.life = p.life - dt
        if p.life <= 0 then
            swapRemove(G.particles, i)
        end
    end
end

------------------------------------------------------------------------
-- 丧尸生成
------------------------------------------------------------------------
------------------------------------------------------------------------
-- 波次开始时批量涌现一大群僵尸
------------------------------------------------------------------------
function E.SpawnWaveHorde(G, count)
    local W = G.screenW
    local H = G.screenH
    for i = 1, count do
        -- 散布在屏幕上方外侧，分成多排涌入
        local row = math.ceil(i / 6)  -- 每排约6个
        local zx = math.random(30, math.floor(W - 30))
        local zy = H + 20 + (row - 1) * 25 + math.random(0, 15)

        local zType
        if G.level >= C.CRAWLER_SPAWN_LEVEL and math.random() < C.CRAWLER_CHANCE then
            zType = 3
        else
            zType = math.random(1, 2)
        end

        local zSpeed
        if zType == 3 then
            zSpeed = C.CRAWLER_SPEED + G.level * C.ZOMBIE_SPEED_PER_LEVEL
        else
            zSpeed = C.ZOMBIE_SPEED + G.level * C.ZOMBIE_SPEED_PER_LEVEL
        end

        local baseHp
        if zType == 1 then
            baseHp = 80
        elseif zType == 2 then
            baseHp = 100
        else
            baseHp = C.CRAWLER_HP_BASE
        end
        local hp = baseHp + math.floor(G.level / 3) * 5

        table.insert(G.zombies, {
            x = zx, y = zy,
            facing = 1,
            phase = math.random() * math.pi * 2,
            speed = zSpeed,
            dead = false,
            hitAnim = 0,
            walkAnim = 0,
            atkTimer = 0,
            atTrain = false,
            zombieType = zType,
            hp = hp,
            maxHp = hp,
        })
    end
end

function E.SpawnZombie(G)
    local zombies = G.zombies
    local maxZ = math.min(C.ZOMBIE_MAX_BASE + G.level * C.ZOMBIE_MAX_PER_LEVEL, C.ZOMBIE_MAX_CAP)
    if #zombies >= maxZ then return end

    local W = G.screenW
    local side = math.random(1, 2)
    local zx
    if side == 1 then
        zx = math.random(30, math.floor(math.max(31, W / 2 - 20)))
    else
        zx = math.random(math.floor(math.min(W / 2 + 20, W - 31)), math.floor(W - 30))
    end
    local zy = math.floor(G.screenH) + 20 + math.random(0, 30)

    -- 决定僵尸类型: 3级后有概率生成爬行僵尸(type 3)
    local zType
    if G.level >= C.CRAWLER_SPAWN_LEVEL and math.random() < C.CRAWLER_CHANCE then
        zType = 3  -- 爬行僵尸
    else
        zType = math.random(1, 2)  -- 1=白T恤僵尸, 2=棕外套僵尸
    end

    local zSpeed
    if zType == 3 then
        zSpeed = C.CRAWLER_SPEED + G.level * C.ZOMBIE_SPEED_PER_LEVEL
    else
        zSpeed = C.ZOMBIE_SPEED + G.level * C.ZOMBIE_SPEED_PER_LEVEL
    end

    table.insert(zombies, {
        x = zx,
        y = zy,
        facing = 1,
        phase = math.random() * math.pi * 2,
        speed = zSpeed,
        dead = false,
        hitAnim = 0,
        walkAnim = 0,        -- 行走动画计数器
        atkTimer = 0,        -- 攻击列车冷却
        atTrain = false,     -- 是否已到达列车
        zombieType = zType,
    })
    local z = zombies[#zombies]
    local baseHp
    if zType == 1 then
        baseHp = 80
    elseif zType == 2 then
        baseHp = 100
    else -- 爬行僵尸: 脆皮快速
        baseHp = C.CRAWLER_HP_BASE
    end
    z.hp = baseHp + math.floor(G.level / 3) * 5  -- 每3级+5HP
    z.maxHp = z.hp
end

------------------------------------------------------------------------
-- 丧尸更新 (朝列车移动，到达后攻击列车)
------------------------------------------------------------------------
function E.UpdateZombies(G, dt)
    local scrollSpeed = (C.BASE_SCROLL_SPEED + G.level * C.SCROLL_SPEED_PER_LEVEL) * G.scrollSpeedMul
    local scrollDelta = scrollSpeed * dt

    -- 列车碰撞区域（与玩家碰撞使用相同参数）
    local trainCX = G.cartCenterX
    local trainBottomY = G.cartBottomY
    local collisionHalfW = math.max(G.cartW / 2, (G.carriageW or G.cartW) / 2) - 11
    local tLeft = trainCX - collisionHalfW
    local tRight = trainCX + collisionHalfW
    local tTop = G.hudH
    local tBottom = trainBottomY + 8

    for i = #G.zombies, 1, -1 do
        local z = G.zombies[i]
        if z.dead then
            swapRemove(G.zombies, i)
            goto continue_z
        end

        z.hitAnim = math.max(0, (z.hitAnim or 0) - dt * 3)

        -- 随世界滚动向上移动
        z.y = z.y - scrollDelta

        -- 目标: 列车底部中央
        local targetX = trainCX
        local targetY = trainBottomY

        local dx = targetX - z.x
        local dy = targetY - z.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist > 25 then
            -- 向列车移动
            local spd = z.speed * dt
            z.x = z.x + (dx / dist) * spd
            z.y = z.y + (dy / dist) * spd
            z.facing = dx > 0 and 1 or -1
            z.walkAnim = (z.walkAnim or 0) + dt * 8
            z.isWalking = true
            z.atTrain = false
        else
            -- 到达列车，开始攻击
            z.isWalking = false
            z.atTrain = true
            z.atkTimer = z.atkTimer + dt
            if z.atkTimer >= C.ZOMBIE_ATK_INTERVAL then
                z.atkTimer = z.atkTimer - C.ZOMBIE_ATK_INTERVAL
                -- 对列车造成伤害（防御减伤）
                local actualDmg = E.CalcTrainDmgTaken(C.ZOMBIE_DAMAGE, G)
                G.trainHP = G.trainHP - actualDmg
                E.SpawnFloatText(G, trainCX, trainBottomY + 5, "-" .. actualDmg, "damage")
                E.SpawnParticles(G, trainCX + math.random(-15, 15), trainBottomY, {200, 195, 180}, 4)

                if G.trainHP <= 0 then
                    G.trainHP = 0
                    G.state = "gameover"
                end
            end
        end

        -- 僵尸也不能进入火车碰撞体积（与玩家逻辑一致，只推向两侧或下方）
        if z.x > tLeft and z.x < tRight and z.y > tTop and z.y < tBottom then
            local pushLeft = z.x - tLeft
            local pushRight = tRight - z.x
            local pushBottom = tBottom - z.y
            local minPush = math.min(pushLeft, pushRight, pushBottom)
            if minPush == pushLeft then
                z.x = tLeft
            elseif minPush == pushRight then
                z.x = tRight
            else
                z.y = tBottom
            end
            -- 紧贴火车边缘就视为到达，开始攻击
            z.atTrain = true
        end

        -- 屏幕外清除 (上方移出)
        if z.y < G.hudH - 40 then
            swapRemove(G.zombies, i)
            goto continue_z
        end

        ::continue_z::
    end
end

------------------------------------------------------------------------
-- 技能系统：上车/下车/近距检测/角色技能
------------------------------------------------------------------------

--- 检测玩家是否靠近列车（可上车范围）
function E.IsNearTrain(G)
    local p = G.player
    local cx = G.cartCenterX or 0
    local bottom = G.cartBottomY or 0
    local halfW = (G.cartW or 72) / 2 + 30  -- 上车判定范围比碰撞体宽
    local dist = bottom + 60                  -- 列车下方60px以内
    return math.abs(p.x - cx) < halfW and p.y < dist and p.y > (G.hudH or 48)
end

--- 上车：锁定在列车顶部
function E.MountTrain(G)
    if G.mounted then return end
    G.mounted = true
    G.mountedAimDir = 0
    local p = G.player
    p.x = G.cartCenterX or (G.screenW / 2)
    p.y = (G.cartBottomY or 200) - 135  -- 放到车头位置（火车向下行驶，车头在底部）
    G.skillBoardCD = G.skillBoardCDMax  -- 上车后触发冷却（下车后才开始倒计时）
    print("[Skill] Mounted train")
end

--- 下车：恢复自由移动
function E.DismountTrain(G)
    if not G.mounted then return end
    G.mounted = false
    local p = G.player
    p.y = (G.cartBottomY or 200) + 20  -- 放到车厢下方
    G.skillBoardCD = G.skillBoardCDMax  -- 开始冷却
    print("[Skill] Dismounted train")
end

--- 上车状态更新：触摸控制瞄准方向，松开后锁定自动射击
function E.UpdateMounted(G, dt, moveX, moveY)
    local p = G.player
    -- 锁定位置在车头（火车向下行驶，车头在底部）
    p.x = G.cartCenterX or (G.screenW / 2)
    p.y = (G.cartBottomY or 200) - 135
    p.vx = 0
    p.vy = 0

    -- 键盘控制瞄准方向（备用）
    if math.abs(moveX) > 0.15 or math.abs(moveY) > 0.15 then
        G.mountedAimDir = math.atan(moveY, moveX)
        if math.abs(moveX) > 0.1 then
            p.facing = moveX > 0 and 1 or -1
        end
    end

    -- 动画
    p.bobAnim = p.bobAnim + dt * 3
    p.atkSwingAnim = math.max(0, p.atkSwingAnim - dt * 4)

    -- 攻击冷却
    local atkInterval = C.AUTO_ATTACK_INTERVAL / (G.atkSpdMul or 1.0)
    p.atkTimer = math.max(0, p.atkTimer - dt)

    if p.atkTimer <= 0 then
        if G.mountedAimActive then
            -- 按住时：朝触摸方向射击（手动瞄准）
            p.atkTimer = atkInterval
            p.atkSwingAnim = 1.0
            E.FireMountedBullet(G, G.mountedAimDir, nil)
        else
            -- 松开后：自动锁定最近敌人，追踪攻击
            local nearest = E.FindNearestZombie(G)
            if nearest then
                local dx = nearest.x - p.x
                local dy = nearest.y - p.y
                local angle = math.atan(dy, dx)
                G.mountedAimDir = angle
                if math.abs(dx) > 5 then
                    p.facing = dx > 0 and 1 or -1
                end
                p.atkTimer = atkInterval
                p.atkSwingAnim = 1.0
                E.FireMountedBullet(G, angle, nearest)
            end
        end
    end
end

--- 查找射程内最近的丧尸
function E.FindNearestZombie(G)
    local p = G.player
    local range = 420  -- 射程 = 子弹速度(350) × 生命(1.2s)
    local rangeSq = range * range
    local bestDist = rangeSq
    local best = nil
    for _, z in ipairs(G.zombies or {}) do
        if not z.dead then
            local dx = z.x - p.x
            local dy = z.y - p.y
            local dist = dx * dx + dy * dy
            if dist < bestDist then
                bestDist = dist
                best = z
            end
        end
    end
    return best
end

--- 上车状态发射子弹
---@param angle number 发射角度
---@param target table|nil 追踪目标（松开时自动锁定）
function E.FireMountedBullet(G, angle, target)
    local p = G.player
    local spd = 350
    local baseMDmg = C.PLAYER_ATK_ZOMBIE + (G.rangedAtkBonus or 0)  -- 射击攻击力（列车射击）
    local dmg, _ = E.CalcDamage(baseMDmg, G)

    if not G.turretProjectiles then G.turretProjectiles = {} end

    local proj = {
        type = "mounted_bullet",
        x = p.x, y = p.y,
        vx = math.cos(angle) * spd,
        vy = math.sin(angle) * spd,
        speed = spd,
        angle = angle,
        life = 1.2, maxLife = 1.2,
        damage = dmg,
    }

    -- 有目标时加入追踪信息
    if target then
        proj.target = target
        proj.tx = target.x
        proj.ty = target.y
    end

    table.insert(G.turretProjectiles, proj)
end

--- 激活角色技能
function E.ActivateCharSkill(G)
    local charId = G.activeCharId or "warrior"

    if charId == "warrior" then
        -- 投掷炸弹：在脚底放置炸弹，1.5秒后爆炸，范围伤害
        local p = G.player
        local bomb = {
            x = p.x,
            y = p.y,
            fuseTimer = 1.5,        -- 引信时间
            radius = 45,            -- 爆炸半径(像素)
            dmgMul = 2.0,           -- 200%攻击力伤害
            exploded = false,
            bobPhase = 0,           -- 抖动动画相位
        }
        G.bombs = G.bombs or {}
        table.insert(G.bombs, bomb)
        -- 瞬发技能，无持续时间
        G.skillCharActive = false
        G.skillCharDuration = 0
        print("[Skill] Warrior placed bomb at (" .. math.floor(p.x) .. "," .. math.floor(p.y) .. ")")

    elseif charId == "auntie" then
        -- 鼓舞士气：8秒近战+射击攻击力各+20%
        G.skillCharActive = true
        G.skillCharDurationMax = 8
        G.skillCharDuration = 8
        local meleeBoost = math.floor(C.PLAYER_ATK * 0.2)
        local rangedBoost = math.floor(C.PLAYER_ATK * 0.2)
        G.meleeAtkBonus  = (G.meleeAtkBonus or 0)  + meleeBoost
        G.rangedAtkBonus = (G.rangedAtkBonus or 0) + rangedBoost
        G._auntieMeleeBoost  = meleeBoost   -- 记录加成量，结束时回退
        G._auntieRangedBoost = rangedBoost
        print("[Skill] Auntie morale boost! MeleeAtk/RangedAtk +20% for 8s")

    elseif charId == "lisanguang" then
        -- 战斗狂怒：7秒内攻速+100%
        G.skillCharActive = true
        G.skillCharDurationMax = 7
        G.skillCharDuration = 7
        G.atkSpdMul = (G.atkSpdMul or 1.0) * 2.0
        print("[Skill] Lisanguang fury activated! AtkSpd x2 for 7s")

    elseif charId == "weifenglong" then
        -- 龙息吐焰：对前方扇形内所有丧尸造成150%近战攻击力伤害 + 3秒灼烧
        G.skillCharActive = true
        G.skillCharDurationMax = 3
        G.skillCharDuration = 3
        local baseDragonDmg = math.floor((C.PLAYER_ATK + (G.meleeAtkBonus or 0)) * 1.5)
        local atkPower, _ = E.CalcDamage(baseDragonDmg, G)
        local p = G.player
        for _, z in ipairs(G.zombies or {}) do
            if not z.dead then
                local dx = z.x - p.x
                local dy = z.y - p.y
                local dist = math.sqrt(dx * dx + dy * dy)
                -- 前方120度扇形，范围120px
                if dist < 120 then
                    local inFront = (p.facing > 0 and dx > -20) or (p.facing < 0 and dx < 20)
                    if inFront then
                        z.hp = z.hp - atkPower
                        z.hitAnim = 0.3
                        z.burnTimer = 3.0    -- 灼烧3秒
                        z.burnDps = math.floor(atkPower * 0.15)  -- 每秒15%伤害
                        E.SpawnParticles(G, z.x, z.y, { 255, 100, 20 }, 5)
                        E.SpawnFloatText(G, z.x, z.y - 10, "-" .. atkPower, "damage")
                        if z.hp <= 0 then
                            z.dead = true
                            G.killCount = (G.killCount or 0) + 1
                        end
                    end
                end
            end
        end
        print("[Skill] Dragon breath!")
    end

    G.skillCharCD = G.skillCharCDMax
end

--- 角色技能持续效果结束时的清理
function E.EndCharSkill(G)
    local charId = G.activeCharId or "warrior"
    if charId == "warrior" then
        -- 炸弹技能是瞬发，无持续效果需要清理
        print("[Skill] Warrior bomb skill ended (no-op)")
    elseif charId == "lisanguang" then
        G.atkSpdMul = math.max(1.0, (G.atkSpdMul or 2.0) / 2.0)
        print("[Skill] Lisanguang fury ended")
    elseif charId == "auntie" then
        G.meleeAtkBonus  = math.max(0, (G.meleeAtkBonus or 0)  - (G._auntieMeleeBoost or 0))
        G.rangedAtkBonus = math.max(0, (G.rangedAtkBonus or 0) - (G._auntieRangedBoost or 0))
        G._auntieMeleeBoost  = nil
        G._auntieRangedBoost = nil
        print("[Skill] Auntie morale ended")
    elseif charId == "weifenglong" then
        print("[Skill] Dragon breath ended")
    end
    G.skillCharActive = false
    G.skillCharDuration = 0
end

------------------------------------------------------------------------
-- 炸弹系统
------------------------------------------------------------------------

--- 炸弹爆炸：对范围内敌人和资源造成伤害
function E.ExplodeBomb(G, bomb)
    local baseDmg = math.floor((C.PLAYER_ATK + (G.meleeAtkBonus or 0)) * bomb.dmgMul)
    local atkPower, _ = E.CalcDamage(baseDmg, G)
    local r2 = bomb.radius * bomb.radius
    local hits = 0

    -- 伤害范围内的僵尸
    for _, z in ipairs(G.zombies or {}) do
        if not z.dead then
            local dx = z.x - bomb.x
            local dy = z.y - bomb.y
            if dx * dx + dy * dy <= r2 then
                z.hp = z.hp - atkPower
                z.hitAnim = 0.3
                E.SpawnParticles(G, z.x, z.y, { 255, 120, 30 }, 5)
                E.SpawnFloatText(G, z.x, z.y - 10, "-" .. atkPower, "damage")
                hits = hits + 1
                if z.hp <= 0 then
                    z.dead = true
                    G.killCount = (G.killCount or 0) + 1
                end
            end
        end
    end

    -- 炸范围内的资源节点
    for _, res in ipairs(G.resources or {}) do
        if not res.dead then
            local dx = res.x - bomb.x
            local dy = res.y - bomb.y
            if dx * dx + dy * dy <= r2 then
                res.hp = res.hp - atkPower
                res.hitAnim = 0.3
                E.SpawnParticles(G, res.x, res.y, { 255, 200, 80 }, 4)
                if res.hp <= 0 then
                    res.dead = true
                    -- 掉落资源（自动拾取到背包）
                    local resInfo = C.RES[res.rtype]
                    if resInfo then
                        local actual = E.AddCarry(G, res.rtype, resInfo.drop)
                        if actual > 0 then
                            E.SpawnFloatText(G, res.x, res.y - 10, "+" .. actual, res.rtype)
                        end
                    end
                else
                    E.SpawnFloatText(G, res.x, res.y - 15, "-" .. atkPower, "damage")
                end
            end
        end
    end

    -- 创建爆炸特效
    G.explosions = G.explosions or {}
    table.insert(G.explosions, {
        x = bomb.x,
        y = bomb.y,
        frame = 1,           -- 当前帧（1-9）
        maxFrame = 9,        -- 总帧数
        frameTimer = 0,      -- 帧计时器
        frameDuration = 0.06, -- 每帧持续时间
        radius = bomb.radius,
    })

    print("[Bomb] Exploded at (" .. math.floor(bomb.x) .. "," .. math.floor(bomb.y) .. ") hit " .. hits .. " targets, dmg=" .. atkPower)
end

--- 更新炸弹（倒计时、滚动、爆炸）
function E.UpdateBombs(G, dt, scrollDelta)
    G.bombs = G.bombs or {}
    for i = #G.bombs, 1, -1 do
        local b = G.bombs[i]
        -- 跟随地面滚动
        b.y = b.y - (scrollDelta or 0)
        -- 抖动动画
        b.bobPhase = b.bobPhase + dt * 12
        -- 倒计时
        b.fuseTimer = b.fuseTimer - dt
        if b.fuseTimer <= 0 then
            E.ExplodeBomb(G, b)
            b.exploded = true
        end
        -- 移除已爆炸或超出屏幕的炸弹
        if b.exploded or b.y < -50 then
            table.remove(G.bombs, i)
        end
    end
end

--- 更新爆炸特效动画
function E.UpdateExplosions(G, dt)
    G.explosions = G.explosions or {}
    for i = #G.explosions, 1, -1 do
        local e = G.explosions[i]
        e.frameTimer = e.frameTimer + dt
        if e.frameTimer >= e.frameDuration then
            e.frameTimer = e.frameTimer - e.frameDuration
            e.frame = e.frame + 1
        end
        if e.frame > e.maxFrame then
            table.remove(G.explosions, i)
        end
    end
end

return E

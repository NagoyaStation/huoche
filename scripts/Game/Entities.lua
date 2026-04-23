-- Game/Entities.lua - 实体逻辑：玩家、资源节点、丧尸(攻击列车)、浮岛物语风格自动攻击
local C = require "Game.Config"
local E = {}

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
    else
        -- 停止移动时快速衰减，回到待机姿态
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
    local atkPower = C.PLAYER_ATK + (G.atkBonus or 0)

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
        local dmg = C.PLAYER_ATK_ZOMBIE + (G.atkBonus or 0)
        bestTarget.hp = bestTarget.hp - dmg
        bestTarget.hitAnim = 0.2

        E.SpawnParticles(G, bestTarget.x, bestTarget.y, {220, 70, 60}, 3)

        if bestTarget.hp <= 0 then
            bestTarget.dead = true
            E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 10, "击杀!", "gold")
            E.SpawnParticles(G, bestTarget.x, bestTarget.y, {220, 70, 60}, 6)
            -- 击杀奖励金币
            local goldReward = 2 + G.level
            G.gold = G.gold + goldReward
            E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 25, "+" .. goldReward, "gold")
        else
            E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 15, "-" .. dmg, "damage")
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
            z.atTrain = false
        else
            -- 到达列车，开始攻击
            z.atTrain = true
            z.atkTimer = z.atkTimer + dt
            if z.atkTimer >= C.ZOMBIE_ATK_INTERVAL then
                z.atkTimer = z.atkTimer - C.ZOMBIE_ATK_INTERVAL
                -- 对列车造成伤害
                G.trainHP = G.trainHP - C.ZOMBIE_DAMAGE
                E.SpawnFloatText(G, trainCX, trainBottomY + 5, "-" .. C.ZOMBIE_DAMAGE, "damage")
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

return E

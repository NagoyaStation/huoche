-- Game/Entities.lua - 实体逻辑：玩家、资源节点、丧尸(攻击列车)、浮岛物语风格自动攻击
local C = require "Game.Config"
local E = {}

--- 计算最终伤害（含攻击百分比加成和暴击）
--- @param baseDmg number 基础伤害
--- @param G table 全局状态
--- @return number dmg 最终伤害
--- @return boolean isCrit 是否暴击
function E.CalcDamage(baseDmg, G)
    local dmg = baseDmg * (G.atkPctMul or 1.0) * (G.weaponDmgMul or 1.0)
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
        carryQueue = {},        -- 携带资源队列（按采集顺序），元素为资源类型字符串
        carrySmooth = {},       -- 携带资源平滑显示位置 {x,y}
        trail = {},             -- 位置历史轨迹，用于资源跟随排队
        trailDist = 0,          -- 累计移动距离（用于采样间隔）
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

    -- 喷气冲刺逐帧推进（带轨迹粒子）
    if G.jetDash then
        local jd = G.jetDash
        local moveDist = jd.speed * dt
        if moveDist > jd.remaining then
            moveDist = jd.remaining
        end
        p.x = p.x + jd.dirX * moveDist
        p.y = p.y + jd.dirY * moveDist
        jd.remaining = jd.remaining - moveDist

        -- 轨迹粒子：每移动约15像素喷一次
        jd.trailTimer = jd.trailTimer + moveDist
        if jd.trailTimer >= 15 then
            jd.trailTimer = jd.trailTimer - 15
            E.SpawnParticles(G, p.x, p.y, {255, 255, 255}, 3)
        end

        -- 冲刺结束
        if jd.remaining <= 0 then
            G.jetDash = nil
        end
    end

    -- 朝向 & 记录最后移动Y方向（供喷气技能使用）
    if math.abs(moveX) > 0.2 then
        p.facing = moveX > 0 and 1 or -1
    end
    if math.abs(moveY) > 0.2 then
        G._lastMoveY = moveY
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

    -- 位置轨迹记录（资源跟随队列用）
    do
        local trail = p.trail
        local TRAIL_STEP = 14  -- 每隔14像素记录一个轨迹点
        local MAX_TRAIL = 80   -- 最多保留的轨迹点数

        -- 轨迹点也要随世界滚动，与 p.y 保持一致
        for i = 1, #trail do
            trail[i].y = trail[i].y - scrollDelta
        end

        if #trail == 0 then
            trail[1] = { x = p.x, y = p.y }
        else
            local last = trail[1]
            local dx = p.x - last.x
            local dy = p.y - last.y
            if dx * dx + dy * dy >= TRAIL_STEP * TRAIL_STEP then
                -- 在队首插入新点
                table.insert(trail, 1, { x = p.x, y = p.y })
                -- 裁剪过长轨迹
                while #trail > MAX_TRAIL do
                    trail[#trail] = nil
                end
            end
        end
    end

    -- 携带资源平滑跟随（lerp到轨迹目标点）
    do
        local smooth = p.carrySmooth
        local trail = p.trail
        local lerpSpd = 12 * dt  -- lerp速度
        for i = 1, #p.carryQueue do
            local trailIdx = i + 1
            if trailIdx > #trail then break end
            local target = trail[trailIdx]
            if not smooth[i] then
                smooth[i] = { x = target.x, y = target.y }
            else
                smooth[i].x = smooth[i].x + (target.x - smooth[i].x) * lerpSpd
                smooth[i].y = smooth[i].y + (target.y - smooth[i].y) * lerpSpd
            end
        end
        -- 裁剪多余的平滑点
        for i = #smooth, #p.carryQueue + 1, -1 do
            smooth[i] = nil
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

    local range = C.AUTO_ATTACK_RANGE * (G.rangeMul or 1.0)

    -- 每帧寻找最近的可攻击目标（保持红圈持续锁定）
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

    -- 每帧更新锁定目标引用（红圈持续显示）
    if bestTarget then
        p.atkTarget = { type = bestType, ref = bestTarget }
    else
        p.atkTarget = nil
    end

    -- 冷却中不执行攻击
    if p.atkTimer > 0 then return end
    if not bestTarget then return end

    -- 执行攻击
    local baseAtk = (C.PLAYER_ATK + (G.meleeAtkBonus or 0)) * (G.meleeAtkMul or 1.0)
    local atkPower, _ = E.CalcDamage(baseAtk, G)
    local atkInterval = C.AUTO_ATTACK_INTERVAL / (G.atkSpdMul or 1.0)
    p.atkTimer = atkInterval
    p.atkSwingAnim = 1.0

    -- 面向目标
    if bestTarget.x > p.x then p.facing = 1 else p.facing = -1 end

    if bestType == "res" then
        local gatherPower = math.floor(atkPower * (G.gatherMul or 1.0))
        bestTarget.hp = bestTarget.hp - gatherPower
        bestTarget.hitAnim = 0.2   -- 受击闪白
        bestTarget.squashAnim = 1.0 -- 受击压缩动画

        -- 攻击爆点 + 击碎粒子
        E.SpawnBurst(G, bestTarget.x, bestTarget.y)
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

            -- 弹出资源动画（无论背包是否满都掉落，满了留在地面等捡）
            E.SpawnDropItem(G, bestTarget.x, bestTarget.y, bestTarget.rtype, amount)
            E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 10, "+" .. amount, bestTarget.rtype)

            p.collectAnim = 0.3
            E.SpawnPuff(G, bestTarget.x, bestTarget.y)
        end

    elseif bestType == "zombie" then
        local baseZDmg = (C.PLAYER_ATK_ZOMBIE + (G.meleeAtkBonus or 0)) * (G.meleeAtkMul or 1.0)  -- 近战攻击力
        local dmg, isCrit = E.CalcDamage(baseZDmg, G)
        bestTarget.hp = bestTarget.hp - dmg
        bestTarget.hitAnim = 0.2

        E.SpawnBurst(G, bestTarget.x, bestTarget.y)
        E.SpawnParticles(G, bestTarget.x, bestTarget.y, {220, 70, 60}, 3)

        if bestTarget.hp <= 0 then
            bestTarget.dead = true
            G.killCount = (G.killCount or 0) + 1
            E.SpawnZombieDeath(G, bestTarget.x, bestTarget.y)
            -- 击杀掉落1枚金币，飞到顶部金币图标
            E.SpawnGoldFly(G, bestTarget.x, bestTarget.y, 1)
        else
            if isCrit then
                E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 15, tostring(dmg), "crit")
            else
                E.SpawnFloatText(G, bestTarget.x, bestTarget.y - 15, tostring(dmg), "damage")
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
    if p.submitting then return end  -- 正在提交中，不重复触发

    local sx = G.submitBox.x
    local sy = G.submitBox.y
    local sw = C.SUBMIT_BOX_W
    local sh = C.SUBMIT_BOX_H

    local px = p.x
    local py = p.y
    if px > sx - sw / 2 - 12 and px < sx + sw / 2 + 12 and
       py > sy - sh / 2 - 12 and py < sy + sh / 2 + 12 then
        -- 启动逐个提交过程
        p.submitting = true
        p.submitTimer = 0
        p.submitAnim = 0.4
    end
end

------------------------------------------------------------------------
-- 逐个提交过程（每帧调用）
------------------------------------------------------------------------
function E.UpdateSubmitProcess(G, dt)
    local p = G.player
    if not p.submitting then return end

    -- 提交间隔：每0.08秒弹出一个资源
    local SUBMIT_INTERVAL = 0.08
    p.submitTimer = p.submitTimer + dt

    while p.submitTimer >= SUBMIT_INTERVAL and #p.carryQueue > 0 do
        p.submitTimer = p.submitTimer - SUBMIT_INTERVAL

        -- 从队尾弹出一个资源
        local idx = #p.carryQueue
        local rtype = p.carryQueue[idx]

        -- 获取该资源的视觉位置
        local startX, startY
        if p.carrySmooth[idx] then
            startX = p.carrySmooth[idx].x
            startY = p.carrySmooth[idx].y
        else
            startX = p.x
            startY = p.y
        end

        -- 从背包移除
        p.carryQueue[idx] = nil
        if p.carrySmooth[idx] then
            p.carrySmooth[idx] = nil
        end
        p.inv[rtype] = math.max(0, (p.inv[rtype] or 1) - 1)
        p.carrying = math.max(0, p.carrying - 1)

        -- 生成飞行动画项
        local sx = G.submitBox.x
        local sy = G.submitBox.y
        table.insert(G.submitFlyItems, {
            x = startX,
            y = startY,
            startX = startX,
            startY = startY,
            targetX = sx,
            targetY = sy - 10,
            rtype = rtype,
            timer = 0,
            duration = 0.25,
            rot = 0,
            rotSpd = (math.random() - 0.5) * 12,
        })
    end

    -- 全部弹出完毕，结束提交过程
    if #p.carryQueue <= 0 then
        p.submitting = false
    end
end

------------------------------------------------------------------------
-- 提交资源飞行动画更新
------------------------------------------------------------------------
function E.UpdateSubmitFlyItems(G, dt)
    for i = #G.submitFlyItems, 1, -1 do
        local item = G.submitFlyItems[i]
        item.timer = item.timer + dt
        local t = math.min(1, item.timer / item.duration)
        -- smoothstep 缓动
        local st = t * t * (3 - 2 * t)

        -- 从起始位置到目标直接插值 + 抛物线弧线（向上弓起）
        local arcY = -70 * 4 * t * (1 - t)  -- 抛物线，中点最高-70px
        item.x = item.startX + (item.targetX - item.startX) * st
        item.y = item.startY + (item.targetY - item.startY) * st + arcY

        item.rot = item.rot + item.rotSpd * dt

        if t >= 1 then
            -- 到达物资点
            local sx = G.submitBox.x
            local sy = G.submitBox.y

            -- 提交时增加资源总量
            local rtype = item.rtype
            G.totalRes[rtype] = (G.totalRes[rtype] or 0) + 1
            -- 同步更新saveData持久化数据（局内外资源一致）
            local sd = G.saveData
            if sd then
                if rtype == "ore" then
                    sd.diamond = (sd.diamond or 0) + 1
                elseif rtype == "wood" or rtype == "bush" then
                    sd.wood = (sd.wood or 0) + 1
                elseif rtype == "stone" or rtype == "pebble" then
                    sd.stone = (sd.stone or 0) + 1
                end
            end

            -- 资源算升级进度，钻石+2
            if rtype == "ore" then
                G.levelProgress = G.levelProgress + 2
            elseif rtype == "wood" or rtype == "bush" or rtype == "stone" or rtype == "pebble" then
                G.levelProgress = G.levelProgress + 1
            end

            -- 钻石提交时左侧显示获得提示
            if rtype == "ore" then
                E.SpawnRewardToast(G, "gem", "获得 x1 钻石")
            end

            -- 白色+黑色描边 "+1" 飘字
            E.SpawnFloatText(G, sx + (math.random() - 0.5) * 16, sy - 15, "+1", "submit")

            -- 小粒子效果
            E.SpawnParticles(G, sx, sy, {255, 220, 80}, 2)

            -- 检查关卡升级（升级状态中不重复触发）
            if G.levelProgress >= G.levelTarget
               and G.state ~= "upgradeVfx" and G.state ~= "upgrade" then
                G.pendingLevelUp = true
            end

            -- 移除
            swapRemove(G.submitFlyItems, i)
        end
    end
end

------------------------------------------------------------------------
-- 击杀僵尸掉落金币飞行
------------------------------------------------------------------------
function E.SpawnGoldFly(G, x, y, amount)
    -- 顶部金币图标目标位置（HUD第一项）
    local s = G.uiScale or 1
    local hudH = G.hudH or 40
    local targetX = 6 * s + 68 * s * 0 + 6 * s + 15 * s / 2
    local targetY = hudH / 2

    for i = 1, amount do
        -- 随机爆开方向
        local angle = math.random() * math.pi * 2
        local popDist = 25 + math.random() * 20
        local landX = x + math.cos(angle) * popDist
        local landY = y + math.sin(angle) * popDist * 0.5  -- 压扁Y轴，俯视感
        table.insert(G.goldFlyItems, {
            x = x, y = y,
            originX = x, originY = y,       -- 爆发原点
            landX = landX, landY = landY,    -- 弹落地点
            targetX = targetX, targetY = targetY,
            timer = 0,
            delay = (i - 1) * 0.03,
            phase = 1,          -- 1=爆开弹起  2=飞向HUD
            popDur = 0.3,       -- 爆开阶段时长
            flyDur = 0.4,       -- 飞向HUD时长
            scale = 1.0,
        })
    end
end

function E.UpdateGoldFlyItems(G, dt)
    for i = #G.goldFlyItems, 1, -1 do
        local item = G.goldFlyItems[i]
        -- 延迟阶段
        if item.delay > 0 then
            item.delay = item.delay - dt
            goto continue_gold
        end

        item.timer = item.timer + dt

        if item.phase == 1 then
            -- 阶段1: 爆开弹起（抛物线从原点飞到落地点）
            local t = math.min(1, item.timer / item.popDur)
            local st = t * t * (3 - 2 * t)
            item.x = item.originX + (item.landX - item.originX) * st
            item.y = item.originY + (item.landY - item.originY) * st + (-60 * 4 * t * (1 - t))
            item.scale = 1.0

            if t >= 1 then
                -- 进入阶段2
                item.phase = 2
                item.timer = 0
                item.startX = item.landX
                item.startY = item.landY
            end
        elseif item.phase == 2 then
            -- 阶段2: 从落地点飞向HUD金币图标
            local t = math.min(1, item.timer / item.flyDur)
            local st = t * t * (3 - 2 * t)
            local arcY = -40 * 4 * t * (1 - t)
            item.x = item.startX + (item.targetX - item.startX) * st
            item.y = item.startY + (item.targetY - item.startY) * st + arcY
            item.scale = 1.0 - t * 0.5

            if t >= 1 then
                G.gold = G.gold + 1
                -- 同步更新saveData金币
                local sd = G.saveData
                if sd then sd.gold = (sd.gold or 0) + 1 end
                swapRemove(G.goldFlyItems, i)
            end
        end

        ::continue_gold::
    end
end

------------------------------------------------------------------------
-- 左侧获得提示 (带图标的 toast)
------------------------------------------------------------------------
function E.SpawnRewardToast(G, icon, text)
    if not G.rewardToasts then G.rewardToasts = {} end
    table.insert(G.rewardToasts, {
        icon = icon,      -- "gem" / "wood" / "stone" / "gold"
        text = text,
        timer = 0,
        life = 2.0,       -- 总显示时长
    })
end

function E.UpdateRewardToasts(G, dt)
    if not G.rewardToasts then return end
    for i = #G.rewardToasts, 1, -1 do
        local t = G.rewardToasts[i]
        t.timer = t.timer + dt
        if t.timer >= t.life then
            swapRemove(G.rewardToasts, i)
        end
    end
end

------------------------------------------------------------------------
-- 开局预生成资源：填满可见区域
------------------------------------------------------------------------
function E.PreSpawnResources(G)
    local W = G.screenW
    local H = G.screenH
    local hudH = G.hudH or 48
    -- 从列车底部下方开始，到屏幕底部+一点缓冲
    local startY = (G.cartBottomY or (hudH + 260)) + 60
    local endY = H + 40
    -- 按行扫描生成，每行间距约 SPAWN_INTERVAL 对应的滚动距离
    local rowGap = 80  -- 每行间距
    local y = startY
    while y < endY do
        -- 每行生成 1~2 个资源
        local count = math.random(C.RES_PER_SPAWN_MIN, C.RES_PER_SPAWN_MAX)
        for ci = 1, count do
            -- 资源类型选择（复用 SpawnResources 的频率逻辑）
            local roll = math.random()
            local oreFreq = C.RES.ore.freq * (G.oreLuckMul or 1)
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

            local pathL, pathR = E.GetPathBounds(W, y)
            local side = (ci % 2 == 1) and 1 or 2
            local rx
            local margin = 20
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

            local ry = y + math.random(-10, 10)

            -- 重叠检测
            local RES_MIN_DIST = 40
            local overlap = false
            for _, r in ipairs(G.resources) do
                local ddx = r.x - rx
                local ddy = r.y - ry
                if ddx * ddx + ddy * ddy < RES_MIN_DIST * RES_MIN_DIST then
                    overlap = true
                    break
                end
            end

            if not overlap then
                local resInfo = C.RES[rtype]
                table.insert(G.resources, {
                    x = rx, y = ry,
                    rtype = rtype,
                    hp = resInfo.hp,
                    maxHp = resInfo.hp,
                    displayHp = resInfo.hp,
                    dead = false,
                    hitAnim = 0,
                    squashAnim = 0,
                    bobPhase = math.random() * math.pi * 2,
                    scale = 0.85 + math.random() * 0.3,
                })
            end
        end
        y = y + rowGap
    end
end

------------------------------------------------------------------------
-- 开局预生成装饰物：填满可见区域
------------------------------------------------------------------------
function E.PreSpawnDecorations(G)
    local W = G.screenW
    local H = G.screenH
    local imgs = G.decoImgs
    if not imgs then return end

    local allImgs = {}
    for _, img in ipairs(imgs.poles  or {}) do if img ~= 0 then table.insert(allImgs, {img = img, cat = "pole"}) end end
    for _, img in ipairs(imgs.houses or {}) do if img ~= 0 then table.insert(allImgs, {img = img, cat = "house"}) end end
    for _, img in ipairs(imgs.small  or {}) do if img ~= 0 then table.insert(allImgs, {img = img, cat = "small"}) end end
    if #allImgs == 0 then return end

    local DECO_GAP_SAME_SIDE = 160
    local startY = (G.cartBottomY or 300) + 40
    local endY = H + 40
    local y = startY
    local lastSide = 0
    while y < endY do
        local pick = allImgs[math.random(#allImgs)]
        local side = (lastSide == 1) and 2 or 1
        local dx
        if pick.cat == "house" then
            if side == 1 then dx = math.random(-25, -5) else dx = W + math.random(5, 25) end
        elseif pick.cat == "small" then
            if side == 1 then dx = math.random(-5, 12) else dx = W - math.random(-5, 12) end
        else
            if side == 1 then dx = math.random(5, 22) else dx = W - math.random(5, 22) end
        end
        table.insert(G.decorations, {
            x = dx, y = y + math.random(-10, 10),
            img = pick.img, cat = pick.cat,
            flip = (math.random(2) == 1),
            side = side,
        })
        lastSide = side
        y = y + DECO_GAP_SAME_SIDE + math.random(0, 40)
    end
    G.lastDecoSide = lastSide
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

        -- 检查与已有资源的最小间距，避免重叠
        local RES_MIN_DIST = 40
        local overlap = false
        for _, r in ipairs(G.resources) do
            local ddx = r.x - rx
            local ddy = r.y - ry
            if ddx * ddx + ddy * ddy < RES_MIN_DIST * RES_MIN_DIST then
                overlap = true
                break
            end
        end

        -- 检查与装饰物的间距，避免资源生成在装饰物附近
        if not overlap then
            local DECO_MIN_DIST = 75
            for _, d in ipairs(G.decorations) do
                local ddx = d.x - rx
                local ddy = d.y - ry
                if ddx * ddx + ddy * ddy < DECO_MIN_DIST * DECO_MIN_DIST then
                    overlap = true
                    break
                end
            end
        end

        if not overlap then
            local resInfo = C.RES[rtype]
            table.insert(G.resources, {
                x = rx, y = ry,
                rtype = rtype,
                hp = resInfo.hp,
                maxHp = resInfo.hp,
                displayHp = resInfo.hp, -- 延时血条显示值
                dead = false,
                hitAnim = 0,
                squashAnim = 0,         -- 受击压缩动画 (0=正常, >0=压缩中)
                bobPhase = math.random() * math.pi * 2,
                scale = 0.85 + math.random() * 0.3,  -- 随机大小变化
            })
        end
    end
end

------------------------------------------------------------------------
-- 资源节点更新 (受击动画、清理)
------------------------------------------------------------------------
function E.UpdateResources(G, dt)
    for i = #G.resources, 1, -1 do
        local r = G.resources[i]
        r.hitAnim = math.max(0, (r.hitAnim or 0) - dt * 3)
        -- 受击压缩动画衰减
        r.squashAnim = math.max(0, (r.squashAnim or 0) - dt * 4)
        -- 延时血条：displayHp 缓慢追赶 hp
        local dhp = r.displayHp or r.hp
        if dhp > r.hp then
            r.displayHp = dhp - (dhp - r.hp) * math.min(1, dt * 3)
            if r.displayHp - r.hp < 0.5 then r.displayHp = r.hp end
        else
            r.displayHp = r.hp
        end
        if r.dead then
            swapRemove(G.resources, i)
        end
    end
end

------------------------------------------------------------------------
-- 装饰物生成 (树、灌木)
------------------------------------------------------------------------
function E.SpawnDecorations(G)
    local W = G.screenW
    local imgs = G.decoImgs
    if not imgs then return end

    local allImgs = {}
    -- 按类别收集: poles(电线杆), houses(装饰房), small(小门栏)。废墟不生成。
    for _, img in ipairs(imgs.poles  or {}) do if img ~= 0 then table.insert(allImgs, {img = img, cat = "pole"}) end end
    for _, img in ipairs(imgs.houses or {}) do if img ~= 0 then table.insert(allImgs, {img = img, cat = "house"}) end end
    for _, img in ipairs(imgs.small  or {}) do if img ~= 0 then table.insert(allImgs, {img = img, cat = "small"}) end end
    if #allImgs == 0 then return end

    -- 装饰物最小间距
    local DECO_GAP_SAME_SIDE = 160   -- 同侧 Y 方向最小间距
    local DECO_GAP_CROSS = 100       -- 跨侧欧几里得最小间距

    for ci = 1, C.DECO_PER_SPAWN do
        -- 随机选一张装饰图
        local pick = allImgs[math.random(#allImgs)]
        -- 左右交替（基于上次生成的一侧取反，避免连续同侧）
        local side
        if G.lastDecoSide == 1 then
            side = 2
        elseif G.lastDecoSide == 2 then
            side = 1
        else
            side = (math.random(2) == 1) and 1 or 2
        end

        -- 检查与所有已有装饰物的距离
        local dy = G.screenH + 30 + math.random(0, 60)
        local tooClose = false
        for _, d in ipairs(G.decorations) do
            if d.side == side then
                -- 同侧：Y方向间距检查
                if math.abs(d.y - dy) < DECO_GAP_SAME_SIDE then
                    tooClose = true
                    break
                end
            else
                -- 异侧：Y距离也不能太近（避免左右对称堆叠）
                if math.abs(d.y - dy) < DECO_GAP_CROSS then
                    tooClose = true
                    break
                end
            end
        end
        if tooClose then goto continue_spawn end

        local dx
        -- 装饰物中心推到屏幕外，只露出边缘一小部分，不影响资源区
        if pick.cat == "house" then
            -- 房屋中心稍微靠外，露出一部分
            if side == 1 then
                dx = math.random(-25, -5)
            else
                dx = W + math.random(5, 25)
            end
        elseif pick.cat == "small" then
            -- 小门栏，靠近屏幕边缘
            if side == 1 then
                dx = math.random(-5, 12)
            else
                dx = W - math.random(-5, 12)
            end
        else
            -- 电线杆较窄，稍微露出来一些
            if side == 1 then
                dx = math.random(5, 22)
            else
                dx = W - math.random(5, 22)
            end
        end

        table.insert(G.decorations, {
            x = dx,
            y = dy,
            img = pick.img,
            cat = pick.cat,
            flip = (math.random(2) == 1),
            side = side,
        })
        G.lastDecoSide = side

        ::continue_spawn::
    end
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

    -- 装饰物向上滚动
    for i = #G.decorations, 1, -1 do
        local d = G.decorations[i]
        d.y = d.y - scrollDelta
        if d.y < G.hudH - 60 then
            swapRemove(G.decorations, i)
        end
    end

    -- 浮动文字向上滚动
    for i = #G.floatTexts, 1, -1 do
        local ft = G.floatTexts[i]
        ft.y = ft.y - scrollDelta
    end

    -- 烟雾向上滚动
    for _, pf in ipairs(G.puffs) do
        pf.y = pf.y - scrollDelta
    end

    -- 攻击爆点向上滚动
    for _, bf in ipairs(G.bursts) do
        bf.y = bf.y - scrollDelta
    end

    -- 弹出资源向上滚动
    for _, di in ipairs(G.dropItems) do
        di.y = di.y - scrollDelta
        if di.groundY then
            di.groundY = di.groundY - scrollDelta
        end
    end

    -- 携带资源平滑位置也要滚动
    if G.player and G.player.carrySmooth then
        for _, cs in ipairs(G.player.carrySmooth) do
            cs.y = cs.y - scrollDelta
        end
    end

    -- 提交飞行资源：起始点跟随世界滚动（目标点submitBox是固定屏幕位置不滚动）
    for _, si in ipairs(G.submitFlyItems) do
        si.startY = si.startY - scrollDelta
    end

    -- 金币飞行：世界坐标点跟随滚动（目标点HUD是固定屏幕位置不滚动）
    for _, gi in ipairs(G.goldFlyItems) do
        if gi.phase == 1 then
            gi.originY = gi.originY - scrollDelta
            gi.landY = gi.landY - scrollDelta
        else
            gi.startY = gi.startY - scrollDelta
        end
    end

    -- 无人机跟随世界滚动
    if G.drones then
        for _, d in ipairs(G.drones) do
            d.y = d.y - scrollDelta
        end
    end
end

------------------------------------------------------------------------
-- 浮动文字
------------------------------------------------------------------------
function E.SpawnFloatText(G, x, y, text, rtype)
    local vx, vy = 0, -40   -- 默认：向上飘
    local life = 1.0
    -- 火车受击：从火车两侧水平飞出，与僵尸伤害区分
    if rtype == "train_damage" then
        local side = (math.random(1, 2) == 1) and -1 or 1
        vx = side * (90 + math.random() * 40)
        vy = -20 - math.random() * 20
        life = 0.7
    -- 提交+1：向上飘，略有左右散开
    elseif rtype == "submit" then
        vx = (math.random() - 0.5) * 30
        vy = -60 - math.random() * 20
        life = 0.7
    -- 伤害/暴击数字：随机弹射方向，快速消失
    elseif rtype == "damage" or rtype == "crit" then
        local dir = math.random(1, 3)  -- 1=左上 2=右上 3=顶部
        if dir == 1 then
            vx, vy = -60 - math.random() * 30, -80 - math.random() * 40
        elseif dir == 2 then
            vx, vy = 60 + math.random() * 30, -80 - math.random() * 40
        else
            vx, vy = -15 + math.random() * 30, -100 - math.random() * 40
        end
        life = 0.6
    end
    table.insert(G.floatTexts, {
        x = x, y = y,
        vx = vx, vy = vy,
        text = text,
        rtype = rtype,
        life = life,
        maxLife = life,
    })
end

function E.UpdateFloatTexts(G, dt)
    for i = #G.floatTexts, 1, -1 do
        local ft = G.floatTexts[i]
        ft.x = ft.x + (ft.vx or 0) * dt
        ft.y = ft.y + (ft.vy or -40) * dt
        -- 伤害数字减速 + 重力
        if ft.rtype == "damage" or ft.rtype == "crit" or ft.rtype == "train_damage" then
            ft.vx = (ft.vx or 0) * 0.95
            ft.vy = (ft.vy or 0) + 120 * dt  -- 重力下落
        end
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
-- 烟雾特效（资源破坏时的白色烟雾）
------------------------------------------------------------------------
function E.SpawnPuff(G, x, y)
    local smokeType = math.random(1, 2)
    local totalFrames = smokeType == 1 and 9 or 16
    table.insert(G.puffs, {
        x = x,
        y = y,
        smokeType = smokeType,
        frame = 1,
        frameTimer = 0,
        frameRate = 0.04,       -- 每帧0.04s → A约0.36s B约0.64s
        totalFrames = totalFrames,
    })
end

function E.UpdatePuffs(G, dt)
    for i = #G.puffs, 1, -1 do
        local p = G.puffs[i]
        p.frameTimer = p.frameTimer + dt
        if p.frameTimer >= p.frameRate then
            p.frameTimer = p.frameTimer - p.frameRate
            p.frame = p.frame + 1
            if p.frame > p.totalFrames then
                swapRemove(G.puffs, i)
            end
        end
    end
end

------------------------------------------------------------------------
-- 攻击爆点特效（序列帧）
------------------------------------------------------------------------
function E.SpawnBurst(G, x, y)
    table.insert(G.bursts, {
        x = x + (math.random() - 0.5) * 8,
        y = y + (math.random() - 0.5) * 6,
        frame = 1,
        frameTimer = 0,
        frameRate = 0.05,
        totalFrames = 4,
    })
end

function E.UpdateBursts(G, dt)
    for i = #G.bursts, 1, -1 do
        local b = G.bursts[i]
        b.frameTimer = b.frameTimer + dt
        if b.frameTimer >= b.frameRate then
            b.frameTimer = b.frameTimer - b.frameRate
            b.frame = b.frame + 1
            if b.frame > b.totalFrames then
                swapRemove(G.bursts, i)
            end
        end
    end
end

------------------------------------------------------------------------
-- 弹出资源动画（破坏后爆出→吸附飞向玩家）
------------------------------------------------------------------------
function E.SpawnDropItem(G, x, y, rtype, amount)
    for _ = 1, amount do
        local angle = -math.pi / 2 + (math.random() - 0.5) * math.pi * 0.6  -- 偏上方弹出
        local spd = 100 + math.random() * 60  -- 更大初速度，弹得更高
        local ox = (math.random() - 0.5) * 20
        table.insert(G.dropItems, {
            x = x + ox,
            y = y,
            groundY = y + 8 + math.random() * 6,  -- 落地目标Y（略低于资源位置）
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd,
            rtype = rtype,
            rot = math.random() * math.pi * 2,
            rotSpd = (math.random() - 0.5) * 16,
            phase = "pop",                          -- pop → land → fly
            landTimer = 0,
            flyTimer = 0,
            scale = 1.0,
        })
    end
end

function E.UpdateDropItems(G, dt)
    local p = G.player
    for i = #G.dropItems, 1, -1 do
        local d = G.dropItems[i]
        if d.phase == "pop" then
            -- 弹出阶段：抛物线运动
            d.x = d.x + d.vx * dt
            d.y = d.y + d.vy * dt
            d.vy = d.vy + 280 * dt  -- 重力
            d.vx = d.vx * 0.96
            d.rot = d.rot + d.rotSpd * dt
            -- 落地检测：当y超过groundY时着陆
            if d.vy > 0 and d.y >= d.groundY then
                d.y = d.groundY
                d.phase = "land"
                d.landTimer = 0
                d.rotSpd = 0
                -- 小幅弹跳缩放效果
                d.squash = 0.15
            end
        elseif d.phase == "land" then
            -- 落地停留阶段
            d.landTimer = d.landTimer + dt
            -- 着地压扁恢复
            if d.squash and d.squash > 0 then
                d.squash = d.squash - dt * 0.8
                if d.squash < 0 then d.squash = 0 end
            end
            if d.landTimer >= 0.15 then
                -- 背包有空位才飞向玩家，否则留在地面等待
                if p.carrying < G.maxCarry then
                    -- 检查与玩家距离，靠近时才吸附
                    local dx2 = d.x - p.x
                    local dy2 = d.y - p.y
                    local pickDist = 90  -- 拾取距离
                    if dx2 * dx2 + dy2 * dy2 < pickDist * pickDist then
                        d.phase = "fly"
                        d.flyTimer = 0
                    end
                end
            end
        else
            -- 飞向玩家阶段
            d.flyTimer = d.flyTimer + dt
            local t = math.min(1, d.flyTimer / 0.3)
            t = t * t * (3 - 2 * t)  -- smoothstep
            local tx, ty = p.x, p.y + 10
            d.x = d.x + (tx - d.x) * t * 0.35
            d.y = d.y + (ty - d.y) * t * 0.35
            d.rot = d.rot * (1 - t * 0.1)
            d.scale = 1.0 - t * 0.3  -- 飞向玩家时略微缩小
            if d.flyTimer >= 0.35 then
                -- 到达玩家：背包有空位才拾取，否则退回地面
                if p.carrying < G.maxCarry then
                    p.inv[d.rtype] = p.inv[d.rtype] + 1
                    p.carrying = p.carrying + 1
                    p.carryQueue[#p.carryQueue + 1] = d.rtype
                    swapRemove(G.dropItems, i)
                    goto cont_drop
                else
                    -- 背包满了，退回地面
                    d.phase = "land"
                    d.landTimer = 0.3
                    d.scale = 1.0
                end
            end
        end
        ::cont_drop::
    end
end

------------------------------------------------------------------------
-- 僵尸死亡效果：爆炸粒子 + 地面血迹
------------------------------------------------------------------------

--- 生成僵尸死亡效果（血色爆炸粒子 + 地面血迹）
function E.SpawnZombieDeath(G, x, y)
    -- 1) 绿色爆炸粒子（僵尸血是绿色的）
    local bloodColors = {
        {30, 160, 20}, {20, 130, 10}, {50, 180, 30},
        {15, 140, 0},  {25, 110, 15},
    }
    for _ = 1, 12 do
        local angle = math.random() * math.pi * 2
        local spd = 80 + math.random() * 120
        local c = bloodColors[math.random(1, #bloodColors)]
        table.insert(G.particles, {
            x = x + (math.random() - 0.5) * 8,
            y = y + (math.random() - 0.5) * 8,
            vx = math.cos(angle) * spd,
            vy = math.sin(angle) * spd - 60,
            life = 0.4 + math.random() * 0.5,
            maxLife = 0.9,
            r = c[1], g = c[2], b = c[3],
            size = 3 + math.random() * 4,
        })
    end

    -- 2) 地面血迹
    table.insert(G.bloodStains, {
        x = x,
        y = y,
        life = 6.0 + math.random() * 3.0,  -- 持续6-9秒后淡出
        maxLife = 9.0,
        size = 10 + math.random() * 8,      -- 血迹大小
        angle = math.random() * math.pi * 2,
        -- 2-4个小溅射斑点
        splats = (function()
            local s = {}
            for _ = 1, math.random(2, 4) do
                s[#s + 1] = {
                    dx = (math.random() - 0.5) * 20,
                    dy = (math.random() - 0.5) * 16,
                    sz = 3 + math.random() * 5,
                }
            end
            return s
        end)(),
    })
end

--- 更新血迹（随世界滚动 + 淡出移除）
function E.UpdateBloodStains(G, dt)
    local scrollDelta = (G.lastScrollDelta or 0)
    for i = #G.bloodStains, 1, -1 do
        local b = G.bloodStains[i]
        b.y = b.y - scrollDelta
        b.life = b.life - dt
        if b.life <= 0 or b.y < -50 then
            swapRemove(G.bloodStains, i)
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
    -- 波次开始时 waveProgress=0，仅使用 midWave=false 的丧尸
    local pool = C.GetZombiePool(G.stage, 0)
    if #pool == 0 then return end

    for i = 1, count do
        local row = math.ceil(i / 6)
        local zx = math.random(30, math.floor(W - 30))
        -- 生成在屏幕下方足够远处，避免 Spine 图形露出屏幕底部产生闪烁
        local zy = H + 80 + (row - 1) * 35 + math.random(0, 20)

        local zt = pool[math.random(1, #pool)]
        local zSpeed = C.GetZombieSpeed(zt.speed, G.level)
        local zHP = C.GetZombieHP(zt.hp, G.level)

        -- 分批入场延迟：每行延迟0.15秒，避免大量僵尸同帧分配Spine导致闪烁
        local spawnDelay = (row - 1) * 0.15

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
            zombieType = zt.id,
            zombieDef = zt,
            hp = zHP,
            maxHp = zHP,
            damage = zt.damage,
            drawScale = zt.drawScale,
            spineAnim = "run",
            spineTime = 0,
            spawnDelay = spawnDelay,  -- 入场延迟（秒）
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

    -- 使用新的关卡池系统选择丧尸类型
    local waveProgress = G.waveProgress or 0
    local pool = C.GetZombiePool(G.stage, waveProgress)
    if #pool == 0 then return end

    local zt = pool[math.random(1, #pool)]
    local zSpeed = C.GetZombieSpeed(zt.speed, G.level)
    local zHP = C.GetZombieHP(zt.hp, G.level)

    table.insert(zombies, {
        x = zx,
        y = zy,
        facing = 1,
        phase = math.random() * math.pi * 2,
        speed = zSpeed,
        dead = false,
        hitAnim = 0,
        walkAnim = 0,
        atkTimer = 0,
        atTrain = false,
        zombieType = zt.id,
        zombieDef = zt,
        hp = zHP,
        maxHp = zHP,
        damage = zt.damage,
        drawScale = zt.drawScale,
        spineAnim = "run",       -- 默认播放 run 动画
        spineTime = 0,
    })
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
        -- 入场延迟：倒计时期间不移动不渲染
        if z.spawnDelay and z.spawnDelay > 0 then
            z.spawnDelay = z.spawnDelay - dt
            goto continue_z
        end
        -- 死亡动画播完后才移除
        if z.deadDone then
            if G.onZombieRemoved then G.onZombieRemoved(z) end
            swapRemove(G.zombies, i)
            goto continue_z
        end
        -- 正在播死亡动画：只随世界滚动，不做其他逻辑
        if z.dying then
            z.y = z.y - scrollDelta
            goto continue_z
        end
        -- 刚被标记死亡：启动死亡动画
        if z.dead and not z.dying then
            z.dying = true
            z.dyingTimer = 0
            -- 播放随机死亡动画
            local deadAnims = { "dead_1", "dead_2", "dead_3" }
            local deadAnim = deadAnims[math.random(1, 3)]
            if z.spineInst then
                z.spineInst:SetAnimation(0, deadAnim, false)
            end
            z.spineAnim = deadAnim
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

        if not z.atTrain and dist > 25 then
            -- 向列车移动
            local spd = z.speed * dt
            z.x = z.x + (dx / dist) * spd
            z.y = z.y + (dy / dist) * spd
            z.facing = dx > 0 and 1 or -1
            z.walkAnim = (z.walkAnim or 0) + dt * 8
            z.isWalking = true
        elseif not z.atTrain and dist <= 25 then
            -- 到达列车，开始攻击
            z.isWalking = false
            z.atTrain = true
        end

        if z.atTrain then
            z.atkTimer = z.atkTimer + dt
            if z.atkTimer >= C.ZOMBIE_ATK_INTERVAL then
                z.atkTimer = z.atkTimer - C.ZOMBIE_ATK_INTERVAL
                -- 对列车造成伤害（防御减伤，每种丧尸伤害不同）
                local actualDmg = E.CalcTrainDmgTaken(z.damage or C.ZOMBIE_DAMAGE, G)
                G.trainHP = G.trainHP - actualDmg
                -- 火车伤害数字从火车中部飞出，与僵尸伤害区分
                local trainMidY = (G.cartTopY or 0) + (G.cartH or 100) * 0.45
                E.SpawnFloatText(G, trainCX, trainMidY, "-" .. actualDmg, "train_damage")
                E.SpawnParticles(G, trainCX + math.random(-15, 15), trainBottomY, {200, 195, 180}, 4)
                -- 火车闪红
                G.trainHitFlash = 0.25

                if G.trainHP <= 0 then
                    G.trainHP = 0
                    G.state = "gameover"
                end
            end
        end

        -- 僵尸不能进入火车碰撞体积（推向两侧或下方）
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
            if G.onZombieRemoved then G.onZombieRemoved(z) end
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
    p.y = (G.cartBottomY or 200) - 125  -- 放到车头位置（火车向下行驶，车头在底部）
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
    p.y = (G.cartBottomY or 200) - 125
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

    -- 上车攻击冷却（比步行更快）
    local atkInterval = 0.55 / (G.atkSpdMul or 1.0)
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

    -- 更新枪口开火帧动画
    if G.muzzleFlash then
        G.muzzleFlash.elapsed = G.muzzleFlash.elapsed + dt
        if G.muzzleFlash.elapsed >= G.muzzleFlash.timer then
            G.muzzleFlash = nil
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
    local baseDmg = (30 + (G.rangedAtkBonus or 0)) * (G.rangedAtkMul or 1.0)  -- 初始30 + 远程加成（含倍率）
    local dmg, isCrit = E.CalcDamage(baseDmg, G)

    if not G.turretProjectiles then G.turretProjectiles = {} end

    -- 子弹从枪口位置发射（沿瞄准方向偏移）
    local muzzleOffset = 28
    local startX = p.x + math.cos(angle) * muzzleOffset
    local startY = p.y + math.sin(angle) * muzzleOffset

    local proj = {
        type = "mounted_bullet",
        x = startX, y = startY,
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

    -- 触发枪口开火帧动画
    G.muzzleFlash = {
        timer = 0.12,       -- 总持续时间
        elapsed = 0,        -- 已过时间
        angle = angle,      -- 开火方向
        x = startX,         -- 枪口位置
        y = startY,
    }
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
        -- 治疗：立即回复列车20%最大生命值
        local healAmount = math.floor((G.trainMaxHP or 1000) * 0.2)
        G.trainHP = math.min((G.trainHP or 0) + healAmount, G.trainMaxHP or 1000)
        -- 瞬发技能，无持续时间
        G.skillCharActive = false
        G.skillCharDuration = 0
        E.SpawnFloatText(G, G.screenW / 2, (G.hudH or 60) + 30, "+" .. healAmount, "heal")
        print("[Skill] Auntie heal! Train HP +" .. healAmount .. " => " .. G.trainHP)

    elseif charId == "lisanguang" then
        -- 战斗狂怒：7秒内攻速+100%
        G.skillCharActive = true
        G.skillCharDurationMax = 7
        G.skillCharDuration = 7
        G.atkSpdMul = (G.atkSpdMul or 1.0) * 2.0
        print("[Skill] Lisanguang fury activated! AtkSpd x2 for 7s")

    elseif charId == "weifenglong" then
        -- 喷气：向最后移动方向快速位移，带移动轨迹
        local p = G.player
        -- 计算位移方向
        local dx = p.facing or 1
        local dy = 0
        if G._lastMoveY and math.abs(G._lastMoveY) > 0.3 then
            dy = G._lastMoveY > 0 and 1 or -1
        end
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then
            dx = dx / len
            dy = dy / len
        end
        -- 设置冲刺状态（在 UpdatePlayer 中逐帧推进）
        G.jetDash = {
            dirX = dx,
            dirY = dy,
            speed = 800,            -- 冲刺速度（像素/秒）
            remaining = 150,        -- 剩余位移距离（像素）
            trailTimer = 0,         -- 轨迹粒子计时
        }
        G.skillCharActive = true
        G.skillCharDurationMax = 0.3
        G.skillCharDuration = 0.3
        print("[Skill] Dragon jet dash start! dir=(" .. dx .. "," .. dy .. ")")
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
        -- 治疗是瞬发技能，无持续效果需要清理
        print("[Skill] Auntie heal ended (no-op)")
    elseif charId == "weifenglong" then
        -- 喷气是瞬发技能，无持续效果需要清理
        print("[Skill] Dragon jet ended (no-op)")
    end
    G.skillCharActive = false
    G.skillCharDuration = 0
end

------------------------------------------------------------------------
-- 炸弹系统
------------------------------------------------------------------------

--- 炸弹爆炸：对范围内敌人和资源造成伤害
function E.ExplodeBomb(G, bomb)
    local baseDmg = math.floor((C.PLAYER_ATK + (G.meleeAtkBonus or 0)) * (G.meleeAtkMul or 1.0) * bomb.dmgMul)
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
                E.SpawnFloatText(G, z.x, z.y - 10, tostring(atkPower), "damage")
                hits = hits + 1
                if z.hp <= 0 then
                    z.dead = true
                    G.killCount = (G.killCount or 0) + 1
                    E.SpawnZombieDeath(G, z.x, z.y)
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
                    -- 弹出资源动画
                    local resInfo = C.RES[res.rtype]
                    if resInfo then
                        local p = G.player
                        local amount = resInfo.drop or 1
                        local actual = math.min(amount, G.maxCarry - p.carrying)
                        if actual > 0 then
                            E.SpawnDropItem(G, res.x, res.y, res.rtype, actual)
                            E.SpawnFloatText(G, res.x, res.y - 10, "+" .. actual, res.rtype)
                        end
                    end
                    E.SpawnPuff(G, res.x, res.y)
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

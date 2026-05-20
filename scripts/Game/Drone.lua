------------------------------------------------------------------------
-- Drone.lua  —— 自动采集无人机系统
-- 通过肉鸽升级卡解锁，自动飞向资源采集后飞回放置点投递
-- 状态机: idle → flying_to → collecting → flying_back → idle
------------------------------------------------------------------------
local C = require "Game.Config"
local E = require "Game.Entities"
local D = {}

------------------------------------------------------------------------
-- 常量
------------------------------------------------------------------------
local DRONE = C.DRONE or {}
local SPEED        = DRONE.SPEED or 200
local COLLECT_TIME = DRONE.COLLECT_TIME or 0.3
local SEARCH_RADIUS = DRONE.SEARCH_RADIUS or 300
local MAX_COUNT    = DRONE.MAX_COUNT or 3
local SIZE         = DRONE.SIZE or 40
local HOVER_AMP    = DRONE.HOVER_AMP or 4
local HOVER_FREQ   = DRONE.HOVER_FREQ or 2

------------------------------------------------------------------------
-- 初始化
------------------------------------------------------------------------
function D.Init(G)
    G.drones = G.drones or {}
end

------------------------------------------------------------------------
-- 解锁一架无人机（升级卡调用）
------------------------------------------------------------------------
function D.UnlockDrone(G)
    if not G.drones then G.drones = {} end
    if #G.drones >= MAX_COUNT then
        print("[Drone] Max drone count reached (" .. MAX_COUNT .. ")")
        return false
    end

    -- 无人机初始位置在列车上方
    local cx = G.cartCenterX or (G.screenW / 2)
    local cy = (G.cartTopY or 100) - 20
    table.insert(G.drones, {
        x = cx,
        y = cy,
        state = "idle",       -- idle / flying_to / collecting / flying_back
        target = nil,         -- 目标资源引用
        targetX = 0,
        targetY = 0,
        collectTimer = 0,     -- 采集计时
        hoverPhase = math.random() * math.pi * 2,
        tilt = math.pi,       -- 旋转角（π=头朝下悬停）
        carryType = nil,      -- 携带的资源类型
        carryAmount = 0,      -- 携带的资源数量
    })
    print("[Drone] Unlocked drone #" .. #G.drones)
    return true
end

------------------------------------------------------------------------
-- 获取已解锁无人机数量
------------------------------------------------------------------------
function D.GetCount(G)
    return G.drones and #G.drones or 0
end

------------------------------------------------------------------------
-- 查找最近的未被 claim 的资源
------------------------------------------------------------------------
local function findNearestResource(G, drone)
    local bestDist = SEARCH_RADIUS * SEARCH_RADIUS
    local best = nil
    for _, r in ipairs(G.resources) do
        if not r.dead and not r.claimedByDrone and r.hp > 0 then
            -- 只搜索屏幕可见范围内的资源
            if r.y > (G.hudH or 48) and r.y < (G.screenH or 800) then
                local dx = r.x - drone.x
                local dy = r.y - drone.y
                local distSq = dx * dx + dy * dy
                if distSq < bestDist then
                    bestDist = distSq
                    best = r
                end
            end
        end
    end
    return best
end

------------------------------------------------------------------------
-- 获取悬停点坐标（放置点上方，idle时停留）
------------------------------------------------------------------------
local function getHoverPoint(G)
    local sb = G.submitBox
    if sb then
        return sb.x, sb.y - 20
    end
    local cx = G.cartCenterX or (G.screenW / 2)
    local cy = (G.cartTopY or 100) - 20
    return cx, cy
end

------------------------------------------------------------------------
-- 获取投递点坐标（submitBox 资源放置点）
------------------------------------------------------------------------
local function getDropPoint(G)
    local sb = G.submitBox
    if sb then
        return sb.x, sb.y
    end
    local cx = G.cartCenterX or (G.screenW / 2)
    local cy = (G.cartTopY or 100)
    return cx, cy
end

------------------------------------------------------------------------
-- 采集资源（击破资源，记录携带物）
------------------------------------------------------------------------
local function collectResource(G, drone, res)
    if not res or res.dead then return end

    res.dead = true
    local resInfo = C.RES[res.rtype]
    if not resInfo then return end

    local amount = resInfo.drop or 1
    -- 双倍检测
    if (G.doubleMul or 0) > 0 and math.random() < G.doubleMul then
        amount = amount * 2
    end

    -- 记录携带物（飞回放置点后才真正增加）
    drone.carryType = res.rtype
    drone.carryAmount = amount

    -- 采集特效
    local rc = C.CLR.wood_color
    if res.rtype == "stone" then rc = C.CLR.stone_color
    elseif res.rtype == "ore" then rc = C.CLR.ore_color
    elseif res.rtype == "bush" then rc = C.CLR.bush_color
    elseif res.rtype == "pebble" then rc = C.CLR.pebble_color end
    E.SpawnParticles(G, res.x, res.y, rc, 5)
end

------------------------------------------------------------------------
-- 投递资源（到达放置点后，与玩家提交逻辑一致）
------------------------------------------------------------------------
local function deliverResource(G, drone)
    if not drone.carryType or drone.carryAmount <= 0 then return end

    local amount = drone.carryAmount
    local dropX, dropY = getDropPoint(G)

    -- 1) 增加资源总量
    G.totalRes[drone.carryType] = (G.totalRes[drone.carryType] or 0) + amount

    -- 2) 增加关卡进度（与玩家提交一致）
    G.levelProgress = G.levelProgress + amount

    -- 3) 奖励金币（与玩家提交一致）
    local goldEarned = math.floor(amount * C.GOLD_PER_SUBMIT * (G.goldMul or 1))
    G.gold = (G.gold or 0) + goldEarned

    -- 4) 检查通关
    if G.levelProgress >= G.levelTarget then
        G.pendingLevelUp = true
    end

    -- 浮动文字：显示金币奖励
    E.SpawnFloatText(G, dropX, dropY - 15, "+" .. goldEarned, "gold")

    -- 投递特效
    E.SpawnParticles(G, dropX, dropY, {255, 220, 80}, 5)

    drone.carryType = nil
    drone.carryAmount = 0
end

------------------------------------------------------------------------
-- 更新所有无人机
------------------------------------------------------------------------
function D.Update(G, dt)
    if not G.drones then return end

    for _, drone in ipairs(G.drones) do
        drone.hoverPhase = drone.hoverPhase + dt * HOVER_FREQ * math.pi * 2

        if drone.state == "idle" then
            -- 悬停在放置点上方，搜索目标
            local homeCX, homeCY = getHoverPoint(G)
            local dx = homeCX - drone.x
            local dy = homeCY - drone.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 2 then
                local moveSpd = SPEED * 0.5 * dt
                drone.x = drone.x + (dx / dist) * math.min(moveSpd, dist)
                drone.y = drone.y + (dy / dist) * math.min(moveSpd, dist)
            end
            -- 悬停时头朝下(π)，平滑归位
            local idleDiff = math.pi - drone.tilt
            while idleDiff > math.pi do idleDiff = idleDiff - 2 * math.pi end
            while idleDiff < -math.pi do idleDiff = idleDiff + 2 * math.pi end
            drone.tilt = drone.tilt + idleDiff * 0.1

            -- 搜索最近资源
            local res = findNearestResource(G, drone)
            if res then
                drone.target = res
                drone.targetX = res.x
                drone.targetY = res.y
                res.claimedByDrone = true
                drone.state = "flying_to"
            end

        elseif drone.state == "flying_to" then
            -- 飞向目标资源
            local target = drone.target
            if not target or target.dead then
                if target then target.claimedByDrone = false end
                drone.target = nil
                drone.state = "idle"
            else
                drone.targetX = target.x
                drone.targetY = target.y

                local dx = drone.targetX - drone.x
                local dy = drone.targetY - drone.y
                local dist = math.sqrt(dx * dx + dy * dy)

                -- 飞行朝向
                if dist > 1 then
                    local targetAngle = math.atan(dy, dx) + math.pi * 0.5
                    local diff = targetAngle - drone.tilt
                    while diff > math.pi do diff = diff - 2 * math.pi end
                    while diff < -math.pi do diff = diff + 2 * math.pi end
                    drone.tilt = drone.tilt + diff * math.min(1, dt * 8)
                end

                if dist < 8 then
                    drone.state = "collecting"
                    drone.collectTimer = COLLECT_TIME
                else
                    local moveSpd = SPEED * dt
                    drone.x = drone.x + (dx / dist) * math.min(moveSpd, dist)
                    drone.y = drone.y + (dy / dist) * math.min(moveSpd, dist)
                end
            end

        elseif drone.state == "collecting" then
            -- 采集停留
            drone.collectTimer = drone.collectTimer - dt
            drone.tilt = drone.tilt + math.sin(drone.hoverPhase * 3) * 0.005

            if drone.collectTimer <= 0 then
                local target = drone.target
                if target and not target.dead then
                    collectResource(G, drone, target)
                end
                if target then target.claimedByDrone = false end
                drone.target = nil
                -- 采集完成，飞回放置点
                drone.state = "flying_back"
            end

        elseif drone.state == "flying_back" then
            -- 飞回资源放置点（submitBox）
            local dropX, dropY = getDropPoint(G)
            local dx = dropX - drone.x
            local dy = dropY - drone.y
            local dist = math.sqrt(dx * dx + dy * dy)

            -- 飞行朝向
            if dist > 1 then
                local targetAngle = math.atan(dy, dx) + math.pi * 0.5
                local diff = targetAngle - drone.tilt
                while diff > math.pi do diff = diff - 2 * math.pi end
                while diff < -math.pi do diff = diff + 2 * math.pi end
                drone.tilt = drone.tilt + diff * math.min(1, dt * 8)
            end

            if dist < 10 then
                -- 到达放置点，投递资源
                deliverResource(G, drone)
                drone.state = "idle"
            else
                local moveSpd = SPEED * dt
                drone.x = drone.x + (dx / dist) * math.min(moveSpd, dist)
                drone.y = drone.y + (dy / dist) * math.min(moveSpd, dist)
            end
        end
    end
end

------------------------------------------------------------------------
-- 绘制所有无人机
------------------------------------------------------------------------
function D.Draw(vg, G)
    if not G.drones or not G.droneImg or G.droneImg == 0 then return end

    local img = G.droneImg
    for _, drone in ipairs(G.drones) do
        local drawX = drone.x
        local drawY = drone.y + math.sin(drone.hoverPhase) * HOVER_AMP
        local halfS = SIZE / 2

        nvgSave(vg)
        nvgTranslate(vg, drawX, drawY)
        nvgRotate(vg, drone.tilt)

        -- 绘制无人机图片
        local paint = nvgImagePattern(vg, -halfS, -halfS, SIZE, SIZE, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, -halfS, -halfS, SIZE, SIZE)
        nvgFillPaint(vg, paint)
        nvgFill(vg)

        nvgRestore(vg)
    end
end

return D

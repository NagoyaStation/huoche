-- Game/Roguelike.lua - 升级系统：三选一强化
local C = require "Game.Config"
local Ent = require "Game.Entities"
local Turret = require "Game.Turret"
local Drone = require "Game.Drone"
local RL = {}

------------------------------------------------------------------------
-- 模块级常量（避免每帧匿名表分配）
------------------------------------------------------------------------
local STROKE_DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

------------------------------------------------------------------------
-- 工具 (必须在使用之前定义)
------------------------------------------------------------------------
local function clr(c, a)
    return nvgRGBA(c[1], c[2], c[3], a or c[4] or 255)
end

------------------------------------------------------------------------
-- 升级准备
------------------------------------------------------------------------
function RL.PrepareUpgrade(G)
    -- 收集已解锁的炮塔类型（局内已拥有的）
    local unlockedTypes = {}
    for _, t in ipairs(G.turrets or {}) do
        unlockedTypes[t.typeKey] = true
    end
    local slotsLeft = #Turret.SLOTS - Turret.GetUnlockedCount(G)

    -- 局外装备的炮台集合（只有装备了的才能在升级中刷到）
    local equippedSet = {}
    for _, tid in ipairs(G.equippedTurrets or {}) do
        if tid then equippedSet[tid] = true end
    end

    -- 第一次强化（level==1）：必定全是武器（炮塔解锁卡）
    local isFirstUpgrade = (G.level == 1)

    -- 过滤可用卡
    local available = {}
    for i = 1, #C.UPGRADES do
        local card = C.UPGRADES[i]
        if card.isTurret then
            -- 炮塔解锁卡：槽位有空 + 该类型尚未解锁 + 该类型在局外已装备
            if slotsLeft > 0 and not unlockedTypes[card.turretType] and equippedSet[card.turretType] then
                table.insert(available, i)
            end
        elseif card.isTurretUpgrade then
            -- 炮塔升级卡：该炮塔已在局内解锁才显示，且不是第一次升级
            if not isFirstUpgrade and unlockedTypes[card.turretType] then
                -- 局外等级门控：卡片有 unlockLevel 时，需局外炮塔等级 >= unlockLevel
                if card.unlockLevel then
                    local metaLv = (G.metaTurretLevels and G.metaTurretLevels[card.turretType]) or 0
                    if metaLv < card.unlockLevel then
                        goto continueFilter
                    end
                end
                -- 传说(4)/至臻(5)卡 / 机制卡已获得过则不再刷出
                if (card.fixedQuality and card.fixedQuality >= 4 or card.isMechanism) and G.acquiredMechCards and G.acquiredMechCards[card.id] then
                    goto continueFilter
                end
                -- 高品质卡品质门控：按当前等级的品质权重决定是否出现
                if card.fixedQuality and card.fixedQuality >= 4 then
                    local mechQ = card.fixedQuality
                    local w = C.QUALITY_WEIGHTS[math.min(G.level, 10)]
                    local total = 0
                    for qi = 1, 5 do total = total + w[qi] end
                    local chance = 0
                    for qi = mechQ, 5 do chance = chance + w[qi] end
                    if math.random() * total > chance then
                        goto continueFilter
                    end
                end
                -- 有前置条件的卡（如[机制]强化卡）需先满足前置
                if not card.prereq or card.prereq(G) then
                    table.insert(available, i)
                end
            end
        elseif card.isDrone then
            -- 无人机卡：数量未达上限
            if Drone.GetCount(G) < (C.DRONE.MAX_COUNT or 3) then
                if not isFirstUpgrade then
                    table.insert(available, i)
                end
            end
        else
            if not isFirstUpgrade then
                table.insert(available, i)
            end
        end
        ::continueFilter::
    end
    -- 打乱
    for i = #available, 2, -1 do
        local j = math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end

    -- 前6次强化：炮塔解锁卡排到最前，确保4种武器尽早解锁
    if G.level <= 6 then
        local turretCards = {}
        local otherCards  = {}
        for _, idx in ipairs(available) do
            if C.UPGRADES[idx].isTurret then
                table.insert(turretCards, idx)
            else
                table.insert(otherCards, idx)
            end
        end
        if #turretCards > 0 then
            available = {}
            for _, idx in ipairs(turretCards) do table.insert(available, idx) end
            for _, idx in ipairs(otherCards)  do table.insert(available, idx) end
        end
    end

    -- 如果第一次升级但炮塔卡不够3张，用非炮塔卡补满
    if isFirstUpgrade and #available < 3 then
        local extras = {}
        for i = 1, #C.UPGRADES do
            local card = C.UPGRADES[i]
            if not card.isTurret then
                if card.isDrone then
                    if Drone.GetCount(G) < (C.DRONE.MAX_COUNT or 3) then
                        table.insert(extras, i)
                    end
                elseif card.isTurretUpgrade then
                    -- 炮塔升级卡：必须局内已解锁该炮塔才能进入备选
                    if unlockedTypes[card.turretType] then
                        if not card.prereq or card.prereq(G) then
                            table.insert(extras, i)
                        end
                    end
                else
                    table.insert(extras, i)
                end
            end
        end
        for i = #extras, 2, -1 do
            local j = math.random(1, i)
            extras[i], extras[j] = extras[j], extras[i]
        end
        local need = 3 - #available
        for i = 1, math.min(need, #extras) do
            table.insert(available, extras[i])
        end
    end

    G.upgradeCards = {}
    for i = 1, math.min(3, #available) do
        local card = C.UPGRADES[available[i]]
        -- 为每张卡 roll 品质
        local quality
        if card.isTurret or card.isDrone then
            -- 炮塔/无人机解锁卡只有1级品质，不分品质
            quality = 1
        elseif card.fixedQuality then
            -- 固定品质卡（如[机制]强化卡固定为史诗紫色3）
            quality = card.fixedQuality
        else
            quality = C.RollQuality(G.level)
        end
        -- clamp 到实际 tiers 数量（只用于取 tier 内容，fixedQuality 不受影响）
        local tierCount = #card.tiers
        local tierIndex = math.min(quality, tierCount)
        local tier = card.tiers[tierIndex]
        -- [机制] 类强制品质：最高阶→至臻(红5)，其余阶→传说(金4)
        -- 注意：有 fixedQuality 的卡（强化卡）跳过此逻辑
        if not card.isTurret and not card.isDrone and not card.fixedQuality
            and card.isMechanism then
            if quality >= tierCount then
                quality = 5
            else
                quality = 4
            end
        end
        table.insert(G.upgradeCards, {
            id              = card.id,
            name            = card.name,
            icon            = card.icon,
            isTurret        = card.isTurret,
            isTurretUpgrade = card.isTurretUpgrade,
            isDrone         = card.isDrone,
            isMechanism     = card.isMechanism,
            turretType      = card.turretType,
            quality         = quality,       -- 品质等级 1~6
            desc            = tier.desc,     -- 该品质的描述
            apply           = tier.apply,    -- 该品质的 apply
        })
    end
    G.upgradeCardBtns = {}
    -- 提前把进度切到下一级（溢出不保留，避免跳关）
    G.level = G.level + 1
    local N = G.level
    local acc = math.max(0, N - 3)
    G.levelTarget = math.ceil(C.BASE_TARGET + (N - 1) * C.TARGET_BASE_STEP + acc * acc * C.TARGET_ACCEL)
    G.levelProgress = 0

    -- 清除正在飞行的提交资源（防止飞行中的资源到达后继续加进度）
    if G.submitFlyItems then
        G.submitFlyItems = {}
    end

    -- 先播升级特效，再弹面板
    G.state = "upgradeVfx"
    G.upgradeVfxTimer = 0
    G.upgradeVfxDuration = 0.85  -- 特效持续时间（符文慢飘）
    G.upgradePanelAnim = 0      -- 面板弹出动画进度 0→1
    G.upgradeCardEnterTimer = 0 -- 卡片入场动画计时器
    G.upgradeGlowTime = 0       -- 品质光晕时钟

    -- 升级奖励金币
    G.gold = G.gold + C.GOLD_PER_LEVEL
    -- 同步更新saveData金币
    local sd = G.saveData
    if sd then sd.gold = (sd.gold or 0) + C.GOLD_PER_LEVEL end
    Ent.SpawnFloatText(G, G.screenW / 2, G.screenH * 0.4, "+" .. C.GOLD_PER_LEVEL .. " Gold!", "gold")
end

------------------------------------------------------------------------
-- 应用升级
------------------------------------------------------------------------
function RL.ApplyUpgrade(G, cardIndex)
    -- 如果正在播选中动画，忽略点击
    if G.upgradeSelectedCard then return end

    -- 启动选中动画
    G.upgradeSelectedCard = cardIndex
    G.upgradeSelectedTimer = 0
    G.upgradeSelectedDuration = 0.45  -- 放大+闪动持续时间
end

-- 真正执行升级（选中动画播完后调用）
function RL.DoApplyUpgrade(G)
    local cardIndex = G.upgradeSelectedCard
    G.upgradeSelectedCard = nil

    local card = G.upgradeCards[cardIndex]
    if card and card.apply then
        card.apply(G)
        local qLabel = C.QUALITY_NAMES[card.quality or 1] or "普通"
        print("[Upgrade] Applied: [" .. qLabel .. "] " .. card.name .. " - " .. card.desc)
        -- 传说(4)/至臻(5)卡 / 机制卡记录已获得，不再刷出
        if card.quality >= 4 or card.isMechanism then
            if not G.acquiredMechCards then G.acquiredMechCards = {} end
            G.acquiredMechCards[card.id] = true
        end
    end

    -- 恢复游戏（level/progress 已在 PrepareUpgrade 中切换）
    G.state = "playing"
    G.upgradeCards = {}
    G.pendingLevelUp = false

    -- 重置关卡距离起点
    G.levelStartDist = math.floor(G.distance / 10)

    -- 提示
    G.hintText = "Lv." .. G.level .. " 目标: " .. G.levelTarget .. " 资源"
    G.hintTimer = 4.0

    Ent.SpawnParticles(G, G.screenW / 2, G.screenH * 0.4, {255, 220, 80}, 15)
end

------------------------------------------------------------------------
-- 刷新强化卡（重新 roll 三张卡，概率偏向高品质）
------------------------------------------------------------------------
function RL.RefreshUpgradeCards(G)
    -- 暂时提升等级用于 roll（模拟更高概率出紫色以上）
    local savedLevel = G.level
    -- 等效提升3级来 roll 品质（让紫色以上概率显著提高）
    G.level = math.min(10, G.level + 3)

    -- 重新调用 PrepareUpgrade 的卡池逻辑（不改 level/progress）
    -- 保存当前 level 状态
    local savedState = G.state
    local savedProgress = G.levelProgress
    local savedTarget = G.levelTarget
    local savedActualLevel = savedLevel  -- 实际 level（PrepareUpgrade 会 +1）

    -- 手动 roll 新卡（复用 PrepareUpgrade 的过滤逻辑但不改状态）
    local unlockedTypes = {}
    for _, t in ipairs(G.turrets or {}) do
        unlockedTypes[t.typeKey] = true
    end
    local slotsLeft = #Turret.SLOTS - Turret.GetUnlockedCount(G)
    local equippedSet = {}
    for _, tid in ipairs(G.equippedTurrets or {}) do
        if tid then equippedSet[tid] = true end
    end

    local available = {}
    for i = 1, #C.UPGRADES do
        local card = C.UPGRADES[i]
        if card.isTurret then
            if slotsLeft > 0 and not unlockedTypes[card.turretType] and equippedSet[card.turretType] then
                table.insert(available, i)
            end
        elseif card.isTurretUpgrade then
            if unlockedTypes[card.turretType] then
                if (card.fixedQuality and card.fixedQuality >= 4 or card.isMechanism) and G.acquiredMechCards and G.acquiredMechCards[card.id] then
                    goto continueRefresh
                end
                if card.fixedQuality and card.fixedQuality >= 4 or card.isMechanism then
                    local mechQ = card.fixedQuality or 5
                    local w = C.QUALITY_WEIGHTS[math.min(G.level, 10)]
                    local total = 0
                    for qi = 1, 5 do total = total + w[qi] end
                    local chance = 0
                    for qi = mechQ, 5 do chance = chance + w[qi] end
                    if math.random() * total > chance then
                        goto continueRefresh
                    end
                end
                if not card.prereq or card.prereq(G) then
                    table.insert(available, i)
                end
            end
        elseif card.isDrone then
            if Drone.GetCount(G) < (C.DRONE.MAX_COUNT or 3) then
                table.insert(available, i)
            end
        else
            table.insert(available, i)
        end
        ::continueRefresh::
    end

    -- 打乱
    for i = #available, 2, -1 do
        local j = math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end

    -- Roll 新卡
    G.upgradeCards = {}
    for i = 1, math.min(3, #available) do
        local card = C.UPGRADES[available[i]]
        local quality
        if card.isTurret or card.isDrone then
            quality = 1
        elseif card.fixedQuality then
            quality = card.fixedQuality
        else
            quality = C.RollQuality(G.level)  -- 用提升后的 level roll
        end
        local tierCount = #card.tiers
        local tierIndex = math.min(quality, tierCount)
        local tier = card.tiers[tierIndex]
        if not card.isTurret and not card.isDrone and not card.fixedQuality
            and card.isMechanism then
            if quality >= tierCount then
                quality = 5
            else
                quality = 4
            end
        end
        table.insert(G.upgradeCards, {
            id              = card.id,
            name            = card.name,
            icon            = card.icon,
            isTurret        = card.isTurret,
            isTurretUpgrade = card.isTurretUpgrade,
            isDrone         = card.isDrone,
            isMechanism     = card.isMechanism,
            turretType      = card.turretType,
            quality         = quality,
            desc            = tier.desc,
            apply           = tier.apply,
        })
    end

    -- 恢复真实等级
    G.level = savedLevel
    -- 重置卡片入场动画
    G.upgradeCardEnterTimer = 0
    G.upgradeCardBtns = {}
    print("[Upgrade] Refreshed cards (boosted level " .. math.min(10, savedLevel + 3) .. ")")
end

------------------------------------------------------------------------
-- 刷新点击处理（免费1次，之后消耗钻石）
------------------------------------------------------------------------
function RL.HandleRefreshClick(G)
    if G.upgradeSelectedCard then return end  -- 正在播动画

    if (G.refreshFreeLeft or 0) > 0 then
        -- 免费刷新
        G.refreshFreeLeft = G.refreshFreeLeft - 1
        RL.RefreshUpgradeCards(G)
        print("[Upgrade] Free refresh used, remaining: " .. G.refreshFreeLeft)
    else
        -- 消耗钻石刷新
        local Meta = require "Meta.MetaMain"
        local sd = Meta.GetSaveData()
        local cost = C.REFRESH_DIAMOND_COST or 30
        if sd.diamond >= cost then
            sd.diamond = sd.diamond - cost
            RL.RefreshUpgradeCards(G)
            print("[Upgrade] Diamond refresh used, cost: " .. cost .. ", remaining diamonds: " .. sd.diamond)
        else
            print("[Upgrade] Not enough diamonds for refresh, need: " .. cost .. ", have: " .. sd.diamond)
        end
    end
end

------------------------------------------------------------------------
-- 获取全部（消耗钻石）点击处理
------------------------------------------------------------------------
function RL.HandleGetAllClick(G)
    if G.upgradeSelectedCard then return end  -- 正在播动画

    local Meta = require "Meta.MetaMain"
    local sd = Meta.GetSaveData()
    local cost = C.GETALL_DIAMOND_COST or 50
    if sd.diamond < cost then
        print("[Upgrade] Not enough diamonds for getAll, need: " .. cost .. ", have: " .. sd.diamond)
        return
    end

    -- 消耗钻石
    sd.diamond = sd.diamond - cost
    print("[Upgrade] GetAll used, cost: " .. cost .. ", remaining diamonds: " .. sd.diamond)

    -- 应用所有3张卡效果
    for _, card in ipairs(G.upgradeCards) do
        if card and card.apply then
            card.apply(G)
            local qLabel = C.QUALITY_NAMES[card.quality or 1] or "普通"
            print("[Upgrade] GetAll applied: [" .. qLabel .. "] " .. card.name)
            -- 记录机制卡
            if card.quality >= 4 or card.isMechanism then
                if not G.acquiredMechCards then G.acquiredMechCards = {} end
                G.acquiredMechCards[card.id] = true
            end
        end
    end

    -- 恢复游戏
    G.state = "playing"
    G.upgradeCards = {}
    G.pendingLevelUp = false
    G.levelStartDist = math.floor(G.distance / 10)
    G.hintText = "Lv." .. G.level .. " 目标: " .. G.levelTarget .. " 资源"
    G.hintTimer = 4.0
    Ent.SpawnParticles(G, G.screenW / 2, G.screenH * 0.4, {255, 220, 80}, 15)
    print("[Upgrade] GetAll complete, remaining: " .. G.getAllVideoLeft)
end

------------------------------------------------------------------------
-- 品质色定义（6 级）
------------------------------------------------------------------------
local QUALITY_COLORS = {
    { 162, 255, 148 },  -- 1 优质
    { 114, 242, 245 },  -- 2 稀有
    { 239, 121, 255 },  -- 3 史诗
    { 255, 237, 0   },  -- 4 传说
    { 255, 0,   0   },  -- 5 至臻
}
local QUALITY_NAMES = { "优质", "稀有", "史诗", "传说", "至臻" }

------------------------------------------------------------------------
-- 卡牌品质边框特效（仿装备光效：外发光+角落闪光+流光）
-- quality: 1-5，对应优质/稀有/史诗/传说/至臻
------------------------------------------------------------------------
-- 外发光层数、呼吸速度、角落闪光、流光
local CARD_QUALITY_FX = {
    [1] = { glowLayers = 1, breathSpeed = 1.2, breathAmp = 0.15, sparkles = 0, flowLight = false },
    [2] = { glowLayers = 2, breathSpeed = 1.8, breathAmp = 0.20, sparkles = 0, flowLight = false },
    [3] = { glowLayers = 3, breathSpeed = 2.2, breathAmp = 0.28, sparkles = 4, flowLight = false },
    [4] = { glowLayers = 4, breathSpeed = 2.8, breathAmp = 0.35, sparkles = 4, flowLight = true  },
    [5] = { glowLayers = 5, breathSpeed = 3.2, breathAmp = 0.40, sparkles = 6, flowLight = true  },
}

local function DrawCardQualityBorder(vg, x, y, w, h, quality, r, g, b, t)
    local fx = CARD_QUALITY_FX[quality] or CARD_QUALITY_FX[1]
    local radius = 12

    -- 呼吸因子
    local breath = 0
    if fx.breathSpeed > 0 then
        breath = (math.sin(t * fx.breathSpeed) * 0.5 + 0.5) * fx.breathAmp
    end
    local baseAlpha = 0.55 + breath

    nvgSave(vg)

    -- == 1. 外发光层（由外向内 alpha 递减，贴着卡牌边缘往外扩）==
    local inset = 2
    if fx.glowLayers > 0 then
        for i = fx.glowLayers, 1, -1 do
            local expand   = i * 1.8 - inset
            local layerA   = math.floor(baseAlpha * (0.28 / i) * 255)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x - expand, y - expand,
                               w + expand * 2, h + expand * 2,
                               radius + expand)
            nvgStrokeColor(vg, nvgRGBA(r, g, b, layerA))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end

    -- == 2. 主边框（实色）==
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + inset, y + inset, w - inset * 2, h - inset * 2,
                   math.max(1, radius - inset))
    nvgStrokeColor(vg, nvgRGBA(r, g, b, math.floor(baseAlpha * 255)))
    nvgStrokeWidth(vg, quality >= 4 and 1.5 or 1)
    nvgStroke(vg)

    -- == 3. 角落闪光粒子 ==
    if fx.sparkles > 0 then
        local ci = inset
        local corners = {
            { x = x + ci,         y = y + ci         },
            { x = x + w - ci,     y = y + ci         },
            { x = x + w - ci,     y = y + h - ci     },
            { x = x + ci,         y = y + h - ci     },
        }
        local sparklePts = {}
        for si = 1, math.min(4, fx.sparkles) do
            sparklePts[#sparklePts + 1] = corners[si]
        end
        if fx.sparkles >= 6 then
            sparklePts[#sparklePts + 1] = { x = x + w / 2, y = y + ci }
            sparklePts[#sparklePts + 1] = { x = x + w / 2, y = y + h - ci }
        end
        for si, sp in ipairs(sparklePts) do
            local phase      = t * 4.0 + si * 1.57
            local sparkAlpha = math.max(0, math.sin(phase)) * baseAlpha
            if sparkAlpha > 0.05 then
                local ss  = 2.5 + sparkAlpha * 2.5
                local sa  = math.floor(sparkAlpha * 255)
                -- 十字
                nvgBeginPath(vg)
                nvgMoveTo(vg, sp.x - ss, sp.y)
                nvgLineTo(vg, sp.x + ss, sp.y)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, sa))
                nvgStrokeWidth(vg, 1.5) nvgStroke(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, sp.x, sp.y - ss)
                nvgLineTo(vg, sp.x, sp.y + ss)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, sa))
                nvgStrokeWidth(vg, 1.5) nvgStroke(vg)
                -- 中心亮点
                nvgBeginPath(vg)
                nvgCircle(vg, sp.x, sp.y, 1.5)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, sa)) nvgFill(vg)
            end
        end
    end

    -- == 4. 流光（沿内缩边框路径流动）==
    if fx.flowLight then
        local iw, ih = w - inset * 2, h - inset * 2
        local ix2, iy2 = x + inset, y + inset
        local perimeter = 2 * (iw + ih)
        local flowSpeed = quality >= 5 and 1.2 or 0.8
        local function perimToXY(p)
            p = p % perimeter
            if p < iw then
                return ix2 + p, iy2
            elseif p < iw + ih then
                return ix2 + iw, iy2 + (p - iw)
            elseif p < 2 * iw + ih then
                return ix2 + iw - (p - iw - ih), iy2 + ih
            else
                return ix2, iy2 + ih - (p - 2 * iw - ih)
            end
        end
        local tailLen  = perimeter * 0.25
        local headPos  = (t * flowSpeed * perimeter / 4) % perimeter
        local segments = 12
        local segLen   = tailLen / segments
        -- 白色流光头
        for si = 0, segments - 1 do
            local p1 = headPos - si * segLen
            local p2 = headPos - (si + 1) * segLen
            local lx1, ly1 = perimToXY(p1)
            local lx2, ly2 = perimToXY(p2)
            local segA = math.floor(baseAlpha * (1.0 - si / segments) * 200)
            if segA > 0 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, lx1, ly1) nvgLineTo(vg, lx2, ly2)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, segA))
                nvgStrokeWidth(vg, 2) nvgStroke(vg)
            end
        end
        local hx, hy = perimToXY(headPos)
        nvgBeginPath(vg) nvgCircle(vg, hx, hy, 3)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(baseAlpha * 255)))
        nvgFill(vg)
        -- 品质色第二道流光（相位偏移半圈）
        local headPos2 = (headPos + perimeter / 2) % perimeter
        for si = 0, segments - 1 do
            local p1 = headPos2 - si * segLen
            local p2 = headPos2 - (si + 1) * segLen
            local lx1, ly1 = perimToXY(p1)
            local lx2, ly2 = perimToXY(p2)
            local segA = math.floor(baseAlpha * 0.6 * (1.0 - si / segments) * 180)
            if segA > 0 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, lx1, ly1) nvgLineTo(vg, lx2, ly2)
                nvgStrokeColor(vg, nvgRGBA(r, g, b, segA))
                nvgStrokeWidth(vg, 1.5) nvgStroke(vg)
            end
        end
        local hx2, hy2 = perimToXY(headPos2)
        nvgBeginPath(vg) nvgCircle(vg, hx2, hy2, 2)
        nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(baseAlpha * 0.7 * 255)))
        nvgFill(vg)
    end

    nvgRestore(vg)
end

------------------------------------------------------------------------
-- 绘制升级选卡 UI（卡牌式设计 - 居中布局）
------------------------------------------------------------------------
function RL.DrawUpgradeUI(vg, G)
    if G.state ~= "upgrade" then return end

    local W, H = G.screenW, G.screenH
    -- 字号缩放因子（skill文档基于1080宽，逻辑约400宽）
    local S = W / 1080

    -- 面板弹出动画进度
    local panelT = math.max(0, math.min(1, G.upgradePanelAnim or 1))
    local easeT = panelT * panelT * (3 - 2 * panelT) -- smoothstep

    -- 半透明遮罩（跟随动画淡入）
    local maskAlpha = math.floor(210 * easeT)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(10, 15, 8, maskAlpha))
    nvgFill(vg)

    -- 如果动画未开始，不绘制内容
    if panelT < 0.01 then return end

    -- 应用整体缩放+淡入变换
    nvgSave(vg)
    local panelScale = 0.7 + 0.3 * easeT  -- 0.7→1.0
    local panelAlpha = easeT               -- 0→1
    nvgTranslate(vg, W / 2, H / 2)
    nvgScale(vg, panelScale, panelScale)
    nvgTranslate(vg, -W / 2, -H / 2)
    nvgGlobalAlpha(vg, panelAlpha)

    nvgFontFace(vg, "sans")

    -- ======== 计算整体布局（偏上显示）========
    local trainH = 200      -- 火车展示区高度（放大正面图）
    local bannerH = 100     -- 横幅高度
    local hpBarH = 20       -- HP 条高度
    local tabH = 26         -- 标签栏高度
    local cardH = 170       -- 卡片高度
    local btnAreaH = 80     -- 底部按钮区域高度
    local gapSmall = 6
    local gapMed = 10

    -- 横幅与火车大幅重叠，不额外占用太多纵向空间
    local bannerOverlap = bannerH * 0.65
    local totalContentH = trainH + (bannerH - bannerOverlap) + gapSmall + hpBarH + gapMed + tabH + gapMed + cardH + gapMed + btnAreaH
    -- 整体偏上
    local startY = (H - totalContentH) / 2 - H * 0.09

    -- ======== 1. 火车展示区（正面图 放大）========
    local trainFront = G.trainFrontImg
    if trainFront and trainFront ~= 0 then
        local drawH = trainH
        local drawW = drawH  -- 1:1 正方形
        local trainX = (W - drawW) / 2
        local trainY = startY
        local paint = nvgImagePattern(vg, trainX, trainY, drawW, drawH, 0, trainFront, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, trainX, trainY, drawW, drawH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- ======== 2. 标题横幅 "强化火车" ========
    -- 横幅位置：与火车底部大幅重叠
    local bannerY = startY + trainH - bannerOverlap
    local bannerW = W * 0.65
    local bannerX = (W - bannerW) / 2

    -- 绘制横幅背景图片
    local bannerImg = G.titleBannerImg
    if bannerImg and bannerImg ~= 0 then
        local bPaint = nvgImagePattern(vg, bannerX, bannerY, bannerW, bannerH, 0, bannerImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, bannerX, bannerY, bannerW, bannerH)
        nvgFillPaint(vg, bPaint)
        nvgFill(vg)
    else
        -- fallback: 深色半透明条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bannerX, bannerY, bannerW, bannerH, 6)
        nvgFillColor(vg, nvgRGBA(50, 30, 15, 220))
        nvgFill(vg)
    end

    -- 标题文字（白色 + 描边）
    local titleY = bannerY + bannerH / 2
    local titleFontSize = math.max(20, math.floor(55 * S))
    nvgFontSize(vg, titleFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    -- 描边（4方向偏移）
    local strokeW = math.max(1, math.floor(5 * S))
    nvgFillColor(vg, nvgRGBA(30, 15, 0, 200))
    for _, off in ipairs(STROKE_DIRS) do
        nvgText(vg, W / 2 + off[1] * strokeW, titleY + off[2] * strokeW, "强化火车", nil)
    end
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, W / 2, titleY, "强化火车", nil)

    -- ======== 3. HP 条 ========
    local barW = 130
    local barH2 = 22
    local barX = (W - barW) / 2
    local barY = bannerY + bannerH - 37
    -- 条底
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH2, 6)
    nvgFillColor(vg, nvgRGBA(40, 20, 15, 200))
    nvgFill(vg)
    -- 条填充
    local hpRatio = math.max(0, math.min(1, (G.trainHP or 100) / (G.trainMaxHP or 100)))
    local fillColor = hpRatio > 0.5 and nvgRGBA(80, 200, 60, 255) or
                      hpRatio > 0.25 and nvgRGBA(220, 180, 30, 255) or nvgRGBA(200, 50, 30, 255)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX + 2, barY + 2, (barW - 4) * hpRatio, barH2 - 4, 4)
    nvgFillColor(vg, fillColor)
    nvgFill(vg)
    -- HP 文字（爱心图标 + 数字）
    local hpFontSize = math.max(9, math.floor(32 * S))
    local hpStr = tostring(math.floor(G.trainHP or 100))
    local hpCenterY = barY + barH2 / 2
    -- 爱心图标尺寸
    local heartSize = hpFontSize * 1.1
    -- 先测量数字文本宽度，以便居中排列
    nvgFontSize(vg, hpFontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local txtW = nvgTextBounds(vg, 0, 0, hpStr)
    local gap = heartSize * 0.15
    local totalW = heartSize + gap + txtW
    local startX = W / 2 - totalW / 2
    -- 绘制爱心图标
    if heartIconHandle and heartIconHandle ~= 0 then
        local hx = startX
        local hy = hpCenterY - heartSize / 2
        local paint = nvgImagePattern(vg, hx, hy, heartSize, heartSize, 0, heartIconHandle, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, hx, hy, heartSize, heartSize)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
    -- 绘制 HP 数字
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgText(vg, startX + heartSize + gap, hpCenterY, hpStr, nil)

    -- ======== 4. 品质概率指示栏 ========
    local curLevel = G.level or 1
    local weightIdx = math.min(curLevel, 10)
    local weights = C.QUALITY_WEIGHTS[weightIdx]
    local tabCount = 5
    local tabW = 74
    local tabH2 = tabW  -- 图片为正方形
    local tabGap = 1
    local tabTotalW = tabW * tabCount + tabGap * (tabCount - 1)
    local tabStartX = (W - tabTotalW) / 2
    local tabY = barY + hpBarH + 4

    local qualityImgs = G.qualityImgs or {}
    for ti = 1, tabCount do
        local tx = tabStartX + (ti - 1) * (tabW + tabGap)
        local hasWeight = weights[ti] > 0
        local imgHandle = qualityImgs[ti]

        -- 图片渲染：等比例缩放居中，始终全亮
        if imgHandle and imgHandle ~= 0 then
            local imgAlpha = 1.0
            local iw, ih = nvgImageSize(vg, imgHandle)
            if iw > 0 and ih > 0 then
                -- 按比例缩放以适应 tabW × tabH2，不裁剪
                local scale = math.min(tabW / iw, tabH2 / ih)
                local dw = iw * scale
                local dh = ih * scale
                local dx = tx + (tabW - dw) / 2
                local dy = tabY + (tabH2 - dh) / 2
                local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, imgHandle, imgAlpha)
                nvgBeginPath(vg)
                nvgRect(vg, dx, dy, dw, dh)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        else
            -- fallback：无图片时仍用色块
            local qc = QUALITY_COLORS[ti]
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx, tabY, tabW, tabH2, 4)
            nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 220))
            nvgFill(vg)
        end

    end
    -- tabH 更新为实际高度（供后续布局使用）
    tabH = tabH2

    -- ======== 5. 卡片区域 ========
    local cardCount = #G.upgradeCards
    local cardW2 = math.min(120, (W - 40) / 3)
    gap = 8
    totalW = cardW2 * cardCount + gap * (cardCount - 1)
    startX = (W - totalW) / 2
    local cardY = tabY + tabH + 4

    G.upgradeCardBtns = {}

    for i, card in ipairs(G.upgradeCards) do
        local cx = startX + (i - 1) * (cardW2 + gap)
        local isSelected = (G.upgradeSelectedCard == i)
        local cardQuality = card.quality or 1
        local borderColor = QUALITY_COLORS[cardQuality]
        local selT = 0

        -- 选中动画：放大 + 闪动
        if isSelected then
            selT = math.min(1, (G.upgradeSelectedTimer or 0) / (G.upgradeSelectedDuration or 0.45))
        end

        -- 卡片入场动画：从左到右依次从下方快速滑入
        local enterDelay = (i - 1) * 0.07  -- 每张卡间隔 0.07s
        local enterAge = (G.upgradeCardEnterTimer or 9) - enterDelay
        local enterDur = 0.18  -- 单张入场时长
        local enterT = math.max(0, math.min(1, enterAge / enterDur))
        -- smoothstep 缓出
        local enterEase = enterT * enterT * (3 - 2 * enterT)
        -- 未到入场时间则跳过此卡
        if enterAge < 0 then goto continueCard end

        nvgSave(vg)

        -- 入场：从下方 40px 滑入 + 缩放 0.85→1.0 + 淡入
        if enterT < 1 then
            local slideY = (1 - enterEase) * 40
            local enterScale = 0.85 + 0.15 * enterEase
            local enterAlpha = enterEase
            local cardCX = cx + cardW2 / 2
            local cardCY = cardY + cardH / 2
            nvgTranslate(vg, 0, slideY)
            nvgTranslate(vg, cardCX, cardCY)
            nvgScale(vg, enterScale, enterScale)
            nvgTranslate(vg, -cardCX, -cardCY)
            nvgGlobalAlpha(vg, enterAlpha * (G.upgradePanelAnim or 1))
        end

        -- 未选中的卡片在有选中卡时暗化+缩小
        if G.upgradeSelectedCard and not isSelected then
            local dimT = math.min(1, (G.upgradeSelectedTimer or 0) / 0.15)
            local dimEase = dimT * dimT * (3 - 2 * dimT)
            local dimScale = 1.0 - 0.06 * dimEase
            local dimAlpha = 1.0 - 0.5 * dimEase
            local cardCX = cx + cardW2 / 2
            local cardCY = cardY + cardH / 2
            nvgTranslate(vg, cardCX, cardCY)
            nvgScale(vg, dimScale, dimScale)
            nvgTranslate(vg, -cardCX, -cardCY)
            nvgGlobalAlpha(vg, dimAlpha * (G.upgradePanelAnim or 1))
        end

        if isSelected then
            -- 上浮 + 弹性放大（overshoot: 1.18 → 1.08）
            local t1 = math.min(1, selT / 0.3)  -- 0~0.3 快速弹出
            local ease1 = 1 - (1 - t1) * (1 - t1)  -- easeOutQuad
            local overshoot = t1 < 1 and (1.18 * ease1) or (1.18 - 0.1 * math.min(1, (selT - 0.3) / 0.15))
            local cardScale = math.max(1.08, overshoot)
            local floatY = -8 * math.min(1, selT / 0.2)  -- 上浮8px
            local cardCX = cx + cardW2 / 2
            local cardCY = cardY + cardH / 2
            nvgTranslate(vg, 0, floatY)
            nvgTranslate(vg, cardCX, cardCY)
            nvgScale(vg, cardScale, cardScale)
            nvgTranslate(vg, -cardCX, -cardCY)
        end

        -- ---- 卡片阴影 ----
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + 2, cardY + 3, cardW2, cardH, 12)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
        nvgFill(vg)

        -- ---- 卡片背景（深色渐变）----
        local cr, cg, cb = borderColor[1], borderColor[2], borderColor[3]
        local glowT = (G.upgradeGlowTime or 0)

        local cardBgTop = nvgRGBA(45, 50, 62, 230)
        local cardBgBot = nvgRGBA(30, 34, 44, 245)
        local bgPaint = nvgLinearGradient(vg, cx, cardY, cx, cardY + cardH, cardBgTop, cardBgBot)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cardY, cardW2, cardH, 12)
        nvgFillPaint(vg, bgPaint)
        nvgFill(vg)

        -- ---- 卡片边框（品质光效，仿装备风格）----
        if isSelected then
            -- 选中：升一档品质光效，额外加白色内边强调
            DrawCardQualityBorder(vg, cx, cardY, cardW2, cardH,
                math.min(cardQuality + 1, 5), cr, cg, cb, glowT)
            -- 额外加一圈纯白实边强调选中
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx + 1, cardY + 1, cardW2 - 2, cardH - 2, 11)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 60))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        else
            DrawCardQualityBorder(vg, cx, cardY, cardW2, cardH,
                cardQuality, cr, cg, cb, glowT)
        end

        -- ---- 品质标签（左上角）----
        if not card.isTurret and not card.isDrone then
            local qName = QUALITY_NAMES[cardQuality] or "普通"
            local qc = borderColor
            local tagX = cx + 4
            local tagY2 = cardY + 4
            local tagFontSize = math.max(8, math.floor(28 * S))
            nvgFontSize(vg, tagFontSize)
            local tagTextW = nvgTextBounds(vg, 0, 0, qName)
            local tagW = tagTextW + 8
            local tagH = tagFontSize + 4
            -- 标签背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tagX, tagY2, tagW, tagH, 3)
            nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 220))
            nvgFill(vg)
            -- 标签文字
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(15, 15, 15, 255))
            nvgText(vg, tagX + tagW / 2, tagY2 + tagH / 2, qName, nil)
        end

        -- ---- NEW 标记（炮塔解锁卡，右上角）----
        if card.isTurret then
            local newW = 35
            local newH = 16
            local newX = cx + cardW2 - newW - 5
            local newY = cardY + 5
            nvgBeginPath(vg)
            nvgRoundedRect(vg, newX, newY, newW, newH, 3)
            nvgFillColor(vg, nvgRGBA(220, 55, 35, 240))
            nvgFill(vg)
            local newFontSize = math.max(9, math.floor(32 * S))
            nvgFontSize(vg, newFontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, newX + newW / 2, newY + newH / 2, "NEW", nil)
        end

        -- ---- 图标区域（圆形底+图片）----
        local iconCX = cx + cardW2 / 2
        local iconCY = cardY + 50
        local iconR = 30

        -- 圆形深色底
        nvgBeginPath(vg)
        nvgCircle(vg, iconCX, iconCY, iconR + 3)
        nvgFillColor(vg, nvgRGBA(25, 28, 35, 200))
        nvgFill(vg)
        -- 圆形边框（品质色）
        nvgBeginPath(vg)
        nvgCircle(vg, iconCX, iconCY, iconR + 3)
        nvgStrokeColor(vg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], 100))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 绘制图标图片
        RL.DrawCardIcon(vg, iconCX, iconCY, iconR * 2, card.icon, G)

        -- ---- 分割线 ----
        local divY = iconCY + iconR + 10
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx + 10, divY)
        nvgLineTo(vg, cx + cardW2 - 10, divY)
        nvgStrokeColor(vg, nvgRGBA(80, 85, 100, 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- ---- 名称（正文字号）----
        local nameFontSize = math.max(13, math.floor(48 * S))
        nvgFontSize(vg, nameFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        -- 名称描边
        local nameStroke = math.max(1, math.floor(5 * S))
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        for _, off in ipairs(STROKE_DIRS) do
            nvgText(vg, iconCX + off[1] * nameStroke, divY + 6 + off[2] * nameStroke, card.name, nil)
        end
        nvgFillColor(vg, nvgRGBA(240, 240, 245, 255))
        nvgText(vg, iconCX, divY + 6, card.name, nil)

        -- ---- 描述（小正文字号，自动换行）----
        local descFontSize = math.max(10, math.floor(38 * S))
        nvgFontSize(vg, descFontSize)
        nvgFillColor(vg, nvgRGBA(170, 180, 200, 200))
        do
            local maxW = cardW2 - 14  -- 左右各留 7px 边距
            local desc = card.desc or ""
            local lineH = descFontSize + 2
            local baseY = divY + 6 + nameFontSize + 6
            -- 按字符逐个累加测量，超宽则换行
            local lines = {}
            local cur = ""
            -- 将 desc 拆成 UTF-8 字符序列
            local chars = {}
            for ch in desc:gmatch("[%z\1-\127\194-\253][\128-\191]*") do
                chars[#chars + 1] = ch
            end
            for _, ch in ipairs(chars) do
                local test = cur .. ch
                local testW = nvgTextBounds(vg, 0, 0, test, nil)
                if testW > maxW and cur ~= "" then
                    lines[#lines + 1] = cur
                    cur = ch
                else
                    cur = test
                end
            end
            if cur ~= "" then lines[#lines + 1] = cur end
            -- 最多显示3行，超出省略
            local maxLines = 3
            for li = 1, math.min(#lines, maxLines) do
                local txt = lines[li]
                if li == maxLines and #lines > maxLines then
                    txt = txt:gsub("..$", "…")
                end
                nvgText(vg, iconCX, baseY + (li - 1) * lineH, txt, nil)
            end
        end

        -- 选中高光扫过效果
        if isSelected then
            -- 从上到下扫一道亮光（0~0.35s）
            local sweepT = math.min(1, selT / 0.35)
            local sweepY = cardY + cardH * sweepT
            local sweepH = cardH * 0.3
            local sweepAlpha = math.floor(80 * (1 - sweepT))
            nvgSave(vg)
            nvgIntersectScissor(vg, cx, cardY, cardW2, cardH)
            local sweepPaint = nvgLinearGradient(vg, cx, sweepY - sweepH, cx, sweepY,
                nvgRGBA(255, 255, 255, 0), nvgRGBA(255, 255, 255, sweepAlpha))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, sweepY - sweepH, cardW2, sweepH, 0)
            nvgFillPaint(vg, sweepPaint)
            nvgFill(vg)
            nvgRestore(vg)
        end

        nvgRestore(vg) -- 恢复卡片 save

        -- 点击区域（不受卡片缩放影响，用原始坐标）
        table.insert(G.upgradeCardBtns, { x = cx, y = cardY, w = cardW2, h = cardH, index = i })

        ::continueCard::
    end

    -- ======== 6. 底部按钮区域（免费刷新 / 获取全部）========
    -- 如果正在播选中动画则不渲染按钮
    if not G.upgradeSelectedCard then
        local btnY = cardY + cardH + 22
        local btnH = btnAreaH
        local btnW = 155  -- 每个按钮宽度（放大）
        local btnGap = 30
        local totalBtnW = btnW * 2 + btnGap
        local btnStartX = (W - totalBtnW) / 2

        -- 提示文字："更高概率出 高级词条"（白色+紫色）
        local hintFontSize = math.max(9, math.floor(32 * S))
        nvgFontSize(vg, hintFontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        -- 先测量总宽度以居中
        local hintPart1 = "更高概率出 "
        local hintPart2 = "高级词条"
        local w1 = nvgTextBounds(vg, 0, 0, hintPart1, nil)
        local w2 = nvgTextBounds(vg, 0, 0, hintPart2, nil)
        local hintTotalW = w1 + w2
        local hintStartX = btnStartX + (btnW - hintTotalW) / 2
        -- 白色部分
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, hintStartX, btnY, hintPart1, nil)
        -- 紫色部分
        nvgFillColor(vg, nvgRGBA(200, 120, 255, 255))
        nvgText(vg, hintStartX + w1, btnY, hintPart2, nil)

        local imgBtnY = btnY + hintFontSize + 4
        local imgBtnH = btnH - hintFontSize - 2

        -- === 获取当前钻石数 ===
        local Meta = require "Meta.MetaMain"
        local sd = Meta.GetSaveData()
        local curDiamond = sd.diamond or 0
        local gemIcon = G.hudIconGem

        -- === 左侧：免费刷新 / 钻石刷新 ===
        local leftBtnX = btnStartX
        local hasFreeRefresh = (G.refreshFreeLeft or 0) > 0
        local refreshImg = hasFreeRefresh and G.refreshFreeImg or G.refreshDiamondImg
        local refreshCost = C.REFRESH_DIAMOND_COST or 30
        local refreshEnabled = hasFreeRefresh or (curDiamond >= refreshCost)

        -- 统一按钮绘制尺寸（两个按钮等比缩放到相同大小）
        local unifiedBtnW = btnW * 0.92
        local unifiedBtnH = imgBtnH * 0.72

        -- 绘制刷新按钮图片
        if refreshImg and refreshImg ~= 0 then
            local alpha = refreshEnabled and 1.0 or 0.4
            local iw, ih = nvgImageSize(vg, refreshImg)
            if iw > 0 and ih > 0 then
                local scale = math.min(unifiedBtnW / iw, unifiedBtnH / ih)
                local dw = iw * scale
                local dh = ih * scale
                local dx = leftBtnX + (btnW - dw) / 2
                local dy = imgBtnY + (imgBtnH - dh) / 2 - 4
                local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, refreshImg, alpha)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, dx, dy, dw, dh, 4)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        end
        -- 底部文字
        local countFontSize = math.max(9, math.floor(30 * S))
        nvgFontSize(vg, countFontSize)
        local countY = imgBtnY + imgBtnH - 5
        local iconSize = countFontSize * 0.9

        if hasFreeRefresh then
            -- 免费时显示"剩余次数：X"
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local labelStr = "剩余次数："
            local numStr = tostring(G.refreshFreeLeft)
            local lw = nvgTextBounds(vg, 0, 0, labelStr, nil)
            local nw = nvgTextBounds(vg, 0, 0, numStr, nil)
            local cx = leftBtnX + (btnW - lw - nw) / 2
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, cx, countY, labelStr, nil)
            nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
            nvgText(vg, cx + lw, countY, numStr, nil)
        else
            -- 钻石消耗：消耗：30 💎
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            local labelCost1 = "消耗："
            local numCost1 = tostring(refreshCost)
            local lw1 = nvgTextBounds(vg, 0, 0, labelCost1, nil)
            local nw1 = nvgTextBounds(vg, 0, 0, numCost1, nil)
            local totalCostW1 = lw1 + nw1 + iconSize + 2
            local cx1 = leftBtnX + (btnW - totalCostW1) / 2
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
            nvgText(vg, cx1, countY, labelCost1, nil)
            nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
            nvgText(vg, cx1 + lw1, countY, numCost1, nil)
            if gemIcon and gemIcon ~= 0 then
                local gx = cx1 + lw1 + nw1 + 2
                local gPaint = nvgImagePattern(vg, gx, countY, iconSize, iconSize, 0, gemIcon, 1.0)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, gx, countY, iconSize, iconSize, 2)
                nvgFillPaint(vg, gPaint)
                nvgFill(vg)
            end
        end

        -- 注册刷新按钮点击区域
        G.upgradeRefreshBtn = refreshEnabled and { x = leftBtnX, y = imgBtnY, w = btnW, h = imgBtnH } or nil

        -- === 右侧：获取全部（消耗钻石）===
        local rightBtnX = btnStartX + btnW + btnGap
        local getAllImg = G.getAllImg
        local getAllCost = C.GETALL_DIAMOND_COST or 50
        local getAllEnabled = curDiamond >= getAllCost

        if getAllImg and getAllImg ~= 0 then
            local alpha = getAllEnabled and 1.0 or 0.4
            local iw, ih = nvgImageSize(vg, getAllImg)
            if iw > 0 and ih > 0 then
                local scale = math.min(unifiedBtnW / iw, unifiedBtnH / ih)
                local dw = iw * scale
                local dh = ih * scale
                local dx = rightBtnX + (btnW - dw) / 2
                local dy = imgBtnY + (imgBtnH - dh) / 2 - 4
                local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, getAllImg, alpha)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, dx, dy, dw, dh, 4)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        end
        -- 消耗文字：消耗：50 💎
        nvgFontSize(vg, countFontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local labelCost2 = "消耗："
        local numCost2 = tostring(getAllCost)
        local lw2 = nvgTextBounds(vg, 0, 0, labelCost2, nil)
        local nw2 = nvgTextBounds(vg, 0, 0, numCost2, nil)
        local totalCostW2 = lw2 + nw2 + iconSize + 2
        local cx2 = rightBtnX + (btnW - totalCostW2) / 2
        -- 白色"消耗："
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgText(vg, cx2, countY, labelCost2, nil)
        -- 绿色数字
        nvgFillColor(vg, nvgRGBA(80, 255, 80, 255))
        nvgText(vg, cx2 + lw2, countY, numCost2, nil)
        -- 钻石图标
        if gemIcon and gemIcon ~= 0 then
            local gx2 = cx2 + lw2 + nw2 + 2
            local gy2 = countY
            local gPaint2 = nvgImagePattern(vg, gx2, gy2, iconSize, iconSize, 0, gemIcon, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, gx2, gy2, iconSize, iconSize, 2)
            nvgFillPaint(vg, gPaint2)
            nvgFill(vg)
        end

        -- 注册获取全部按钮点击区域
        G.upgradeGetAllBtn = getAllEnabled and { x = rightBtnX, y = imgBtnY, w = btnW, h = imgBtnH } or nil
    else
        G.upgradeRefreshBtn = nil
        G.upgradeGetAllBtn = nil
    end

    nvgRestore(vg) -- 恢复面板整体 save（缩放+淡入）
end

------------------------------------------------------------------------
-- 卡片图标（使用图片资源）
------------------------------------------------------------------------
function RL.DrawCardIcon(vg, cx, cy, size, iconKey, G)
    local icons = G and G.upgradeIcons
    local img = icons and icons[iconKey]

    if img and img ~= 0 then
        -- 使用图片绘制
        local hs = size / 2
        local paint = nvgImagePattern(vg, cx - hs, cy - hs, size, size, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, hs)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- fallback: 简单圆形
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, size / 4)
        nvgFillColor(vg, nvgRGBA(150, 150, 160, 200))
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 升级特效 + 面板动画 更新（在 HandleUpdate 中调用）
------------------------------------------------------------------------
function RL.UpdateUpgradeAnim(G, dt)
    -- 升级特效阶段
    if G.state == "upgradeVfx" then
        G.upgradeVfxTimer = (G.upgradeVfxTimer or 0) + dt
        if G.upgradeVfxTimer >= (G.upgradeVfxDuration or 1.2) then
            G.state = "upgrade"
            G.upgradePanelAnim = 0
            G.upgradeVfxParticles = nil  -- 清理粒子数据
        end
    end
    -- 面板弹出动画
    if G.state == "upgrade" and (G.upgradePanelAnim or 0) < 1 then
        G.upgradePanelAnim = math.min(1, (G.upgradePanelAnim or 0) + dt / 0.35)
    end
    -- 卡片入场动画计时器 & 光晕时钟
    if G.state == "upgrade" then
        G.upgradeCardEnterTimer = (G.upgradeCardEnterTimer or 0) + dt
        G.upgradeGlowTime = (G.upgradeGlowTime or 0) + dt
    end
    -- 卡片选中动画
    if G.state == "upgrade" and G.upgradeSelectedCard then
        G.upgradeSelectedTimer = (G.upgradeSelectedTimer or 0) + dt
        if G.upgradeSelectedTimer >= (G.upgradeSelectedDuration or 0.45) then
            RL.DoApplyUpgrade(G)
        end
    end
end

------------------------------------------------------------------------
-- 升级特效：多个符文从火车上方向上飘散消失
------------------------------------------------------------------------

-- 初始化升级符文（2~3个，从火车上方垂直上升消失）
local function ensureVfxParticles(G)
    if G.upgradeVfxParticles then return end
    local W, H = G.screenW, G.screenH
    -- 火车中心位置（与 DrawUpgradeUI 布局一致）
    local trainH = 200
    local bannerH2 = 100
    local bannerOverlap = bannerH2 * 0.65
    local cardH2 = 170
    local tabH2 = 26
    local totalContentH = trainH + (bannerH2 - bannerOverlap) + 6 + 20 + 10 + tabH2 + 10 + cardH2
    local startY = (H - totalContentH) / 2 - H * 0.05
    local cx = W / 2
    local cy = startY + trainH * 0.35  -- 火车上方

    local particles = {}
    local count = 3
    -- 左-右-左 交错分布 + 垂直随机偏移
    local offsets = {
        { -20 - math.random() * 15,  -10 - math.random() * 20 },  -- 左上
        {  20 + math.random() * 15,    5 + math.random() * 15 },  -- 右中
        { -10 - math.random() * 20,   15 + math.random() * 15 },  -- 左下
    }
    for i = 1, count do
        particles[i] = {
            x = cx + offsets[i][1],
            y = cy + offsets[i][2],
            vy = -40,                      -- 向上速度（慢飘）
            size = 34 + math.random() * 18, -- 34~52 随机大小
            delay = (i - 1) * 0.08,        -- 依次出现
        }
    end
    G.upgradeVfxParticles = particles
end

function RL.DrawUpgradeVfx(vg, G)
    if G.state ~= "upgradeVfx" then return end

    local W, H = G.screenW, G.screenH
    local elapsed = G.upgradeVfxTimer or 0
    local duration = G.upgradeVfxDuration or 0.5

    ensureVfxParticles(G)

    -- 火车中心位置（与 ensureVfxParticles 一致）
    local trainH = 200
    local bannerH2 = 100
    local bannerOverlap = bannerH2 * 0.65
    local cardH2 = 170
    local tabH2 = 26
    local totalContentH = trainH + (bannerH2 - bannerOverlap) + 6 + 20 + 10 + tabH2 + 10 + cardH2
    local startY = (H - totalContentH) / 2 - H * 0.05
    local trainCX = W / 2
    local trainCY = startY + trainH * 0.15

    -- smoothstep 缓动
    local function smooth(x)
        x = math.max(0, math.min(1, x))
        return x * x * (3 - 2 * x)
    end

    -- 光效帧动画（6帧，火车上方）
    local glowFrames = upgradeVfxGlow
    if glowFrames and #glowFrames >= 6 then
        local t = math.min(1, elapsed / duration)
        local frameIdx = math.floor(elapsed * 18) + 1  -- 单次播放，18fps
        if frameIdx > 6 then goto skipGlow end       -- 播完即消失
        local glowImg = glowFrames[frameIdx]
        if glowImg and glowImg ~= 0 then
            -- 透明度：smoothstep 淡入淡出
            local glowAlpha
            if t < 0.2 then
                glowAlpha = smooth(t / 0.2) * 0.9
            elseif t > 0.55 then
                glowAlpha = smooth((1 - t) / 0.45) * 0.9
            else
                glowAlpha = 0.9
            end
            -- 缩放脉冲：从 0.85 → 1.0 缓入
            local glowScale = 0.85 + 0.15 * smooth(math.min(1, t / 0.3))
            local glowSize = 350 * glowScale
            local hs = glowSize / 2
            nvgSave(vg)
            nvgTranslate(vg, trainCX, trainCY)
            local paint = nvgImagePattern(vg, -hs, -hs, glowSize, glowSize, 0, glowImg, glowAlpha)
            nvgBeginPath(vg)
            nvgRect(vg, -hs, -hs, glowSize, glowSize)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
            nvgRestore(vg)
        end
    end
    ::skipGlow::

    -- 绘制符文（缓动上移 + 缩放动画）
    local symImg = upgradeVfxSymbol
    if not symImg or symImg == 0 then return end

    for _, p in ipairs(G.upgradeVfxParticles) do
        local age = elapsed - p.delay
        if age > 0 then
            local life = duration - p.delay
            local lifeT = math.min(1, age / life)
            local px = p.x
            -- 缓出上移：开始快，越来越慢
            local moveT = 1 - (1 - lifeT) * (1 - lifeT)
            local py = p.y + p.vy * life * moveT
            local sz = p.size
            -- 缩放：弹入 → 缩小消失
            local scale
            if lifeT < 0.2 then
                local st = smooth(lifeT / 0.2)
                scale = 0.3 + 0.8 * st  -- 0.3→1.1 弹入
            elseif lifeT < 0.35 then
                scale = 1.1 - 0.1 * smooth((lifeT - 0.2) / 0.15)  -- 1.1→1.0 回弹
            elseif lifeT > 0.6 then
                scale = 1.0 - 0.7 * smooth((lifeT - 0.6) / 0.4)  -- 1.0→0.3 缩小
            else
                scale = 1.0
            end
            sz = sz * scale
            -- 透明度：smoothstep 淡入淡出
            local alpha
            if lifeT < 0.15 then
                alpha = smooth(lifeT / 0.15)
            elseif lifeT > 0.55 then
                alpha = smooth((1 - lifeT) / 0.45)
            else
                alpha = 1.0
            end

            local hs2 = sz / 2
            local paint = nvgImagePattern(vg, px - hs2, py - hs2, sz, sz, 0, symImg, alpha)
            nvgBeginPath(vg)
            nvgRect(vg, px - hs2, py - hs2, sz, sz)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    end
end

return RL

-- Game/Roguelike.lua - 升级系统：三选一强化
local C = require "Game.Config"
local Ent = require "Game.Entities"
local Turret = require "Game.Turret"
local RL = {}

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
    -- 收集已解锁的炮塔类型
    local unlockedTypes = {}
    for _, t in ipairs(G.turrets or {}) do
        unlockedTypes[t.typeKey] = true
    end
    local slotsLeft = #Turret.SLOTS - Turret.GetUnlockedCount(G)

    -- 第一次强化（level==1）：必定全是武器（炮塔解锁卡）
    local isFirstUpgrade = (G.level == 1)

    -- 过滤可用卡
    local available = {}
    for i = 1, #C.UPGRADES do
        local card = C.UPGRADES[i]
        if card.isTurret then
            if slotsLeft > 0 and not unlockedTypes[card.turretType] then
                table.insert(available, i)
            end
        else
            if not isFirstUpgrade then
                table.insert(available, i)
            end
        end
    end
    -- 打乱
    for i = #available, 2, -1 do
        local j = math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end
    G.upgradeCards = {}
    for i = 1, math.min(3, #available) do
        table.insert(G.upgradeCards, C.UPGRADES[available[i]])
    end
    G.upgradeCardBtns = {}
    G.state = "upgrade"

    -- 升级奖励金币
    G.gold = G.gold + C.GOLD_PER_LEVEL
    Ent.SpawnFloatText(G, G.screenW / 2, G.screenH * 0.4, "+" .. C.GOLD_PER_LEVEL .. " Gold!", "gold")
end

------------------------------------------------------------------------
-- 应用升级
------------------------------------------------------------------------
function RL.ApplyUpgrade(G, cardIndex)
    local card = G.upgradeCards[cardIndex]
    if card and card.apply then
        card.apply(G)
        print("[Upgrade] Applied: " .. card.name .. " - " .. card.desc)
    end

    -- 进入下一级
    G.level = G.level + 1
    G.levelProgress = 0
    G.levelTarget = math.ceil(C.BASE_TARGET * (C.TARGET_GROWTH ^ (G.level - 1)))
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
-- 品质色定义（6 级）
------------------------------------------------------------------------
local QUALITY_COLORS = {
    { 181, 181, 181 },  -- 1 普通
    { 162, 255, 148 },  -- 2 优质
    { 114, 242, 245 },  -- 3 稀有
    { 239, 121, 255 },  -- 4 史诗
    { 255, 237, 0   },  -- 5 传说
    { 255, 0,   0   },  -- 6 至臻
}
local QUALITY_NAMES = { "普通", "优质", "稀有", "史诗", "传说", "至臻" }

------------------------------------------------------------------------
-- 绘制升级选卡 UI（卡牌式设计 - 居中布局）
------------------------------------------------------------------------
function RL.DrawUpgradeUI(vg, G)
    if G.state ~= "upgrade" then return end

    local W, H = G.screenW, G.screenH
    -- 字号缩放因子（skill文档基于1080宽，逻辑约400宽）
    local S = W / 1080

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(10, 15, 8, 210))
    nvgFill(vg)

    nvgFontFace(vg, "sans")

    -- ======== 计算整体布局（偏上显示）========
    local trainH = 200      -- 火车展示区高度（放大正面图）
    local bannerH = 100     -- 横幅高度
    local hpBarH = 20       -- HP 条高度
    local tabH = 26         -- 标签栏高度
    local cardH = 170       -- 卡片高度
    local gapSmall = 6
    local gapMed = 10

    -- 横幅与火车大幅重叠，不额外占用太多纵向空间
    local bannerOverlap = bannerH * 0.65
    local totalContentH = trainH + (bannerH - bannerOverlap) + gapSmall + hpBarH + gapMed + tabH + gapMed + cardH
    -- 整体偏上
    local startY = (H - totalContentH) / 2 - H * 0.05

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
    for _, off in ipairs({{-strokeW,0},{strokeW,0},{0,-strokeW},{0,strokeW}}) do
        nvgText(vg, W / 2 + off[1], titleY + off[2], "强化火车", nil)
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

    -- ======== 4. 品质标签栏 ========
    local rarity = math.min(6, math.floor((G.level or 1) / 2) + 1)
    local tabCount = 6
    local tabW = 42
    local tabGap = 5
    local tabTotalW = tabW * tabCount + tabGap * (tabCount - 1)
    local tabStartX = (W - tabTotalW) / 2
    local tabY = barY + hpBarH + gapMed

    for ti = 1, tabCount do
        local tx = tabStartX + (ti - 1) * (tabW + tabGap)
        local isActive = (ti == rarity)
        local qc = QUALITY_COLORS[ti]

        nvgBeginPath(vg)
        nvgRoundedRect(vg, tx, tabY, tabW, tabH, 4)
        if isActive then
            nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(35, 38, 48, 200))
        end
        nvgFill(vg)

        if not isActive then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx, tabY, tabW, tabH, 4)
            nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 80))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 标签文字
        local tabFontSize = math.max(9, math.floor(32 * S))
        nvgFontSize(vg, tabFontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isActive then
            nvgFillColor(vg, nvgRGBA(20, 20, 20, 255))
        else
            nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 120))
        end
        nvgText(vg, tx + tabW / 2, tabY + tabH / 2, QUALITY_NAMES[ti], nil)
    end

    -- ======== 5. 卡片区域 ========
    local cardCount = #G.upgradeCards
    local cardW2 = math.min(120, (W - 40) / 3)
    gap = 8
    totalW = cardW2 * cardCount + gap * (cardCount - 1)
    startX = (W - totalW) / 2
    local cardY = tabY + tabH + gapMed

    local borderColor = QUALITY_COLORS[rarity]

    G.upgradeCardBtns = {}

    for i, card in ipairs(G.upgradeCards) do
        local cx = startX + (i - 1) * (cardW2 + gap)

        -- ---- 卡片阴影 ----
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + 2, cardY + 3, cardW2, cardH, 12)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
        nvgFill(vg)

        -- ---- 卡片背景（深色渐变）----
        local cardBgTop = nvgRGBA(45, 50, 62, 245)
        local cardBgBot = nvgRGBA(30, 34, 44, 250)
        local bgPaint = nvgLinearGradient(vg, cx, cardY, cx, cardY + cardH, cardBgTop, cardBgBot)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cardY, cardW2, cardH, 12)
        nvgFillPaint(vg, bgPaint)
        nvgFill(vg)

        -- ---- 卡片边框（品质色）----
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx, cardY, cardW2, cardH, 12)
        nvgStrokeColor(vg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], 140))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- ---- NEW 标记（所有炮塔解锁卡）----
        if card.isTurret then
            local newX = cx + 5
            local newY = cardY + 5
            local newW = 35
            local newH = 16
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
        for _, off in ipairs({{-nameStroke,0},{nameStroke,0},{0,-nameStroke},{0,nameStroke}}) do
            nvgText(vg, iconCX + off[1], divY + 6 + off[2], card.name, nil)
        end
        nvgFillColor(vg, nvgRGBA(240, 240, 245, 255))
        nvgText(vg, iconCX, divY + 6, card.name, nil)

        -- ---- 描述（小正文字号）----
        local descFontSize = math.max(10, math.floor(38 * S))
        nvgFontSize(vg, descFontSize)
        nvgFillColor(vg, nvgRGBA(170, 180, 200, 200))
        nvgText(vg, iconCX, divY + 6 + nameFontSize + 4, card.desc, nil)

        -- 点击区域
        table.insert(G.upgradeCardBtns, { x = cx, y = cardY, w = cardW2, h = cardH, index = i })
    end
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

return RL

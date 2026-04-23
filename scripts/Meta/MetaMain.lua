-- Meta/MetaMain.lua - 局外系统主模块
-- NanoVG 渲染的完整局外 UI：顶栏 + 底部Tab + 5个面板
-- 与游戏内 NanoVG 管线一致，通过 main.lua 状态切换

local MD = require("Meta.MetaData")

local M = {}

------------------------------------------------------------------------
-- 局外状态
------------------------------------------------------------------------
local activeTab = "battle"   -- 当前激活的Tab
local saveData = nil         -- 玩家存档
local tabAnimT = {}          -- Tab 动画时间 {battle=0, shop=0, ...}
local panelAlpha = 1.0       -- 面板切换淡入透明度
local panelFadeTarget = 1.0
local scrollY = 0            -- 当前面板滚动偏移
local maxScrollY = 0         -- 最大滚动
local touchStartY = 0        -- 触摸拖动起点
local isDragging = false
local imgCache = {}          -- NanoVG 图片句柄缓存
local elapsedTime = 0        -- 累计时间（用于动画）

-- 天赋弹窗状态
local talentPopup = {
    show = false,       -- 是否显示弹窗
    idx  = 0,           -- 当前查看的天赋索引（MD.TALENTS 的下标）
}

-- 布局缓存
local L = {}

------------------------------------------------------------------------
-- 初始化
------------------------------------------------------------------------
function M.Init(vg)
    saveData = MD.NewSaveData()
    -- 初始化 Tab 动画
    for _, tab in ipairs(MD.TABS) do
        tabAnimT[tab.id] = 0
    end
    -- 预加载图片
    M.PreloadImages(vg)
end

function M.PreloadImages(vg)
    -- Tab 图标
    for _, tab in ipairs(MD.TABS) do
        imgCache[tab.icon] = nvgCreateImage(vg, tab.icon, NVG_IMAGE_NEAREST)
    end
    -- 货币图标
    for k, path in pairs(MD.CURRENCY_ICONS) do
        imgCache[path] = nvgCreateImage(vg, path, 0)
    end
    -- 装备图标
    for _, slot in ipairs(MD.EQUIP_SLOTS) do
        imgCache[slot.icon] = nvgCreateImage(vg, slot.icon, NVG_IMAGE_NEAREST)
    end
    for _, eq in ipairs(MD.EQUIP_DB) do
        if not imgCache[eq.icon] then
            imgCache[eq.icon] = nvgCreateImage(vg, eq.icon, NVG_IMAGE_NEAREST)
        end
    end
    -- 宝箱图标
    for k, path in pairs(MD.CHEST_ICONS) do
        imgCache[path] = nvgCreateImage(vg, path, NVG_IMAGE_NEAREST)
    end
    -- 天赋图标
    for _, t in ipairs(MD.TALENTS) do
        imgCache[t.icon] = nvgCreateImage(vg, t.icon, NVG_IMAGE_NEAREST)
    end
    -- 天赋面板背景
    imgCache["talent_bg"] = nvgCreateImage(vg, "image/talent_bg_clean_20260421083616.png", 0)
    -- 炮塔图标
    for _, t in ipairs(MD.TURRET_UPGRADES) do
        imgCache[t.icon] = nvgCreateImage(vg, t.icon, NVG_IMAGE_NEAREST)
    end
    -- 商城日购图标
    for _, item in ipairs(MD.SHOP_DAILY) do
        if not imgCache[item.icon] then
            imgCache[item.icon] = nvgCreateImage(vg, item.icon, 0)
        end
    end
    print("[Meta] Preloaded " .. M.CountTable(imgCache) .. " images")
end

function M.CountTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function M.GetSaveData()
    return saveData
end

------------------------------------------------------------------------
-- 布局计算
------------------------------------------------------------------------
function M.CalcLayout(W, H)
    L.W = W
    L.H = H
    L.topBarH = 52       -- 顶栏高度
    L.tabBarH = 58       -- 底部Tab高度
    L.contentY = L.topBarH
    L.contentH = H - L.topBarH - L.tabBarH
    L.pad = 10           -- 通用内边距
    L.cardGap = 8        -- 卡片间距
end

------------------------------------------------------------------------
-- 更新（动画、滚动惯性等）
------------------------------------------------------------------------
function M.Update(dt)
    -- Tab 选中动画
    for _, tab in ipairs(MD.TABS) do
        local target = (tab.id == activeTab) and 1.0 or 0.0
        tabAnimT[tab.id] = tabAnimT[tab.id] + (target - tabAnimT[tab.id]) * math.min(1.0, dt * 10)
    end
    -- 面板淡入
    panelAlpha = panelAlpha + (panelFadeTarget - panelAlpha) * math.min(1.0, dt * 12)
    -- 累计时间
    elapsedTime = elapsedTime + dt
end

------------------------------------------------------------------------
-- 绘制入口
------------------------------------------------------------------------
function M.Draw(vg, W, H)
    M.CalcLayout(W, H)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(MD.CLR.bg_dark[1], MD.CLR.bg_dark[2], MD.CLR.bg_dark[3], 255))
    nvgFill(vg)

    -- 内容区域（带裁剪）
    nvgSave(vg)
    nvgScissor(vg, 0, L.contentY, W, L.contentH)
    nvgTranslate(vg, 0, -scrollY)

    nvgGlobalAlpha(vg, panelAlpha)

    if activeTab == "battle" then
        maxScrollY = M.DrawBattlePanel(vg, W)
    elseif activeTab == "shop" then
        maxScrollY = M.DrawShopPanel(vg, W)
    elseif activeTab == "equip" then
        maxScrollY = M.DrawEquipPanel(vg, W)
    elseif activeTab == "train" then
        maxScrollY = M.DrawTrainPanel(vg, W)
    elseif activeTab == "talent" then
        maxScrollY = M.DrawTalentPanel(vg, W)
    end

    nvgGlobalAlpha(vg, 1.0)
    nvgRestore(vg)

    -- 顶栏
    M.DrawTopBar(vg, W)

    -- 底部Tab栏
    M.DrawTabBar(vg, W, H)

    -- 天赋弹窗（覆盖在所有 UI 之上，不受滚动裁剪影响）
    if activeTab == "talent" then
        M.DrawTalentPopup(vg, W, H)
    end
end

------------------------------------------------------------------------
-- 顶栏（玩家信息 + 货币）
------------------------------------------------------------------------
function M.DrawTopBar(vg, W)
    local h = L.topBarH
    local c = MD.CLR

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, h)
    nvgFillColor(vg, nvgRGBA(c.bar_bg[1], c.bar_bg[2], c.bar_bg[3], c.bar_bg[4]))
    nvgFill(vg)

    -- 底部边框线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, h)
    nvgLineTo(vg, W, h)
    nvgStrokeColor(vg, nvgRGBA(c.bar_border[1], c.bar_border[2], c.bar_border[3], 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 玩家头像框（左侧）
    local avSize = 32
    local avX = 12
    local avY = (h - avSize) / 2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, avX, avY, avSize, avSize, 6)
    nvgFillColor(vg, nvgRGBA(50, 55, 70, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(c.tab_active[1], c.tab_active[2], c.tab_active[3], 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 头像文字 (简化)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, avX + avSize / 2, avY + avSize / 2, "😊")

    -- 玩家名
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, avX + avSize + 6, h / 2 - 7, saveData.playerName)

    -- Lv 标签
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(c.text_gray[1], c.text_gray[2], c.text_gray[3], 255))
    nvgText(vg, avX + avSize + 6, h / 2 + 8, "Lv." .. saveData.playerLevel)

    -- 货币显示（右侧）
    local currencies = {
        { val = saveData.gold,    icon = MD.CURRENCY_ICONS.gold,    clr = c.text_gold },
        { val = saveData.diamond, icon = MD.CURRENCY_ICONS.diamond, clr = {120, 180, 255, 255} },
        { val = saveData.wood,    icon = MD.CURRENCY_ICONS.wood,    clr = {180, 140, 80, 255} },
        { val = saveData.stone,   icon = MD.CURRENCY_ICONS.stone,   clr = c.text_gray },
    }

    local cx = W - 8
    for i = #currencies, 1, -1 do
        local cur = currencies[i]
        local txt = tostring(cur.val)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(cur.clr[1], cur.clr[2], cur.clr[3], cur.clr[4] or 255))
        nvgText(vg, cx, h / 2, txt)

        local tw = nvgTextBounds(vg, 0, 0, txt)
        cx = cx - tw - 2

        -- 图标
        local img = imgCache[cur.icon]
        if img and img ~= 0 then
            local icoS = 16
            M.DrawImage(vg, img, cx - icoS, h / 2 - icoS / 2, icoS, icoS)
            cx = cx - icoS - 8
        end
    end
end

------------------------------------------------------------------------
-- 底部Tab栏
------------------------------------------------------------------------
function M.DrawTabBar(vg, W, H)
    local h = L.tabBarH
    local y = H - h
    local c = MD.CLR

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, y, W, h)
    nvgFillColor(vg, nvgRGBA(c.tab_bg[1], c.tab_bg[2], c.tab_bg[3], c.tab_bg[4]))
    nvgFill(vg)

    -- 顶部边框线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, y)
    nvgLineTo(vg, W, y)
    nvgStrokeColor(vg, nvgRGBA(c.bar_border[1], c.bar_border[2], c.bar_border[3], 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local tabCount = #MD.TABS
    local tabW = W / tabCount

    for i, tab in ipairs(MD.TABS) do
        local tx = (i - 1) * tabW
        local centerX = tx + tabW / 2
        local isActive = (tab.id == activeTab)
        local anim = tabAnimT[tab.id] or 0

        -- 选中指示条
        if anim > 0.01 then
            local barW = 28 * anim
            nvgBeginPath(vg)
            nvgRoundedRect(vg, centerX - barW / 2, y + 2, barW, 3, 1.5)
            nvgFillColor(vg, nvgRGBA(c.tab_active[1], c.tab_active[2], c.tab_active[3], math.floor(255 * anim)))
            nvgFill(vg)
        end

        -- 图标
        local img = imgCache[tab.icon]
        local icoS = 24 + 4 * anim  -- 选中时稍大
        local icoY = y + 12 - 2 * anim
        if img and img ~= 0 then
            if isActive then
                nvgGlobalAlpha(vg, 1.0)
            else
                nvgGlobalAlpha(vg, 0.5)
            end
            M.DrawImage(vg, img, centerX - icoS / 2, icoY, icoS, icoS)
            nvgGlobalAlpha(vg, 1.0)
        end

        -- 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if isActive then
            nvgFillColor(vg, nvgRGBA(c.tab_active[1], c.tab_active[2], c.tab_active[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(c.tab_inactive[1], c.tab_inactive[2], c.tab_inactive[3], 255))
        end
        nvgText(vg, centerX, y + 38, tab.name)
    end
end

------------------------------------------------------------------------
-- 战斗面板（关卡选择）
------------------------------------------------------------------------
function M.DrawBattlePanel(vg, W)
    local c = MD.CLR
    local y = L.contentY + L.pad
    local padX = L.pad

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, padX, y, "选择关卡")
    y = y + 28

    -- 进度条（总体进度）
    local progress = (saveData.maxLevel - 1) / (#MD.LEVELS - 1)
    local barW = W - padX * 2
    local barH = 6
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, y, barW, barH, 3)
    nvgFillColor(vg, nvgRGBA(40, 45, 58, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, y, barW * progress, barH, 3)
    nvgFillColor(vg, nvgRGBA(c.tab_active[1], c.tab_active[2], c.tab_active[3], 255))
    nvgFill(vg)
    y = y + barH + 12

    -- 关卡卡片列表
    for i, level in ipairs(MD.LEVELS) do
        local cardH = 72
        local cardY = y
        local unlocked = (i <= saveData.maxLevel)
        local stars = saveData.levelStars[i] or 0

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, cardY, W - padX * 2, cardH, 8)
        if unlocked then
            nvgFillColor(vg, nvgRGBA(c.bg_card[1], c.bg_card[2], c.bg_card[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(25, 28, 38, 200))
        end
        nvgFill(vg)

        -- 卡片边框
        nvgStrokeColor(vg, nvgRGBA(c.divider[1], c.divider[2], c.divider[3], unlocked and 200 or 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 关卡编号圆圈
        local circR = 18
        local circX = padX + 24
        local circY = cardY + cardH / 2
        nvgBeginPath(vg)
        nvgCircle(vg, circX, circY, circR)
        if unlocked then
            nvgFillColor(vg, nvgRGBA(c.tab_active[1], c.tab_active[2], c.tab_active[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(55, 60, 75, 255))
        end
        nvgFill(vg)

        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, unlocked and 255 or 100))
        nvgText(vg, circX, circY, tostring(i))

        -- 关卡名称 + 波次
        local textX = circX + circR + 12
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFontSize(vg, 14)
        if unlocked then
            nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(c.text_dim[1], c.text_dim[2], c.text_dim[3], 255))
        end
        nvgText(vg, textX, cardY + cardH / 2 - 10, level.name)

        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(c.text_gray[1], c.text_gray[2], c.text_gray[3], 255))
        nvgText(vg, textX, cardY + cardH / 2 + 8, level.waves .. "波  奖励:" .. level.reward_gold .. "金")

        -- 星星评级
        if stars > 0 then
            for s = 1, 3 do
                local sx = textX + (s - 1) * 16
                nvgFontSize(vg, 13)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                if s <= stars then
                    nvgFillColor(vg, nvgRGBA(c.text_gold[1], c.text_gold[2], c.text_gold[3], 255))
                    nvgText(vg, sx, cardY + cardH / 2 + 22, "★")
                else
                    nvgFillColor(vg, nvgRGBA(c.text_dim[1], c.text_dim[2], c.text_dim[3], 255))
                    nvgText(vg, sx, cardY + cardH / 2 + 22, "☆")
                end
            end
        end

        -- 宝箱图标（右侧）
        local chestImg = imgCache[MD.CHEST_ICONS[level.chest]]
        if chestImg and chestImg ~= 0 then
            local chS = 36
            M.DrawImage(vg, chestImg, W - padX - chS - 12, cardY + (cardH - chS) / 2, chS, chS)
        end

        -- 锁定遮罩
        if not unlocked then
            nvgFontSize(vg, 20)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(c.text_dim[1], c.text_dim[2], c.text_dim[3], 180))
            nvgText(vg, W - padX - 30, cardY + cardH / 2, "🔒")
        end

        y = y + cardH + L.cardGap
    end

    return math.max(0, y - L.contentY - L.contentH + 20)
end

------------------------------------------------------------------------
-- 商城面板
------------------------------------------------------------------------
function M.DrawShopPanel(vg, W)
    local c = MD.CLR
    local y = L.contentY + L.pad
    local padX = L.pad

    -- 抽卡区域
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, padX, y, "末日抽卡")
    y = y + 26

    -- 抽卡大卡片
    local gachaH = 100
    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, y, W - padX * 2, gachaH, 10)
    -- 渐变背景
    local grad = nvgLinearGradient(vg, padX, y, W - padX, y + gachaH,
        nvgRGBA(35, 50, 80, 255), nvgRGBA(55, 35, 75, 255))
    nvgFillPaint(vg, grad)
    nvgFill(vg)

    -- 边框光效
    nvgStrokeColor(vg, nvgRGBA(c.tab_active[1], c.tab_active[2], c.tab_active[3], 100))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 抽卡文字
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, W / 2, y + 25, "装备碎片抽取")

    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(c.text_gray[1], c.text_gray[2], c.text_gray[3], 255))
    nvgText(vg, W / 2, y + 44, "有机会获得稀有/史诗/传说装备碎片")

    -- 两个按钮
    local btnW = (W - padX * 2 - 12) / 2
    local btnH = 32
    local btnY = y + gachaH - btnH - 10
    -- 单抽
    M.DrawBtn(vg, padX + 6, btnY, btnW, btnH, "单抽 ×1", c.btn_primary, "💎" .. MD.SHOP_GACHA.cost_single)
    -- 十连
    M.DrawBtn(vg, padX + 6 + btnW + 8, btnY, btnW, btnH, "十连 ×10", c.btn_gold, "💎" .. MD.SHOP_GACHA.cost_ten)

    y = y + gachaH + 16

    -- 每日商品
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, padX, y, "每日限购")
    y = y + 24

    -- 商品网格 (2列)
    local cols = 2
    local gap = 8
    local itemW = (W - padX * 2 - gap * (cols - 1)) / cols
    local itemH = 100

    for i, item in ipairs(MD.SHOP_DAILY) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local ix = padX + col * (itemW + gap)
        local iy = y + row * (itemH + gap)

        -- 商品卡片
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ix, iy, itemW, itemH, 8)
        nvgFillColor(vg, nvgRGBA(c.bg_card[1], c.bg_card[2], c.bg_card[3], 255))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(c.divider[1], c.divider[2], c.divider[3], 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 图标
        local img = imgCache[item.icon]
        if img and img ~= 0 then
            local icoS = 32
            M.DrawImage(vg, img, ix + (itemW - icoS) / 2, iy + 8, icoS, icoS)
        end

        -- 名称
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
        nvgText(vg, ix + itemW / 2, iy + 44, item.name)

        -- 价格
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(120, 180, 255, 255))
        nvgText(vg, ix + itemW / 2, iy + 60, "💎 " .. item.price)

        -- 购买按钮
        M.DrawBtn(vg, ix + 8, iy + itemH - 28, itemW - 16, 22, "购买", c.btn_primary, nil)
    end

    local totalRows = math.ceil(#MD.SHOP_DAILY / cols)
    y = y + totalRows * (itemH + gap) + 10

    return math.max(0, y - L.contentY - L.contentH + 20)
end

------------------------------------------------------------------------
-- 装备面板
------------------------------------------------------------------------
function M.DrawEquipPanel(vg, W)
    local c = MD.CLR
    local y = L.contentY + L.pad
    local padX = L.pad

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, padX, y, "装备栏")
    y = y + 28

    -- 装备槽位网格 (3x2)
    local cols = 3
    local gap = 8
    local slotW = (W - padX * 2 - gap * (cols - 1)) / cols
    local slotH = 90

    for i, slot in ipairs(MD.EQUIP_SLOTS) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local sx = padX + col * (slotW + gap)
        local sy = y + row * (slotH + gap)

        -- 装备位背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, slotW, slotH, 8)
        nvgFillColor(vg, nvgRGBA(c.bg_card[1], c.bg_card[2], c.bg_card[3], 255))
        nvgFill(vg)

        -- 品质边框（如已装备）
        local equippedId = saveData.equipped[slot.id]
        local qualityClr = c.divider
        if equippedId then
            for _, eq in ipairs(MD.EQUIP_DB) do
                if eq.id == equippedId then
                    qualityClr = MD.QUALITY[eq.quality].color
                    break
                end
            end
        end
        nvgStrokeColor(vg, nvgRGBA(qualityClr[1], qualityClr[2], qualityClr[3], 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 图标
        local img = imgCache[slot.icon]
        if img and img ~= 0 then
            local icoS = 36
            M.DrawImage(vg, img, sx + (slotW - icoS) / 2, sy + 10, icoS, icoS)
        end

        -- 槽位名称
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(c.text_gray[1], c.text_gray[2], c.text_gray[3], 255))
        nvgText(vg, sx + slotW / 2, sy + 50, slot.name)

        -- 已装备物品名
        if equippedId then
            for _, eq in ipairs(MD.EQUIP_DB) do
                if eq.id == equippedId then
                    nvgFontSize(vg, 10)
                    local qc = MD.QUALITY[eq.quality].color
                    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
                    nvgText(vg, sx + slotW / 2, sy + 64, eq.name)
                    break
                end
            end
        else
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(c.text_dim[1], c.text_dim[2], c.text_dim[3], 255))
            nvgText(vg, sx + slotW / 2, sy + 64, "空")
        end
    end

    local slotRows = math.ceil(#MD.EQUIP_SLOTS / cols)
    y = y + slotRows * (slotH + gap) + 16

    -- 背包区域
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, padX, y, "背包")
    y = y + 24

    -- 背包物品网格 (4列)
    local invCols = 4
    local invSlotW = (W - padX * 2 - gap * (invCols - 1)) / invCols
    local invSlotH = 70

    for i, itemId in ipairs(saveData.inventory) do
        -- 查找物品数据
        local itemData = nil
        for _, eq in ipairs(MD.EQUIP_DB) do
            if eq.id == itemId then itemData = eq; break end
        end
        if not itemData then goto continue end

        local col = (i - 1) % invCols
        local row = math.floor((i - 1) / invCols)
        local ix = padX + col * (invSlotW + gap)
        local iy = y + row * (invSlotH + gap)

        -- 物品格子
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ix, iy, invSlotW, invSlotH, 6)
        nvgFillColor(vg, nvgRGBA(c.bg_card[1], c.bg_card[2], c.bg_card[3], 255))
        nvgFill(vg)
        local qc = MD.QUALITY[itemData.quality].color
        nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 图标
        local img = imgCache[itemData.icon]
        if img and img ~= 0 then
            local icoS = 28
            M.DrawImage(vg, img, ix + (invSlotW - icoS) / 2, iy + 6, icoS, icoS)
        end

        -- 名称
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
        nvgText(vg, ix + invSlotW / 2, iy + 38, itemData.name)

        -- 品质标签
        nvgFontSize(vg, 8)
        nvgFillColor(vg, nvgRGBA(c.text_dim[1], c.text_dim[2], c.text_dim[3], 255))
        nvgText(vg, ix + invSlotW / 2, iy + 52, MD.QUALITY[itemData.quality].name)

        ::continue::
    end

    local invRows = math.ceil(#saveData.inventory / invCols)
    y = y + math.max(1, invRows) * (invSlotH + gap) + 10

    return math.max(0, y - L.contentY - L.contentH + 20)
end

------------------------------------------------------------------------
-- 列车/炮塔升级面板
------------------------------------------------------------------------
function M.DrawTrainPanel(vg, W)
    local c = MD.CLR
    local y = L.contentY + L.pad
    local padX = L.pad

    -- 标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
    nvgText(vg, padX, y, "炮塔升级")
    y = y + 28

    -- 炮塔列表
    for i, turret in ipairs(MD.TURRET_UPGRADES) do
        local cardH = 70
        local cardY = y

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, cardY, W - padX * 2, cardH, 8)
        nvgFillColor(vg, nvgRGBA(c.bg_card[1], c.bg_card[2], c.bg_card[3], 255))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(c.divider[1], c.divider[2], c.divider[3], 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 炮塔图标
        local img = imgCache[turret.icon]
        if img and img ~= 0 then
            local icoS = 40
            M.DrawImage(vg, img, padX + 12, cardY + (cardH - icoS) / 2, icoS, icoS)
        end

        -- 炮塔名称
        local textX = padX + 60
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(c.text_white[1], c.text_white[2], c.text_white[3], 255))
        nvgText(vg, textX, cardY + cardH / 2 - 10, turret.name)

        -- 等级 + 碎片
        local lv = (saveData.turretLevels[turret.id] or 0)
        local frags = (saveData.turretFrags[turret.id] or 0)
        local needFrags = math.floor(turret.fragBase * (turret.fragGrow ^ lv))

        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(c.text_gray[1], c.text_gray[2], c.text_gray[3], 255))
        nvgText(vg, textX, cardY + cardH / 2 + 6, "Lv." .. lv .. "/" .. turret.maxLv)

        -- 碎片进度条
        local progX = textX
        local progY = cardY + cardH / 2 + 18
        local progW = 80
        local progH = 5
        local progFill = math.min(1.0, frags / needFrags)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, progX, progY, progW, progH, 2)
        nvgFillColor(vg, nvgRGBA(30, 32, 40, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, progX, progY, progW * progFill, progH, 2)
        nvgFillColor(vg, nvgRGBA(c.tab_active[1], c.tab_active[2], c.tab_active[3], 255))
        nvgFill(vg)

        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(c.text_dim[1], c.text_dim[2], c.text_dim[3], 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(vg, progX + progW + 4, progY - 2, frags .. "/" .. needFrags)

        -- 升级按钮
        local canUpgrade = (lv < turret.maxLv and frags >= needFrags)
        local btnW2 = 56
        local btnH2 = 26
        local btnClr = canUpgrade and c.btn_primary or c.btn_secondary
        M.DrawBtn(vg, W - padX - btnW2 - 8, cardY + (cardH - btnH2) / 2, btnW2, btnH2, "升级", btnClr, nil)

        y = y + cardH + L.cardGap
    end

    return math.max(0, y - L.contentY - L.contentH + 20)
end

------------------------------------------------------------------------
-- 天赋面板（阶梯式）
------------------------------------------------------------------------
-- 绘制六边形路径（中心 cx,cy，外接半径 r）
local function hexPath(vg, cx, cy, r)
    nvgBeginPath(vg)
    for k = 0, 5 do
        local ang = math.rad(60 * k - 90)  -- 顶部尖角起
        local px = cx + r * math.cos(ang)
        local py = cy + r * math.sin(ang)
        if k == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgClosePath(vg)
end

-- 天赋面板布局常量（供点击判定复用）
local TALENT_HEX_R    = 32          -- 六边形外接半径
local TALENT_SPACING  = 95          -- 节点间距（中心到中心）
local TALENT_START_Y_OFFSET = 40    -- 顶部留白
local TALENT_CENTERX_RATIO = 0.35   -- 主轴 X 占比

-- 预生成雪花数据（避免每帧 randomseed）
local snowParticles = {}
do
    math.randomseed(314)
    for s = 1, 40 do
        snowParticles[s] = {
            x0    = math.random() * 1.2 - 0.1,  -- 归一化 X（-0.1 ~ 1.1）
            speed = 0.3 + math.random() * 0.6,   -- 下落速度因子
            size  = 1.0 + math.random() * 2.5,
            drift = (math.random() - 0.5) * 0.4, -- 水平漂移
            phase = math.random() * 6.28,         -- 初始相位
            alpha = 80 + math.floor(math.random() * 120),
        }
    end
    math.randomseed(math.floor(os.clock() * 1000))
end

-- 判断天赋 i 是否可解锁（前一个已激活 or 第一个天赋）
local function canUnlockTalent(i)
    if i == 1 then return true end  -- 第一个天赋无条件可解锁
    local prevTalent = MD.TALENTS[i - 1]
    local prevLv = (saveData.talents[prevTalent.id] or 0)
    return prevLv >= 1  -- 前一个已激活
end

function M.DrawTalentPanel(vg, W)
    local c = MD.CLR
    local n = #MD.TALENTS
    local baseY = L.contentY + L.pad
    local hexR = TALENT_HEX_R
    local spacing = TALENT_SPACING
    local centerX = W * 0.5  -- 节点居中
    local totalH_content = n * spacing + TALENT_START_Y_OFFSET + 60
    local startY = baseY + TALENT_START_Y_OFFSET
    local t = elapsedTime  -- 动画时间

    -- ================================================================
    -- 1. 背景图 + 动态飘雪叠加
    -- ================================================================
    -- 背景图（cover-fit 铺满）
    local bgImg = imgCache["talent_bg"]
    if bgImg and bgImg ~= 0 then
        local imgW, imgH = 572, 1024  -- 生成图的实际尺寸
        local scale = math.max(W / imgW, totalH_content / imgH)
        local drawW = imgW * scale
        local drawH = imgH * scale
        local ox = (W - drawW) / 2
        local oy = baseY + (totalH_content - drawH) / 2
        local paint = nvgImagePattern(vg, ox, oy, drawW, drawH, 0, bgImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, baseY, W, totalH_content)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- fallback 纯色
        nvgBeginPath(vg)
        nvgRect(vg, 0, baseY, W, totalH_content)
        nvgFillColor(vg, nvgRGBA(15, 20, 40, 255))
        nvgFill(vg)
    end

    -- 轻微暗化叠层（让节点更突出）
    nvgBeginPath(vg)
    nvgRect(vg, 0, baseY, W, totalH_content)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
    nvgFill(vg)

    -- 动态飘雪（保留动感）
    for s = 1, #snowParticles do
        local p = snowParticles[s]
        local sx = (p.x0 + math.sin(t * 0.8 + p.phase) * p.drift) * W
        local sy = baseY + ((t * p.speed * 50 + p.phase * 100) % totalH_content)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, p.size)
        nvgFillColor(vg, nvgRGBA(220, 235, 255, p.alpha))
        nvgFill(vg)
    end

    -- ================================================================
    -- 2. 金币标签（右上角）
    -- ================================================================
    nvgFontFace(vg, "sans")
    nvgBeginPath(vg)
    nvgRoundedRect(vg, W - 94, baseY + 8, 84, 22, 11)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
    nvgText(vg, W - 14, baseY + 19, "💰 " .. saveData.gold)

    -- ================================================================
    -- 3. 中轴连接线（参考图二：激活区间绿色，锁定区间灰色）
    -- ================================================================
    local lineW = 6  -- 连接线宽度

    -- 逐段绘制连接线（从底部 i=1 到顶部 i=n）
    for i = 1, n - 1 do
        local slotBot = n - i       -- 下方节点 slot
        local slotTop = n - (i + 1) -- 上方节点 slot
        local botCY = startY + slotBot * spacing + hexR
        local topCY = startY + slotTop * spacing + hexR

        local lvBot = (saveData.talents[MD.TALENTS[i].id] or 0)
        local lvTop = (saveData.talents[MD.TALENTS[i + 1].id] or 0)
        local botActive = (lvBot >= 1)
        local topActive = (lvTop >= 1)

        nvgBeginPath(vg)
        nvgMoveTo(vg, centerX, botCY - hexR)
        nvgLineTo(vg, centerX, topCY + hexR)
        if botActive and topActive then
            -- 两端都激活：绿色
            nvgStrokeColor(vg, nvgRGBA(80, 210, 120, 255))
        elseif botActive then
            -- 下方激活，上方未激活：绿色（可解锁段）
            nvgStrokeColor(vg, nvgRGBA(80, 210, 120, 200))
        else
            -- 都未激活：灰色
            nvgStrokeColor(vg, nvgRGBA(70, 75, 90, 180))
        end
        nvgStrokeWidth(vg, lineW)
        nvgStroke(vg)
    end

    -- ================================================================
    -- 4. 绘制节点（反转：i=1 在底部，i=n 在顶部）
    --    状态：已激活(lit) / 可激活(next) / 锁定(locked)
    -- ================================================================
    for i, talent in ipairs(MD.TALENTS) do
        local lv = (saveData.talents[talent.id] or 0)
        local activated = (lv >= 1)
        local unlockable = (not activated) and canUnlockTalent(i)

        -- 反转 Y：i=1 在底部 (slot = n-1), i=n 在顶部 (slot = 0)
        local slot = n - i
        local cy = startY + slot * spacing + hexR
        local cx = centerX

        -- 微动呼吸动画（已激活节点）
        local breathe = 0
        if activated then
            breathe = math.sin(t * 2.0 + i * 0.8) * 1.5
        end
        local drawR = hexR + breathe

        -- 六边形外发光（已激活）
        if activated then
            local glowA = math.floor(30 + 20 * math.sin(t * 1.5 + i))
            hexPath(vg, cx, cy, drawR + 6)
            nvgFillColor(vg, nvgRGBA(255, 200, 50, glowA))
            nvgFill(vg)
        elseif unlockable then
            -- 可激活的下一个节点：脉冲提示
            local pulseA = math.floor(15 + 12 * math.sin(t * 3.0))
            hexPath(vg, cx, cy, hexR + 5)
            nvgFillColor(vg, nvgRGBA(80, 220, 120, pulseA))
            nvgFill(vg)
        end

        -- 六边形阴影
        hexPath(vg, cx + 2, cy + 3, drawR + 1)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 50))
        nvgFill(vg)

        -- 六边形底色
        hexPath(vg, cx, cy, drawR)
        if activated then
            -- 已激活：金色
            local grd = nvgLinearGradient(vg, cx, cy - drawR, cx, cy + drawR,
                nvgRGBA(200, 170, 50, 255), nvgRGBA(150, 120, 25, 255))
            nvgFillPaint(vg, grd)
        elseif unlockable then
            -- 可激活：深蓝（稍亮）
            local grd = nvgLinearGradient(vg, cx, cy - drawR, cx, cy + drawR,
                nvgRGBA(50, 100, 160, 255), nvgRGBA(35, 70, 120, 255))
            nvgFillPaint(vg, grd)
        else
            -- 锁定：灰暗
            local grd = nvgLinearGradient(vg, cx, cy - drawR, cx, cy + drawR,
                nvgRGBA(45, 48, 58, 255), nvgRGBA(32, 35, 42, 255))
            nvgFillPaint(vg, grd)
        end
        nvgFill(vg)

        -- 六边形边框
        hexPath(vg, cx, cy, drawR)
        if activated then
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 230))
            nvgStrokeWidth(vg, 3)
        elseif unlockable then
            nvgStrokeColor(vg, nvgRGBA(100, 200, 140, 200))
            nvgStrokeWidth(vg, 2.5)
        else
            nvgStrokeColor(vg, nvgRGBA(55, 58, 68, 180))
            nvgStrokeWidth(vg, 2)
        end
        nvgStroke(vg)

        -- 图标（锁定状态半透明）
        local img = imgCache[talent.icon]
        if img and img ~= 0 then
            local icoS = drawR * 1.1
            if not activated and not unlockable then
                nvgGlobalAlpha(vg, 0.35)
            end
            M.DrawImage(vg, img, cx - icoS / 2, cy - icoS / 2, icoS, icoS)
            nvgGlobalAlpha(vg, 1.0)
        end

        -- 节点下方：天赋名称（简短标识）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if activated then
            nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
        elseif unlockable then
            nvgFillColor(vg, nvgRGBA(200, 220, 240, 200))
        else
            nvgFillColor(vg, nvgRGBA(100, 105, 115, 150))
        end
        nvgText(vg, cx, cy + drawR + 4, talent.name)

        -- 锁定节点：显示锁图标
        if not activated and not unlockable then
            nvgFontSize(vg, 18)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(100, 105, 115, 140))
            nvgText(vg, cx, cy, "🔒")
        end

        -- 已激活节点：勾号
        if activated then
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, cx + drawR * 0.55, cy - drawR * 0.55, "✓")
        end
    end

    -- ================================================================
    -- 5. 弹窗（在滚动之外层绘制，需要特殊处理）
    --    实际在 Draw 主入口 restore 之后绘制，见 DrawTalentPopup
    -- ================================================================

    return math.max(0, totalH_content - L.contentH + 20)
end

------------------------------------------------------------------------
-- 天赋弹窗（覆盖层，不受滚动影响）
------------------------------------------------------------------------
function M.DrawTalentPopup(vg, W, H)
    if not talentPopup.show then return end
    local idx = talentPopup.idx
    if idx < 1 or idx > #MD.TALENTS then
        talentPopup.show = false
        return
    end

    local talent = MD.TALENTS[idx]
    local lv = (saveData.talents[talent.id] or 0)
    local activated = (lv >= 1)
    local unlockable = (not activated) and canUnlockTalent(idx)
    local cost = talent.costBase  -- 单次激活，固定费用
    local canAfford = (saveData.gold >= cost)
    local c = MD.CLR
    local t = elapsedTime

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗卡片
    local popW = math.min(W * 0.75, 260)
    local popH = 260
    local popX = (W - popW) / 2
    local popY = (H - popH) / 2

    -- 卡片阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popX + 3, popY + 4, popW, popH, 14)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgFill(vg)

    -- 卡片背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popX, popY, popW, popH, 14)
    local bgGrad = nvgLinearGradient(vg, popX, popY, popX, popY + popH,
        nvgRGBA(30, 38, 55, 250), nvgRGBA(22, 28, 40, 250))
    nvgFillPaint(vg, bgGrad)
    nvgFill(vg)

    -- 卡片边框
    nvgStrokeWidth(vg, 1.5)
    if activated then
        nvgStrokeColor(vg, nvgRGBA(255, 210, 60, 180))
    elseif unlockable then
        nvgStrokeColor(vg, nvgRGBA(80, 200, 140, 180))
    else
        nvgStrokeColor(vg, nvgRGBA(60, 65, 80, 180))
    end
    nvgStroke(vg)

    -- 关闭按钮（右上角 X）
    local closeR = 14
    local closeX = popX + popW - 20
    local closeY = popY + 20
    nvgBeginPath(vg)
    nvgCircle(vg, closeX, closeY, closeR)
    nvgFillColor(vg, nvgRGBA(60, 65, 80, 200))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 205, 215, 220))
    nvgText(vg, closeX, closeY, "✕")

    -- 天赋图标（顶部居中，带六边形框）
    local iconCX = popX + popW / 2
    local iconCY = popY + 52
    local iconR = 30

    -- 六边形底色
    hexPath(vg, iconCX, iconCY, iconR)
    if activated then
        local grd = nvgLinearGradient(vg, iconCX, iconCY - iconR, iconCX, iconCY + iconR,
            nvgRGBA(200, 170, 50, 255), nvgRGBA(150, 120, 25, 255))
        nvgFillPaint(vg, grd)
    elseif unlockable then
        local grd = nvgLinearGradient(vg, iconCX, iconCY - iconR, iconCX, iconCY + iconR,
            nvgRGBA(50, 100, 160, 255), nvgRGBA(35, 70, 120, 255))
        nvgFillPaint(vg, grd)
    else
        nvgFillColor(vg, nvgRGBA(50, 55, 65, 255))
    end
    nvgFill(vg)

    hexPath(vg, iconCX, iconCY, iconR)
    if activated then
        nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 230))
    elseif unlockable then
        nvgStrokeColor(vg, nvgRGBA(100, 200, 140, 200))
    else
        nvgStrokeColor(vg, nvgRGBA(70, 75, 85, 180))
    end
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 图标
    local img = imgCache[talent.icon]
    if img and img ~= 0 then
        local icoS = iconR * 1.2
        M.DrawImage(vg, img, iconCX - icoS / 2, iconCY - icoS / 2, icoS, icoS)
    end

    -- 天赋名称
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(240, 245, 255, 255))
    nvgText(vg, popX + popW / 2, iconCY + iconR + 10, talent.name)

    -- 分割线
    local divY = iconCY + iconR + 34
    nvgBeginPath(vg)
    nvgMoveTo(vg, popX + 20, divY)
    nvgLineTo(vg, popX + popW - 20, divY)
    nvgStrokeColor(vg, nvgRGBA(60, 65, 80, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 效果描述
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 230))
    nvgText(vg, popX + popW / 2, divY + 12, talent.desc)

    -- 状态标签
    local statusY = divY + 38
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if activated then
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, popX + popW / 2, statusY, "已激活 ✓")
    elseif not unlockable then
        nvgFillColor(vg, nvgRGBA(130, 135, 150, 200))
        nvgText(vg, popX + popW / 2, statusY, "需先激活前置天赋")
    else
        -- 费用显示
        nvgFillColor(vg, nvgRGBA(c.text_gray[1], c.text_gray[2], c.text_gray[3], 255))
        nvgText(vg, popX + popW / 2, statusY, "激活费用")

        -- 金币数字
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, popX + popW / 2, statusY + 18, "💰 " .. cost)

        -- 当前余额 / 费用
        nvgFontSize(vg, 11)
        if canAfford then
            nvgFillColor(vg, nvgRGBA(100, 220, 130, 200))
        else
            nvgFillColor(vg, nvgRGBA(220, 80, 60, 200))
        end
        nvgText(vg, popX + popW / 2, statusY + 44, "拥有: " .. saveData.gold .. " / 需要: " .. cost)
    end

    -- 底部按钮
    local btnW = popW - 40
    local btnH = 38
    local btnX = popX + 20
    local btnY = popY + popH - btnH - 16

    if activated then
        -- 已激活：灰色"已激活"按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
        nvgFillColor(vg, nvgRGBA(50, 55, 65, 200))
        nvgFill(vg)
        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(130, 135, 145, 200))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "已激活")
    elseif unlockable then
        -- 可激活：绿色"激活"按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
        if canAfford then
            local bg = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
                nvgRGBA(55, 170, 95, 255), nvgRGBA(35, 130, 65, 255))
            nvgFillPaint(vg, bg)
        else
            nvgFillColor(vg, nvgRGBA(50, 55, 65, 200))
        end
        nvgFill(vg)
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, canAfford and 255 or 100))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "激活")
    else
        -- 锁定：灰色按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 8)
        nvgFillColor(vg, nvgRGBA(40, 43, 52, 200))
        nvgFill(vg)
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 105, 115, 160))
        nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "🔒 未解锁")
    end
end

------------------------------------------------------------------------
-- 通用工具函数
------------------------------------------------------------------------

-- 绘制精灵图
function M.DrawImage(vg, img, x, y, w, h)
    if not img or img == 0 then return end
    local paint = nvgImagePattern(vg, x, y, w, h, 0, img, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

-- 绘制按钮
function M.DrawBtn(vg, x, y, w, h, text, clr, subText)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 4)
    nvgFillColor(vg, nvgRGBA(clr[1], clr[2], clr[3], clr[4] or 255))
    nvgFill(vg)

    nvgFontFace(vg, "sans")

    if subText then
        -- 主文字 + 副文字 (并排)
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, x + w / 2, y + h / 2 - 6, text)
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(200, 210, 230, 255))
        nvgText(vg, x + w / 2, y + h / 2 + 6, subText)
    else
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, x + w / 2, y + h / 2, text)
    end
end

------------------------------------------------------------------------
-- 点击处理
------------------------------------------------------------------------
function M.HandleClick(x, y, W, H)
    M.CalcLayout(W, H)

    -- 天赋弹窗优先拦截
    if talentPopup.show then
        return M.HandleTalentPopupClick(x, y, W, H)
    end

    -- 底部Tab检测
    local tabY = H - L.tabBarH
    if y >= tabY then
        local tabCount = #MD.TABS
        local tabW = W / tabCount
        local tabIndex = math.floor(x / tabW) + 1
        if tabIndex >= 1 and tabIndex <= tabCount then
            local newTab = MD.TABS[tabIndex].id
            if newTab ~= activeTab then
                activeTab = newTab
                scrollY = 0
                panelAlpha = 0.3
                panelFadeTarget = 1.0
                print("[Meta] Tab switched to: " .. activeTab)
            end
        end
        return true
    end

    -- 内容区域点击
    if y >= L.contentY and y < tabY then
        local contentClickY = y + scrollY  -- 考虑滚动偏移

        if activeTab == "battle" then
            return M.HandleBattleClick(x, contentClickY, W)
        elseif activeTab == "talent" then
            return M.HandleTalentClick(x, contentClickY, W)
        elseif activeTab == "train" then
            return M.HandleTrainClick(x, contentClickY, W)
        elseif activeTab == "shop" then
            return M.HandleShopClick(x, contentClickY, W)
        end
    end

    return true
end

-- 战斗面板点击（选关卡开始游戏）
function M.HandleBattleClick(x, y, W)
    local padX = L.pad
    local startY = L.contentY + L.pad + 28 + 6 + 12  -- 标题+进度条+间距

    for i, level in ipairs(MD.LEVELS) do
        local cardH = 72
        local cardY = startY + (i - 1) * (cardH + L.cardGap)
        local unlocked = (i <= saveData.maxLevel)

        if unlocked and x >= padX and x <= W - padX and y >= cardY and y <= cardY + cardH then
            print("[Meta] Start level " .. i .. ": " .. level.name)
            return "start_level", i
        end
    end
    return true
end

-- 天赋弹窗点击处理（在屏幕坐标，不含滚动偏移）
function M.HandleTalentPopupClick(x, y, W, H)
    if not talentPopup.show then return false end
    local idx = talentPopup.idx
    local talent = MD.TALENTS[idx]
    if not talent then
        talentPopup.show = false
        return true
    end

    local popW = math.min(W * 0.75, 260)
    local popH = 260
    local popX = (W - popW) / 2
    local popY = (H - popH) / 2

    -- 关闭按钮检测（右上角圆形）
    local closeX = popX + popW - 20
    local closeY = popY + 20
    local closeR = 14
    local cdx = x - closeX
    local cdy = y - closeY
    if cdx * cdx + cdy * cdy <= closeR * closeR then
        talentPopup.show = false
        print("[Meta] Talent popup closed")
        return true
    end

    -- 底部按钮检测（激活按钮）
    local btnW = popW - 40
    local btnH = 38
    local btnX = popX + 20
    local btnY = popY + popH - btnH - 16

    if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
        local lv = (saveData.talents[talent.id] or 0)
        local activated = (lv >= 1)
        local unlockable = (not activated) and canUnlockTalent(idx)
        local cost = talent.costBase

        if unlockable and saveData.gold >= cost then
            saveData.gold = saveData.gold - cost
            saveData.talents[talent.id] = 1
            print("[Meta] Talent " .. talent.name .. " activated!")
            talentPopup.show = false
        elseif unlockable then
            print("[Meta] Not enough gold for " .. talent.name)
        end
        return true
    end

    -- 点击弹窗外部区域 → 关闭
    if x < popX or x > popX + popW or y < popY or y > popY + popH then
        talentPopup.show = false
        print("[Meta] Talent popup closed (outside)")
        return true
    end

    return true  -- 弹窗内其他区域消费点击
end

-- 天赋面板点击（打开弹窗）
function M.HandleTalentClick(x, y, W)
    local n = #MD.TALENTS
    local centerX = W * 0.5
    local hexR = TALENT_HEX_R
    local spacing = TALENT_SPACING
    local startY = L.contentY + L.pad + TALENT_START_Y_OFFSET

    for i, talent in ipairs(MD.TALENTS) do
        -- 反转 Y：与绘制逻辑一致
        local slot = n - i
        local cy = startY + slot * spacing + hexR
        local cx = centerX

        -- 点击六边形节点 → 打开弹窗
        local dx = x - cx
        local dy2 = y - cy
        if dx * dx + dy2 * dy2 <= (hexR + 5) * (hexR + 5) then
            talentPopup.show = true
            talentPopup.idx = i
            print("[Meta] Open talent popup: " .. talent.name)
            return true
        end
    end
    return true
end

-- 火车面板点击
function M.HandleTrainClick(x, y, W)
    local padX = L.pad
    local startY = L.contentY + L.pad + 28

    for i, turret in ipairs(MD.TURRET_UPGRADES) do
        local cardH = 70
        local cardY = startY + (i - 1) * (cardH + L.cardGap)
        local lv = (saveData.turretLevels[turret.id] or 0)
        local frags = (saveData.turretFrags[turret.id] or 0)
        local needFrags = math.floor(turret.fragBase * (turret.fragGrow ^ lv))

        -- 升级按钮
        local btnW2 = 56
        local btnH2 = 26
        local btnX = W - padX - btnW2 - 8
        local btnY = cardY + (cardH - btnH2) / 2

        if x >= btnX and x <= btnX + btnW2 and y >= btnY and y <= btnY + btnH2 then
            if lv < turret.maxLv and frags >= needFrags then
                saveData.turretFrags[turret.id] = frags - needFrags
                saveData.turretLevels[turret.id] = lv + 1
                print("[Meta] Turret " .. turret.name .. " upgraded to Lv." .. (lv + 1))
            end
            return true
        end
    end
    return true
end

-- 商城面板点击
function M.HandleShopClick(x, y, W)
    -- 简化处理：检测购买按钮
    local padX = L.pad
    local c = MD.CLR

    -- 检测每日商品购买按钮
    local dailyStartY = L.contentY + L.pad + 26 + 100 + 16 + 24
    local cols = 2
    local gap = 8
    local itemW = (W - padX * 2 - gap * (cols - 1)) / cols
    local itemH = 100

    for i, item in ipairs(MD.SHOP_DAILY) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local ix = padX + col * (itemW + gap)
        local iy = dailyStartY + row * (itemH + gap)

        -- 购买按钮区域
        local btnX = ix + 8
        local btnY = iy + itemH - 28
        local btnW = itemW - 16
        local btnH = 22

        if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
            if saveData.diamond >= item.price then
                saveData.diamond = saveData.diamond - item.price
                -- 发放奖励（简化）
                if item.id == "daily_gold" then saveData.gold = saveData.gold + 500 end
                if item.id == "daily_wood" then saveData.wood = saveData.wood + 20 end
                if item.id == "daily_stone" then saveData.stone = saveData.stone + 15 end
                print("[Meta] Bought " .. item.name)
            else
                print("[Meta] Not enough diamonds")
            end
            return true
        end
    end

    return true
end

------------------------------------------------------------------------
-- 滚动处理
------------------------------------------------------------------------
function M.HandleTouchStart(x, y)
    touchStartY = y
    isDragging = false
end

function M.HandleTouchMove(x, y)
    local dy = touchStartY - y
    if math.abs(dy) > 5 then
        isDragging = true
    end
    if isDragging then
        scrollY = math.max(0, math.min(maxScrollY, scrollY + dy))
        touchStartY = y
    end
end

function M.HandleTouchEnd()
    isDragging = false
end

function M.GetActiveTab()
    return activeTab
end

function M.SetActiveTab(tabId)
    if activeTab ~= tabId then
        activeTab = tabId
        scrollY = 0
        panelAlpha = 0.3
        panelFadeTarget = 1.0
    end
end

return M

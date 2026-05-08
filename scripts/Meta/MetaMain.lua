-- Meta/MetaMain.lua - 局外系统主模块
-- NanoVG 渲染的完整局外 UI：顶栏 + 底部Tab + 5个面板
-- 与游戏内 NanoVG 管线一致，通过 main.lua 状态切换

local MD = require("Meta.MetaData")
local Def = require("Editor.UIElementDef")

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

-- 装备面板状态
local equipState = {
    catIndex = 2,           -- 子标签页: 1=角色, 2=装备, 3=藏品
    sortMode = 1,           -- 1=默认, 2=等级, 3=品质
    isLocked = false,       -- 锁定模式
    showDropdown = false,   -- 一键分解下拉菜单
    showConfirm = false,    -- 确认弹窗
    confirmQuality = nil,   -- 选中的分解品质
}
local SORT_LABELS = { "排序:默认", "排序:等级", "排序:品质" }
local DECOMPOSE_QUALITIES = {
    { label = "普通及以下", color = {160, 160, 160} },
    { label = "优质及以下", color = { 60, 180,  80} },
    { label = "稀有及以下", color = { 60, 140, 220} },
    { label = "史诗及以下", color = {160,  80, 200} },
    { label = "传说",       color = {220, 160,  40} },
}
-- 副框按钮点击区域缓存
local equipSubBtns = {}  -- { {x,y,w,h,id}, ... }

-- 炮塔装备面板
local turretDetailId = nil  -- 当前打开的炮塔详情弹窗ID（nil=关闭）

-- 装备详情弹窗
local equipDetailIdx = nil  -- 当前打开的背包装备索引（nil=关闭）

-- 角色详情弹窗
local charDetailId = nil    -- 当前打开的角色ID（nil=关闭）
local charAnimTimer = 0     -- 角色攻击帧动画计时器

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

    -- 获取真实账号信息
    ---@diagnostic disable-next-line: undefined-global
    local ok, myId = pcall(function() return lobby:GetMyUserId() end)
    if ok and myId and myId ~= 0 then
        saveData.userId = myId
        GetUserNickname({
            userIds = { myId },
            onSuccess = function(nicknames)
                if nicknames and #nicknames > 0 and nicknames[1].nickname then
                    saveData.playerName = nicknames[1].nickname
                    print("[Meta] Real nickname loaded: " .. saveData.playerName)
                end
            end,
            onError = function(errorCode)
                print("[Meta] GetUserNickname failed, errorCode=" .. tostring(errorCode))
            end
        })
    end
end

function M.PreloadImages(vg)
    -- Tab 按钮图片（选中 + 未选中）
    for _, tab in ipairs(MD.TABS) do
        imgCache[tab.img_normal] = nvgCreateImage(vg, tab.img_normal, 0)
        imgCache[tab.img_active] = nvgCreateImage(vg, tab.img_active, 0)
    end
    -- 货币图标
    for k, path in pairs(MD.CURRENCY_ICONS) do
        imgCache[path] = nvgCreateImage(vg, path, 0)
    end
    -- 装备图标
    for _, slot in ipairs(MD.EQUIP_SLOTS) do
        imgCache[slot.icon] = nvgCreateImage(vg, slot.icon, 0)
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
    -- 开始战斗按钮
    imgCache["start_battle_btn"] = nvgCreateImage(vg, "image/开始战斗按钮.png", 0)
    imgCache["common_bg"] = nvgCreateImage(vg, "image/通用背景.png", 0)
    -- 关卡场景图片
    imgCache["level_scene"] = nvgCreateImage(vg, "image/图层_13.png", 0)
    -- 头像框
    imgCache["avatar_frame"] = nvgCreateImage(vg, "image/Layer_0.png", 0)
    imgCache["avatar_portrait"] = nvgCreateImage(vg, "image/Layer_0 (1).png", 0)
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
    -- 商城界面素材
    imgCache["shop_title"]       = nvgCreateImage(vg, "image/商城界面/商城.png", 0)
    imgCache["shop_gacha_bg"]    = nvgCreateImage(vg, "image/商城界面/抽奖底.png", 0)
    imgCache["shop_single_btn"]  = nvgCreateImage(vg, "image/商城界面/单抽框2.png", 0)
    imgCache["shop_ten_btn"]     = nvgCreateImage(vg, "image/商城界面/十连抽框2.png", 0)
    imgCache["shop_item_frame"]  = nvgCreateImage(vg, "image/商城界面/商城界面商品底框.png", 0)
    imgCache["shop_diamond_btn"] = nvgCreateImage(vg, "image/商城界面/钻石购买框.png", 0)
    imgCache["shop_diamond_icon"] = nvgCreateImage(vg, "image/图层_4 (1).png", 0)
    imgCache["shop_free_btn"]    = nvgCreateImage(vg, "image/商城界面/免费框.png", 0)
    imgCache["shop_daily_title"] = nvgCreateImage(vg, "image/商城界面/每日商品.png", 0)
    -- 战斗面板按钮图标
    imgCache["btn_settings"]     = nvgCreateImage(vg, "image/设置.png", 0)
    imgCache["btn_announce"]     = nvgCreateImage(vg, "image/公告.png", 0)
    imgCache["btn_ranking"]      = nvgCreateImage(vg, "image/排行.png", 0)
    imgCache["btn_signin"]       = nvgCreateImage(vg, "image/签到.png", 0)
    imgCache["btn_red_badge"]    = nvgCreateImage(vg, "image/左上角通用红标.png", 0)
    -- 装备界面素材
    imgCache["equip_bg"]           = nvgCreateImage(vg, "image/装备界面/装备背景.png", 0)
    imgCache["equip_hero"]         = nvgCreateImage(vg, "image/装备界面/装备界面主角 .png", 0)
    imgCache["equip_slot_frame"]   = nvgCreateImage(vg, "image/装备界面/装备界面顶部装备栏.png", 0)
    imgCache["equip_cat_label"]    = nvgCreateImage(vg, "image/装备界面/系类.png", 0)
    imgCache["equip_cat_active"]   = nvgCreateImage(vg, "image/装备界面/分类选中.png", 0)
    imgCache["equip_cat_inactive"] = nvgCreateImage(vg, "image/装备界面/分类未选中.png", 0)
    imgCache["equip_grid_bg"]      = nvgCreateImage(vg, "image/装备界面/装备界面装备底部栏.png", 0)
    imgCache["equip_grid_slot"]    = nvgCreateImage(vg, "image/装备界面/装备底部栏装备.png", 0)
    imgCache["equip_sub_inner"]    = nvgCreateImage(vg, "image/装备界面/装备界面副框内.png", 0)
    imgCache["equip_sub_outer"]    = nvgCreateImage(vg, "image/装备界面/装备界面副框外.png", 0)
    -- 角色系统图片预加载
    for _, charDef in ipairs(MD.CHARACTERS) do
        imgCache["char_" .. charDef.id] = nvgCreateImage(vg, charDef.icon, 0)
        -- 头像和装备展示图预加载
        if charDef.portrait then
            imgCache["char_portrait_" .. charDef.id] = nvgCreateImage(vg, charDef.portrait, 0)
        end
        if charDef.equipDisplay then
            imgCache["char_equip_" .. charDef.id] = nvgCreateImage(vg, charDef.equipDisplay, 0)
        end
        -- 攻击帧动画预加载
        if charDef.attackFrames then
            for fi, framePath in ipairs(charDef.attackFrames) do
                imgCache["char_atk_" .. charDef.id .. "_" .. fi] = nvgCreateImage(vg, framePath, 0)
            end
        end
        -- 行走帧动画预加载
        if charDef.walkFrames then
            for fi, framePath in ipairs(charDef.walkFrames) do
                imgCache["char_walk_" .. charDef.id .. "_" .. fi] = nvgCreateImage(vg, framePath, 0)
            end
        end
    end
    -- 炮塔装备界面素材
    imgCache["turret_train_bg"]    = nvgCreateImage(vg, "image/炮塔界面/3409728c-6db3-454f-a6a7-82f9105b8f9c.png", 0)
    imgCache["train_title"]        = nvgCreateImage(vg, "image/火车标题.png", 0)
    imgCache["turret_slot_frame"]  = nvgCreateImage(vg, "image/炮塔界面/炮塔装备界面.png", 0)
    imgCache["turret_display"]     = nvgCreateImage(vg, "image/炮塔显示框.png", 0)
    imgCache["turret_lock"]        = nvgCreateImage(vg, "image/炮塔上锁.png", 0)
    imgCache["common_lock"]        = nvgCreateImage(vg, "image/通用锁.png", 0)
    imgCache["turret_base_top"]    = nvgCreateImage(vg, "image/炮塔底（顶部）.png", 0)
    imgCache["turret_base_mid"]    = nvgCreateImage(vg, "image/炮塔底（中部）.png", 0)
    imgCache["turret_base_bot"]    = nvgCreateImage(vg, "image/炮塔底（底部）.png", 0)
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
    L.tabBarH = 76       -- 底部Tab高度
    L.contentY = L.topBarH
    L.contentH = H - L.topBarH - L.tabBarH
    L.pad = 10           -- 通用内边距
    L.cardGap = 8        -- 卡片间距
end

------------------------------------------------------------------------
-- 更新（动画、滚动惯性等）
------------------------------------------------------------------------
--- 获取今天0点的时间戳（秒）
local function getTodayMidnight()
    local t = os.date("*t")
    t.hour, t.min, t.sec = 0, 0, 0
    return os.time(t)
end

--- 获取距离明天0点的剩余秒数
local function getSecondsToNextMidnight()
    local now = os.time()
    local todayMid = getTodayMidnight()
    local nextMid = todayMid + 86400  -- +24h
    return math.max(0, nextMid - now)
end

--- 每日商品刷新检测：跨天后重置（免费金币除外）
local function checkDailyReset()
    local todayMid = getTodayMidnight()
    if saveData.lastDailyReset < todayMid then
        -- 保留免费金币的已领取状态
        local freeGoldClaimed = saveData.dailyBought["daily_gold"]
        saveData.dailyBought = {}
        if freeGoldClaimed then
            saveData.dailyBought["daily_gold"] = true
        end
        saveData.lastDailyReset = todayMid
        print("[Meta] 每日商品已刷新（免费金币状态保留）")
    end
end

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
    -- 角色攻击帧动画计时器
    charAnimTimer = charAnimTimer + dt
    -- 每日商品刷新检测
    checkDailyReset()
end

------------------------------------------------------------------------
-- 绘制入口
------------------------------------------------------------------------
function M.Draw(vg, W, H)
    M.CalcLayout(W, H)
    Def.BeginFrame()  -- 编辑器：每帧重置元素注册列表

    -- 面板背景
    local bgImg = imgCache["common_bg"]
    if bgImg and bgImg ~= 0 then
        local paint = nvgImagePattern(vg, 0, 0, W, H, 0, bgImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBA(MD.CLR.bg_dark[1], MD.CLR.bg_dark[2], MD.CLR.bg_dark[3], 255))
        nvgFill(vg)
    end

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

    -- 装备面板：一键分解下拉菜单（仅装备子标签页）
    if activeTab == "equip" and equipState.catIndex == 2 and equipState.showDropdown then
        M.DrawDecomposeDropdown(vg, W, H)
    end

    -- 装备面板：批量分解确认弹窗
    if activeTab == "equip" and equipState.showConfirm then
        M.DrawDecomposeConfirm(vg, W, H)
    end

    -- 装备面板：装备详情弹窗（全屏覆盖，不受滚动裁剪）
    -- 注：弹窗已在 DrawEquipPanel 内部绘制，此处无需重复
end

------------------------------------------------------------------------
-- 顶栏（玩家信息 + 货币）
------------------------------------------------------------------------
function M.DrawTopBar(vg, W)
    local h = L.topBarH
    local c = MD.CLR

    -- 背景（深色半透明）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, h)
    nvgFillColor(vg, nvgRGBA(15, 18, 25, 230))
    nvgFill(vg)

    -- 底部淡金色分割线（两侧渐隐）
    local lineH = 1.5
    local lineY = h - lineH / 2
    local fadeW = W * 0.30

    local paintL = nvgLinearGradient(vg, 0, lineY, fadeW, lineY,
        nvgRGBA(210, 180, 100, 0), nvgRGBA(210, 180, 100, 90))
    nvgBeginPath(vg)
    nvgRect(vg, 0, lineY - lineH / 2, fadeW, lineH)
    nvgFillPaint(vg, paintL)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgRect(vg, fadeW, lineY - lineH / 2, W - fadeW * 2, lineH)
    nvgFillColor(vg, nvgRGBA(210, 180, 100, 90))
    nvgFill(vg)

    local paintR = nvgLinearGradient(vg, W - fadeW, lineY, W, lineY,
        nvgRGBA(210, 180, 100, 90), nvgRGBA(210, 180, 100, 0))
    nvgBeginPath(vg)
    nvgRect(vg, W - fadeW, lineY - lineH / 2, fadeW, lineH)
    nvgFillPaint(vg, paintR)
    nvgFill(vg)

    -- ========== 左侧：头像框 + 头像 + 玩家名 ==========
    local frameSize = h - 4  -- 头像框略小于顶栏高度
    local frameX = 4
    local frameY = (h - frameSize) / 2
    frameX, frameY = Def.Apply("topbar.avatar", frameX, frameY)
    Def.Register("topbar.avatar", frameX, frameY, frameSize + 60, frameSize, "头像+名称")

    -- 头像内容（圆形裁剪的头像图片）
    local avatarPad = frameSize * 0.22  -- 内缩留出边框空间
    local avatarR = (frameSize - avatarPad * 2) / 2
    local avatarCX = frameX + frameSize / 2
    local avatarCY = frameY + frameSize / 2

    -- 根据当前使用角色动态选择头像
    local activeCharId = saveData and saveData.activeChar or "warrior"
    local portraitImg = imgCache["char_portrait_" .. activeCharId] or imgCache["avatar_portrait"]
    if portraitImg and portraitImg ~= 0 then
        -- 圆形裁剪
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, avatarCX, avatarCY, avatarR)
        -- 用 ImagePattern 填充头像
        local imgPat = nvgImagePattern(vg,
            avatarCX - avatarR, avatarCY - avatarR,
            avatarR * 2, avatarR * 2, 0, portraitImg, 1.0)
        nvgFillPaint(vg, imgPat)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 头像框图片（覆盖在头像上方）
    local frameImg = imgCache["avatar_frame"]
    if frameImg and frameImg ~= 0 then
        M.DrawImage(vg, frameImg, frameX, frameY, frameSize, frameSize)
    end

    -- 玩家名（白色，头像右侧）
    local nameX = frameX + frameSize + 6
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, nameX, h / 2, saveData.playerName)

    -- ========== 右侧：货币资源（白色字体统一） ==========
    local currencies = {
        { val = saveData.gold,    icon = MD.CURRENCY_ICONS.gold },
        { val = saveData.diamond, icon = MD.CURRENCY_ICONS.diamond },
        { val = saveData.wood,    icon = MD.CURRENCY_ICONS.wood },
        { val = saveData.stone,   icon = MD.CURRENCY_ICONS.stone },
    }

    local cx = W - 10
    local icoS = 18
    local currAreaW = W * 0.55  -- 货币区域大致宽度
    local currAreaX = W - 10 - currAreaW
    local currAreaY = (h - icoS) / 2
    currAreaX, currAreaY = Def.Apply("topbar.currencies", currAreaX, currAreaY)
    Def.Register("topbar.currencies", currAreaX, currAreaY, currAreaW, icoS, "货币区域")
    for i = #currencies, 1, -1 do
        local cur = currencies[i]
        -- 格式化数值
        local txt
        if cur.val >= 10000 then
            txt = string.format("%.1fK", cur.val / 1000)
        elseif cur.val >= 1000 then
            txt = string.format("%.1fK", cur.val / 1000)
        else
            txt = tostring(cur.val)
        end

        -- 数值（白色）
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, cx, h / 2, txt)

        local tw = nvgTextBounds(vg, 0, 0, txt)
        cx = cx - tw - 3

        -- 图标
        local img = imgCache[cur.icon]
        if img and img ~= 0 then
            M.DrawImage(vg, img, cx - icoS, h / 2 - icoS / 2, icoS, icoS)
            cx = cx - icoS - 10
        end
    end
end

------------------------------------------------------------------------
-- 底部Tab栏（完整按钮图片渲染）
------------------------------------------------------------------------
function M.DrawTabBar(vg, W, H)
    local h = L.tabBarH
    local y = H - h
    local tabCount = #MD.TABS
    local tabW = W / tabCount
    Def.Register("tabbar", 0, y, W, h, "底部Tab栏")

    -- 整体深色底板
    nvgBeginPath(vg)
    nvgRect(vg, 0, y, W, h)
    nvgFillColor(vg, nvgRGBA(18, 20, 26, 255))
    nvgFill(vg)

    for i, tab in ipairs(MD.TABS) do
        local tx = (i - 1) * tabW
        local isActive = (tab.id == activeTab)

        -- 选择对应的按钮图片
        local imgKey = isActive and tab.img_active or tab.img_normal
        local img = imgCache[imgKey]

        if img and img ~= 0 then
            -- 高度撑满，宽度按比例居中
            local icoH = h
            local icoW = icoH  -- 图标近正方形
            local ix = tx + (tabW - icoW) / 2
            M.DrawImage(vg, img, ix, y, icoW, icoH)
        end
    end
end

------------------------------------------------------------------------
-- 战斗面板（聚焦关卡视图 - 参照参考图）
------------------------------------------------------------------------

-- 当前选中的关卡索引（用于翻页浏览）
local battleSelectedLevel = 1

-- 绘制盾牌暗纹背景图案
local function drawShieldPattern(vg, x, y, w, h)
    -- 浅蓝色背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(95, 185, 230, 255))
    nvgFill(vg)

    -- 盾牌暗纹（半透明图案）
    local shieldSize = 36
    local spacingX = 52
    local spacingY = 50
    local cols = math.ceil(w / spacingX) + 1
    local rows = math.ceil(h / spacingY) + 1

    for row = 0, rows do
        for col = 0, cols do
            local sx = x + col * spacingX + (row % 2 == 1 and spacingX * 0.5 or 0)
            local sy = y + row * spacingY
            local s = shieldSize * 0.5

            nvgBeginPath(vg)
            -- 简化盾牌形状
            nvgMoveTo(vg, sx, sy - s * 0.9)
            nvgLineTo(vg, sx + s * 0.7, sy - s * 0.5)
            nvgLineTo(vg, sx + s * 0.7, sy + s * 0.1)
            nvgLineTo(vg, sx, sy + s * 0.7)
            nvgLineTo(vg, sx - s * 0.7, sy + s * 0.1)
            nvgLineTo(vg, sx - s * 0.7, sy - s * 0.5)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(80, 170, 215, 60))
            nvgFill(vg)
        end
    end
end

-- 绘制场景插图（简化版村庄场景）
local function drawLevelScene(vg, cx, cy, sceneW, sceneH, levelIdx)
    -- 地面
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - sceneW * 0.45, cy + sceneH * 0.15, sceneW * 0.9, sceneH * 0.35, 10)
    nvgFillColor(vg, nvgRGBA(90, 65, 40, 200))
    nvgFill(vg)

    -- 草地层
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - sceneW * 0.45, cy + sceneH * 0.12, sceneW * 0.9, sceneH * 0.08, 6)
    nvgFillColor(vg, nvgRGBA(60, 140, 50, 220))
    nvgFill(vg)

    -- 树木（根据关卡绘制不同树木密度）
    local treePositions = {
        { -0.35, 0.05, 0.7 },
        { -0.2, -0.05, 0.9 },
        { 0.15, -0.02, 0.85 },
        { 0.3, 0.08, 0.65 },
        { -0.05, -0.1, 1.0 },
    }
    local treeCount = math.min(#treePositions, 2 + levelIdx)

    for i = 1, treeCount do
        local tp = treePositions[i]
        local tx = cx + tp[1] * sceneW
        local ty = cy + tp[2] * sceneH
        local sc = tp[3]
        local treeH = sceneH * 0.35 * sc

        -- 树干
        nvgBeginPath(vg)
        nvgRect(vg, tx - 4 * sc, ty, 8 * sc, treeH * 0.4)
        nvgFillColor(vg, nvgRGBA(100, 70, 40, 255))
        nvgFill(vg)

        -- 树冠（三角）
        for layer = 0, 2 do
            local layerY = ty - layer * treeH * 0.2
            local layerW = (20 - layer * 4) * sc
            nvgBeginPath(vg)
            nvgMoveTo(vg, tx, layerY - treeH * 0.3)
            nvgLineTo(vg, tx + layerW, layerY)
            nvgLineTo(vg, tx - layerW, layerY)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(30 + layer * 15, 120 + layer * 15, 40 + layer * 10, 255))
            nvgFill(vg)
        end
    end

    -- 中心建筑（房子）
    local hx = cx
    local hy = cy + sceneH * 0.05
    local hw = sceneW * 0.25
    local hh = sceneH * 0.22

    -- 房屋主体
    nvgBeginPath(vg)
    nvgRect(vg, hx - hw / 2, hy - hh * 0.5, hw, hh)
    nvgFillColor(vg, nvgRGBA(180, 100, 50, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(140, 75, 35, 255))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 屋顶
    nvgBeginPath(vg)
    nvgMoveTo(vg, hx, hy - hh * 0.5 - hh * 0.45)
    nvgLineTo(vg, hx + hw * 0.65, hy - hh * 0.5)
    nvgLineTo(vg, hx - hw * 0.65, hy - hh * 0.5)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(160, 45, 30, 255))
    nvgFill(vg)

    -- 门
    nvgBeginPath(vg)
    nvgRoundedRect(vg, hx - hw * 0.12, hy + hh * 0.1, hw * 0.24, hh * 0.4, 3)
    nvgFillColor(vg, nvgRGBA(80, 50, 25, 255))
    nvgFill(vg)

    -- 窗户
    nvgBeginPath(vg)
    nvgRect(vg, hx - hw * 0.35, hy - hh * 0.25, hw * 0.18, hw * 0.18)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(140, 75, 35, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgRect(vg, hx + hw * 0.17, hy - hh * 0.25, hw * 0.18, hw * 0.18)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(140, 75, 35, 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

function M.DrawBattlePanel(vg, W)
    local c = MD.CLR
    local baseY = L.contentY
    local contentH = L.contentH

    -- 确保选中关卡在合法范围内
    if battleSelectedLevel < 1 then battleSelectedLevel = 1 end
    if battleSelectedLevel > #MD.LEVELS then battleSelectedLevel = #MD.LEVELS end
    local level = MD.LEVELS[battleSelectedLevel]
    local unlocked = (battleSelectedLevel <= saveData.maxLevel)

    -- ================================================================
    -- 1. 背景（使用通用背景图片，由 M.Draw 统一绘制）
    -- ================================================================

    -- ================================================================
    -- 2. 设置按钮（左侧）
    -- ================================================================
    local icoSize = 38
    local iconMargin = 10
    local icoBtnY = baseY + 8
    do
        local sw, sh = icoSize, icoSize
        local sx = iconMargin
        local sy = icoBtnY
        sx, sy = Def.Apply("battle.gear", sx, sy)
        Def.Register("battle.gear", sx, sy, sw, sh + 14, "设置")
        local btnImg = imgCache["btn_settings"]
        if btnImg and btnImg ~= 0 then
            M.DrawImage(vg, btnImg, sx, sy, sw, sh)
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 220))
        nvgText(vg, sx + sw / 2, sy + sh + 2, "设置")
    end

    -- ================================================================
    -- 3. 功能按钮横排（公告、排行、签到）右侧 + 文字标签
    -- ================================================================
    -- 签到按钮按原图比例（406x586），高度40，宽度按比例
    local signinH = 40
    local signinW = math.floor(signinH * 406 / 586)  -- ≈ 28
    local rightBtns = {
        { imgKey = "btn_announce", id = "battle.icon_announce",  label = "公告", hasBadge = true,  w = 38, h = math.floor(38 * 360 / 454) },  -- 原图454x360
        { imgKey = "btn_ranking",  id = "battle.icon_ranking",   label = "排行", hasBadge = false, w = icoSize, h = icoSize },
        { imgKey = "btn_signin",   id = "battle.icon_signin",    label = "签到", hasBadge = false, w = signinW,  h = signinH },
    }
    local icoGap = 14
    -- 找最大高度用于底部对齐
    local maxH = 0
    for _, btn in ipairs(rightBtns) do
        if btn.h > maxH then maxH = btn.h end
    end
    -- 计算总宽度
    local totalBtnW = 0
    for i, btn in ipairs(rightBtns) do
        totalBtnW = totalBtnW + btn.w
        if i < #rightBtns then totalBtnW = totalBtnW + icoGap end
    end
    local btnStartX = W - iconMargin - totalBtnW

    local curX = btnStartX
    for i, btn in ipairs(rightBtns) do
        local bw, bh = btn.w, btn.h
        local bx = curX
        -- 垂直底部对齐
        local by = icoBtnY + (maxH - bh)
        bx, by = Def.Apply(btn.id, bx, by)
        Def.Register(btn.id, bx, by, bw, bh + 14, btn.label)

        -- 图标图片
        local btnImg = imgCache[btn.imgKey]
        if btnImg and btnImg ~= 0 then
            M.DrawImage(vg, btnImg, bx, by, bw, bh)
        end

        -- 红标
        if btn.hasBadge then
            local badgeImg = imgCache["btn_red_badge"]
            if badgeImg and badgeImg ~= 0 then
                local badgeS = 14
                M.DrawImage(vg, badgeImg, bx + bw - badgeS * 0.55, by - badgeS * 0.35, badgeS, badgeS)
            end
        end

        -- 文字标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 210, 220))
        nvgText(vg, bx + bw / 2, by + bh + 2, btn.label)

        curX = curX + bw + icoGap
    end

    -- ================================================================
    -- 4. 关卡场景插图（居中大图）— 标题和波次叠加在卡片上
    -- ================================================================
    local sceneW = W * 0.75
    local sceneH = contentH * 0.30
    local sceneCX = W / 2
    local sceneCY = baseY + contentH * 0.36
    sceneCX, sceneCY = Def.Apply("battle.scene_card", sceneCX, sceneCY)
    Def.Register("battle.scene_card", sceneCX - sceneW / 2, sceneCY - sceneH / 2, sceneW, sceneH, "场景卡片")

    -- 场景卡片背景（带阴影）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sceneCX - sceneW / 2 + 3, sceneCY - sceneH / 2 + 3, sceneW, sceneH, 14)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 30))
    nvgFill(vg)

    -- 场景卡片（关卡场景图片）
    local sceneImg = imgCache["level_scene"]
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sceneCX - sceneW / 2, sceneCY - sceneH / 2, sceneW, sceneH, 14)
    if sceneImg and sceneImg ~= 0 then
        local paint = nvgImagePattern(vg, sceneCX - sceneW / 2, sceneCY - sceneH / 2, sceneW, sceneH, 0, sceneImg, 1.0)
        nvgFillPaint(vg, paint)
    else
        nvgFillColor(vg, nvgRGBA(200, 230, 250, 255))
    end
    nvgFill(vg)

    -- 场景卡片边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sceneCX - sceneW / 2, sceneCY - sceneH / 2, sceneW, sceneH, 14)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 120))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- ================================================================
    -- 4b. 关卡标题 + 波数（叠加在场景卡片顶部）
    -- ================================================================
    local titleText = battleSelectedLevel .. "." .. level.name
    local titleY = sceneCY - sceneH / 2 + 14
    titleY = select(2, Def.Apply("battle.title", sceneCX, titleY))
    Def.Register("battle.title", sceneCX - 80, titleY - 4, 160, 50, "关卡标题")
    nvgFontFace(vg, "sans")

    -- 关卡名称（大字，白色带深色描边，在图片上清晰可读）
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    -- 描边（深色阴影）
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
    nvgText(vg, sceneCX + 1, titleY + 1, titleText)
    -- 主文字（白色）
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, sceneCX, titleY, titleText)

    -- 总波数（小字，浅色半透明）
    local wavesY = titleY + 26
    wavesY = select(2, Def.Apply("battle.waves_text", sceneCX, wavesY))
    Def.Register("battle.waves_text", sceneCX - 50, wavesY - 7, 100, 18, "波数文字")
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
    nvgText(vg, sceneCX + 1, wavesY + 1, "总波数: " .. level.waves)
    nvgFillColor(vg, nvgRGBA(220, 220, 230, 240))
    nvgText(vg, sceneCX, wavesY, "总波数: " .. level.waves)

    -- 锁定遮罩
    if not unlocked then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sceneCX - sceneW / 2, sceneCY - sceneH / 2, sceneW, sceneH, 14)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
        nvgFill(vg)

        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgText(vg, sceneCX, sceneCY, "🔒")
    end

    -- ================================================================
    -- 6. 左右翻页箭头（如果有多个关卡）
    -- ================================================================
    if #MD.LEVELS > 1 then
        local arrowSize = 28
        local arrowY = sceneCY - arrowSize / 2

        -- 左箭头
        if battleSelectedLevel > 1 then
            local laX = sceneCX - sceneW / 2 - arrowSize - 4
            laX, arrowY = Def.Apply("battle.arrow_left", laX, arrowY)
            Def.Register("battle.arrow_left", laX, arrowY, arrowSize, arrowSize, "左翻页")
            nvgBeginPath(vg)
            nvgRoundedRect(vg, laX, arrowY, arrowSize, arrowSize, 6)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
            nvgFill(vg)
            nvgFontSize(vg, 18)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(60, 70, 90, 255))
            nvgText(vg, laX + arrowSize / 2, arrowY + arrowSize / 2, "◀")
        end

        -- 右箭头
        if battleSelectedLevel < saveData.maxLevel then
            local raX = sceneCX + sceneW / 2 + 4
            local raY = arrowY
            raX, raY = Def.Apply("battle.arrow_right", raX, raY)
            Def.Register("battle.arrow_right", raX, raY, arrowSize, arrowSize, "右翻页")
            nvgBeginPath(vg)
            nvgRoundedRect(vg, raX, raY, arrowSize, arrowSize, 6)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
            nvgFill(vg)
            nvgFontSize(vg, 18)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(60, 70, 90, 255))
            nvgText(vg, raX + arrowSize / 2, raY + arrowSize / 2, "▶")
        end
    end

    -- ================================================================
    -- 7. 3个奖励宝箱 + 金色虚线连接 + 进度百分比
    -- ================================================================
    local chestY = sceneCY + sceneH / 2 + 24
    local chestSize = 48
    do
        local _cx, _cy = Def.Apply("battle.chests", W / 2, chestY)
        chestY = _cy
    end
    local chestGap = 40
    local totalChestW = 3 * chestSize + 2 * chestGap
    local chestStartX = W / 2 - totalChestW / 2
    Def.Register("battle.chests", chestStartX, chestY, totalChestW, chestSize + 20, "奖励宝箱")

    local chestTypes = { "bronze", "silver", "gold" }
    local chestPercents = { "25%", "50%", "100%" }
    local stars = saveData.levelStars[battleSelectedLevel] or 0

    -- 计算每个宝箱的中心位置
    local chestCenters = {}
    for i = 1, 3 do
        chestCenters[i] = {
            x = chestStartX + (i - 1) * (chestSize + chestGap) + chestSize / 2,
            y = chestY + chestSize / 2,
        }
    end

    -- 绘制宝箱之间的金色虚线连接
    nvgSave(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 165, 60, 180))
    nvgStrokeWidth(vg, 2)
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 2 do
        local x1 = chestCenters[i].x + chestSize / 2 + 2
        local x2 = chestCenters[i + 1].x - chestSize / 2 - 2
        local ly = chestCenters[i].y
        -- 绘制虚线：用小段实线模拟
        local dashLen = 6
        local gapLen = 4
        local totalLen = x2 - x1
        local pos = 0
        while pos < totalLen do
            local segStart = x1 + pos
            local segEnd = math.min(segStart + dashLen, x2)
            nvgBeginPath(vg)
            nvgMoveTo(vg, segStart, ly)
            nvgLineTo(vg, segEnd, ly)
            nvgStroke(vg)
            pos = pos + dashLen + gapLen
        end
    end
    nvgRestore(vg)

    -- 绘制宝箱图标和百分比标签
    for i, chestType in ipairs(chestTypes) do
        local cx = chestCenters[i].x
        local claimed = (stars >= i)

        -- 宝箱图标
        local chestImg = imgCache[MD.CHEST_ICONS[chestType]]
        if chestImg and chestImg ~= 0 then
            M.DrawImage(vg, chestImg, cx - chestSize / 2, chestY, chestSize, chestSize)
        end

        -- 百分比标签
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if claimed then
            nvgFillColor(vg, nvgRGBA(220, 185, 80, 255))
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
        end
        nvgText(vg, cx, chestY + chestSize + 4, chestPercents[i])
    end

    -- ================================================================
    -- 8. 大金色"开始战斗"按钮（图片）
    -- ================================================================
    local btnW = W * 0.52
    local btnH = btnW * 0.30
    local btnX = W / 2 - btnW / 2
    local btnY = chestY + chestSize + 30
    btnX, btnY = Def.Apply("battle.start_btn", btnX, btnY)
    Def.Register("battle.start_btn", btnX, btnY, btnW, btnH, "开始战斗按钮")

    if unlocked then
        local btnImg = imgCache["start_battle_btn"]
        if btnImg and btnImg ~= 0 then
            local paint = nvgImagePattern(vg, btnX, btnY, btnW, btnH, 0, btnImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, btnX, btnY, btnW, btnH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    else
        -- 灰色锁定按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 10)
        nvgFillColor(vg, nvgRGBA(100, 105, 115, 200))
        nvgFill(vg)

        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 180))
        nvgText(vg, W / 2, btnY + btnH / 2, "🔒 未解锁")
    end

    -- 不需要滚动
    return 0
end

------------------------------------------------------------------------
-- 商城面板
------------------------------------------------------------------------
function M.DrawShopPanel(vg, W)
    local c = MD.CLR
    local y = L.contentY + L.pad
    local padX = L.pad
    local innerW = W - padX * 2

    nvgFontFace(vg, "sans")

    -- ========== 1. 商城标题（图片） ==========
    -- 商城.png 原始尺寸 147x75，比例 147/75 = 1.96
    local titleImg = imgCache["shop_title"]
    local titleH = 26
    local titleW = math.floor(titleH * 1.96)
    local titleX, titleY = Def.Apply("shop.title", padX, y)
    Def.Register("shop.title", titleX, titleY, titleW, titleH, "商城标题")
    M.DrawImage(vg, titleImg, titleX, titleY, titleW, titleH)
    y = y + titleH + 10

    -- ========== 2. 抽奖区域（抽奖底.png 作背景） ==========
    local gachaBgImg = imgCache["shop_gacha_bg"]
    local gachaW = innerW
    -- 抽奖底.png 原始尺寸 1529x786，比例 0.514
    local gachaH = math.floor(gachaW * 0.514)
    local gachaX, gachaY = Def.Apply("shop.gacha_card", padX, y)
    Def.Register("shop.gacha_card", gachaX, gachaY, gachaW, gachaH, "抽卡卡片")

    -- 背景图
    M.DrawImage(vg, gachaBgImg, gachaX, gachaY, gachaW, gachaH)

    -- 两个抽奖按钮（底部并排，缩小一圈）
    -- 单抽框2.png / 十连抽框2.png 747x276，比例 0.369
    local btnGap = 8
    local btnW = math.floor((gachaW * 0.82 - btnGap) / 2)
    local btnH = math.floor(btnW * 0.369)
    local btnOffX = math.floor((gachaW - btnW * 2 - btnGap) / 2)
    local btnY2 = gachaY + math.floor((gachaH - btnH) * 0.88)

    -- 钻石图标素材（用于按钮上叠加价格）
    local dIconImg = imgCache["shop_diamond_icon"]
    local dIconH = math.floor(btnH * 0.35)
    local dIconW = math.floor(dIconH * 1.20)  -- 618/514=1.20

    -- 单抽按钮
    local singleImg = imgCache["shop_single_btn"]
    local singleX = gachaX + btnOffX
    L.shopSingleBtn = { x = singleX, y = btnY2, w = btnW, h = btnH }
    Def.Register("shop.btn_single", singleX, btnY2, btnW, btnH, "单抽按钮")
    M.DrawImage(vg, singleImg, singleX, btnY2, btnW, btnH)
    -- 单抽价格：钻石图标 + x200
    do
        local priceStr = "x" .. MD.SHOP_GACHA.cost_single
        nvgFontSize(vg, 11)
        local tw = nvgTextBounds(vg, 0, 0, priceStr)
        local totalW = dIconW + 3 + tw
        local sx = singleX + (btnW - totalW) / 2
        local sy = btnY2 + btnH * 0.68
        M.DrawImage(vg, dIconImg, sx, sy - dIconH / 2, dIconW, dIconH)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 200, 150, 255))
        nvgText(vg, sx + dIconW + 3, sy, priceStr)
    end

    -- 十连按钮
    local tenImg = imgCache["shop_ten_btn"]
    local tenX = singleX + btnW + btnGap
    L.shopTenBtn = { x = tenX, y = btnY2, w = btnW, h = btnH }
    Def.Register("shop.btn_ten", tenX, btnY2, btnW, btnH, "十连按钮")
    M.DrawImage(vg, tenImg, tenX, btnY2, btnW, btnH)
    -- 十连价格：钻石图标 + x2000
    do
        local priceStr = "x" .. MD.SHOP_GACHA.cost_ten
        nvgFontSize(vg, 11)
        local tw = nvgTextBounds(vg, 0, 0, priceStr)
        local totalW = dIconW + 3 + tw
        local sx = tenX + (btnW - totalW) / 2
        local sy = btnY2 + btnH * 0.68
        M.DrawImage(vg, dIconImg, sx, sy - dIconH / 2, dIconW, dIconH)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 200, 150, 255))
        nvgText(vg, sx + dIconW + 3, sy, priceStr)
    end

    y = gachaY + gachaH + 12

    -- ========== 3. 每日商品标题（图片） + 刷新倒计时 ==========
    -- 每日商品.png 原始尺寸 210x53，比例 210/53 = 3.96
    local dailyTitleImg = imgCache["shop_daily_title"]
    local dtH = 22
    local dtW = math.floor(dtH * 3.96)
    local dtX, dtY = Def.Apply("shop.daily_title", padX, y)
    Def.Register("shop.daily_title", dtX, dtY, dtW, dtH, "每日商品标题")
    M.DrawImage(vg, dailyTitleImg, dtX, dtY, dtW, dtH)

    -- 刷新倒计时（右侧，实时计算）
    local remain = getSecondsToNextMidnight()
    local rh = math.floor(remain / 3600)
    local rm = math.floor((remain % 3600) / 60)
    local rs = remain % 60
    local countdownStr = string.format("刷新倒计时: %02d:%02d:%02d", rh, rm, rs)
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 180, 160, 200))
    nvgText(vg, W - padX, dtY + dtH / 2, countdownStr)
    y = dtY + dtH + 10

    -- ========== 4. 每日商品网格（4列） ==========
    local cols = 4
    local gap = 5
    local itemW = math.floor((innerW - gap * (cols - 1)) / cols)
    -- 商品底框.png 原始尺寸 703x1182，比例 1.68
    local itemH = math.floor(itemW * 1.68)

    local frameImg = imgCache["shop_item_frame"]
    local diamondBtnImg = imgCache["shop_diamond_btn"]
    local freeBtnImg = imgCache["shop_free_btn"]

    -- 缓存商品按钮位置供点击使用
    L.shopItems = {}

    for i, item in ipairs(MD.SHOP_DAILY) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local ix = padX + col * (itemW + gap)
        local iy = y + row * (itemH + gap)
        local itemId = "shop.item_" .. i
        ix, iy = Def.Apply(itemId, ix, iy)
        Def.Register(itemId, ix, iy, itemW, itemH, "商品" .. i .. ":" .. item.name)

        -- 商品底框
        M.DrawImage(vg, frameImg, ix, iy, itemW, itemH)

        -- 物品名称（顶部）
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(240, 230, 200, 255))
        nvgText(vg, ix + itemW / 2, iy + 6, item.name)

        -- 物品图标（居中偏上，足够大）
        local iconImg = imgCache[item.icon]
        if iconImg and iconImg ~= 0 then
            local icoS = math.floor(itemW * 0.55)
            M.DrawImage(vg, iconImg, ix + (itemW - icoS) / 2, iy + itemH * 0.20, icoS, icoS)
        end

        -- 数量描述（图标下方）
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 180, 230))
        nvgText(vg, ix + itemW / 2, iy + itemH * 0.60, item.desc)

        -- 购买按钮（底部，统一大小）
        -- 钻石购买框.png 1097x439 比例0.40，免费框.png 1268x379 比例0.30
        local pBtnW = math.floor(itemW * 0.92)
        local pBtnH = math.floor(pBtnW * 0.40)
        local pBtnX = ix + (itemW - pBtnW) / 2
        local pBtnY = iy + itemH - pBtnH - 4

        -- 已购买/已领取：整个卡片置灰
        local bought = saveData.dailyBought[item.id]
        if bought then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix + 2, iy + 2, itemW - 4, itemH - 4, 4)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
            nvgFill(vg)
            local label = (item.currency == "free") and "已领取" or "已售罄"
            nvgFontSize(vg, 13)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 220))
            nvgText(vg, ix + itemW / 2, iy + itemH * 0.45, label)
        end

        if item.currency == "free" then
            M.DrawImage(vg, freeBtnImg, pBtnX, pBtnY, pBtnW, pBtnH)
        else
            -- 钻石购买框背景
            M.DrawImage(vg, diamondBtnImg, pBtnX, pBtnY, pBtnW, pBtnH)
            -- 钻石图标 + 价格（居中排列，复用上方 dIconImg）
            local diH = math.floor(pBtnH * 0.70)
            local diW = math.floor(diH * 1.20)
            local priceStr = tostring(item.price)
            nvgFontSize(vg, 11)
            local tw = nvgTextBounds(vg, 0, 0, priceStr)
            local totalW = diW + 2 + tw
            local startX = pBtnX + (pBtnW - totalW) / 2
            M.DrawImage(vg, dIconImg, startX, pBtnY + (pBtnH - diH) / 2, diW, diH)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(220, 200, 150, 255))
            nvgText(vg, startX + diW + 2, pBtnY + pBtnH / 2, priceStr)
        end

        -- 缓存按钮区域
        L.shopItems[i] = { x = pBtnX, y = pBtnY, w = pBtnW, h = pBtnH }
    end

    local totalRows = math.ceil(#MD.SHOP_DAILY / cols)
    y = y + totalRows * (itemH + gap) - gap + 10

    -- ========== 5. 固定商店标题（文字渲染，与每日商品标题对齐） ==========
    nvgFontSize(vg, 16)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(240, 230, 200, 255))
    local fTitleX, fTitleY = Def.Apply("shop.fixed_title", padX, y)
    Def.Register("shop.fixed_title", fTitleX, fTitleY, 80, 20, "固定商店标题")
    nvgText(vg, fTitleX, fTitleY, "固定商店")
    y = fTitleY + 28

    -- ========== 6. 固定商店商品网格（4列，可多行） ==========
    L.shopFixedItems = {}

    for i, item in ipairs(MD.SHOP_FIXED) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local ix = padX + col * (itemW + gap)
        local iy = y + row * (itemH + gap)
        local itemId = "shop.fixed_" .. i
        ix, iy = Def.Apply(itemId, ix, iy)
        Def.Register(itemId, ix, iy, itemW, itemH, "固定商品" .. i .. ":" .. item.name)

        -- 商品底框
        M.DrawImage(vg, frameImg, ix, iy, itemW, itemH)

        -- 物品名称（顶部）
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(240, 230, 200, 255))
        nvgText(vg, ix + itemW / 2, iy + 6, item.name)

        -- 物品图标
        local iconImg = imgCache[item.icon]
        if iconImg and iconImg ~= 0 then
            local icoS = math.floor(itemW * 0.55)
            M.DrawImage(vg, iconImg, ix + (itemW - icoS) / 2, iy + itemH * 0.20, icoS, icoS)
        end

        -- 数量描述
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(200, 200, 180, 230))
        nvgText(vg, ix + itemW / 2, iy + itemH * 0.60, item.desc)

        -- 购买按钮
        local pBtnW2 = math.floor(itemW * 0.92)
        local pBtnH2 = math.floor(pBtnW2 * 0.40)
        local pBtnX2 = ix + (itemW - pBtnW2) / 2
        local pBtnY2 = iy + itemH - pBtnH2 - 4

        -- 钻石购买框 + 价格
        M.DrawImage(vg, diamondBtnImg, pBtnX2, pBtnY2, pBtnW2, pBtnH2)
        local fiH = math.floor(pBtnH2 * 0.70)
        local fiW = math.floor(fiH * 1.20)
        local priceStr = tostring(item.price)
        nvgFontSize(vg, 11)
        local tw = nvgTextBounds(vg, 0, 0, priceStr)
        local ftotalW = fiW + 2 + tw
        local fstartX = pBtnX2 + (pBtnW2 - ftotalW) / 2
        M.DrawImage(vg, dIconImg, fstartX, pBtnY2 + (pBtnH2 - fiH) / 2, fiW, fiH)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 200, 150, 255))
        nvgText(vg, fstartX + fiW + 2, pBtnY2 + pBtnH2 / 2, priceStr)

        -- 缓存按钮区域
        L.shopFixedItems[i] = { x = pBtnX2, y = pBtnY2, w = pBtnW2, h = pBtnH2 }
    end

    local fixedRows = math.ceil(#MD.SHOP_FIXED / cols)
    y = y + fixedRows * (itemH + gap) - gap + 10

    return math.max(0, y - L.contentY - L.contentH + 20)
end

-- 根据装备id查找 EQUIP_DB 数据
local function findEquipData(equipId)
    for _, eq in ipairs(MD.EQUIP_DB) do
        if eq.id == equipId then return eq end
    end
    return nil
end

------------------------------------------------------------------------
-- 装备面板
------------------------------------------------------------------------
function M.DrawEquipPanel(vg, W)
    local c = MD.CLR
    local contentY = L.contentY
    local contentH = L.contentH
    local padX = 6

    -- ========== 1. 全屏背景（往上偏移） ==========
    local bgImg = imgCache["equip_bg"]
    if bgImg and bgImg ~= 0 then
        -- 原图 941×1672，比内容区更高，往上移让聚光灯偏上
        local bgH = math.floor(contentH * 1.15)
        local bgY = contentY - math.floor(contentH * 0.50)
        M.DrawImage(vg, bgImg, 0, bgY, W, bgH)
    end

    -- ========== 2. 顶部角色 + 装备槽（左右各3个） ==========
    local topAreaH = math.floor(contentH * 0.43)
    local topY = contentY + 4

    -- 装备槽底图（每个槽位单独使用）
    local slotFrameImg = imgCache["equip_slot_frame"]

    -- 角色图片（居中显示，支持帧动画）
    local heroH = math.floor(topAreaH * 0.88)
    local heroW = heroH
    local heroX = (W - heroW) / 2
    local heroY = topY + (topAreaH - heroH) / 2

    -- 查找当前角色数据
    local activeCharDef = nil
    for _, cd in ipairs(MD.CHARACTERS) do
        if cd.id == saveData.activeChar then activeCharDef = cd; break end
    end

    -- 装备界面角色展示：优先使用 equipDisplay 静态图
    local activeId = saveData.activeChar or "warrior"
    local equipDisplayImg = imgCache["char_equip_" .. activeId]
    if equipDisplayImg and equipDisplayImg ~= 0 then
        M.DrawImageFit(vg, equipDisplayImg, heroX, heroY, heroW, heroH)
    elseif activeCharDef and activeCharDef.walkFrames then
        -- 无 equipDisplay 时回退到行走帧动画
        local fps = activeCharDef.walkFPS or 10
        local totalFrames = #activeCharDef.walkFrames
        local frameIdx = math.floor(charAnimTimer * fps) % totalFrames + 1
        local frameImg = imgCache["char_walk_" .. activeCharDef.id .. "_" .. frameIdx]
        if frameImg and frameImg ~= 0 then
            M.DrawImageFit(vg, frameImg, heroX, heroY, heroW, heroH)
        end
    else
        -- 最终回退到默认角色图
        local heroImg = imgCache["equip_hero"]
        if heroImg and heroImg ~= 0 then
            M.DrawImageFit(vg, heroImg, heroX, heroY, heroW, heroH)
        end
    end

    -- 6 个装备槽：左侧3个（1,2,3），右侧3个（4,5,6）
    local slotW = math.floor(W * 0.16)
    local slotH = slotW
    local slotGapY = 4
    local totalSlotH = 3 * slotH + 2 * slotGapY
    local slotStartY = topY + (topAreaH - totalSlotH) / 2

    L.equipSlotCells = {}
    for si = 1, #MD.EQUIP_SLOTS do
        local slotDef = MD.EQUIP_SLOTS[si]
        local sx, sy
        if si <= 3 then
            -- 左侧
            sx = padX + 4
            sy = slotStartY + (si - 1) * (slotH + slotGapY)
        else
            -- 右侧
            sx = W - padX - slotW - 4
            sy = slotStartY + (si - 4) * (slotH + slotGapY)
        end

        -- 槽位底图
        if slotFrameImg and slotFrameImg ~= 0 then
            M.DrawImage(vg, slotFrameImg, sx, sy, slotW, slotH)
        end

        -- 检查是否已装备
        local invIdx = saveData.equipped and saveData.equipped[slotDef.id]
        if invIdx then
            local inst = saveData.inventory[invIdx]
            if inst then
                local itemData = findEquipData(inst.id)
                if itemData then
                    -- 品质发光
                    local gt = (equipState.showConfirm or equipState.showDropdown) and 0 or elapsedTime
                    M.DrawQualityGlow(vg, sx, sy, slotW, slotH, itemData.quality, gt)
                    -- 装备图标
                    local eqIcon = imgCache[itemData.icon]
                    if eqIcon and eqIcon ~= 0 then
                        local iconPad = math.floor(slotW * 0.1)
                        M.DrawImageFit(vg, eqIcon, sx + iconPad, sy + iconPad, slotW - iconPad * 2, slotH - iconPad * 2)
                    end
                    -- 等级标签（右下角）
                    if inst.level and inst.level > 1 then
                        nvgFontFace(vg, "sans")
                        nvgFontSize(vg, math.floor(slotW * 0.22))
                        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
                        nvgText(vg, sx + slotW - 2, sy + slotH - 2, "Lv" .. inst.level)
                    end
                end
            end
            -- 缓存点击区域
            L.equipSlotCells[si] = { x = sx, y = sy, w = slotW, h = slotH, slotId = slotDef.id, invIdx = invIdx }
        else
            -- 空槽：显示槽位默认图标（半透明）
            local slotIcon = imgCache[slotDef.icon]
            if slotIcon and slotIcon ~= 0 then
                nvgGlobalAlpha(vg, 0.35)
                local iconPad = math.floor(slotW * 0.15)
                M.DrawImageFit(vg, slotIcon, sx + iconPad, sy + iconPad, slotW - iconPad * 2, slotH - iconPad * 2)
                nvgGlobalAlpha(vg, 1.0)
            end
        end
        Def.Register("equip.slot_" .. slotDef.id, sx, sy, slotW, slotH, "装备槽:" .. slotDef.name)
    end

    -- ========== 3. 分类标签栏（3个等宽Tab） ==========
    local catY = topY + topAreaH + 2
    local catActiveImg = imgCache["equip_cat_active"]
    local catInactiveImg = imgCache["equip_cat_inactive"]

    local catTabs = {
        { label = "角色" },
        { label = "装备" },
        { label = "藏品" },
    }
    local catCount = #catTabs
    local catTotalW = W - padX * 2
    local catBtnW = math.floor(catTotalW / catCount)
    local catBtnH = math.floor(catBtnW * 92 / 234)
    local catBarH = catBtnH

    L.equipCatBtns = {}
    for ci, tab in ipairs(catTabs) do
        local cx = padX + (ci - 1) * catBtnW
        local cy = catY
        local isSelected = (equipState.catIndex == ci)
        local img = isSelected and catActiveImg or catInactiveImg
        if img and img ~= 0 then
            M.DrawImage(vg, img, cx, cy, catBtnW, catBtnH)
        end
        -- 按钮文字
        nvgFontSize(vg, math.floor(catBtnH * 0.44))
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isSelected then
            nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
        else
            nvgFillColor(vg, nvgRGBA(180, 180, 180, 255))
        end
        nvgText(vg, cx + catBtnW / 2, cy + catBtnH / 2, tab.label)
        L.equipCatBtns[ci] = { x = cx, y = cy, w = catBtnW, h = catBtnH, idx = ci }
        Def.Register("equip.cat_" .. ci, cx, cy, catBtnW, catBtnH, "分类:" .. tab.label)
    end

    -- ========== 底部区域（根据标签页切换内容） ==========
    local bottomY = catY + catBarH + 8

    if equipState.catIndex == 2 then
    -- ========== 3.5 副框（副框外=两侧边框，副框内=中间平铺）[装备] ==========
    local subFrameY = bottomY
    local subInnerImg = imgCache["equip_sub_inner"]   -- 59×93 中间平铺
    local subOuterImg = imgCache["equip_sub_outer"]   -- 55×93 左右边框
    local subH = math.floor(catBtnH * 0.6)
    local subOuterW = math.floor(subH * 55 / 93)
    local subTileW = math.floor(subH * 59 / 93)  -- 单个瓦片宽度（保持比例）
    local subInnerX = padX + subOuterW
    local subInnerEndX = W - padX - subOuterW
    -- 左侧边框（水平翻转）
    if subOuterImg and subOuterImg ~= 0 then
        nvgSave(vg)
        nvgTranslate(vg, padX + subOuterW, 0)
        nvgScale(vg, -1, 1)
        M.DrawImage(vg, subOuterImg, 0, subFrameY, subOuterW, subH)
        nvgRestore(vg)
    end
    -- 中间平铺副框内
    if subInnerImg and subInnerImg ~= 0 then
        nvgSave(vg)
        nvgScissor(vg, subInnerX, subFrameY, subInnerEndX - subInnerX, subH)
        local tx = subInnerX
        while tx < subInnerEndX do
            local tw = math.min(subTileW, math.floor(subInnerEndX - tx))
            M.DrawImage(vg, subInnerImg, tx, subFrameY, tw, subH)
            tx = tx + subTileW
        end
        nvgRestore(vg)
    end
    -- 右侧边框（原始方向）
    if subOuterImg and subOuterImg ~= 0 then
        M.DrawImage(vg, subOuterImg, subInnerEndX, subFrameY, subOuterW, subH)
    end
    -- 副框内3个功能按钮（排序/锁定/一键分解）
    local subBtnImg = imgCache["equip_cat_label"]  -- 215×66
    equipSubBtns = {}  -- 重置点击区域
    if subBtnImg and subBtnImg ~= 0 then
        local sbH = math.floor(subH * 0.85)
        local sbW = math.floor(sbH * 215 / 66)
        local sbY = subFrameY + (subH - sbH) / 2
        local innerW = subInnerEndX - subInnerX
        local sbGap = (innerW - sbW * 3) / 4  -- 均匀间距
        local subBtnDefs = {
            { id = "sort",      label = SORT_LABELS[equipState.sortMode] },
            { id = "lock",      label = equipState.isLocked and "锁定中" or "锁定" },
            { id = "decompose", label = "一键分解" },
        }
        for si, btnDef in ipairs(subBtnDefs) do
            local sbX = subInnerX + sbGap + (si - 1) * (sbW + sbGap)
            M.DrawImage(vg, subBtnImg, sbX, sbY, sbW, sbH)
            -- 缓存点击区域
            equipSubBtns[si] = { x = sbX, y = sbY, w = sbW, h = sbH, id = btnDef.id }
            -- 按钮文字
            nvgFontSize(vg, math.floor(sbH * 0.42))
            nvgFontFace(vg, "sans")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 锁定中用高亮色，一键分解用橙色
            if btnDef.id == "lock" and equipState.isLocked then
                nvgFillColor(vg, nvgRGBA(255, 100, 80, 255))
            elseif btnDef.id == "decompose" then
                nvgFillColor(vg, nvgRGBA(255, 180, 60, 255))
            else
                nvgFillColor(vg, nvgRGBA(240, 230, 200, 255))
            end
            nvgText(vg, sbX + sbW / 2, sbY + sbH / 2, btnDef.label)
            Def.Register("equip.sub_" .. btnDef.id, sbX, sbY, sbW, sbH, "功能:" .. btnDef.label)
        end
    end

    -- 缓存副框位置用于下拉菜单定位
    L.equipSubFrameY = subFrameY
    L.equipSubH = subH
    L.equipSubInnerX = subInnerX
    L.equipSubInnerEndX = subInnerEndX

    -- ========== 4. 底部装备格子面板 ==========
    local gridY = subFrameY + subH + 2
    local gridH = contentY + contentH - gridY - 4  -- 填满剩余空间

    -- 底部栏背景（装备界面装备底部栏.png 598×551）
    local gridBgImg = imgCache["equip_grid_bg"]
    if gridBgImg and gridBgImg ~= 0 then
        M.DrawImage(vg, gridBgImg, padX, gridY, W - padX * 2, gridH)
    end
    Def.Register("equip.grid_bg", padX, gridY, W - padX * 2, gridH, "装备格子背景")

    -- 格子内部布局 (6列)，留出内边距不顶着外框
    local gridCols = 6
    local gridPadX = math.floor(W * 0.04)   -- 左右内边距
    local gridPadTop = math.floor(W * 0.04) -- 上方内边距
    local gridPadBot = math.floor(W * 0.025) -- 下方内边距
    local gridInnerW = W - padX * 2 - gridPadX * 2
    local cellGap = 3  -- 间距缩小
    local cellSize = math.floor((gridInnerW - (gridCols - 1) * cellGap) / gridCols)
    local gridSlotImg = imgCache["equip_grid_slot"]

    -- 计算可用行数
    local gridInnerH = gridH - gridPadTop - gridPadBot
    local gridRows = math.floor((gridInnerH + cellGap) / (cellSize + cellGap))
    if gridRows < 1 then gridRows = 1 end
    local totalCells = gridRows * gridCols

    -- 构建未装备物品的 inventory 索引列表（已装备的不在下方格子显示）
    local equippedSet = {}
    if saveData.equipped then
        for _, invIdx in pairs(saveData.equipped) do
            equippedSet[invIdx] = true
        end
    end
    local unequippedList = {}  -- { invIdx1, invIdx2, ... }
    for i = 1, #saveData.inventory do
        if not equippedSet[i] then
            unequippedList[#unequippedList + 1] = i
        end
    end

    -- 排序
    local sm = equipState.sortMode
    if sm == 2 then
        -- 按等级降序
        table.sort(unequippedList, function(a, b)
            local la = saveData.inventory[a].level or 1
            local lb = saveData.inventory[b].level or 1
            if la ~= lb then return la > lb end
            return a < b
        end)
    elseif sm == 3 then
        -- 按品质降序
        table.sort(unequippedList, function(a, b)
            local ea = findEquipData(saveData.inventory[a].id)
            local eb = findEquipData(saveData.inventory[b].id)
            local qa = ea and ea.quality or 1
            local qb = eb and eb.quality or 1
            if qa ~= qb then return qa > qb end
            return a < b
        end)
    end

    -- 绘制所有格子
    L.equipGridCells = {}
    for idx = 1, totalCells do
        local col = (idx - 1) % gridCols
        local row = math.floor((idx - 1) / gridCols)
        local cx = padX + gridPadX + col * (cellSize + cellGap)
        local cy = gridY + gridPadTop + row * (cellSize + cellGap)

        local cellId = "equip.grid_" .. idx
        cx, cy = Def.Apply(cellId, cx, cy)
        Def.Register(cellId, cx, cy, cellSize, cellSize, "格子" .. idx)

        -- 格子框架
        if gridSlotImg and gridSlotImg ~= 0 then
            M.DrawImage(vg, gridSlotImg, cx, cy, cellSize, cellSize)
        end

        -- 背包物品（跳过已装备的）
        local invIdx = unequippedList[idx]
        if invIdx then
            local inst = saveData.inventory[invIdx]
            local itemData = findEquipData(inst.id)
            if itemData then
                local eqImg = imgCache[itemData.icon]
                if eqImg and eqImg ~= 0 then
                    local icoS = math.floor(cellSize * 0.65)
                    M.DrawImage(vg, eqImg, cx + (cellSize - icoS) / 2, cy + (cellSize - icoS) / 2, icoS, icoS)
                end
                -- 品质光效（弹窗打开时冻结动画）
                local gt = (equipState.showConfirm or equipState.showDropdown) and 0 or elapsedTime
                M.DrawQualityGlow(vg, cx, cy, cellSize, cellSize, itemData.quality, gt)

                -- 等级标签（右下角）
                if inst.level and inst.level > 1 then
                    nvgFontFace(vg, "sans")
                    nvgFontSize(vg, math.floor(cellSize * 0.22))
                    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                    nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
                    nvgText(vg, cx + cellSize - 4, cy + cellSize - 3, tostring(inst.level))
                end

                -- 已锁定装备：左下角锁图标（保持宽高比）
                if inst.locked then
                    local lkImg = imgCache["common_lock"]
                    if lkImg and lkImg ~= 0 then
                        local lkS = math.floor(cellSize * 0.28)
                        M.DrawImageFit(vg, lkImg, cx + 2, cy + cellSize - lkS - 2, lkS, lkS)
                    end
                end
            end
            -- 缓存有物品的格子（存真实 inventory 索引）
            L.equipGridCells[idx] = { x = cx, y = cy, w = cellSize, h = cellSize, invIdx = invIdx }
        end
    end

    -- 装备详情弹窗（覆盖在格子之上）
    if equipDetailIdx then
        M.DrawEquipDetailPopup(vg, W, equipDetailIdx)
    end

    elseif equipState.catIndex == 1 then
    -- ========== 角色标签页 ==========
    local charAreaH = contentY + contentH - bottomY - 4
    local charBgImg = imgCache["equip_grid_bg"]
    if charBgImg and charBgImg ~= 0 then
        M.DrawImage(vg, charBgImg, padX, bottomY, W - padX * 2, charAreaH)
    end

    -- 角色卡片网格（4列）
    local charCols = 4
    local charGap = 6
    local charPadX = math.floor(W * 0.04)
    local charPadTop = math.floor(W * 0.04)
    local charInnerW = W - padX * 2 - charPadX * 2
    local charCardW = math.floor((charInnerW - charGap * (charCols - 1)) / charCols)
    -- 商品底框比例 703x1182 ≈ 1.68
    local charCardH = math.floor(charCardW * 1.68)
    local charFrameImg = imgCache["shop_item_frame"]

    -- 品质边框颜色
    local qualityBorderColors = {
        {160, 165, 175},  -- 1 白
        { 65, 170,  80},  -- 2 绿
        { 55, 120, 210},  -- 3 蓝
        {150,  60, 200},  -- 4 紫
        {220, 165,  30},  -- 5 橙
        {210,  45,  45},  -- 6 红
    }

    L.charGridCells = {}
    for ci, charDef in ipairs(MD.CHARACTERS) do
        local col = (ci - 1) % charCols
        local row = math.floor((ci - 1) / charCols)
        local cx = padX + charPadX + col * (charCardW + charGap)
        local cy = bottomY + charPadTop + row * (charCardH + charGap)

        local isUnlocked = saveData.unlockedChars and saveData.unlockedChars[charDef.id]
        local isActive = (saveData.activeChar == charDef.id)

        -- 底框
        if charFrameImg and charFrameImg ~= 0 then
            M.DrawImage(vg, charFrameImg, cx, cy, charCardW, charCardH)
        end

        -- 品质边框
        local qc = qualityBorderColors[charDef.quality] or qualityBorderColors[1]
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx + 2, cy + 2, charCardW - 4, charCardH - 4, 4)
        nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], isUnlocked and 220 or 80))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 角色图标
        local charIcon = imgCache["char_" .. charDef.id]
        if charIcon and charIcon ~= 0 then
            local icoS = math.floor(charCardW * 0.70)
            local icoX = cx + (charCardW - icoS) / 2
            local icoY = cy + charCardH * 0.12
            if not isUnlocked then
                nvgGlobalAlpha(vg, 0.35)
            end
            M.DrawImageFit(vg, charIcon, icoX, icoY, icoS, icoS)
            if not isUnlocked then
                nvgGlobalAlpha(vg, 1.0)
            end
        end

        -- 已解锁 + 品质光效
        if isUnlocked then
            local gt = (equipState.showConfirm or equipState.showDropdown) and 0 or elapsedTime
            M.DrawQualityGlow(vg, cx, cy, charCardW, charCardH, charDef.quality, gt)
        end

        -- "使用中"标签（左上角）
        if isActive then
            local tagW = math.floor(charCardW * 0.65)
            local tagH = math.floor(charCardW * 0.22)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, cy, tagW, tagH, 3)
            nvgFillColor(vg, nvgRGBA(220, 165, 30, 230))
            nvgFill(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.floor(tagH * 0.70))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(40, 20, 0, 255))
            nvgText(vg, cx + tagW / 2, cy + tagH / 2, "使用中")
        end

        -- 角色名称（底部）
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(charCardW * 0.18))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(240, 230, 200, 255))
        nvgText(vg, cx + charCardW / 2, cy + charCardH - charCardH * 0.22, charDef.name)

        -- 底部信息
        if isUnlocked then
            -- 碎片进度
            local frags = (saveData.charFrags and saveData.charFrags[charDef.id]) or 0
            local maxFrags = 10
            nvgFontSize(vg, math.floor(charCardW * 0.16))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(100, 180, 255, 230))
            nvgText(vg, cx + charCardW / 2, cy + charCardH - 4, frags .. "/" .. maxFrags)
        else
            -- 未解锁
            nvgFontSize(vg, math.floor(charCardW * 0.16))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(vg, nvgRGBA(140, 140, 140, 200))
            nvgText(vg, cx + charCardW / 2, cy + charCardH - 4, "未解锁")
        end

        -- 缓存点击区域
        L.charGridCells[ci] = { x = cx, y = cy, w = charCardW, h = charCardH, charId = charDef.id, unlocked = isUnlocked }
        Def.Register("equip.char_" .. ci, cx, cy, charCardW, charCardH, "角色:" .. charDef.name)
    end

    -- 角色详情弹窗（覆盖在网格之上）
    if charDetailId then
        M.DrawCharDetailPopup(vg, W, charDetailId)
    end

    elseif equipState.catIndex == 3 then
    -- ========== 藏品标签页 ==========
    local placeholderH = contentY + contentH - bottomY - 4
    local phBgImg = imgCache["equip_grid_bg"]
    if phBgImg and phBgImg ~= 0 then
        M.DrawImage(vg, phBgImg, padX, bottomY, W - padX * 2, placeholderH)
    end
    -- 提示文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(W * 0.045))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(160, 150, 130, 200))
    nvgText(vg, W / 2, bottomY + placeholderH / 2, "藏品系统 · 敬请期待")

    end -- catIndex 条件结束

    return 0 -- 不需要滚动，整体自适应
end

------------------------------------------------------------------------
-- 装备详情弹窗（背包装备点击后弹出）
------------------------------------------------------------------------

function M.DrawEquipDetailPopup(vg, W, invIdx)
    local inst = saveData.inventory[invIdx]
    if not inst then equipDetailIdx = nil; return end

    local eqData = findEquipData(inst.id)
    if not eqData then equipDetailIdx = nil; return end

    local contentY = L.contentY
    local contentH = L.contentH
    local qInfo = MD.QUALITY[eqData.quality] or MD.QUALITY[1]
    local qc = qInfo.color

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, contentY, W, contentH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗尺寸
    local popW = math.floor(W * 0.78)
    local popH = math.floor(contentH * 0.72)
    local popX = (W - popW) / 2
    local popY = contentY + (contentH - popH) / 2
    local innerPad = math.floor(popW * 0.05)

    -- 弹窗背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popX, popY, popW, popH, 8)
    nvgFillColor(vg, nvgRGBA(30, 32, 42, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popX, popY, popW, popH, 8)
    nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 140))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local px = popX
    local py = popY

    -- ====== 标题栏 ======
    local titleH = math.floor(popH * 0.07)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, popW, titleH, 8)
    nvgFillColor(vg, nvgRGBA(45, 48, 60, 255))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(titleH * 0.50))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
    nvgText(vg, px + innerPad, py + titleH / 2, eqData.name)

    -- 关闭按钮 X
    local closeS = math.floor(titleH * 0.6)
    local closeX = px + popW - innerPad - closeS
    local closeY = py + (titleH - closeS) / 2
    nvgFontSize(vg, math.floor(closeS * 0.8))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 170, 160, 200))
    nvgText(vg, closeX + closeS / 2, closeY + closeS / 2, "X")
    L.equipDetailClose = { x = closeX, y = closeY, w = closeS, h = closeS }

    -- ====== 装备信息卡片（图标 + 名称/等级/品质） ======
    local cardY = py + titleH + 6
    local cardH = math.floor(popH * 0.16)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + innerPad, cardY, popW - innerPad * 2, cardH, 6)
    nvgFillColor(vg, nvgRGBA(38, 42, 55, 200))
    nvgFill(vg)

    -- 左侧：大图标 + 品质边框
    local bigIcoS = math.floor(cardH * 0.72)
    local bigIcoPad = math.floor((cardH - bigIcoS) / 2)
    local eqImg = imgCache[eqData.icon]
    if eqImg and eqImg ~= 0 then
        M.DrawImage(vg, eqImg, px + innerPad + bigIcoPad, cardY + bigIcoPad, bigIcoS, bigIcoS)
    end
    -- 品质边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + innerPad + bigIcoPad - 1, cardY + bigIcoPad - 1, bigIcoS + 2, bigIcoS + 2, 4)
    nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 右侧：名称 + 等级/品质标签
    local infoX = px + innerPad + bigIcoPad + bigIcoS + 12
    local infoFont = math.floor(popW * 0.038)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(infoFont * 1.1))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
    nvgText(vg, infoX, cardY + cardH * 0.30, eqData.name)

    -- 等级和品质徽标
    local badgeY = cardY + cardH * 0.62
    local badgeH = math.floor(infoFont * 1.3)
    local badgeW = math.floor(badgeH * 2.2)

    -- 等级徽标
    nvgBeginPath(vg)
    nvgRoundedRect(vg, infoX, badgeY, badgeW, badgeH, 3)
    nvgFillColor(vg, nvgRGBA(50, 55, 70, 255))
    nvgFill(vg)
    nvgFontSize(vg, math.floor(badgeH * 0.65))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, infoX + badgeW / 2, badgeY + badgeH / 2, "等级 " .. (inst.level or 1))

    -- 品质徽标
    local qBadgeX = infoX + badgeW + 6
    nvgBeginPath(vg)
    nvgRoundedRect(vg, qBadgeX, badgeY, badgeW, badgeH, 3)
    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 60))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, qBadgeX, badgeY, badgeW, badgeH, 3)
    nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, math.floor(badgeH * 0.65))
    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
    nvgText(vg, qBadgeX + badgeW / 2, badgeY + badgeH / 2, qInfo.name)

    -- ====== 分割线 ======
    local divY1 = cardY + cardH + 8
    nvgBeginPath(vg)
    nvgRect(vg, px + innerPad, divY1, popW - innerPad * 2, 1)
    nvgFillColor(vg, nvgRGBA(60, 65, 80, 180))
    nvgFill(vg)

    -- ====== 基础属性 ======
    local secFont = math.floor(popW * 0.036)
    local rowH = math.floor(secFont * 2.0)
    local secTitleH = math.floor(secFont * 1.8)
    local curY = divY1 + 4

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(secFont * 0.9))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 175, 160, 220))
    nvgText(vg, px + popW / 2, curY + secTitleH / 2, "基础属性")
    curY = curY + secTitleH

    -- 基础属性行
    if eqData.baseStats then
        for statId, val in pairs(eqData.baseStats) do
            local statName = MD.STAT_NAMES[statId] or statId
            local unit = MD.STAT_UNITS[statId] or ""

            -- 行背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px + innerPad, curY, popW - innerPad * 2, rowH, 4)
            nvgFillColor(vg, nvgRGBA(38, 42, 55, 140))
            nvgFill(vg)

            nvgFontSize(vg, secFont)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(200, 195, 180, 230))
            nvgText(vg, px + innerPad + 12, curY + rowH / 2, statName)

            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(100, 220, 140, 255))
            nvgText(vg, px + popW - innerPad - 12, curY + rowH / 2, "+" .. val .. unit)

            curY = curY + rowH + 2
        end
    end

    -- ====== 分割线 ======
    curY = curY + 4
    nvgBeginPath(vg)
    nvgRect(vg, px + innerPad, curY, popW - innerPad * 2, 1)
    nvgFillColor(vg, nvgRGBA(60, 65, 80, 180))
    nvgFill(vg)
    curY = curY + 4

    -- ====== 随机属性 ======
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(secFont * 0.9))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 175, 160, 220))
    nvgText(vg, px + popW / 2, curY + secTitleH / 2, "随机属性")
    curY = curY + secTitleH

    if inst.affixes and #inst.affixes > 0 then
        for _, aff in ipairs(inst.affixes) do
            local affData = MD.FindAffix(aff.affixId)
            if affData then
                local grade = math.max(1, math.min(aff.grade, 5))
                local gradeLetter = MD.AFFIX_GRADES[grade]
                local gradeColor = MD.AFFIX_GRADE_COLORS[grade]
                local val = affData.values[grade]
                local statName = MD.STAT_NAMES[aff.affixId] or aff.affixId
                local unit = MD.STAT_UNITS[aff.affixId] or ""

                -- 行背景
                nvgBeginPath(vg)
                nvgRoundedRect(vg, px + innerPad, curY, popW - innerPad * 2, rowH, 4)
                nvgFillColor(vg, nvgRGBA(38, 42, 55, 140))
                nvgFill(vg)

                -- 等级徽标
                local gBadgeW = math.floor(rowH * 0.75)
                nvgFontSize(vg, math.floor(rowH * 0.40))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(gradeColor[1], gradeColor[2], gradeColor[3], 255))
                nvgFontFace(vg, "sans")
                nvgText(vg, px + innerPad + 8 + gBadgeW / 2, curY + rowH / 2, gradeLetter)

                -- 属性名
                nvgFontSize(vg, secFont)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(200, 195, 180, 230))
                nvgText(vg, px + innerPad + 8 + gBadgeW + 8, curY + rowH / 2, statName)

                -- 属性值
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(gradeColor[1], gradeColor[2], gradeColor[3], 255))
                nvgText(vg, px + popW - innerPad - 12, curY + rowH / 2, "+" .. val .. unit)

                curY = curY + rowH + 2
            end
        end
    else
        nvgFontSize(vg, math.floor(secFont * 0.85))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 95, 85, 160))
        nvgText(vg, px + popW / 2, curY + rowH / 2, "无随机属性")
        curY = curY + rowH
    end

    -- ====== 底部按钮区域（3个按钮：分解 / 装备 / 洗练） ======
    local btnAreaH = math.floor(popH * 0.10)
    local btnAreaY = py + popH - btnAreaH - 6
    local btnCount = 3
    local btnGap = math.floor(innerPad * 0.6)
    local btnW2 = math.floor((popW - innerPad * 2 - (btnCount - 1) * btnGap) / btnCount)
    local btnH2 = math.floor(btnAreaH * 0.70)
    local btnY2 = btnAreaY + (btnAreaH - btnH2) / 2

    -- 检查是否已装备到某个槽位
    local eqSlotId = nil
    for slotName, idx in pairs(saveData.equipped) do
        if idx == invIdx then eqSlotId = slotName; break end
    end

    -- 按钮1：分解（红色）
    local decompX = px + innerPad
    nvgBeginPath(vg)
    nvgRoundedRect(vg, decompX, btnY2, btnW2, btnH2, 5)
    nvgFillColor(vg, nvgRGBA(160, 50, 40, 220))
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(btnH2 * 0.42))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, decompX + btnW2 / 2, btnY2 + btnH2 / 2, "分解")
    L.equipDetailDecompBtn = { x = decompX, y = btnY2, w = btnW2, h = btnH2 }

    -- 按钮2：装备/卸下（绿色/暗色）
    local equipBtnX = decompX + btnW2 + btnGap
    nvgBeginPath(vg)
    nvgRoundedRect(vg, equipBtnX, btnY2, btnW2, btnH2, 5)
    if eqSlotId then
        nvgFillColor(vg, nvgRGBA(100, 70, 50, 220))
    else
        nvgFillColor(vg, nvgRGBA(55, 130, 85, 220))
    end
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(btnH2 * 0.42))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, equipBtnX + btnW2 / 2, btnY2 + btnH2 / 2, eqSlotId and "卸下" or "装备")
    L.equipDetailEquipBtn = { x = equipBtnX, y = btnY2, w = btnW2, h = btnH2 }

    -- 按钮3：洗练（金色）
    local reforgeX = equipBtnX + btnW2 + btnGap
    local reforgeCost = MD.REFORGE_COST[eqData.quality] or 50
    local canReforge = saveData.gold >= reforgeCost and inst.affixes and #inst.affixes > 0
    nvgBeginPath(vg)
    nvgRoundedRect(vg, reforgeX, btnY2, btnW2, btnH2, 5)
    if canReforge then
        nvgFillColor(vg, nvgRGBA(180, 145, 40, 220))
    else
        nvgFillColor(vg, nvgRGBA(80, 75, 60, 160))
    end
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(btnH2 * 0.42))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, canReforge and 240 or 120))
    nvgText(vg, reforgeX + btnW2 / 2, btnY2 + btnH2 / 2, "洗练")
    -- 洗练费用小字
    nvgFontSize(vg, math.floor(btnH2 * 0.28))
    nvgFillColor(vg, nvgRGBA(255, 220, 100, canReforge and 200 or 80))
    nvgText(vg, reforgeX + btnW2 / 2, btnY2 + btnH2 * 0.82, reforgeCost .. "金")
    L.equipDetailReforgeBtn = { x = reforgeX, y = btnY2, w = btnW2, h = btnH2 }

    -- 缓存弹窗区域
    L.equipDetailPopup = { x = popX, y = popY, w = popW, h = popH }
end

------------------------------------------------------------------------
-- 角色详情弹窗（角色卡片点击后弹出）
------------------------------------------------------------------------
function M.DrawCharDetailPopup(vg, W, cId)
    -- 查找角色数据
    local charDef = nil
    for _, c in ipairs(MD.CHARACTERS) do
        if c.id == cId then charDef = c; break end
    end
    if not charDef then charDetailId = nil; return end

    local isUnlocked = saveData.unlockedChars and saveData.unlockedChars[cId]
    local isActive = (saveData.activeChar == cId)
    local curStar = (saveData.charStars and saveData.charStars[cId]) or 0
    local qInfo = MD.QUALITY[charDef.quality] or MD.QUALITY[1]
    local qc = qInfo.color

    local contentY = L.contentY
    local contentH = L.contentH

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, contentY, W, contentH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗尺寸
    local popW = math.floor(W * 0.82)
    local popH = math.floor(contentH * 0.82)
    local popX = (W - popW) / 2
    local popY = contentY + (contentH - popH) / 2
    local pad = math.floor(popW * 0.04)

    local px = popX
    local py = popY

    -- ====== 顶部头像卡片区 ======
    local headerH = math.floor(popH * 0.16)
    -- 头部背景（带品质色渐变）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, popW, headerH, 8)
    nvgFillColor(vg, nvgRGBA(40, 44, 58, 250))
    nvgFill(vg)
    -- 品质色底边
    nvgBeginPath(vg)
    nvgRect(vg, px, py + headerH - 2, popW, 2)
    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 140))
    nvgFill(vg)

    -- 角色头像（左侧）
    local avatarS = math.floor(headerH * 0.72)
    local avatarPad = math.floor((headerH - avatarS) / 2)
    local charIcon = imgCache["char_" .. cId]
    if charIcon and charIcon ~= 0 then
        -- 头像背景框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad, py + avatarPad, avatarS, avatarS, 6)
        nvgFillColor(vg, nvgRGBA(25, 28, 38, 200))
        nvgFill(vg)
        if not isUnlocked then nvgGlobalAlpha(vg, 0.4) end
        M.DrawImageFit(vg, charIcon, px + pad + 2, py + avatarPad + 2, avatarS - 4, avatarS - 4)
        if not isUnlocked then nvgGlobalAlpha(vg, 1.0) end
        -- 品质边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad, py + avatarPad, avatarS, avatarS, 6)
        nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 右侧信息：角色名
    local infoX = px + pad + avatarS + math.floor(pad * 0.8)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(headerH * 0.30))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
    nvgText(vg, infoX, py + headerH * 0.30, charDef.name)

    -- 星级 + 品质徽标（框包住标题和数值）
    local bdgFont = math.floor(headerH * 0.13)
    local bdgW = math.floor(bdgFont * 3.2)
    local bdgTotalH = math.floor(bdgFont * 3.2)
    local bdgY = py + headerH * 0.52

    -- 星级徽标
    nvgBeginPath(vg)
    nvgRoundedRect(vg, infoX, bdgY, bdgW, bdgTotalH, 4)
    nvgFillColor(vg, nvgRGBA(50, 55, 70, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, infoX, bdgY, bdgW, bdgTotalH, 4)
    nvgStrokeColor(vg, nvgRGBA(80, 85, 100, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, bdgFont)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, infoX + bdgW / 2, bdgY + bdgTotalH * 0.30, "星级")
    nvgFontSize(vg, math.floor(bdgFont * 1.1))
    nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
    nvgText(vg, infoX + bdgW / 2, bdgY + bdgTotalH * 0.72, tostring(curStar))

    -- 品质徽标
    local qBdgX = infoX + bdgW + math.floor(headerH * 0.08)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, qBdgX, bdgY, bdgW, bdgTotalH, 4)
    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 50))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, qBdgX, bdgY, bdgW, bdgTotalH, 4)
    nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 160))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontSize(vg, bdgFont)
    nvgFillColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 255))
    nvgText(vg, qBdgX + bdgW / 2, bdgY + bdgTotalH * 0.30, "品质")
    local qInfo2 = MD.QUALITY[charDef.quality] or MD.QUALITY[1]
    nvgFontSize(vg, math.floor(bdgFont * 1.0))
    nvgText(vg, qBdgX + bdgW / 2, bdgY + bdgTotalH * 0.72, qInfo2.name)

    -- 关闭按钮（右上角圆形）
    local closeR = math.floor(headerH * 0.18)
    local closeCX = px + popW - pad - closeR
    local closeCY = py + pad + closeR
    nvgBeginPath(vg)
    nvgCircle(vg, closeCX, closeCY, closeR)
    nvgFillColor(vg, nvgRGBA(60, 65, 80, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, closeCX, closeCY, closeR)
    nvgStrokeColor(vg, nvgRGBA(100, 105, 120, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(closeR * 1.2))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 175, 165, 220))
    nvgText(vg, closeCX, closeCY, "X")
    L.charDetailClose = { x = closeCX - closeR, y = closeCY - closeR, w = closeR * 2, h = closeR * 2 }

    -- ====== 主体区域背景 ======
    local bodyY = py + headerH
    local bodyH = popH - headerH
    nvgBeginPath(vg)
    local cr = 8
    -- 只圆底部两角
    nvgRoundedRect(vg, px, bodyY, popW, bodyH, cr)
    nvgFillColor(vg, nvgRGBA(30, 33, 45, 245))
    nvgFill(vg)
    -- 整体弹窗边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, popW, popH, cr)
    nvgStrokeColor(vg, nvgRGBA(qc[1], qc[2], qc[3], 100))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local curY = bodyY + math.floor(pad * 0.8)
    local innerW = popW - pad * 2
    local secFont = math.floor(popW * 0.044)
    local rowH = math.floor(secFont * 2.6)

    -- ====== 被动效果 ======
    if charDef.passive then
        local passiveH = math.floor(rowH * 1.2)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad, curY, innerW, passiveH, 5)
        nvgFillColor(vg, nvgRGBA(38, 42, 58, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad, curY, innerW, passiveH, 5)
        nvgStrokeColor(vg, nvgRGBA(80, 85, 100, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(secFont * 1.1))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(100, 220, 140, 240))
        nvgText(vg, px + popW / 2, curY + passiveH / 2, charDef.passive)
        curY = curY + passiveH + math.floor(pad * 0.6)
    end

    -- ====== 技能区 ======
    if charDef.skill then
        local skillH = math.floor(rowH * 1.8)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad, curY, innerW, skillH, 5)
        nvgFillColor(vg, nvgRGBA(38, 42, 58, 200))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad, curY, innerW, skillH, 5)
        nvgStrokeColor(vg, nvgRGBA(80, 85, 100, 120))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 技能图标占位（左侧方块）
        local skIcoS = math.floor(skillH * 0.65)
        local skIcoPad = math.floor((skillH - skIcoS) / 2)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad + skIcoPad, curY + skIcoPad, skIcoS, skIcoS, 4)
        nvgFillColor(vg, nvgRGBA(60, 55, 45, 200))
        nvgFill(vg)
        -- 用角色头像作技能图标
        if charIcon and charIcon ~= 0 then
            M.DrawImageFit(vg, charIcon, px + pad + skIcoPad + 2, curY + skIcoPad + 2, skIcoS - 4, skIcoS - 4)
        end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + pad + skIcoPad, curY + skIcoPad, skIcoS, skIcoS, 4)
        nvgStrokeColor(vg, nvgRGBA(220, 165, 30, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 技能名称
        local skTextX = px + pad + skIcoPad + skIcoS + 10
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(secFont * 1.1))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 235, 220, 255))
        nvgText(vg, skTextX, curY + skillH * 0.34, charDef.skill.name)
        -- 技能描述
        nvgFontSize(vg, math.floor(secFont * 0.92))
        nvgFillColor(vg, nvgRGBA(170, 165, 150, 210))
        nvgText(vg, skTextX, curY + skillH * 0.66, charDef.skill.desc)

        curY = curY + skillH + math.floor(pad * 0.6)
    end

    -- ====== 星级列表 ======
    if charDef.stars then
        local starRowH = math.floor(rowH * 1.1)
        for si, starDesc in ipairs(charDef.stars) do
            local isReached = (curStar >= si)
            -- 行背景（交替色）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px + pad, curY, innerW, starRowH, 4)
            if si % 2 == 1 then
                nvgFillColor(vg, nvgRGBA(38, 42, 55, 160))
            else
                nvgFillColor(vg, nvgRGBA(44, 48, 62, 160))
            end
            nvgFill(vg)
            -- 底部分隔线
            nvgBeginPath(vg)
            nvgRect(vg, px + pad, curY + starRowH - 1, innerW, 1)
            nvgFillColor(vg, nvgRGBA(60, 65, 80, 80))
            nvgFill(vg)

            -- 星级标签
            local starBdgW = math.floor(innerW * 0.16)
            local starBdgH = math.floor(starRowH * 0.60)
            local starBdgX = px + pad + 6
            local starBdgY = curY + (starRowH - starBdgH) / 2
            nvgBeginPath(vg)
            nvgRoundedRect(vg, starBdgX, starBdgY, starBdgW, starBdgH, 3)
            if isReached then
                nvgFillColor(vg, nvgRGBA(55, 130, 85, 200))
            else
                nvgFillColor(vg, nvgRGBA(55, 60, 75, 200))
            end
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, starBdgX, starBdgY, starBdgW, starBdgH, 3)
            nvgStrokeColor(vg, isReached and nvgRGBA(80, 180, 120, 160) or nvgRGBA(80, 85, 100, 120))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.floor(starBdgH * 0.65))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, isReached and 240 or 140))
            nvgText(vg, starBdgX + starBdgW / 2, starBdgY + starBdgH / 2, si .. "星")

            -- 描述文字
            nvgFontSize(vg, math.floor(secFont * 1.0))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            if isReached then
                nvgFillColor(vg, nvgRGBA(240, 235, 220, 240))
            else
                nvgFillColor(vg, nvgRGBA(140, 135, 125, 180))
            end
            nvgText(vg, starBdgX + starBdgW + 10, curY + starRowH / 2, starDesc)

            curY = curY + starRowH
        end
    end

    -- ====== 底部升星条 ======
    local footerH = math.floor(popH * 0.10)
    local footerY = py + popH - footerH * 2 - 6
    -- 升星条背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + pad, footerY, innerW, footerH, 5)
    nvgFillColor(vg, nvgRGBA(38, 42, 58, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + pad, footerY, innerW, footerH, 5)
    nvgStrokeColor(vg, nvgRGBA(80, 85, 100, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 碎片图标（用角色头像缩小）
    local fragS = math.floor(footerH * 0.65)
    local fragPad = math.floor((footerH - fragS) / 2)
    if charIcon and charIcon ~= 0 then
        M.DrawImageFit(vg, charIcon, px + pad + fragPad, footerY + fragPad, fragS, fragS)
        -- 小星星角标
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(fragS * 0.45))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, px + pad + fragPad + fragS - 2, footerY + fragPad + 4, "★")
    end

    -- 碎片进度
    local frags = (saveData.charFrags and saveData.charFrags[cId]) or 0
    local nextStar = math.min(curStar + 1, MD.MAX_STAR)
    local needFrags = MD.STAR_FRAG_COST[nextStar] or 10
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(footerH * 0.42))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 235, 220, 240))
    nvgText(vg, px + pad + fragPad + fragS + 10, footerY + footerH / 2, frags .. "/" .. needFrags)

    -- 升星按钮（右侧金色）
    local starBtnW = math.floor(innerW * 0.30)
    local starBtnH = math.floor(footerH * 0.72)
    local starBtnX = px + pad + innerW - starBtnW - 4
    local starBtnY = footerY + (footerH - starBtnH) / 2
    local canUpgrade = isUnlocked and curStar < MD.MAX_STAR and frags >= needFrags
    nvgBeginPath(vg)
    nvgRoundedRect(vg, starBtnX, starBtnY, starBtnW, starBtnH, 5)
    if canUpgrade then
        nvgFillColor(vg, nvgRGBA(220, 170, 30, 240))
    else
        nvgFillColor(vg, nvgRGBA(90, 85, 70, 180))
    end
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(starBtnH * 0.55))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(40, 25, 0, canUpgrade and 255 or 140))
    nvgText(vg, starBtnX + starBtnW / 2, starBtnY + starBtnH / 2, "升星")
    L.charDetailStarBtn = { x = starBtnX, y = starBtnY, w = starBtnW, h = starBtnH, canUpgrade = canUpgrade }

    -- ====== 底部使用按钮 ======
    local useBtnH = math.floor(footerH * 0.80)
    local useBtnW = math.floor(popW * 0.40)
    local useBtnX = px + (popW - useBtnW) / 2
    local useBtnY = footerY + footerH + math.floor(pad * 0.4)

    if isUnlocked then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, useBtnX, useBtnY, useBtnW, useBtnH, 6)
        if isActive then
            nvgFillColor(vg, nvgRGBA(55, 130, 85, 160))
        else
            nvgFillColor(vg, nvgRGBA(55, 130, 85, 230))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, useBtnX, useBtnY, useBtnW, useBtnH, 6)
        nvgStrokeColor(vg, nvgRGBA(80, 180, 120, isActive and 100 or 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(useBtnH * 0.55))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, isActive and 160 or 250))
        nvgText(vg, useBtnX + useBtnW / 2, useBtnY + useBtnH / 2, isActive and "使用中" or "使用")
        L.charDetailUseBtn = { x = useBtnX, y = useBtnY, w = useBtnW, h = useBtnH, disabled = isActive }
    else
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(useBtnH * 0.38))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(140, 135, 120, 160))
        nvgText(vg, px + popW / 2, useBtnY + useBtnH / 2, "收集碎片解锁该角色")
        L.charDetailUseBtn = nil
    end

    -- 缓存弹窗区域
    L.charDetailPopup = { x = popX, y = popY, w = popW, h = popH }
end

------------------------------------------------------------------------
-- 列车/炮塔装备面板（类似装备界面风格）
------------------------------------------------------------------------
-- 根据炮塔id查找 TURRET_UPGRADES 数据
local function findTurretData(turretId)
    for _, t in ipairs(MD.TURRET_UPGRADES) do
        if t.id == turretId then return t end
    end
    return nil
end

function M.DrawTrainPanel(vg, W)
    local c = MD.CLR
    local contentY = L.contentY
    local contentH = L.contentH
    local padX = 6

    -- ========== 1. 顶部火车展示区域（占内容区 ~45%） ==========
    local topAreaH = math.floor(contentH * 0.43)
    local topY = contentY + 4

    -- 火车背景图（1086×1448）
    local trainBgImg = imgCache["turret_train_bg"]
    if trainBgImg and trainBgImg ~= 0 then
        -- 保持比例填充顶部区域
        local bgRatio = 1086 / 1448
        local bgH = topAreaH
        local bgW = math.floor(bgH * bgRatio)
        if bgW < W then
            bgW = W
            bgH = math.floor(bgW / bgRatio)
        end
        local bgX = (W - bgW) / 2
        local bgY = topY + (topAreaH - bgH) / 2
        M.DrawImage(vg, trainBgImg, bgX, bgY, bgW, bgH)
    end
    Def.Register("train.bg", 0, topY, W, topAreaH, "火车展示区")

    -- 火车标题图片（左上角）
    local trainTitleImg = imgCache["train_title"]
    if trainTitleImg and trainTitleImg ~= 0 then
        local titleH = math.floor(topAreaH * 0.09)
        local titleW = math.floor(titleH * 3.2)  -- 根据标题图比例
        local titleX = -8
        local titleY = topY + 4
        M.DrawImageFit(vg, trainTitleImg, titleX, titleY, titleW, titleH)
    end

    -- ========== 2. 左右两侧炮塔装备槽（各2个） ==========
    -- 槽位框架（183×205）
    local slotW = math.floor(W * 0.20)
    local slotH = math.floor(slotW * 205 / 183)
    local slotGap = 6
    local slotFrameImg = imgCache["turret_slot_frame"]

    -- 垂直居中排列2个槽
    local totalSlotH = 2 * slotH + slotGap
    local slotStartY = topY + (topAreaH - totalSlotH) / 2

    -- 初始化装备槽位（确保存档兼容）
    if not saveData.turretEquipped then
        saveData.turretEquipped = {"arrow", "minigun", "sniper", "rocket"}
    end
    if not saveData.turretUnlocked then
        saveData.turretUnlocked = {arrow = true, minigun = true, sniper = true, rocket = true}
    end

    L.turretSlots = {}
    local slotPositions = {
        -- 左侧2个
        { side = "left",  idx = 0 },
        { side = "left",  idx = 1 },
        -- 右侧2个
        { side = "right", idx = 0 },
        { side = "right", idx = 1 },
    }
    for slotIdx = 1, 4 do
        local sp = slotPositions[slotIdx]
        local sx, sy
        if sp.side == "left" then
            sx = padX + 2
        else
            sx = W - padX - slotW - 2
        end
        sy = slotStartY + sp.idx * (slotH + slotGap)

        local slotId = "train.slot_" .. slotIdx
        sx, sy = Def.Apply(slotId, sx, sy)
        Def.Register(slotId, sx, sy, slotW, slotH, "炮塔槽" .. slotIdx)

        -- 缓存槽位位置
        L.turretSlots[slotIdx] = { x = sx, y = sy, w = slotW, h = slotH }

        -- 绘制槽位框架
        if slotFrameImg and slotFrameImg ~= 0 then
            M.DrawImage(vg, slotFrameImg, sx, sy, slotW, slotH)
        end

        -- 已装备的炮塔图标
        local equippedId = saveData.turretEquipped[slotIdx]
        if equippedId then
            local tData = findTurretData(equippedId)
            if tData then
                local tImg = imgCache[tData.icon]
                if tImg and tImg ~= 0 then
                    local icoS = math.floor(slotW * 0.55)
                    M.DrawImage(vg, tImg, sx + (slotW - icoS) / 2, sy + (slotH - icoS) / 2 - 4, icoS, icoS)
                end
                -- 炮塔名称
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, math.floor(slotW * 0.15))
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(240, 230, 200, 255))
                nvgText(vg, sx + slotW / 2, sy + slotH - 6, tData.name)
            end
        else
            -- 空槽 + 号提示
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, math.floor(slotW * 0.35))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(120, 120, 120, 120))
            nvgText(vg, sx + slotW / 2, sy + slotH / 2, "+")
        end
    end

    -- ========== 3. 底部炮塔列表背景 ==========
    local listY = topY + topAreaH + 6
    local listH = contentY + contentH - listY - 4

    -- 复用装备界面的底部栏背景
    local listBgImg = imgCache["equip_grid_bg"]
    if listBgImg and listBgImg ~= 0 then
        M.DrawImage(vg, listBgImg, padX, listY, W - padX * 2, listH)
    end
    Def.Register("train.list_bg", padX, listY, W - padX * 2, listH, "炮塔列表背景")

    -- ========== 4. 绘制炮塔列表 ==========
    local listPadX = math.floor(W * 0.04)
    local listPadTop = math.floor(W * 0.03)
    local listInnerW = W - padX * 2 - listPadX * 2
    local rowH = math.floor(listH * 0.14)
    if rowH < 30 then rowH = 30 end
    if rowH > 48 then rowH = 48 end
    local rowGap = 3
    local lockImg = imgCache["common_lock"]

    -- 构建所有炮塔列表（解锁的在前，未解锁的在后）
    local allTurrets = {}
    for _, t in ipairs(MD.TURRET_UPGRADES) do
        if saveData.turretUnlocked[t.id] then
            allTurrets[#allTurrets + 1] = t
        end
    end
    for _, t in ipairs(MD.TURRET_UPGRADES) do
        if not saveData.turretUnlocked[t.id] then
            allTurrets[#allTurrets + 1] = t
        end
    end

    -- 检查炮塔是否已被装备到某个槽位
    local function isTurretEquipped(turretId)
        for s = 1, 4 do
            if saveData.turretEquipped[s] == turretId then return s end
        end
        return nil
    end

    L.turretRows = {}

    for idx = 1, #allTurrets do
        local t = allTurrets[idx]
        local ry = listY + listPadTop + (idx - 1) * (rowH + rowGap)

        -- 超出可见区域则停止
        if ry + rowH > listY + listH then break end

        local rx = padX + listPadX
        local rw = listInnerW

        local rowId = "train.list_" .. idx
        rx, ry = Def.Apply(rowId, rx, ry)
        Def.Register(rowId, rx, ry, rw, rowH, "炮塔行" .. idx)

        local unlocked = saveData.turretUnlocked[t.id]
        local eqSlot = isTurretEquipped(t.id)
        local lv = saveData.turretLevels[t.id] or 0

        -- 行背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rx, ry, rw, rowH, 4)
        if unlocked then
            nvgFillColor(vg, nvgRGBA(40, 40, 50, 140))
        else
            nvgFillColor(vg, nvgRGBA(30, 30, 35, 160))
        end
        nvgFill(vg)

        -- 行边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rx, ry, rw, rowH, 4)
        nvgStrokeColor(vg, nvgRGBA(80, 75, 60, 100))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 左侧：炮塔图标
        local icoS = math.floor(rowH * 0.7)
        local icoPad = math.floor((rowH - icoS) / 2)
        local tImg = imgCache[t.icon]
        if tImg and tImg ~= 0 then
            if not unlocked then
                nvgSave(vg)
                nvgGlobalAlpha(vg, 0.35)
                M.DrawImage(vg, tImg, rx + icoPad, ry + icoPad, icoS, icoS)
                nvgRestore(vg)
            else
                M.DrawImage(vg, tImg, rx + icoPad, ry + icoPad, icoS, icoS)
            end
        end

        -- 未解锁时叠加锁图标
        if not unlocked and lockImg and lockImg ~= 0 then
            local lkS = math.floor(icoS * 0.55)
            M.DrawImageFit(vg, lockImg, rx + icoPad + (icoS - lkS) / 2, ry + icoPad + (icoS - lkS) / 2, lkS, lkS)
        end

        -- 名称 + 等级
        local textX = rx + icoPad + icoS + 6
        local fontSize = math.floor(rowH * 0.28)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if unlocked then
            nvgFillColor(vg, nvgRGBA(230, 220, 200, 255))
        else
            nvgFillColor(vg, nvgRGBA(120, 120, 120, 180))
        end
        nvgText(vg, textX, ry + rowH * 0.5, t.name .. (unlocked and ("  Lv." .. lv) or ""))

        -- 右侧状态标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, math.floor(fontSize * 0.85))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if not unlocked then
            nvgFillColor(vg, nvgRGBA(140, 130, 120, 150))
            nvgText(vg, rx + rw - 8, ry + rowH / 2, "未解锁")
        elseif eqSlot then
            nvgFillColor(vg, nvgRGBA(200, 180, 100, 200))
            nvgText(vg, rx + rw - 8, ry + rowH / 2, "槽位" .. eqSlot)
        else
            nvgFillColor(vg, nvgRGBA(160, 155, 140, 140))
            nvgText(vg, rx + rw - 8, ry + rowH / 2, "详情 >")
        end

        -- 缓存整行点击区域
        L.turretRows[idx] = { x = rx, y = ry, w = rw, h = rowH, turretIdx = idx }
    end

    L.turretGridList = allTurrets

    -- ========== 5. 炮塔详情弹窗 ==========
    if turretDetailId then
        M.DrawTurretDetailPopup(vg, W, turretDetailId)
    end

    return 0
end

------------------------------------------------------------------------
-- 炮塔详情弹窗绘制
------------------------------------------------------------------------
function M.DrawTurretDetailPopup(vg, W, tId)
    local tData = findTurretData(tId)
    if not tData then turretDetailId = nil; return end

    local contentY = L.contentY
    local contentH = L.contentH

    local unlocked = saveData.turretUnlocked[tId]
    local lv = saveData.turretLevels[tId] or 0
    local frags = saveData.turretFrags[tId] or 0
    local needFrags = math.floor(tData.fragBase * (tData.fragGrow ^ lv))
    local canUpgrade = unlocked and lv < tData.maxLv and frags >= needFrags
    local affixes = MD.TURRET_AFFIXES[tId] or {}

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, contentY, W, contentH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗尺寸（紧凑）
    local popW = math.floor(W * 0.72)
    local popH = math.floor(contentH * 0.68)
    local popX = (W - popW) / 2
    local popY = contentY + (contentH - popH) / 2

    -- 弹窗背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popX, popY, popW, popH, 8)
    nvgFillColor(vg, nvgRGBA(30, 32, 42, 245))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, popX, popY, popW, popH, 8)
    nvgStrokeColor(vg, nvgRGBA(90, 85, 70, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local px = popX  -- 弹窗左边
    local py = popY  -- 弹窗顶部
    local innerPad = math.floor(popW * 0.05)

    -- ====== 标题栏 ======
    local titleH = math.floor(popH * 0.08)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, popW, titleH, 8)
    nvgFillColor(vg, nvgRGBA(45, 48, 60, 255))
    nvgFill(vg)

    -- 标题文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(titleH * 0.50))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(240, 230, 200, 255))
    nvgText(vg, px + innerPad, py + titleH / 2, tData.name)

    -- 关闭按钮 X
    local closeS = math.floor(titleH * 0.6)
    local closeX = px + popW - innerPad - closeS
    local closeY = py + (titleH - closeS) / 2
    nvgFontSize(vg, math.floor(closeS * 0.8))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(180, 170, 160, 200))
    nvgText(vg, closeX + closeS / 2, closeY + closeS / 2, "X")
    L.turretDetailClose = { x = closeX, y = closeY, w = closeS, h = closeS }

    -- ====== 炮塔信息卡片 ======
    local cardY = py + titleH + 6
    local cardH = math.floor(popH * 0.22)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px + innerPad, cardY, popW - innerPad * 2, cardH, 6)
    nvgFillColor(vg, nvgRGBA(38, 42, 55, 200))
    nvgFill(vg)

    -- 左侧：大图标
    local bigIcoS = math.floor(cardH * 0.70)
    local bigIcoPad = math.floor((cardH - bigIcoS) / 2)
    local tImg = imgCache[tData.icon]
    if tImg and tImg ~= 0 then
        if not unlocked then
            nvgSave(vg)
            nvgGlobalAlpha(vg, 0.35)
            M.DrawImage(vg, tImg, px + innerPad + bigIcoPad, cardY + bigIcoPad, bigIcoS, bigIcoS)
            nvgRestore(vg)
        else
            M.DrawImage(vg, tImg, px + innerPad + bigIcoPad, cardY + bigIcoPad, bigIcoS, bigIcoS)
        end
    end

    -- 右侧：属性信息
    local infoX = px + innerPad + bigIcoPad + bigIcoS + 10
    local infoFontSize = math.floor(popW * 0.035)
    local lineH = math.floor(infoFontSize * 1.6)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, infoFontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 等级
    nvgFillColor(vg, nvgRGBA(200, 180, 100, 255))
    nvgText(vg, infoX, cardY + bigIcoPad + lineH * 0.5, "Lv." .. lv .. " / " .. tData.maxLv)

    -- 攻击力
    nvgFillColor(vg, nvgRGBA(200, 195, 180, 220))
    nvgText(vg, infoX, cardY + bigIcoPad + lineH * 1.5, "攻击: " .. tData.baseDmg)

    -- 攻速
    nvgText(vg, infoX, cardY + bigIcoPad + lineH * 2.5, "攻速: " .. string.format("%.1fs", tData.baseCD))

    -- 射程
    nvgText(vg, infoX, cardY + bigIcoPad + lineH * 3.5, "射程: " .. string.format("%.1f", tData.baseRange))

    -- 碎片进度条
    if unlocked and lv < tData.maxLv then
        local barX = px + innerPad
        local barY = cardY + cardH - math.floor(cardH * 0.18)
        local barW = popW - innerPad * 2
        local barH = math.floor(cardH * 0.12)

        -- 进度条背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBA(25, 25, 30, 200))
        nvgFill(vg)

        -- 进度条填充
        local pct = math.min(frags / math.max(needFrags, 1), 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, math.floor(barW * pct), barH, 3)
        nvgFillColor(vg, nvgRGBA(180, 145, 40, 220))
        nvgFill(vg)

        -- 碎片文字
        nvgFontSize(vg, math.floor(barH * 0.75))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgText(vg, barX + barW / 2, barY + barH / 2, "碎片 " .. frags .. "/" .. needFrags)
    end

    -- ====== 等级进度标题 ======
    local affixTitleY = cardY + cardH + 8
    local affixTitleH = math.floor(popH * 0.05)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(affixTitleH * 0.6))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 160, 255))
    if lv < tData.maxLv then
        nvgText(vg, px + innerPad, affixTitleY + affixTitleH / 2,
            "LV." .. lv .. " >> LV." .. (lv + 1))
    else
        nvgText(vg, px + innerPad, affixTitleY + affixTitleH / 2, "已满级 LV." .. lv)
    end

    -- ====== 词条列表 ======
    local affixListY = affixTitleY + affixTitleH + 4
    local affixRowH = math.floor(popH * 0.06)
    local affixFont = math.floor(affixRowH * 0.45)

    for i, aff in ipairs(affixes) do
        local ay = affixListY + (i - 1) * (affixRowH + 2)

        -- 词条行背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px + innerPad, ay, popW - innerPad * 2, affixRowH, 4)
        if aff.lv <= lv then
            -- 已解锁词条
            nvgFillColor(vg, nvgRGBA(40, 45, 55, 180))
        else
            -- 未解锁词条（灰暗）
            nvgFillColor(vg, nvgRGBA(28, 30, 38, 180))
        end
        nvgFill(vg)

        -- 等级标签
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, affixFont)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if aff.lv <= lv then
            nvgFillColor(vg, nvgRGBA(200, 180, 100, 255))
        else
            nvgFillColor(vg, nvgRGBA(100, 95, 85, 180))
        end
        nvgText(vg, px + innerPad + 8, ay + affixRowH / 2, "Lv." .. aff.lv)

        -- 词条描述
        local descX = px + innerPad + math.floor(popW * 0.16)
        if aff.lv <= lv then
            local ac = aff.color or {220, 220, 200}
            nvgFillColor(vg, nvgRGBA(ac[1], ac[2], ac[3], 240))
        else
            nvgFillColor(vg, nvgRGBA(90, 88, 80, 160))
        end
        nvgText(vg, descX, ay + affixRowH / 2, aff.desc)

        -- 已解锁的勾
        if aff.lv <= lv then
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(100, 200, 120, 220))
            nvgText(vg, px + popW - innerPad - 8, ay + affixRowH / 2, "✓")
        end
    end

    -- ====== 底部按钮区域 ======
    local btnAreaH = math.floor(popH * 0.10)
    local btnAreaY = py + popH - btnAreaH - 6
    local btnW2 = math.floor((popW - innerPad * 3) / 2)
    local btnH2 = math.floor(btnAreaH * 0.7)
    local btnY2 = btnAreaY + (btnAreaH - btnH2) / 2

    -- 检查是否已装备
    local eqSlot = nil
    for s = 1, 4 do
        if saveData.turretEquipped[s] == tId then eqSlot = s; break end
    end

    -- 升级按钮
    local upgBtnX = px + innerPad
    nvgBeginPath(vg)
    nvgRoundedRect(vg, upgBtnX, btnY2, btnW2, btnH2, 5)
    if canUpgrade then
        nvgFillColor(vg, nvgRGBA(180, 145, 40, 230))
    elseif not unlocked or lv >= tData.maxLv then
        nvgFillColor(vg, nvgRGBA(60, 58, 50, 160))
    else
        nvgFillColor(vg, nvgRGBA(80, 75, 60, 180))
    end
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(btnH2 * 0.42))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if lv >= tData.maxLv then
        nvgFillColor(vg, nvgRGBA(180, 170, 140, 150))
        nvgText(vg, upgBtnX + btnW2 / 2, btnY2 + btnH2 / 2, "已满级")
    elseif not unlocked then
        nvgFillColor(vg, nvgRGBA(140, 130, 120, 120))
        nvgText(vg, upgBtnX + btnW2 / 2, btnY2 + btnH2 / 2, "未解锁")
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, canUpgrade and 240 or 120))
        nvgText(vg, upgBtnX + btnW2 / 2, btnY2 + btnH2 / 2, "升级")
    end
    L.turretDetailUpgradeBtn = { x = upgBtnX, y = btnY2, w = btnW2, h = btnH2 }

    -- 装备/卸下按钮
    local eqBtnX = px + innerPad * 2 + btnW2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, eqBtnX, btnY2, btnW2, btnH2, 5)
    if not unlocked then
        nvgFillColor(vg, nvgRGBA(60, 58, 50, 160))
    elseif eqSlot then
        nvgFillColor(vg, nvgRGBA(140, 60, 50, 220))
    else
        nvgFillColor(vg, nvgRGBA(60, 130, 80, 220))
    end
    nvgFill(vg)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, math.floor(btnH2 * 0.42))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if not unlocked then
        nvgFillColor(vg, nvgRGBA(140, 130, 120, 120))
        nvgText(vg, eqBtnX + btnW2 / 2, btnY2 + btnH2 / 2, "未解锁")
    elseif eqSlot then
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, eqBtnX + btnW2 / 2, btnY2 + btnH2 / 2, "卸下")
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, eqBtnX + btnW2 / 2, btnY2 + btnH2 / 2, "装备")
    end
    L.turretDetailEquipBtn = { x = eqBtnX, y = btnY2, w = btnW2, h = btnH2 }

    -- 缓存弹窗区域用于点击外区域关闭
    L.turretDetailPopup = { x = popX, y = popY, w = popW, h = popH }
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
        local nodeId = "talent.node_" .. i
        cx, cy = Def.Apply(nodeId, cx, cy)
        Def.Register(nodeId, cx - hexR, cy - hexR, hexR * 2, hexR * 2 + 18, "天赋:" .. talent.name)

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

        -- 锁定节点：显示锁图标（保持宽高比）
        if not activated and not unlockable then
            local lkImg = imgCache["common_lock"]
            if lkImg and lkImg ~= 0 then
                local lkS = math.floor(drawR * 0.7)
                M.DrawImageFit(vg, lkImg, cx - lkS / 2, cy - lkS / 2, lkS, lkS)
            end
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
-- 装备：一键分解下拉菜单
------------------------------------------------------------------------
function M.DrawDecomposeDropdown(vg, W, H)
    local ddBtn = equipSubBtns[3]
    if not ddBtn then return end

    local ddW = ddBtn.w + 20
    local ddX = ddBtn.x - 10
    local ddItemH = math.floor(ddBtn.h * 1.0)
    local ddY = ddBtn.y + ddBtn.h + 4 - scrollY  -- 补偿滚动偏移
    local ddTotalH = ddItemH * #DECOMPOSE_QUALITIES
    local ddRad = 6

    -- 背景阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, ddX - 2, ddY - 2, ddW + 4, ddTotalH + 4, ddRad + 2)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, ddX, ddY, ddW, ddTotalH, ddRad)
    nvgFillColor(vg, nvgRGBA(40, 30, 20, 240))
    nvgFill(vg)

    -- 各品质选项
    for qi, q in ipairs(DECOMPOSE_QUALITIES) do
        local iy = ddY + (qi - 1) * ddItemH
        -- hover 风格分隔线
        if qi > 1 then
            nvgBeginPath(vg)
            nvgMoveTo(vg, ddX + 8, iy)
            nvgLineTo(vg, ddX + ddW - 8, iy)
            nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
        -- 品质色点
        local dotR = math.floor(ddItemH * 0.14)
        nvgBeginPath(vg)
        nvgCircle(vg, ddX + 16 + dotR, iy + ddItemH / 2, dotR)
        nvgFillColor(vg, nvgRGBA(q.color[1], q.color[2], q.color[3], 255))
        nvgFill(vg)
        -- 文字
        nvgFontSize(vg, math.floor(ddItemH * 0.44))
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(q.color[1], q.color[2], q.color[3], 255))
        nvgText(vg, ddX + 16 + dotR * 2 + 8, iy + ddItemH / 2, q.label)
    end

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, ddX, ddY, ddW, ddTotalH, ddRad)
    nvgStrokeColor(vg, nvgRGBA(180, 140, 60, 180))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

------------------------------------------------------------------------
-- 装备：批量分解确认弹窗
------------------------------------------------------------------------
function M.DrawDecomposeConfirm(vg, W, H)
    local qi = equipState.confirmQuality
    if not qi then return end
    local q = DECOMPOSE_QUALITIES[qi]

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
    nvgFill(vg)

    -- 弹窗尺寸
    local dlgW = math.floor(W * 0.7)
    local dlgH = math.floor(dlgW * 0.55)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2
    local dlgRad = 10

    -- 弹窗背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, dlgRad)
    nvgFillColor(vg, nvgRGBA(50, 35, 20, 245))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 标题：批量分解
    nvgFontSize(vg, math.floor(dlgH * 0.14))
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
    nvgText(vg, W / 2, dlgY + math.floor(dlgH * 0.08), "批量分解")

    -- 说明文字
    local descY = dlgY + math.floor(dlgH * 0.28)
    nvgFontSize(vg, math.floor(dlgH * 0.10))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(220, 210, 190, 255))
    nvgText(vg, W / 2, descY, "分解 [" .. q.label .. "] 品质的装备")

    -- 从背包实际统计可分解数量和金币
    local itemCount = 0
    local goldReward = 0
    for i = 1, #saveData.inventory do
        local inst = saveData.inventory[i]
        if inst and not inst.locked then
            local eqData = findEquipData(inst.id)
            local iq = eqData and eqData.quality or 1
            if iq <= qi then
                -- 排除已装备的
                local isEquipped = false
                for _, idx in pairs(saveData.equipped) do
                    if idx == i then isEquipped = true; break end
                end
                if not isEquipped then
                    itemCount = itemCount + 1
                    goldReward = goldReward + (MD.DECOMPOSE_GOLD[iq] or 10)
                end
            end
        end
    end
    local infoY = descY + math.floor(dlgH * 0.16)
    nvgFontSize(vg, math.floor(dlgH * 0.10))
    nvgFillColor(vg, nvgRGBA(q.color[1], q.color[2], q.color[3], 255))
    nvgText(vg, W / 2, infoY, "数量: " .. itemCount .. "  金币: +" .. goldReward)

    -- 底部按钮
    local btnH = math.floor(dlgH * 0.18)
    local btnW = math.floor(dlgW * 0.35)
    local btnY = dlgY + dlgH - btnH - math.floor(dlgH * 0.08)
    local gap = math.floor(dlgW * 0.06)
    local cancelX = dlgX + dlgW / 2 - btnW - gap / 2
    local confirmX = dlgX + dlgW / 2 + gap / 2
    local btnRad = 6

    -- 取消按钮
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cancelX, btnY, btnW, btnH, btnRad)
    nvgFillColor(vg, nvgRGBA(80, 70, 50, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(140, 120, 80, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontSize(vg, math.floor(btnH * 0.55))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 170, 255))
    nvgText(vg, cancelX + btnW / 2, btnY + btnH / 2, "取消")

    -- 确认按钮
    nvgBeginPath(vg)
    nvgRoundedRect(vg, confirmX, btnY, btnW, btnH, btnRad)
    nvgFillColor(vg, nvgRGBA(180, 100, 30, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(220, 160, 60, 200))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgFontSize(vg, math.floor(btnH * 0.55))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 240, 200, 255))
    nvgText(vg, confirmX + btnW / 2, btnY + btnH / 2, "确认")
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

--- 在 maxW x maxH 区域内保持宽高比居中绘制图片
function M.DrawImageFit(vg, img, x, y, maxW, maxH)
    if not img or img == 0 then return end
    local iw, ih = nvgImageSize(vg, img)
    if iw <= 0 or ih <= 0 then
        M.DrawImage(vg, img, x, y, maxW, maxH)
        return
    end
    local s = math.min(maxW / iw, maxH / ih)
    local dw = math.floor(iw * s)
    local dh = math.floor(ih * s)
    local dx = x + math.floor((maxW - dw) / 2)
    local dy = y + math.floor((maxH - dh) / 2)
    M.DrawImage(vg, img, dx, dy, dw, dh)
end

------------------------------------------------------------------------
-- 装备品质光效（NanoVG 动态特效）
------------------------------------------------------------------------
-- 品质光效参数：
-- glowLayers: 外发光层数(越多越亮)  breathSpeed: 呼吸频率  breathAmp: 呼吸幅度
-- sparkles: 角落闪光数  innerGlow: 是否有内发光  flameEffect: 是否有火焰流光
local QUALITY_FX = {
    [1] = { glowLayers = 0, breathSpeed = 0,   breathAmp = 0,    sparkles = 0, flameEffect = false }, -- 普通：仅细边框
    [2] = { glowLayers = 1, breathSpeed = 1.5, breathAmp = 0.2,  sparkles = 0, flameEffect = false }, -- 优质：微光
    [3] = { glowLayers = 2, breathSpeed = 2.0, breathAmp = 0.3,  sparkles = 0, flameEffect = false }, -- 稀有：光晕
    [4] = { glowLayers = 3, breathSpeed = 2.5, breathAmp = 0.35, sparkles = 4, flameEffect = false }, -- 史诗：光晕+闪光
    [5] = { glowLayers = 4, breathSpeed = 3.0, breathAmp = 0.4,  sparkles = 4, flameEffect = true  }, -- 传说：全效
    [6] = { glowLayers = 5, breathSpeed = 3.5, breathAmp = 0.45, sparkles = 6, flameEffect = true  }, -- 至臻：极致
}

--- 绘制装备品质光效（带呼吸脉冲、外发光、角落闪光、流光动效）
---@param vg NVGContextWrapper
---@param x number 格子左上角 x
---@param y number 格子左上角 y
---@param w number 格子宽
---@param h number 格子高
---@param quality number 品质等级 1-6
---@param t number 动画时间（elapsedTime）
function M.DrawQualityGlow(vg, x, y, w, h, quality, t)
    local qInfo = MD.QUALITY[quality]
    if not qInfo then return end
    local c = qInfo.color
    local fx = QUALITY_FX[quality] or QUALITY_FX[1]
    local r, g, b = c[1], c[2], c[3]

    -- 呼吸因子 (0.0 ~ 1.0 脉冲)
    local breath = 0
    if fx.breathSpeed > 0 then
        breath = (math.sin(t * fx.breathSpeed) * 0.5 + 0.5) * fx.breathAmp
    end
    local baseAlpha = 0.55 + breath

    nvgSave(vg)

    -- == 1. 外发光层（由外到内，alpha 递减，模拟柔和光晕）==
    local inset = 3  -- 整体向内收缩
    if fx.glowLayers > 0 then
        for i = fx.glowLayers, 1, -1 do
            local expand = i * 1.5 - inset            -- 每层扩展更小，整体内缩
            local layerAlpha = baseAlpha * (0.25 / i)
            local alpha255 = math.floor(layerAlpha * 255)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, x - expand, y - expand, w + expand * 2, h + expand * 2, 3)
            nvgStrokeColor(vg, nvgRGBA(r, g, b, alpha255))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end
    end

    -- == 2. 主边框（实色，呼吸透明度）==
    local borderAlpha = math.floor(baseAlpha * 255)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + inset, y + inset, w - inset * 2, h - inset * 2, 2)
    nvgStrokeColor(vg, nvgRGBA(r, g, b, borderAlpha))
    nvgStrokeWidth(vg, quality >= 4 and 1.5 or 1)
    nvgStroke(vg)

    -- (内发光已移除，避免遮挡图标)

    -- == 4. 角落闪光粒子 ==
    if fx.sparkles > 0 then
        local ci = inset  -- 闪光也内缩
        local corners = {
            { x = x + ci,     y = y + ci },         -- 左上
            { x = x + w - ci, y = y + ci },         -- 右上
            { x = x + w - ci, y = y + h - ci },     -- 右下
            { x = x + ci,     y = y + h - ci },     -- 左下
        }
        -- 沿边缘分布闪光点
        local sparklePositions = {}
        if fx.sparkles >= 4 then
            for si2 = 1, 4 do
                sparklePositions[#sparklePositions + 1] = corners[si2]
            end
        end
        if fx.sparkles >= 6 then
            -- 追加边中点
            sparklePositions[#sparklePositions + 1] = { x = x + w / 2, y = y + ci }
            sparklePositions[#sparklePositions + 1] = { x = x + w / 2, y = y + h - ci }
        end

        for si, sp in ipairs(sparklePositions) do
            -- 每个闪光有不同相位
            local phase = t * 4.0 + si * 1.57
            local sparkAlpha = math.max(0, math.sin(phase)) * baseAlpha
            if sparkAlpha > 0.05 then
                local sparkSize = 3 + sparkAlpha * 3
                local sa255 = math.floor(sparkAlpha * 255)
                -- 十字闪光
                nvgBeginPath(vg)
                nvgMoveTo(vg, sp.x - sparkSize, sp.y)
                nvgLineTo(vg, sp.x + sparkSize, sp.y)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, sa255))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgMoveTo(vg, sp.x, sp.y - sparkSize)
                nvgLineTo(vg, sp.x, sp.y + sparkSize)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, sa255))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
                -- 中心亮点
                nvgBeginPath(vg)
                nvgCircle(vg, sp.x, sp.y, 1.5)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, sa255))
                nvgFill(vg)
            end
        end
    end

    -- == 5. 流光效果（小亮点沿边框流动，不覆盖内部）==
    if fx.flameEffect then
        -- 流光沿内缩后的边框路径
        local iw, ih = w - inset * 2, h - inset * 2
        local ix, iy = x + inset, y + inset
        local perimeter = 2 * (iw + ih)
        local flowSpeed = quality >= 6 and 1.2 or 0.8

        -- 辅助函数：周长位置 → 内缩边框坐标
        local function perimToXY(p)
            p = p % perimeter
            if p < iw then
                return ix + p, iy                        -- 上边
            elseif p < iw + ih then
                return ix + iw, iy + (p - iw)            -- 右边
            elseif p < 2 * iw + ih then
                return ix + iw - (p - iw - ih), iy + ih  -- 下边
            else
                return ix, iy + ih - (p - 2 * iw - ih)   -- 左边
            end
        end

        -- 流光尾迹长度（占周长比例）
        local tailLen = perimeter * 0.25
        local headPos = (t * flowSpeed * perimeter / 4) % perimeter

        -- 绘制流光尾迹（分段描边，alpha 递减）
        local segments = 12
        local segLen = tailLen / segments
        for si = 0, segments - 1 do
            local p1 = headPos - si * segLen
            local p2 = headPos - (si + 1) * segLen
            local lx1, ly1 = perimToXY(p1)
            local lx2, ly2 = perimToXY(p2)
            local segAlpha = math.floor(baseAlpha * (1.0 - si / segments) * 200)
            if segAlpha > 0 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, lx1, ly1)
                nvgLineTo(vg, lx2, ly2)
                nvgStrokeColor(vg, nvgRGBA(255, 255, 255, segAlpha))
                nvgStrokeWidth(vg, quality >= 6 and 2.5 or 2)
                nvgStroke(vg)
            end
        end

        -- 头部亮点（小圆点）
        local hx, hy = perimToXY(headPos)
        nvgBeginPath(vg)
        nvgCircle(vg, hx, hy, 3)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(baseAlpha * 255)))
        nvgFill(vg)

        -- 第二道流光（相位偏移半圈）
        local headPos2 = (headPos + perimeter / 2) % perimeter
        for si = 0, segments - 1 do
            local p1 = headPos2 - si * segLen
            local p2 = headPos2 - (si + 1) * segLen
            local lx1, ly1 = perimToXY(p1)
            local lx2, ly2 = perimToXY(p2)
            local segAlpha = math.floor(baseAlpha * 0.6 * (1.0 - si / segments) * 180)
            if segAlpha > 0 then
                nvgBeginPath(vg)
                nvgMoveTo(vg, lx1, ly1)
                nvgLineTo(vg, lx2, ly2)
                nvgStrokeColor(vg, nvgRGBA(r, g, b, segAlpha))
                nvgStrokeWidth(vg, quality >= 6 and 2 or 1.5)
                nvgStroke(vg)
            end
        end

        local hx2, hy2 = perimToXY(headPos2)
        nvgBeginPath(vg)
        nvgCircle(vg, hx2, hy2, 2)
        nvgFillColor(vg, nvgRGBA(r, g, b, math.floor(baseAlpha * 0.7 * 255)))
        nvgFill(vg)
    end

    nvgRestore(vg)
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

    -- 装备分解弹窗/下拉菜单优先拦截
    if equipState.showConfirm then
        return M.HandleEquipConfirmClick(x, y, W, H)
    end
    if equipState.showDropdown then
        return M.HandleEquipDropdownClick(x, y, W, H)
    end

    -- 天赋弹窗优先拦截
    if talentPopup.show then
        return M.HandleTalentPopupClick(x, y, W, H)
    end

    -- 装备详情弹窗优先拦截
    if equipDetailIdx then
        local function hitBtn(b)
            return b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h
        end

        -- 关闭按钮
        if hitBtn(L.equipDetailClose) then
            equipDetailIdx = nil
            return true
        end

        -- 分解按钮
        if hitBtn(L.equipDetailDecompBtn) then
            local inst = saveData.inventory[equipDetailIdx]
            if inst then
                local eqData = findEquipData(inst.id)
                local goldGain = MD.DECOMPOSE_GOLD[eqData and eqData.quality or 1] or 10
                -- 先卸下（如果已装备）
                for slotName, idx in pairs(saveData.equipped) do
                    if idx == equipDetailIdx then
                        saveData.equipped[slotName] = nil
                        break
                    end
                end
                -- 移除背包物品
                table.remove(saveData.inventory, equipDetailIdx)
                -- 修正 equipped 中的索引（后面的元素前移了）
                local newEquipped = {}
                for slotName, idx in pairs(saveData.equipped) do
                    if idx > equipDetailIdx then
                        newEquipped[slotName] = idx - 1
                    else
                        newEquipped[slotName] = idx
                    end
                end
                saveData.equipped = newEquipped
                saveData.gold = saveData.gold + goldGain
                print("[Equip] 分解 " .. (eqData and eqData.name or inst.id) .. "，获得 " .. goldGain .. " 金币")
                equipDetailIdx = nil
            end
            return true
        end

        -- 装备/卸下按钮
        if hitBtn(L.equipDetailEquipBtn) then
            local inst = saveData.inventory[equipDetailIdx]
            if inst then
                local eqData = findEquipData(inst.id)
                if eqData then
                    local slot = eqData.slot
                    if saveData.equipped[slot] == equipDetailIdx then
                        saveData.equipped[slot] = nil
                        print("[Equip] 卸下 " .. eqData.name)
                    else
                        saveData.equipped[slot] = equipDetailIdx
                        print("[Equip] 装备 " .. eqData.name .. " → " .. slot)
                    end
                end
            end
            return true
        end

        -- 洗练按钮
        if hitBtn(L.equipDetailReforgeBtn) then
            local inst = saveData.inventory[equipDetailIdx]
            if inst then
                local eqData = findEquipData(inst.id)
                local cost = MD.REFORGE_COST[eqData and eqData.quality or 1] or 50
                if saveData.gold >= cost and inst.affixes and #inst.affixes > 0 then
                    saveData.gold = saveData.gold - cost
                    inst.affixes = MD.GenerateAffixes(eqData and eqData.quality or 1)
                    print("[Equip] 洗练 " .. (eqData and eqData.name or inst.id) .. "，花费 " .. cost)
                else
                    print("[Equip] 金币不足或无随机属性")
                end
            end
            return true
        end

        -- 点击弹窗外 → 关闭
        if L.equipDetailPopup then
            local p = L.equipDetailPopup
            if x < p.x or x > p.x + p.w or y < p.y or y > p.y + p.h then
                equipDetailIdx = nil
                return true
            end
        end

        -- 弹窗内其他区域，吞掉点击
        return true
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
        elseif activeTab == "equip" then
            return M.HandleEquipClick(x, contentClickY, W)
        end
    end

    return true
end

-- 战斗面板点击（聚焦关卡视图）
function M.HandleBattleClick(x, y, W)
    local baseY = L.contentY
    local contentH = L.contentH
    local unlocked = (battleSelectedLevel <= saveData.maxLevel)

    -- 场景区域参数（与绘制一致）
    local sceneW = W * 0.75
    local sceneH = contentH * 0.30
    local sceneCX = W / 2
    local sceneCY = baseY + contentH * 0.36

    -- "开始战斗" 按钮检测
    local chestY = sceneCY + sceneH / 2 + 24
    local chestSize = 48
    local btnW = W * 0.52
    local btnH = btnW * 0.30
    local btnX = W / 2 - btnW / 2
    local btnY = chestY + chestSize + 30

    if unlocked and x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
        print("[Meta] Start level " .. battleSelectedLevel .. ": " .. MD.LEVELS[battleSelectedLevel].name)
        return "start_level", battleSelectedLevel
    end

    -- 左右翻页箭头检测
    if #MD.LEVELS > 1 then
        local arrowSize = 28
        local arrowY = sceneCY - arrowSize / 2

        -- 左箭头
        if battleSelectedLevel > 1 then
            local laX = sceneCX - sceneW / 2 - arrowSize - 4
            if x >= laX and x <= laX + arrowSize and y >= arrowY and y <= arrowY + arrowSize then
                battleSelectedLevel = battleSelectedLevel - 1
                print("[Meta] Switch to level " .. battleSelectedLevel)
                return true
            end
        end

        -- 右箭头
        if battleSelectedLevel < saveData.maxLevel then
            local raX = sceneCX + sceneW / 2 + 4
            if x >= raX and x <= raX + arrowSize and y >= arrowY and y <= arrowY + arrowSize then
                battleSelectedLevel = battleSelectedLevel + 1
                print("[Meta] Switch to level " .. battleSelectedLevel)
                return true
            end
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
    local function hitBtn(b)
        return b and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h
    end

    -- ====== 弹窗打开时，优先处理弹窗内点击 ======
    if turretDetailId then
        local tData = findTurretData(turretDetailId)

        -- 关闭按钮
        if hitBtn(L.turretDetailClose) then
            turretDetailId = nil
            return true
        end

        -- 升级按钮
        if tData and hitBtn(L.turretDetailUpgradeBtn) then
            local unlocked = saveData.turretUnlocked[turretDetailId]
            local lv = saveData.turretLevels[turretDetailId] or 0
            local frags = saveData.turretFrags[turretDetailId] or 0
            local needFrags = math.floor(tData.fragBase * (tData.fragGrow ^ lv))
            if unlocked and lv < tData.maxLv and frags >= needFrags then
                saveData.turretFrags[turretDetailId] = frags - needFrags
                saveData.turretLevels[turretDetailId] = lv + 1
                print("[Meta] " .. tData.name .. " 升级到 Lv." .. (lv + 1))
            else
                print("[Meta] 碎片不足，需要 " .. needFrags)
            end
            return true
        end

        -- 装备/卸下按钮
        if tData and hitBtn(L.turretDetailEquipBtn) then
            local unlocked = saveData.turretUnlocked[turretDetailId]
            if unlocked then
                local equippedInSlot = nil
                for s = 1, 4 do
                    if saveData.turretEquipped[s] == turretDetailId then
                        equippedInSlot = s
                        break
                    end
                end
                if equippedInSlot then
                    saveData.turretEquipped[equippedInSlot] = nil
                    print("[Meta] 卸下 " .. tData.name .. " 从槽" .. equippedInSlot)
                else
                    local emptySlot = nil
                    for s = 1, 4 do
                        if not saveData.turretEquipped[s] then
                            emptySlot = s
                            break
                        end
                    end
                    if emptySlot then
                        saveData.turretEquipped[emptySlot] = turretDetailId
                        print("[Meta] 装备 " .. tData.name .. " 到槽" .. emptySlot)
                    else
                        local old = saveData.turretEquipped[1]
                        saveData.turretEquipped[1] = turretDetailId
                        print("[Meta] 槽位已满，替换槽1: " .. (old or "空") .. " → " .. tData.name)
                    end
                end
            end
            return true
        end

        -- 点击弹窗外区域 → 关闭
        if L.turretDetailPopup then
            local p = L.turretDetailPopup
            if x < p.x or x > p.x + p.w or y < p.y or y > p.y + p.h then
                turretDetailId = nil
                return true
            end
        end

        -- 弹窗内其他区域，吞掉点击
        return true
    end

    -- ====== 无弹窗时，检测列表行点击 ======
    if L.turretRows and L.turretGridList then
        for idx, row in ipairs(L.turretRows) do
            if x >= row.x and x <= row.x + row.w and y >= row.y and y <= row.y + row.h then
                local tData = L.turretGridList[idx]
                if tData then
                    turretDetailId = tData.id
                    print("[Meta] 打开炮塔详情: " .. tData.name)
                end
                return true
            end
        end
    end

    return true
end

-- 商城面板点击
function M.HandleShopClick(x, y, W)
    -- 检测单抽按钮
    local sb = L.shopSingleBtn
    if sb and x >= sb.x and x <= sb.x + sb.w and y >= sb.y and y <= sb.y + sb.h then
        local cost = MD.SHOP_GACHA.cost_single
        if saveData.diamond >= cost then
            saveData.diamond = saveData.diamond - cost
            print("[Meta] 单抽 x1，消耗 💎" .. cost)
        else
            print("[Meta] 钻石不足")
        end
        return true
    end

    -- 检测十连按钮
    local tb = L.shopTenBtn
    if tb and x >= tb.x and x <= tb.x + tb.w and y >= tb.y and y <= tb.y + tb.h then
        local cost = MD.SHOP_GACHA.cost_ten
        if saveData.diamond >= cost then
            saveData.diamond = saveData.diamond - cost
            print("[Meta] 十连 x10，消耗 💎" .. cost)
        else
            print("[Meta] 钻石不足")
        end
        return true
    end

    -- 检测每日商品购买按钮
    if L.shopItems then
        for i, btn in ipairs(L.shopItems) do
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                local item = MD.SHOP_DAILY[i]
                if item then
                    -- 已购买/已领取 → 不可重复操作
                    if saveData.dailyBought[item.id] then
                        print("[Meta] 今日已购买 " .. item.name)
                        return true
                    end
                    if item.currency == "free" then
                        if item.id == "daily_gold" then saveData.gold = saveData.gold + 100 end
                        saveData.dailyBought[item.id] = true
                        print("[Meta] 免费领取 " .. item.name)
                    elseif saveData.diamond >= item.price then
                        saveData.diamond = saveData.diamond - item.price
                        -- 发放对应奖励
                        if item.id == "daily_wood" then saveData.wood = saveData.wood + 1000
                        elseif item.id == "daily_stone" then saveData.stone = saveData.stone + 1000
                        end
                        saveData.dailyBought[item.id] = true
                        print("[Meta] 购买 " .. item.name .. "，消耗 💎" .. item.price)
                    else
                        print("[Meta] 钻石不足")
                    end
                end
                return true
            end
        end
    end

    -- 检测固定商店购买按钮
    if L.shopFixedItems then
        for i, btn in ipairs(L.shopFixedItems) do
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                local item = MD.SHOP_FIXED[i]
                if item and saveData.diamond >= item.price then
                    saveData.diamond = saveData.diamond - item.price
                    -- 发放金币奖励
                    if item.id == "fixed_gold_s" then saveData.gold = saveData.gold + 200
                    elseif item.id == "fixed_gold_m" then saveData.gold = saveData.gold + 800
                    end
                    print("[Meta] 购买 " .. item.name .. "，消耗 💎" .. item.price)
                elseif item then
                    print("[Meta] 钻石不足")
                end
                return true
            end
        end
    end

    return true
end

------------------------------------------------------------------------
-- 装备面板点击
------------------------------------------------------------------------
function M.HandleEquipClick(x, y, W)
    -- 检测上方装备槽点击（已装备的物品）
    if L.equipSlotCells then
        for _, cell in pairs(L.equipSlotCells) do
            if x >= cell.x and x <= cell.x + cell.w and y >= cell.y and y <= cell.y + cell.h then
                local inst = saveData.inventory[cell.invIdx]
                if inst then
                    equipDetailIdx = cell.invIdx
                    print("[Equip] 打开已装备详情: " .. inst.id .. " (槽位:" .. cell.slotId .. ")")
                end
                return true
            end
        end
    end

    -- 检测分类标签页点击
    if L.equipCatBtns then
        for _, btn in pairs(L.equipCatBtns) do
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                if equipState.catIndex ~= btn.idx then
                    equipState.catIndex = btn.idx
                    equipState.showDropdown = false
                    equipState.showConfirm = false
                    equipDetailIdx = nil
                    charDetailId = nil
                    print("[Equip] 切换标签页: " .. btn.idx)
                end
                return true
            end
        end
    end

    -- 检测角色详情弹窗点击（弹窗打开时优先处理）
    if charDetailId and L.charDetailPopup then
        local pp = L.charDetailPopup
        -- 关闭按钮
        if L.charDetailClose then
            local cb = L.charDetailClose
            if x >= cb.x and x <= cb.x + cb.w and y >= cb.y and y <= cb.y + cb.h then
                charDetailId = nil
                print("[Char] 关闭角色弹窗")
                return true
            end
        end
        -- "使用"按钮
        if L.charDetailUseBtn and not L.charDetailUseBtn.disabled then
            local ub = L.charDetailUseBtn
            if x >= ub.x and x <= ub.x + ub.w and y >= ub.y and y <= ub.y + ub.h then
                saveData.activeChar = charDetailId
                print("[Char] 使用角色: " .. charDetailId)
                return true
            end
        end
        -- "升星"按钮
        if L.charDetailStarBtn and L.charDetailStarBtn.canUpgrade then
            local sb = L.charDetailStarBtn
            if x >= sb.x and x <= sb.x + sb.w and y >= sb.y and y <= sb.y + sb.h then
                local curStar = (saveData.charStars and saveData.charStars[charDetailId]) or 1
                local cost = MD.STAR_FRAG_COST[curStar + 1] or 999
                local frags = (saveData.charFragments and saveData.charFragments[charDetailId]) or 0
                if curStar < MD.MAX_STAR and frags >= cost then
                    saveData.charStars[charDetailId] = curStar + 1
                    saveData.charFragments[charDetailId] = frags - cost
                    print("[Char] 升星: " .. charDetailId .. " → " .. (curStar + 1) .. "星")
                end
                return true
            end
        end
        -- 点击弹窗内部：吞掉事件
        if x >= pp.x and x <= pp.x + pp.w and y >= pp.y and y <= pp.y + pp.h then
            return true
        end
        -- 点击弹窗外部：关闭弹窗
        charDetailId = nil
        print("[Char] 点击外部关闭角色弹窗")
        return true
    end

    -- 检测角色卡片点击（打开弹窗）
    if equipState.catIndex == 1 and L.charGridCells then
        for _, cell in pairs(L.charGridCells) do
            if x >= cell.x and x <= cell.x + cell.w and y >= cell.y and y <= cell.y + cell.h then
                charDetailId = cell.charId
                print("[Char] 打开角色详情: " .. cell.charId)
                return true
            end
        end
    end

    -- 检测背包格子点击
    if L.equipGridCells then
        for _, cell in pairs(L.equipGridCells) do
            if x >= cell.x and x <= cell.x + cell.w and y >= cell.y and y <= cell.y + cell.h then
                local inst = saveData.inventory[cell.invIdx]
                if inst then
                    if equipState.isLocked then
                        -- 锁定模式：切换单件装备锁定状态
                        inst.locked = not inst.locked
                        local eqData = findEquipData(inst.id)
                        print("[Equip] " .. (inst.locked and "锁定" or "解锁") .. " " .. (eqData and eqData.name or inst.id))
                    else
                        -- 正常模式：打开详情弹窗
                        equipDetailIdx = cell.invIdx
                        print("[Equip] 打开装备详情: " .. inst.id)
                    end
                end
                return true
            end
        end
    end

    -- 检测副框内3个功能按钮（仅装备子标签页）
    if equipState.catIndex ~= 2 then
        -- 非装备子标签页，关闭残留下拉并跳过
        equipState.showDropdown = false
    end
    for _, btn in ipairs(equipSubBtns) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if btn.id == "sort" then
                equipState.sortMode = equipState.sortMode % 3 + 1
                print("[Equip] Sort mode: " .. SORT_LABELS[equipState.sortMode])
            elseif btn.id == "lock" then
                equipState.isLocked = not equipState.isLocked
                print("[Equip] Lock: " .. tostring(equipState.isLocked))
            elseif btn.id == "decompose" then
                equipState.showDropdown = not equipState.showDropdown
                print("[Equip] Dropdown: " .. tostring(equipState.showDropdown))
            end
            return true
        end
    end
    -- 点击其他区域关闭下拉
    if equipState.showDropdown then
        equipState.showDropdown = false
        return true
    end
    return true
end

-- 一键分解下拉菜单点击
function M.HandleEquipDropdownClick(x, y, W, H)
    M.CalcLayout(W, H)
    -- 计算下拉菜单位置（与渲染一致）
    local ddBtn = equipSubBtns[3]  -- 一键分解按钮
    if ddBtn then
        local ddW = ddBtn.w + 20
        local ddX = ddBtn.x - 10
        local ddItemH = math.floor(ddBtn.h * 1.0)
        local ddY = ddBtn.y + ddBtn.h + 4 - scrollY  -- 补偿滚动偏移

        for qi, q in ipairs(DECOMPOSE_QUALITIES) do
            local iy = ddY + (qi - 1) * ddItemH
            if x >= ddX and x <= ddX + ddW and y >= iy and y <= iy + ddItemH then
                equipState.confirmQuality = qi
                equipState.showDropdown = false
                equipState.showConfirm = true
                print("[Equip] Decompose quality: " .. q.label)
                return true
            end
        end
    end
    -- 点击下拉外部，关闭
    equipState.showDropdown = false
    return true
end

-- 批量分解确认弹窗点击
function M.HandleEquipConfirmClick(x, y, W, H)
    -- 弹窗居中，与渲染一致
    local dlgW = math.floor(W * 0.7)
    local dlgH = math.floor(dlgW * 0.55)
    local dlgX = (W - dlgW) / 2
    local dlgY = (H - dlgH) / 2

    -- 按钮区域（底部）
    local btnH = math.floor(dlgH * 0.18)
    local btnW = math.floor(dlgW * 0.35)
    local btnY = dlgY + dlgH - btnH - math.floor(dlgH * 0.08)
    local gap = math.floor(dlgW * 0.06)
    local cancelX = dlgX + dlgW / 2 - btnW - gap / 2
    local confirmX = dlgX + dlgW / 2 + gap / 2

    -- 取消
    if x >= cancelX and x <= cancelX + btnW and y >= btnY and y <= btnY + btnH then
        equipState.showConfirm = false
        equipState.confirmQuality = nil
        print("[Equip] Decompose cancelled")
        return true
    end
    -- 确认
    if x >= confirmX and x <= confirmX + btnW and y >= btnY and y <= btnY + btnH then
        local qi = equipState.confirmQuality
        local qLabel = DECOMPOSE_QUALITIES[qi].label
        -- 实际分解逻辑：分解 <= qi 品质的未锁定、未装备物品
        local totalGold = 0
        local decompCount = 0
        -- 从后往前遍历避免索引偏移问题
        for i = #saveData.inventory, 1, -1 do
            local inst = saveData.inventory[i]
            if inst and not inst.locked then
                local eqData = findEquipData(inst.id)
                local quality = eqData and eqData.quality or 1
                -- 检查品质是否在分解范围内
                if quality <= qi then
                    -- 检查是否已装备
                    local isEquipped = false
                    for _, idx in pairs(saveData.equipped) do
                        if idx == i then isEquipped = true; break end
                    end
                    if not isEquipped then
                        local goldGain = MD.DECOMPOSE_GOLD[quality] or 10
                        totalGold = totalGold + goldGain
                        decompCount = decompCount + 1
                        table.remove(saveData.inventory, i)
                        -- 修正 equipped 索引
                        local newEquipped = {}
                        for slotName, idx in pairs(saveData.equipped) do
                            if idx > i then
                                newEquipped[slotName] = idx - 1
                            else
                                newEquipped[slotName] = idx
                            end
                        end
                        saveData.equipped = newEquipped
                    end
                end
            end
        end
        saveData.gold = saveData.gold + totalGold
        print("[Equip] 一键分解 " .. qLabel .. ": 分解" .. decompCount .. "件，获得" .. totalGold .. "金币")
        equipState.showConfirm = false
        equipState.confirmQuality = nil
        return true
    end
    -- 点击弹窗外部关闭
    if x < dlgX or x > dlgX + dlgW or y < dlgY or y > dlgY + dlgH then
        equipState.showConfirm = false
        equipState.confirmQuality = nil
        return true
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

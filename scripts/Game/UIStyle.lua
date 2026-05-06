-- Game/UIStyle.lua - 金属质感 UI 绘制库（蒸汽朋克风格）
local US = {}

------------------------------------------------------------------------
-- 调色板
------------------------------------------------------------------------
US.PAL = {
    -- 金属框架
    frameBg1     = {35, 38, 45},      -- 框架背景上（深灰蓝）
    frameBg2     = {28, 30, 36},      -- 框架背景下
    frameBorder  = {58, 52, 44},      -- 外边框（暗褐）
    frameHilight = {85, 78, 65},      -- 内高光
    frameInner   = {22, 24, 30},      -- 内凹区域

    -- 铆钉
    rivetDark    = {40, 38, 34},
    rivetLight   = {90, 85, 75},

    -- 按钮
    btnNormal1   = {50, 48, 44},
    btnNormal2   = {38, 36, 33},
    btnHover1    = {62, 58, 52},
    btnHover2    = {48, 44, 40},
    btnPress1    = {30, 28, 26},
    btnPress2    = {40, 38, 35},
    btnDisabled1 = {35, 34, 32},
    btnDisabled2 = {30, 29, 27},
    btnBorder    = {65, 60, 50},
    btnBorderHi  = {95, 88, 72},

    -- 资源项
    itemBg       = {30, 32, 38},
    itemBorder   = {55, 50, 42},
    itemHover    = {70, 65, 55},

    -- 加号按钮
    plusColor     = {220, 185, 55},
    plusBg        = {45, 42, 35},

    -- 文字
    textWhite    = {235, 235, 228},
    textRed      = {220, 60, 50},
    textGrey     = {130, 130, 125},
    textShadow   = {0, 0, 0},

    -- 设置面板
    panelBg1     = {38, 40, 48},
    panelBg2     = {28, 30, 36},
    panelBorder  = {60, 55, 46},
    panelDivider = {50, 48, 44},
    panelItemHover = {50, 52, 60},
}

------------------------------------------------------------------------
-- 辅助
------------------------------------------------------------------------
local function rgba(c, a)
    return nvgRGBA(c[1], c[2], c[3], a or 255)
end

------------------------------------------------------------------------
-- 铆钉
------------------------------------------------------------------------
function US.drawRivet(vg, x, y, r)
    r = r or 3
    -- 外圈暗色
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFillColor(vg, rgba(US.PAL.rivetDark))
    nvgFill(vg)
    -- 内圈渐变
    local rp = nvgRadialGradient(vg, x - r * 0.3, y - r * 0.3, r * 0.1, r * 0.8,
        rgba(US.PAL.rivetLight, 120), rgba(US.PAL.rivetDark, 200))
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r - 0.5)
    nvgFillPaint(vg, rp)
    nvgFill(vg)
    -- 高光点
    nvgBeginPath(vg)
    nvgCircle(vg, x - r * 0.25, y - r * 0.25, r * 0.3)
    nvgFillColor(vg, rgba(US.PAL.rivetLight, 80))
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 金属框架背景
------------------------------------------------------------------------
function US.drawMetalFrame(vg, x, y, w, h, opts)
    opts = opts or {}
    local cr = opts.cornerRadius or 8
    local rivetSize = opts.rivetSize or 3
    local showRivets = opts.showRivets ~= false
    local pad = opts.padding or 4

    -- 外边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgStrokeColor(vg, rgba(US.PAL.frameBorder))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 背景渐变
    local bgP = nvgLinearGradient(vg, x, y, x, y + h,
        rgba(US.PAL.frameBg1), rgba(US.PAL.frameBg2))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + 1, y + 1, w - 2, h - 2, cr - 1)
    nvgFillPaint(vg, bgP)
    nvgFill(vg)

    -- 顶部高光线
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + cr, y + 1.5)
    nvgLineTo(vg, x + w - cr, y + 1.5)
    nvgStrokeColor(vg, rgba(US.PAL.frameHilight, 50))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 内凹边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + pad, y + pad, w - pad * 2, h - pad * 2, cr - 2)
    nvgStrokeColor(vg, rgba(US.PAL.frameInner, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 四角铆钉
    if showRivets then
        local rx = cr + 1
        local ry = cr + 1
        US.drawRivet(vg, x + rx, y + ry, rivetSize)
        US.drawRivet(vg, x + w - rx, y + ry, rivetSize)
        US.drawRivet(vg, x + rx, y + h - ry, rivetSize)
        US.drawRivet(vg, x + w - rx, y + h - ry, rivetSize)
    end
end

------------------------------------------------------------------------
-- 金属按钮
------------------------------------------------------------------------
-- state: "normal", "hover", "pressed", "disabled"
function US.drawMetalButton(vg, x, y, w, h, state)
    state = state or "normal"
    local cr = 4

    local bg1, bg2, borderC
    if state == "hover" then
        bg1 = US.PAL.btnHover1
        bg2 = US.PAL.btnHover2
        borderC = US.PAL.btnBorderHi
    elseif state == "pressed" then
        bg1 = US.PAL.btnPress1
        bg2 = US.PAL.btnPress2
        borderC = US.PAL.btnBorder
    elseif state == "disabled" then
        bg1 = US.PAL.btnDisabled1
        bg2 = US.PAL.btnDisabled2
        borderC = US.PAL.rivetDark
    else
        bg1 = US.PAL.btnNormal1
        bg2 = US.PAL.btnNormal2
        borderC = US.PAL.btnBorder
    end

    -- 外边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgStrokeColor(vg, rgba(borderC))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 背景渐变
    local bgP = nvgLinearGradient(vg, x, y, x, y + h, rgba(bg1), rgba(bg2))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + 0.5, y + 0.5, w - 1, h - 1, cr - 0.5)
    nvgFillPaint(vg, bgP)
    nvgFill(vg)

    -- 顶部高光
    if state ~= "pressed" and state ~= "disabled" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + cr, y + 1.5)
        nvgLineTo(vg, x + w - cr, y + 1.5)
        nvgStrokeColor(vg, rgba(US.PAL.frameHilight, 40))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
    end

    -- 内阴影（按下时）
    if state == "pressed" then
        local sh = nvgLinearGradient(vg, x, y, x, y + h * 0.4,
            rgba({0, 0, 0}, 50), rgba({0, 0, 0}, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + 1, y + 1, w - 2, h * 0.4, cr - 1)
        nvgFillPaint(vg, sh)
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 加号按钮（小型金色+号）
------------------------------------------------------------------------
function US.drawPlusButton(vg, cx, cy, size, state)
    size = size or 16
    local half = size / 2
    US.drawMetalButton(vg, cx - half, cy - half, size, size, state or "normal")

    -- 绘制 + 号
    local plusC = (state == "disabled") and US.PAL.textGrey or US.PAL.plusColor
    local thick = 1.8
    local len = size * 0.38
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - len, cy)
    nvgLineTo(vg, cx + len, cy)
    nvgMoveTo(vg, cx, cy - len)
    nvgLineTo(vg, cx, cy + len)
    nvgStrokeColor(vg, rgba(plusC))
    nvgStrokeWidth(vg, thick)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
end

------------------------------------------------------------------------
-- 齿轮图标（程序化绘制）
------------------------------------------------------------------------
function US.drawGearIcon(vg, cx, cy, radius, color)
    color = color or US.PAL.textGrey
    local r = radius
    local teeth = 8
    local innerR = r * 0.55
    local toothDepth = r * 0.25
    local toothWidth = math.pi * 2 / teeth * 0.35

    nvgBeginPath(vg)
    for i = 0, teeth - 1 do
        local angle = i * math.pi * 2 / teeth
        -- 齿顶
        local a1 = angle - toothWidth
        local a2 = angle + toothWidth
        local outerR = r
        nvgLineTo(vg, cx + math.cos(a1) * (outerR - toothDepth), cy + math.sin(a1) * (outerR - toothDepth))
        nvgLineTo(vg, cx + math.cos(a1) * outerR, cy + math.sin(a1) * outerR)
        nvgLineTo(vg, cx + math.cos(a2) * outerR, cy + math.sin(a2) * outerR)
        nvgLineTo(vg, cx + math.cos(a2) * (outerR - toothDepth), cy + math.sin(a2) * (outerR - toothDepth))
    end
    nvgClosePath(vg)
    nvgFillColor(vg, rgba(color, 200))
    nvgFill(vg)

    -- 中心圆孔
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, innerR)
    nvgFillColor(vg, rgba(US.PAL.frameBg2))
    nvgFill(vg)
    -- 内圆环
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, innerR * 0.65)
    nvgFillColor(vg, rgba(color, 150))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, innerR * 0.35)
    nvgFillColor(vg, rgba(US.PAL.frameBg2))
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 资源项绘制
------------------------------------------------------------------------
-- state: "normal", "hover", "insufficient", "disabled"
function US.drawResourceItem(vg, x, y, w, h, icon, count, accentColor, state, drawSpriteFunc)
    state = state or "normal"
    local cr = 5

    -- 背景
    local bgA = (state == "hover") and 50 or 30
    local borderC = (state == "hover") and US.PAL.itemHover or US.PAL.itemBorder
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgFillColor(vg, rgba(US.PAL.itemBg, bgA))
    nvgFill(vg)
    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgStrokeColor(vg, rgba(borderC, 100))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
    -- 底部微光
    if state ~= "disabled" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + cr, y + h - 0.5)
        nvgLineTo(vg, x + w - cr, y + h - 0.5)
        nvgStrokeColor(vg, rgba(accentColor or US.PAL.frameHilight, 35))
        nvgStrokeWidth(vg, 0.8)
        nvgStroke(vg)
    end

    -- 图标
    local iconSz = h * 0.7
    local iconCx = x + 6 + iconSz / 2
    local iconCy = y + h / 2
    if icon and icon ~= 0 and drawSpriteFunc then
        local iconAlpha = (state == "disabled") and 0.35 or 1.0
        drawSpriteFunc(vg, icon, iconCx, iconCy, iconSz, iconSz, iconAlpha)
    end

    -- 数量文字
    local textX = x + 6 + iconSz + 4
    local textY = y + h / 2
    local textC
    local numStr
    if state == "disabled" then
        numStr = "--"
        textC = US.PAL.textGrey
    elseif state == "insufficient" or count == 0 then
        numStr = tostring(count)
        textC = US.PAL.textRed
    else
        numStr = tostring(count)
        textC = US.PAL.textWhite
    end

    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    -- 文字阴影
    nvgFillColor(vg, rgba(US.PAL.textShadow, 100))
    nvgText(vg, textX + 0.8, textY + 0.8, numStr, nil)
    -- 文字
    nvgFillColor(vg, rgba(textC))
    nvgText(vg, textX, textY, numStr, nil)
end

------------------------------------------------------------------------
-- 设置面板
------------------------------------------------------------------------
function US.drawSettingsPanel(vg, x, y, w, items, hoverIdx)
    local itemH = 40
    local h = #items * itemH + 16  -- 上下 padding 各 8
    local cr = 10

    -- 阴影
    local shP = nvgRadialGradient(vg, x + w / 2, y + h / 2, w * 0.3, w * 0.8,
        rgba({0, 0, 0}, 80), rgba({0, 0, 0}, 0))
    nvgBeginPath(vg)
    nvgRect(vg, x - 20, y - 20, w + 40, h + 40)
    nvgFillPaint(vg, shP)
    nvgFill(vg)

    -- 面板框架
    US.drawMetalFrame(vg, x, y, w, h, {
        cornerRadius = cr,
        rivetSize = 2.5,
        padding = 3,
    })

    -- 菜单项
    nvgFontFace(vg, "sans")
    for i, item in ipairs(items) do
        local iy = y + 8 + (i - 1) * itemH
        local iw = w - 16
        local ix = x + 8

        -- 悬停高亮
        if hoverIdx == i then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix, iy, iw, itemH - 2, 5)
            nvgFillColor(vg, rgba(US.PAL.panelItemHover, 80))
            nvgFill(vg)
        end

        -- 分隔线
        if i < #items then
            nvgBeginPath(vg)
            nvgMoveTo(vg, ix + 4, iy + itemH - 1)
            nvgLineTo(vg, ix + iw - 4, iy + itemH - 1)
            nvgStrokeColor(vg, rgba(US.PAL.panelDivider, 60))
            nvgStrokeWidth(vg, 0.8)
            nvgStroke(vg)
        end

        -- 图标 emoji + 文字
        local textCy = iy + itemH / 2

        -- 左侧图标文字
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, rgba(US.PAL.textGrey))
        nvgText(vg, ix + 8, textCy, item.icon or "", nil)

        -- 标签
        nvgFontSize(vg, 14)
        nvgFillColor(vg, rgba(US.PAL.textWhite))
        nvgText(vg, ix + 32, textCy, item.label or "", nil)

        -- 右侧值（如果有）
        if item.value then
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 13)
            nvgFillColor(vg, rgba(US.PAL.textGrey))
            nvgText(vg, ix + iw - 8, textCy, item.value .. " >", nil)
        end

        -- 开关（如果有）
        if item.toggle ~= nil then
            local swX = ix + iw - 36
            local swY = textCy - 8
            local swW = 28
            local swH = 16
            US.drawToggle(vg, swX, swY, swW, swH, item.toggle)
        end
    end

    return h  -- 返回面板高度
end

------------------------------------------------------------------------
-- 开关
------------------------------------------------------------------------
function US.drawToggle(vg, x, y, w, h, isOn)
    local cr = h / 2
    local knobR = h / 2 - 2

    -- 背景槽
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    if isOn then
        nvgFillColor(vg, rgba({80, 160, 80}, 200))
    else
        nvgFillColor(vg, rgba({50, 48, 45}, 200))
    end
    nvgFill(vg)
    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, cr)
    nvgStrokeColor(vg, rgba(US.PAL.btnBorder, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 圆形旋钮
    local knobX
    if isOn then
        knobX = x + w - cr
    else
        knobX = x + cr
    end
    local knobY = y + h / 2
    -- 金属质感旋钮
    local kp = nvgRadialGradient(vg, knobX - 1, knobY - 1, 1, knobR,
        rgba({200, 195, 185}), rgba({120, 115, 105}))
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, knobY, knobR)
    nvgFillPaint(vg, kp)
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 完整 HUD 绘制（替换原始版本）
------------------------------------------------------------------------
function US.drawHUD(vg, G, drawSpriteFunc)
    local W = G.screenW
    local hudH = G.hudH
    local cy = hudH / 2

    -- 金属框架背景（全宽）
    US.drawMetalFrame(vg, 0, 0, W, hudH, {
        cornerRadius = 0,     -- 顶部不圆角
        rivetSize = 2.5,
        showRivets = false,   -- 顶栏不显示铆钉
        padding = 3,
    })

    nvgFontFace(vg, "sans")

    -- 资源项
    local items = {
        { img = G.hudIconGold,  count = G.gold,          ac = {220, 185, 55}  },
        { img = G.hudIconWood,  count = G.totalRes.wood,  ac = {160, 120, 70}  },
        { img = G.hudIconStone, count = G.totalRes.stone, ac = {140, 145, 155} },
        { img = G.hudIconGem,   count = G.totalRes.ore,   ac = {110, 140, 210} },
    }

    local itemH = 30
    local gap = 3
    local plusBtnSz = 16
    local startX = 8

    local cx = startX
    for _, item in ipairs(items) do
        local numStr = tostring(item.count)
        local textW = #numStr * 8.5 + 4
        local iconSz = itemH * 0.7
        local itemW = 8 + iconSz + 4 + textW + 6

        local iy = cy - itemH / 2

        -- 资源状态
        local state = "normal"
        if item.count == 0 then state = "insufficient" end

        US.drawResourceItem(vg, cx, iy, itemW, itemH, item.img, item.count, item.ac, state, drawSpriteFunc)

        -- 加号按钮
        local plusCx = cx + itemW + plusBtnSz / 2 + 2
        US.drawPlusButton(vg, plusCx, cy, plusBtnSz, "normal")

        cx = cx + itemW + plusBtnSz + gap + 4
    end

    -- 右侧齿轮按钮
    local gearBtnSz = 32
    local gearX = W - gearBtnSz - 6
    local gearY = cy - gearBtnSz / 2
    local gearState = G.showSettings and "pressed" or "normal"
    US.drawMetalButton(vg, gearX, gearY, gearBtnSz, gearBtnSz, gearState)
    US.drawGearIcon(vg, gearX + gearBtnSz / 2, cy, gearBtnSz * 0.35, {160, 158, 150})

    -- 保存齿轮按钮位置用于点击检测
    G.gearBtnRect = { x = gearX, y = gearY, w = gearBtnSz, h = gearBtnSz }
end

------------------------------------------------------------------------
-- 设置菜单绘制
------------------------------------------------------------------------
function US.drawSettingsMenu(vg, G)
    if not G.showSettings then return end

    local W = G.screenW
    local H = G.screenH

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgFill(vg)

    nvgFontFace(vg, "sans")

    -- 面板位置（右上角，齿轮下方）
    local panelW = 180
    local panelX = W - panelW - 10
    local panelY = G.hudH + 6

    local menuItems = {
        { icon = "\xE2\x9A\x99", label = "设置",   header = true },
        { icon = "\xF0\x9F\x94\x8A", label = "音效",   toggle = G.sfxEnabled ~= false },
        { icon = "\xF0\x9F\x8E\xB5", label = "音乐",   toggle = G.musicEnabled ~= false },
        { icon = "\xF0\x9F\x93\xB3", label = "震动",   toggle = G.vibrationEnabled ~= false },
        { icon = "\xF0\x9F\x8C\x90", label = "语言",   value = "简体中文" },
    }

    local h = US.drawSettingsPanel(vg, panelX, panelY, panelW, menuItems, G.settingsHoverIdx)

    -- 保存面板区域用于点击检测
    G.settingsPanelRect = { x = panelX, y = panelY, w = panelW, h = h }
    G.settingsMenuItems = menuItems
end

return US

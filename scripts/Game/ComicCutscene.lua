-- ComicCutscene.lua - 开幕漫画剧情系统
-- 两页漫画，每页4格，点击逐格显示，带入场动画

local CC = {}

------------------------------------------------------------------------
-- 配置
------------------------------------------------------------------------
local BG_IMG_PATH  = "image/通用背景.png"      -- 背景图片
local SKIP_IMG_PATH = "image/Layer_0 (10).png"  -- 跳过按钮图片
local GAP       = 5                          -- 格间距
local MARGIN_X  = 12                         -- 左右边距
local CORNER_R  = 6                          -- 面板圆角半径

-- 入场动画时长（秒）
local ANIM_DUR  = 0.4

-- 每页的漫画格布局定义
-- imgRatio = 图片宽高比 (w/h)，用于按原始比例计算面板高度
local PAGE_LAYOUTS = {
    {
        { type = "full",  img = "image/开幕剧情/1-1.png", anim = "fadeSlideDown", imgRatio = 827/384  },
        { type = "left",  img = "image/开幕剧情/1-2.png", anim = "slideLeft",     imgRatio = 385/427  },
        { type = "right", img = "image/开幕剧情/1-3.png", anim = "slideRight",    imgRatio = 431/427  },
        { type = "full",  img = "image/开幕剧情/1-4.png", anim = "fadeSlideUp",   imgRatio = 827/587  },
    },
    {
        { type = "full",  img = "image/开幕剧情/2-1.png", anim = "fadeSlideDown", imgRatio = 843/441  },
        { type = "left",  img = "image/开幕剧情/2-2.png", anim = "slideLeft",     imgRatio = 421/422  },
        { type = "right", img = "image/开幕剧情/2-3.png", anim = "slideRight",    imgRatio = 413/422  },
        { type = "full",  img = "image/开幕剧情/2-4.png", anim = "fadeSlideUp",   imgRatio = 844/587  },
    },
}

------------------------------------------------------------------------
-- 状态
------------------------------------------------------------------------
local state = {
    active    = false,
    page      = 1,
    revealed  = 0,
    animT     = {},
    imgHandles = {},
    done      = false,
    onFinish  = nil,
    hintBlink = 0,
}

------------------------------------------------------------------------
-- 缓动
------------------------------------------------------------------------
local function easeOutCubic(t)
    t = t - 1
    return t * t * t + 1
end

------------------------------------------------------------------------
-- 初始化 / 销毁
------------------------------------------------------------------------

function CC.Start(vg, onFinish)
    state.active   = true
    state.page     = 1
    state.revealed = 0
    state.done     = false
    state.onFinish = onFinish
    state.hintBlink = 0

    -- 加载背景图片
    state.bgHandle = nvgCreateImage(vg, BG_IMG_PATH, 0)
    if state.bgHandle == 0 then
        print("[Comic] WARNING: Failed to load background " .. BG_IMG_PATH)
    end

    -- 加载跳过按钮图片
    state.skipHandle = nvgCreateImage(vg, SKIP_IMG_PATH, 0)
    if state.skipHandle == 0 then
        print("[Comic] WARNING: Failed to load skip button " .. SKIP_IMG_PATH)
    end

    state.imgHandles = {}
    state.animT = {}
    for pi, page in ipairs(PAGE_LAYOUTS) do
        state.imgHandles[pi] = {}
        state.animT[pi] = {}
        for ci, cell in ipairs(page) do
            state.imgHandles[pi][ci] = nvgCreateImage(vg, cell.img, 0)
            state.animT[pi][ci] = 0
            if state.imgHandles[pi][ci] == 0 then
                print("[Comic] WARNING: Failed to load " .. cell.img)
            end
        end
    end
    print("[Comic] Started, pages=" .. #PAGE_LAYOUTS)
end

function CC.IsActive()
    return state.active
end

function CC.Close()
    state.active = false
    state.done = true
    if state.onFinish then
        state.onFinish()
    end
end

------------------------------------------------------------------------
-- 输入
------------------------------------------------------------------------

function CC.HandleClick(x, y, DW, DH)
    if not state.active then return end

    -- 跳过按钮点击区域（左上角，与 Draw 中绘制位置对齐，加宽松区域）
    local skipH = 30
    local skipW = 78
    local skipX = 12
    local skipY = 46
    -- 扩大点击区域（上下左右各扩展 10px）
    if x >= skipX - 10 and x <= skipX + skipW + 10
       and y >= skipY - 10 and y <= skipY + skipH + 10 then
        CC.Close()
        return
    end

    -- 点击推进
    local page = PAGE_LAYOUTS[state.page]
    if state.revealed < #page then
        state.revealed = state.revealed + 1
        state.animT[state.page][state.revealed] = 0
    else
        if state.page < #PAGE_LAYOUTS then
            state.page = state.page + 1
            state.revealed = 0
        else
            CC.Close()
        end
    end
end

------------------------------------------------------------------------
-- 更新
------------------------------------------------------------------------

function CC.Update(dt)
    if not state.active then return end
    state.hintBlink = state.hintBlink + dt

    local pi = state.page
    for ci = 1, state.revealed do
        if state.animT[pi][ci] < 1.0 then
            state.animT[pi][ci] = math.min(1.0, state.animT[pi][ci] + dt / ANIM_DUR)
        end
    end
end

------------------------------------------------------------------------
-- 布局计算 — 按图片原始比例，不拉伸不裁切
------------------------------------------------------------------------

local function calcPanelRects(DW, DH, page)
    local contentW = DW - MARGIN_X * 2

    -- 按图片原始宽高比计算每行自然高度
    local nat1 = contentW / page[1].imgRatio

    local halfW  = math.floor((contentW - GAP) / 2)
    local rightW = contentW - halfW - GAP
    local nat2L  = halfW  / page[2].imgRatio
    local nat2R  = rightW / page[3].imgRatio
    local nat2   = math.max(nat2L, nat2R)

    local nat3 = contentW / page[4].imgRatio

    local natTotal = nat1 + nat2 + nat3 + GAP * 2

    -- 如果自然总高超过可用空间，等比缩小；否则不拉伸
    local maxH = DH - 80 -- 上下各留40给按钮/提示
    local scale = 1.0
    if natTotal > maxH then
        scale = maxH / natTotal
    end

    local h1 = math.floor(nat1 * scale)
    local h2 = math.floor(nat2 * scale)
    local h3 = math.floor(nat3 * scale)
    local totalUsed = h1 + h2 + h3 + GAP * 2

    -- 垂直居中
    local startY = math.floor((DH - totalUsed) / 2)

    local rects = {}
    local curY = startY

    rects[1] = { x = MARGIN_X, y = curY, w = contentW, h = h1 }
    curY = curY + h1 + GAP

    rects[2] = { x = MARGIN_X, y = curY, w = halfW, h = h2 }
    rects[3] = { x = MARGIN_X + halfW + GAP, y = curY, w = rightW, h = h2 }
    curY = curY + h2 + GAP

    rects[4] = { x = MARGIN_X, y = curY, w = contentW, h = h3 }

    return rects, startY, totalUsed
end

------------------------------------------------------------------------
-- 绘制辅助
------------------------------------------------------------------------

local function drawRoundedPanel(vg, x, y, w, h, r)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, r)
end

--- 图片 cover 模式填充面板，居中裁切溢出
local function drawImageCover(vg, handle, x, y, w, h, alpha)
    if handle == 0 then return end
    local imgW, imgH = nvgImageSize(vg, handle)
    if imgW == 0 or imgH == 0 then return end

    local scaleX = w / imgW
    local scaleY = h / imgH
    local s = math.max(scaleX, scaleY)
    local drawW = imgW * s
    local drawH = imgH * s
    local ox = x + (w - drawW) / 2
    local oy = y + (h - drawH) / 2

    local paint = nvgImagePattern(vg, ox, oy, drawW, drawH, 0, handle, alpha / 255)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 主绘制
------------------------------------------------------------------------

function CC.Draw(vg, DW, DH)
    if not state.active then return end

    -- 1. 背景图片（cover模式铺满）
    if state.bgHandle and state.bgHandle ~= 0 then
        local bgW, bgH = nvgImageSize(vg, state.bgHandle)
        if bgW > 0 and bgH > 0 then
            local sx = DW / bgW
            local sy = DH / bgH
            local s = math.max(sx, sy)
            local dw = bgW * s
            local dh = bgH * s
            local ox = (DW - dw) / 2
            local oy = (DH - dh) / 2
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, DW, DH)
            local bgPaint = nvgImagePattern(vg, ox, oy, dw, dh, 0, state.bgHandle, 1.0)
            nvgFillPaint(vg, bgPaint)
            nvgFill(vg)
        end
    else
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, DW, DH)
        nvgFillColor(vg, nvgRGBA(190, 205, 215, 255))
        nvgFill(vg)
    end

    -- 2. 漫画格
    local page = PAGE_LAYOUTS[state.page]
    local rects, startY, totalUsed = calcPanelRects(DW, DH, page)

    for ci = 1, #page do
        local r = rects[ci]
        local cell = page[ci]
        local handle = state.imgHandles[state.page][ci]
        local revealed = ci <= state.revealed
        local t = state.animT[state.page][ci]

        if revealed then
            local eased = easeOutCubic(t)
            local offsetX, offsetY = 0, 0
            local alpha = math.floor(eased * 255)

            if cell.anim == "fadeSlideDown" then
                offsetY = (1 - eased) * -20
            elseif cell.anim == "fadeSlideUp" then
                offsetY = (1 - eased) * 20
            elseif cell.anim == "slideLeft" then
                offsetX = (1 - eased) * -36
            elseif cell.anim == "slideRight" then
                offsetX = (1 - eased) * 36
            end

            nvgSave(vg)
            nvgIntersectScissor(vg, r.x - 1, r.y - 1, r.w + 2, r.h + 2)

            -- 图片（cover模式填满面板）
            drawRoundedPanel(vg, r.x + offsetX, r.y + offsetY, r.w, r.h, CORNER_R)
            drawImageCover(vg, handle, r.x + offsetX, r.y + offsetY, r.w, r.h, alpha)

            -- 细边框
            drawRoundedPanel(vg, r.x + offsetX, r.y + offsetY, r.w, r.h, CORNER_R)
            nvgStrokeColor(vg, nvgRGBA(40, 45, 50, math.floor(alpha * 0.6)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgRestore(vg)
        else
            -- 未揭示占位（仅淡色填充，无边框）
            drawRoundedPanel(vg, r.x, r.y, r.w, r.h, CORNER_R)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 15))
            nvgFill(vg)
        end
    end

    -- 3. 跳过按钮（左上角，图片）
    local skipH = 30
    local skipW = 78
    if state.skipHandle and state.skipHandle ~= 0 then
        local sW, sH = nvgImageSize(vg, state.skipHandle)
        if sW > 0 and sH > 0 then
            skipH = 30
            skipW = math.floor(skipH * (sW / sH))
        end
    end
    local skipX = 12
    local skipY = 46

    if state.skipHandle and state.skipHandle ~= 0 then
        local paint = nvgImagePattern(vg, skipX, skipY, skipW, skipH, 0, state.skipHandle, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, skipX, skipY, skipW, skipH, 6)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- fallback：程序化绘制
        nvgBeginPath(vg)
        nvgRoundedRect(vg, skipX, skipY, skipW, skipH, skipH / 2)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 210))
        nvgText(vg, skipX + skipW / 2, skipY + skipH / 2, "▶▶ 跳过")
    end

    -- 4. 底部提示文字（常驻）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 220, 180))
    nvgText(vg, DW / 2, DH - 16, "点击屏幕继续")
end

return CC

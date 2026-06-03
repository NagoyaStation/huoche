-- Game/Renderer.lua - NanoVG 渲染：末世：我开火车送快递
local C = require "Game.Config"
local Ent = require "Game.Entities"
local Turret = require "Game.Turret"
local R = {}

------------------------------------------------------------------------
-- 模块级复用表/常量（避免每帧分配）
------------------------------------------------------------------------
local _pts = {}           -- DrawPath 采样点复用表
local _ptCount = 0        -- 当前采样点数量
local STROKE_DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } -- 描边偏移方向
local _imgSizeCache = {}  -- nvgImageSize 缓存: img handle → {w, h}

--- 缓存版 nvgImageSize：图片尺寸加载后不变，避免每帧 C 调用
local function imgSize(vg, img)
    local c = _imgSizeCache[img]
    if c then return c[1], c[2] end
    local w, h = nvgImageSize(vg, img)
    _imgSizeCache[img] = { w, h }
    return w, h
end

------------------------------------------------------------------------
-- 工具
------------------------------------------------------------------------
local function clr(c, a)
    return nvgRGBA(c[1], c[2], c[3], a or c[4] or 255)
end

-- 绘制精灵图（居中绘制，支持缩放和透明度）
local function drawSprite(vg, img, cx, cy, drawW, drawH, alpha)
    if not img or img == 0 then return end
    alpha = alpha or 1.0
    local dx = cx - drawW / 2
    local dy = cy - drawH / 2
    local paint = nvgImagePattern(vg, dx, dy, drawW, drawH, 0, img, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, dx, dy, drawW, drawH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)
end

------------------------------------------------------------------------
-- 布局计算
------------------------------------------------------------------------
function R.CalcLayout(G, W, H)
    G.screenW = W
    G.screenH = H

    -- UI 缩放因子：以短边 390 为基准（竖屏设计宽度），横屏时短边是高度
    local shortDim = math.min(W, H)
    local uiScale = shortDim / 390
    G.uiScale = math.max(1.0, math.min(uiScale, 1.5))

    G.hudH = math.floor(48 * G.uiScale)
    G.renderTopY = 0   -- 游戏场景渲染起点（从屏幕顶部开始，HUD覆盖在上面）

    -- 列车位置 (屏幕上方，蒸汽机车)
    G.cartCenterX = W / 2
    G.cartTopY = G.hudH + 4
    G.cartW = 103
    G.cartH = 247
    G.cartBottomY = G.cartTopY + G.cartH

    -- 铁轨参数
    G.railSep = 40  -- 两根钢轨之间的距离

    -- 车厢精灵边界（用于碰撞检测，与 DrawTrain 中的绘制参数保持一致）
    local cScale = 0.78
    G.carriageW = (G.cartH + 20) * 207 / 308 * cScale
    G.carriageH = (G.cartH + 20) * 277 / 308 * cScale
    G.carriageTopY = G.cartTopY + 27 - G.carriageH  -- 车厢顶部Y

    -- 提交方块位置 (列车正下方)
    G.submitBox = {
        x = W / 2,
        y = G.cartBottomY + C.SUBMIT_BOX_H / 2 + 8,
    }
end

------------------------------------------------------------------------
-- 1. 绘制雪地背景 (暗黑写实：灰烬污雪 + 浓雾 + 暗沉)
------------------------------------------------------------------------
function R.DrawSnow(vg, G)
    local W, H = G.screenW, G.screenH
    local gameH = H - G.renderTopY
    local scrollY = G.scrollY or 0
    local bgImg = G.bgGroundImg

    -- 像素风雪地纹理平铺（随滚动移动，覆盖全屏含HUD区域）
    if bgImg and bgImg ~= 0 then
        local tileSize = 512  -- 纹理原始尺寸
        local offsetY = scrollY % tileSize
        -- 用 ImagePattern 平铺纹理（从y=0开始，去掉HUD区黑底）
        local bgPaint = nvgImagePattern(vg, 0, -offsetY, tileSize, tileSize, 0, bgImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillPaint(vg, bgPaint)
        nvgFill(vg)
    end

    -- 浓雾层 (上方远处的厚重雾气)
    do
        local fogGrad = nvgLinearGradient(vg, 0, G.renderTopY, 0, G.renderTopY + gameH * 0.45,
            nvgRGBA(90, 95, 105, 85),
            nvgRGBA(90, 95, 105, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, G.renderTopY + gameH * 0.45)
        nvgFillPaint(vg, fogGrad)
        nvgFill(vg)
    end

    -- 暗角 (左右两侧压暗，覆盖全屏)
    local vigW = W * 0.25
    do
        local vigL = nvgLinearGradient(vg, 0, 0, vigW, 0,
            nvgRGBA(10, 12, 18, 60), nvgRGBA(10, 12, 18, 0))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, vigW, H)
        nvgFillPaint(vg, vigL)
        nvgFill(vg)
    end
    do
        local vigR = nvgLinearGradient(vg, W - vigW, 0, W, 0,
            nvgRGBA(10, 12, 18, 0), nvgRGBA(10, 12, 18, 60))
        nvgBeginPath(vg)
        nvgRect(vg, W - vigW, 0, vigW, H)
        nvgFillPaint(vg, vigR)
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 2. 绘制道路 (暗黑写实：龟裂冻土 + 血渍暗斑 + 深沟)
------------------------------------------------------------------------
function R.DrawPath(vg, G)
    local W, H = G.screenW, G.screenH
    local scrollY = G.scrollY or 0

    local step = 4
    local pR, pG, pB = C.CLR.path[1], C.CLR.path[2], C.CLR.path[3]
    local pdR, pdG, pdB = C.CLR.path_dark[1], C.CLR.path_dark[2], C.CLR.path_dark[3]

    -- 预计算采样点（复用模块级表，避免每帧分配）
    local pts = _pts
    local n = 0
    for sy = G.renderTopY, H + step, step do
        local worldY = sy + scrollY
        local pathL, pathR, cx = Ent.GetPathBounds(W, worldY)
        n = n + 1
        local p = pts[n]
        if p then
            p.y, p.l, p.r, p.cx = sy, pathL, pathR, cx
        else
            pts[n] = { y = sy, l = pathL, r = pathR, cx = cx }
        end
    end
    -- 清除多余旧数据
    for i = n + 1, _ptCount do pts[i] = nil end
    _ptCount = n
    if n < 2 then return end

    -- 辅助：用采样点画闭合多边形（左偏移、右偏移）
    local function polyFill(lOff, rOff, paint)
        nvgBeginPath(vg)
        nvgMoveTo(vg, pts[1].l + lOff, pts[1].y)
        for i = 2, n do nvgLineTo(vg, pts[i].l + lOff, pts[i].y) end
        for i = n, 1, -1 do nvgLineTo(vg, pts[i].r + rOff, pts[i].y) end
        nvgClosePath(vg)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
    local function polyFillColor(lOff, rOff, color)
        nvgBeginPath(vg)
        nvgMoveTo(vg, pts[1].l + lOff, pts[1].y)
        for i = 2, n do nvgLineTo(vg, pts[i].l + lOff, pts[i].y) end
        for i = n, 1, -1 do nvgLineTo(vg, pts[i].r + rOff, pts[i].y) end
        nvgClosePath(vg)
        nvgFillColor(vg, color)
        nvgFill(vg)
    end

    -- 渐变锚点固定在屏幕中心，不随滚动变化（路径宽度恒定）
    local halfW = W * C.PATH_WIDTH_RATIO / 2
    local cx0 = W / 2          -- 固定中心
    local fl = cx0 - halfW     -- 固定左边界
    local fr = cx0 + halfW     -- 固定右边界

    -- 主路面 → 连续多边形
    do
        local roadPaint = nvgLinearGradient(vg, fl, 0, fr, 0,
            nvgRGBA(pR + 8, pG + 6, pB + 4, 255),
            nvgRGBA(pR - 6, pG - 8, pB - 5, 255))
        polyFill(0, 0, roadPaint)
    end

    -- 边缘过渡
    local edgeW = 4
    do -- 左边缘
        local leftGrad = nvgLinearGradient(vg, fl - edgeW, 0, fl, 0,
            nvgRGBA(230, 233, 238, 0), nvgRGBA(pdR, pdG, pdB, 200))
        nvgBeginPath(vg)
        nvgMoveTo(vg, pts[1].l - edgeW, pts[1].y)
        for i = 2, n do nvgLineTo(vg, pts[i].l - edgeW, pts[i].y) end
        for i = n, 1, -1 do nvgLineTo(vg, pts[i].l, pts[i].y) end
        nvgClosePath(vg)
        nvgFillPaint(vg, leftGrad)
        nvgFill(vg)
    end
    do -- 右边缘
        local rightGrad = nvgLinearGradient(vg, fr, 0, fr + edgeW, 0,
            nvgRGBA(pdR, pdG, pdB, 200), nvgRGBA(230, 233, 238, 0))
        nvgBeginPath(vg)
        nvgMoveTo(vg, pts[1].r, pts[1].y)
        for i = 2, n do nvgLineTo(vg, pts[i].r, pts[i].y) end
        for i = n, 1, -1 do nvgLineTo(vg, pts[i].r + edgeW, pts[i].y) end
        nvgClosePath(vg)
        nvgFillPaint(vg, rightGrad)
        nvgFill(vg)
    end

    -- 道路内侧深沟阴影 → 连续多边形
    do -- 左侧凹陷阴影
        local lShadow = nvgLinearGradient(vg, fl, 0, fl + 6, 0,
            nvgRGBA(15, 12, 8, 50), nvgRGBA(15, 12, 8, 0))
        polyFill(0, -halfW * 2 + 6, lShadow)
    end
    do -- 右侧凹陷阴影
        local rShadow = nvgLinearGradient(vg, fr - 6, 0, fr, 0,
            nvgRGBA(15, 12, 8, 0), nvgRGBA(15, 12, 8, 50))
        nvgBeginPath(vg)
        nvgMoveTo(vg, pts[1].r - 6, pts[1].y)
        for i = 2, n do nvgLineTo(vg, pts[i].r - 6, pts[i].y) end
        for i = n, 1, -1 do nvgLineTo(vg, pts[i].r, pts[i].y) end
        nvgClosePath(vg)
        nvgFillPaint(vg, rShadow)
        nvgFill(vg)
    end
    do -- 中心微亮高光条
        local hw = halfW * 0.12
        local cHighlight = nvgLinearGradient(vg, cx0 - hw, 0, cx0 + hw, 0,
            nvgRGBA(pR + 18, pG + 15, pB + 10, 0),
            nvgRGBA(pR + 18, pG + 15, pB + 10, 18))
        nvgBeginPath(vg)
        nvgMoveTo(vg, pts[1].cx - hw, pts[1].y)
        for i = 2, n do nvgLineTo(vg, pts[i].cx - hw, pts[i].y) end
        for i = n, 1, -1 do nvgLineTo(vg, pts[i].cx + hw, pts[i].y) end
        nvgClosePath(vg)
        nvgFillPaint(vg, cHighlight)
        nvgFill(vg)
    end

    -- 龟裂纹路 (世界坐标固定，随滚动移动)
    local crackSpacing = 120  -- 每120像素世界距离一组裂缝
    local worldTop = scrollY + G.renderTopY
    local worldBot = scrollY + H
    local crackStart = math.floor(worldTop / crackSpacing) * crackSpacing
    for wy = crackStart, worldBot + crackSpacing, crackSpacing do
        local sy = wy - scrollY  -- 世界→屏幕
        if sy > G.renderTopY - 30 and sy < H + 30 then
            local idx = math.abs(math.floor(wy / crackSpacing)) % 97  -- 稳定伪随机索引
            local pathL, pathR = Ent.GetPathBounds(W, wy)
            local pw = math.max(1, pathR - pathL)
            local cx1 = pathL + ((idx * 41 + 7) % math.floor(pw))
            local offA = idx % 6
            local offB = idx % 8
            local offC = idx % 4
            local offD = idx % 10
            -- 裂缝暗线
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx1, sy)
            nvgLineTo(vg, cx1 + 8 + offA, sy + 12 + offB)
            nvgLineTo(vg, cx1 + 4 - offC, sy + 22 + offD)
            nvgStrokeColor(vg, nvgRGBA(pdR, pdG, pdB, 55))
            nvgStrokeWidth(vg, 1.0)
            nvgStroke(vg)
            -- 裂缝亮边
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx1 + 1, sy)
            nvgLineTo(vg, cx1 + 9 + offA, sy + 12 + offB)
            nvgStrokeColor(vg, nvgRGBA(pR + 20, pG + 18, pB + 12, 20))
            nvgStrokeWidth(vg, 0.6)
            nvgStroke(vg)
        end
    end

    -- 血渍/锈斑 (世界坐标固定)
    local bloodSpacing = 160
    local bloodStart = math.floor(worldTop / bloodSpacing) * bloodSpacing
    for wy = bloodStart, worldBot + bloodSpacing, bloodSpacing do
        local sy = wy - scrollY
        if sy > G.renderTopY - 20 and sy < H + 20 then
            local idx = math.abs(math.floor(wy / bloodSpacing)) % 89
            local pathL, pathR = Ent.GetPathBounds(W, wy)
            local pw = math.max(1, pathR - pathL)
            local px = pathL + ((idx * 53 + 11) % math.floor(pw))
            local bRx = 5 + idx % 4
            local bRy = 3 + idx % 3
            local bAlpha = 25 + (idx % 3) * 10
            do
                local bloodPaint = nvgRadialGradient(vg, px, sy, bRx * 0.2, bRx,
                    nvgRGBA(80, 25, 18, bAlpha),
                    nvgRGBA(80, 25, 18, 0))
                nvgBeginPath(vg)
                nvgEllipse(vg, px, sy, bRx * 1.3, bRy * 1.2)
                nvgFillPaint(vg, bloodPaint)
                nvgFill(vg)
            end
        end
    end

    -- 碎石亮面杂斑 (世界坐标固定)
    local stoneSpacing = 90
    local stoneStart = math.floor(worldTop / stoneSpacing) * stoneSpacing
    for wy = stoneStart, worldBot + stoneSpacing, stoneSpacing do
        local sy = wy - scrollY
        if sy > G.renderTopY - 15 and sy < H + 15 then
            local idx = math.abs(math.floor(wy / stoneSpacing)) % 73
            local pathL, pathR = Ent.GetPathBounds(W, wy)
            local pw = math.max(1, pathR - pathL)
            local px = pathL + ((idx * 53 + 7) % math.floor(pw))
            local sRx = 6 + idx % 4
            local sRy = 3 + idx % 2
            do
                local stonePaint = nvgRadialGradient(vg, px, sy, sRx * 0.15, sRx,
                    nvgRGBA(C.CLR.path_light[1], C.CLR.path_light[2], C.CLR.path_light[3], 30),
                    nvgRGBA(C.CLR.path_light[1], C.CLR.path_light[2], C.CLR.path_light[3], 0))
                nvgBeginPath(vg)
                nvgEllipse(vg, px, sy, sRx * 1.2, sRy * 1.1)
                nvgFillPaint(vg, stonePaint)
                nvgFill(vg)
            end
        end
    end

    -- 路面纵深渐变 (远处暗 → 近处微亮)
    do
        local roadDepth = nvgLinearGradient(vg, 0, G.renderTopY, 0, H,
            nvgRGBA(15, 12, 8, 45),
            nvgRGBA(60, 55, 45, 10))
        nvgBeginPath(vg)
        nvgRect(vg, 0, G.renderTopY, W, H - G.renderTopY)
        nvgFillPaint(vg, roadDepth)
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 2.5 绘制铁轨 (枕木 + 钢轨)
------------------------------------------------------------------------
function R.DrawRailway(vg, G)
    local W, H = G.screenW, G.screenH
    local cx = G.cartCenterX
    local scrollY = G.scrollY or 0

    local img = G.railwayImg
    if not img or img == 0 then return end

    -- 获取铁轨图片原始尺寸
    local imgW, imgH = imgSize(vg, img)
    if imgW == 0 or imgH == 0 then return end

    -- 铁轨显示宽度 = railSep + 一些余量，与道路宽度协调
    local railSep = G.railSep or 40
    local displayW = railSep + 24
    -- 按宽度等比计算显示高度
    local displayH = displayW * (imgH / imgW)

    -- 用 scrollY 控制铁轨滚动（向下平铺）
    local offsetY = scrollY % displayH

    -- 从屏幕顶部往下平铺铁轨图片
    local startY = G.renderTopY - offsetY
    for ty = startY, H, displayH do
        local paint = nvgImagePattern(vg, cx - displayW / 2, ty, displayW, displayH, 0, img, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, cx - displayW / 2, ty, displayW, displayH)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 3. 绘制装饰物 (枯树、雪堆、残骸)
------------------------------------------------------------------------
------------------------------------------------------------------------
-- 地面血迹（僵尸死亡后残留）
------------------------------------------------------------------------
function R.DrawBloodStains(vg, G)
    local stains = G.bloodStains
    if not stains or #stains == 0 then return end

    for _, b in ipairs(stains) do
        if b.y < -30 or b.y > G.screenH + 30 then goto cont_bs end

        -- 淡出：最后2秒开始渐隐
        local alpha = 1.0
        if b.life < 2.0 then
            alpha = math.max(0, b.life / 2.0)
        end
        local a = math.floor(alpha * 160)

        nvgSave(vg)
        nvgTranslate(vg, b.x, b.y)
        nvgRotate(vg, b.angle)

        -- 主血迹（不规则椭圆，绿色僵尸血）
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, b.size, b.size * 0.6)
        nvgFillColor(vg, nvgRGBA(20, 100, 15, a))
        nvgFill(vg)

        -- 深色内核
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, b.size * 0.5, b.size * 0.3)
        nvgFillColor(vg, nvgRGBA(10, 70, 5, a))
        nvgFill(vg)

        -- 溅射斑点
        for _, sp in ipairs(b.splats) do
            nvgBeginPath(vg)
            nvgCircle(vg, sp.dx, sp.dy, sp.sz)
            nvgFillColor(vg, nvgRGBA(25, 110, 20, math.floor(alpha * 120)))
            nvgFill(vg)
        end

        nvgRestore(vg)
        ::cont_bs::
    end
end

function R.DrawDecorations(vg, G)
    -- 裁剪区域：限制在设计分辨率内，不让装饰物溢出到黑边
    nvgSave(vg)
    nvgScissor(vg, 0, 0, G.screenW, G.screenH)

    for _, d in ipairs(G.decorations) do
        if d.y < G.renderTopY - 80 or d.y > G.screenH + 80 then goto continue_deco end
        local img = d.img
        if not img or img == 0 then goto continue_deco end

        -- 获取图片原始尺寸，保持宽高比
        local imgW, imgH = imgSize(vg, img)
        if imgW <= 0 or imgH <= 0 then goto continue_deco end

        -- 装饰物使用固定缩放（不随滚动变化，避免看起来在"动"）
        local baseH
        if d.cat == "pole" then
            baseH = 70
        elseif d.cat == "small" then
            baseH = 35
        else
            baseH = 80
        end
        local drawH = baseH
        local drawW = drawH * (imgW / imgH)

        -- 翻转支持：左侧默认朝右，右侧翻转朝左
        local flipX = (d.side == 2)
        if d.flip then flipX = not flipX end

        if flipX then
            nvgSave(vg)
            nvgTranslate(vg, d.x, d.y)
            nvgScale(vg, -1, 1)
            drawSprite(vg, img, 0, 0, drawW, drawH, 0.9)
            nvgRestore(vg)
        else
            drawSprite(vg, img, d.x, d.y, drawW, drawH, 0.9)
        end

        ::continue_deco::
    end

    nvgRestore(vg)  -- 移除裁剪
end

------------------------------------------------------------------------
-- 4. 绘制蒸汽机车 (俯视图，车头/烟囱朝下=前进方向)
------------------------------------------------------------------------
function R.DrawTrain(vg, G)
    local cx = G.cartCenterX
    local topY = G.cartTopY
    local cw = G.cartW
    local ch = G.cartH
    local halfW = cw / 2
    local t = G.gameTime or 0
    local bottomY = topY + ch

    -- === 车影 (径向渐变柔阴影) ===
    do
        local shPaint = nvgRadialGradient(vg, cx + 4, topY + ch / 2 + 8, ch * 0.15, ch / 2 + 12,
            nvgRGBA(5, 8, 3, 65), nvgRGBA(5, 8, 3, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, cx + 4, topY + ch / 2 + 8, halfW + 14, ch / 2 + 12)
        nvgFillPaint(vg, shPaint)
        nvgFill(vg)
    end

    -- 闪红参数
    local hitFlash = (G.trainHitFlash or 0) > 0
    local hitShakeX = 0
    if hitFlash then
        hitShakeX = math.sin(t * 50) * 2.0
    end

    -- === 车厢精灵 (先绘制，图层在火车下方) ===
    local carriageImg = G.trainCarriageImg
    if carriageImg and carriageImg ~= 0 then
        -- 车厢原图 207x277，比火车略小
        local cScale = 0.78
        local cDrawH = (ch + 20) * 277 / 308 * cScale
        local cDrawW = (ch + 20) * 207 / 308 * cScale

        -- 同步震动效果（稍微延迟相位）
        local cVibeX = math.sin(t * 25 + 0.3) * 0.35
        local cVibeY = math.sin(t * 30 + 0.3) * 0.25

        -- 紧接火车顶部上方（火车朝下行驶，后方=屏幕上方）
        local cDrawX = cx - cDrawW / 2 + cVibeX + hitShakeX
        local cDrawY = topY - 5 - cDrawH + 32 + cVibeY

        -- 车厢闪红：三步法（擦除→红色填充→降透明度重绘）
        if hitFlash then
            local ts = math.min(1.0, G.trainHitFlash / 0.25)
            -- Step1: 用精灵alpha擦除该区域，打出精灵形状的"透明洞"
            nvgGlobalCompositeBlendFunc(vg, NVG_ZERO, NVG_ONE_MINUS_SRC_ALPHA)
            local cErase = nvgImagePattern(vg, cDrawX, cDrawY, cDrawW, cDrawH, 0, carriageImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, cDrawX, cDrawY, cDrawW, cDrawH)
            nvgFillPaint(vg, cErase)
            nvgFill(vg)
            -- Step2: 红色只填充透明洞（1-dst_alpha仅在洞内>0）
            nvgGlobalCompositeBlendFunc(vg, NVG_ONE_MINUS_DST_ALPHA, NVG_ONE)
            nvgBeginPath(vg)
            nvgRect(vg, cDrawX, cDrawY, cDrawW, cDrawH)
            nvgFillColor(vg, nvgRGBA(255, 50, 25, 255))
            nvgFill(vg)
            -- Step3: 恢复正常混合，降透明度重绘让红色透出
            nvgGlobalCompositeOperation(vg, NVG_SOURCE_OVER)
            local cBlendA = 1.0 - ts * 0.55
            local cPaint = nvgImagePattern(vg, cDrawX, cDrawY, cDrawW, cDrawH, 0, carriageImg, cBlendA)
            nvgBeginPath(vg)
            nvgRect(vg, cDrawX, cDrawY, cDrawW, cDrawH)
            nvgFillPaint(vg, cPaint)
            nvgFill(vg)
        else
            local cPaint = nvgImagePattern(vg, cDrawX, cDrawY, cDrawW, cDrawH, 0, carriageImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, cDrawX, cDrawY, cDrawW, cDrawH)
            nvgFillPaint(vg, cPaint)
            nvgFill(vg)
        end
    end

    -- === 火车精灵 ===
    local trainImg = G.trainImg
    if trainImg and trainImg ~= 0 then
        -- 保持原图比例 (382x1380)
        local drawH = ch + 20
        local drawW = drawH * 382 / 1380

        -- 引擎震动效果 (微小抖动，模拟蒸汽机运转)
        local vibeX = math.sin(t * 25) * 0.4
        local vibeY = math.sin(t * 30) * 0.3

        local drawX = cx - drawW / 2 + vibeX + hitShakeX
        local drawY = topY - 5 + vibeY

        -- 火车闪红：三步法（擦除→红色填充→降透明度重绘）
        if hitFlash then
            local ts = math.min(1.0, G.trainHitFlash / 0.25)
            -- Step1: 用精灵alpha擦除该区域
            nvgGlobalCompositeBlendFunc(vg, NVG_ZERO, NVG_ONE_MINUS_SRC_ALPHA)
            local tErase = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, trainImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawW, drawH)
            nvgFillPaint(vg, tErase)
            nvgFill(vg)
            -- Step2: 红色填充透明洞
            nvgGlobalCompositeBlendFunc(vg, NVG_ONE_MINUS_DST_ALPHA, NVG_ONE)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawW, drawH)
            nvgFillColor(vg, nvgRGBA(255, 50, 25, 255))
            nvgFill(vg)
            -- Step3: 恢复正常混合，降透明度重绘
            nvgGlobalCompositeOperation(vg, NVG_SOURCE_OVER)
            local tBlendA = 1.0 - ts * 0.55
            local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, trainImg, tBlendA)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawW, drawH)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, trainImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawW, drawH)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        end
    end

    -- === 沙袋射击掩体 (绘制在火车精灵上方，作为上车射击点) ===
    local sandbagImg = G.trainSandbagImg
    if sandbagImg and sandbagImg ~= 0 then
        -- 沙袋原图 925x589，等比缩放到适合火车的尺寸
        local sbDrawW = 52
        local sbDrawH = sbDrawW * 589 / 925

        -- 同步火车震动
        local sbVibeX = math.sin(t * 25) * 0.4
        local sbVibeY = math.sin(t * 30) * 0.3

        -- 放在上车射击点位置（cartBottomY - 125 = 玩家上车锁定Y）
        local sbCenterY = bottomY - 125
        local sbDrawX = cx - sbDrawW / 2 + sbVibeX + hitShakeX
        local sbDrawY = sbCenterY - sbDrawH / 2 + sbVibeY

        -- 沙袋闪红：同火车三步法
        if hitFlash then
            local ts = math.min(1.0, G.trainHitFlash / 0.25)
            nvgGlobalCompositeBlendFunc(vg, NVG_ZERO, NVG_ONE_MINUS_SRC_ALPHA)
            local sbErase = nvgImagePattern(vg, sbDrawX, sbDrawY, sbDrawW, sbDrawH, 0, sandbagImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, sbDrawX, sbDrawY, sbDrawW, sbDrawH)
            nvgFillPaint(vg, sbErase)
            nvgFill(vg)
            nvgGlobalCompositeBlendFunc(vg, NVG_ONE_MINUS_DST_ALPHA, NVG_ONE)
            nvgBeginPath(vg)
            nvgRect(vg, sbDrawX, sbDrawY, sbDrawW, sbDrawH)
            nvgFillColor(vg, nvgRGBA(255, 50, 25, 255))
            nvgFill(vg)
            nvgGlobalCompositeOperation(vg, NVG_SOURCE_OVER)
            local sbBlendA = 1.0 - ts * 0.55
            local sbPaint = nvgImagePattern(vg, sbDrawX, sbDrawY, sbDrawW, sbDrawH, 0, sandbagImg, sbBlendA)
            nvgBeginPath(vg)
            nvgRect(vg, sbDrawX, sbDrawY, sbDrawW, sbDrawH)
            nvgFillPaint(vg, sbPaint)
            nvgFill(vg)
        else
            local sbPaint = nvgImagePattern(vg, sbDrawX, sbDrawY, sbDrawW, sbDrawH, 0, sandbagImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, sbDrawX, sbDrawY, sbDrawW, sbDrawH)
            nvgFillPaint(vg, sbPaint)
            nvgFill(vg)
        end
    end

    -- === 程序化烟雾粒子 (血量低于50%时出现) ===
    if (G.trainHP or 0) < (G.trainMaxHP or 1) * 0.5 then
        -- 烟囱位置：火车中部偏下（图片约70%高度处的圆形烟囱口）
        local chimneyX = cx
        local chimneyY = topY + ch * 0.72

        -- 12个烟雾粒子，错开相位持续循环
        local smokeCount = 12
        for i = 1, smokeCount do
            local phase = (i - 1) / smokeCount
            local life = (t * 0.5 + phase) % 1.0

            -- 向上飘散（火车向下行驶，烟雾向后=向上拖尾），参数按ch等比缩放
            local windX = math.sin(t * 0.8 + i * 1.7) * (ch * 0.02 + life * ch * 0.09)
            local trailY = life * ch * 0.43
            local px = chimneyX + windX
            local py = chimneyY - trailY

            -- 大小：出生小 → 中间大 → 消散缩小
            local sizeCurve = math.sin(life * 3.14159)
            local radius = ch * 0.03 + sizeCurve * ch * 0.12

            -- 透明度：淡入 → 浓 → 消散
            local alpha
            if life < 0.15 then
                alpha = math.floor(life / 0.15 * 180)
            else
                alpha = math.floor((1 - life) / 0.85 * 180)
            end
            if alpha < 2 then alpha = 0 end

            if alpha > 0 then
                local smokePaint = nvgRadialGradient(vg, px, py, radius * 0.15, radius,
                    nvgRGBA(25, 22, 20, alpha),
                    nvgRGBA(35, 32, 28, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, px, py, radius)
                nvgFillPaint(vg, smokePaint)
                nvgFill(vg)
            end
        end
    end

    -- 血条已拆分到 DrawTrainHP，在玩家之后绘制以确保最高层级
end

------------------------------------------------------------------------
-- 4b. 绘制列车血条 (独立函数，在玩家之后调用以保证最高显示层级)
------------------------------------------------------------------------
function R.DrawTrainHP(vg, G)
    if not (G.trainHP and G.trainMaxHP and G.trainMaxHP > 0) then return end

    local cx = G.cartCenterX
    local barW = 85
    local barH = 25
    local bx = cx - barW / 2
    local by = G.hudH + 14
    local ratio = math.max(0, G.trainHP / G.trainMaxHP)

    -- 血量填充背景（暗底）
    local pad = 3
    nvgBeginPath(vg)
    nvgRoundedRect(vg, bx + pad, by + pad, barW - pad * 2, barH - pad * 2, 2)
    nvgFillColor(vg, nvgRGBA(15, 10, 10, 200))
    nvgFill(vg)

    -- 血量颜色 (绿→黄→红)
    local hr, hg, hb
    if ratio > 0.5 then
        hr = math.floor(80 + (1 - ratio) * 300)
        hg = 200
        hb = 60
    else
        hr = 220
        hg = math.floor(ratio * 2 * 200)
        hb = 50
    end

    -- 血量填充（渐变）
    local fillW = (barW - pad * 2) * ratio
    if fillW > 1 then
        local hpGrad = nvgLinearGradient(vg, bx + pad, by, bx + pad, by + barH,
            nvgRGBA(hr + 40, hg + 30, hb + 20, 255),
            nvgRGBA(hr - 20, hg - 20, hb, 230))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + pad, by + pad, fillW, barH - pad * 2, 2)
        nvgFillPaint(vg, hpGrad)
        nvgFill(vg)

        -- 高光条
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx + pad + 1, by + pad + 1, fillW - 2, (barH - pad * 2) * 0.35, 1)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 50))
        nvgFill(vg)
    end

    -- 血条边框图片（拉伸覆盖在血条上方）
    local frameImg = G.hpBarFrame
    if frameImg and frameImg ~= 0 then
        local fPadX = 30   -- 边框左右延伸（装饰部分）
        local fPadY = 33   -- 边框上下延伸
        local fX = bx - fPadX
        local fY = by - fPadY
        local fW = barW + fPadX * 2
        local fH = barH + fPadY * 2
        local fPaint = nvgImagePattern(vg, fX, fY, fW, fH, 0, frameImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, fX, fY, fW, fH)
        nvgFillPaint(vg, fPaint)
        nvgFill(vg)
    end

    -- HP数字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 9)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgText(vg, cx + 0.5, by + barH / 2 + 0.5, math.floor(G.trainHP) .. "/" .. math.floor(G.trainMaxHP), nil)
    nvgFillColor(vg, nvgRGBA(255, 255, 240, 220))
    nvgText(vg, cx, by + barH / 2, math.floor(G.trainHP) .. "/" .. math.floor(G.trainMaxHP), nil)
end

------------------------------------------------------------------------
-- 5. 绘制提交方块 (资源收集框 — 列车下方)
--    上方: 资源图标堆叠  下方: 进度数字+绿色填充条
------------------------------------------------------------------------
function R.DrawSubmitBox(vg, G)
    local sb = G.submitBox
    local t = G.gameTime or 0
    local sw = C.SUBMIT_BOX_W
    local sh = C.SUBMIT_BOX_H
    local sx = sb.x - sw / 2
    local sy = sb.y - sh / 2
    local r = 8        -- 圆角
    local ratio = math.min(1, G.levelProgress / math.max(1, G.levelTarget))

    -- 投影
    do
        local shP = nvgRadialGradient(vg, sb.x, sb.y + sh / 2 + 3, 4, sw * 0.45,
            nvgRGBA(0, 0, 0, 50), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, sb.x, sb.y + sh / 2 + 3, sw * 0.45, 5)
        nvgFillPaint(vg, shP)
        nvgFill(vg)
    end

    -- 底部深色背景（整个框体）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, r)
    nvgFillColor(vg, nvgRGBA(45, 40, 35, 230))
    nvgFill(vg)

    -- 绿色进度条从底部往上填充（整个框体高度）
    local numZoneH = sh               -- 进度条覆盖整个框体
    local numZoneY = sy
    local fillH = numZoneH * ratio

    if ratio > 0 then
        nvgSave(vg)
        -- 裁剪到框体范围
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, sw, sh, r)
        nvgPathWinding(vg, NVG_SOLID)
        nvgIntersectScissor(vg, sx, numZoneY + numZoneH - fillH, sw, fillH)

        -- 绿色渐变填充
        local gp = nvgLinearGradient(vg, 0, numZoneY + numZoneH, 0, numZoneY,
            nvgRGBA(60, 150, 50, 255), nvgRGBA(90, 180, 60, 255))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, sx, sy, sw, sh, r)
        nvgFillPaint(vg, gp)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 框体边框（白色边框）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, r)
    nvgStrokeColor(vg, nvgRGBA(240, 240, 240, 220))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    -- 上方资源图标堆叠（木头在下层偏左，石头在上层偏右，紧凑叠放）
    local iconSz = 20
    local iconCY = sy + sh * 0.28    -- 图标中心在上部28%处
    -- 木头：底层，略偏左下
    drawSprite(vg, G.hudIconWood, sb.x - 3, iconCY + 1, iconSz, iconSz, 1.0)
    -- 石头：上层，略偏右上，稍小
    drawSprite(vg, G.hudIconStone, sb.x + 4, iconCY + 3, iconSz * 0.8, iconSz * 0.8, 1.0)

    -- 下方数字：显示升级所需总资源量
    local remaining = math.max(0, (G.levelTarget or 0) - (G.levelProgress or 0))
    local targetStr = tostring(remaining)
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local numCY = sy + sh * 0.72
    -- 阴影
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgText(vg, sb.x + 0.8, numCY + 0.8, targetStr, nil)
    -- 白色数字
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, sb.x, numCY, targetStr, nil)
end

------------------------------------------------------------------------
-- 6. 绘制资源节点 (有HP，可采集) — 真实树木/岩石/矿石外观
------------------------------------------------------------------------
function R.DrawResources(vg, G)
    local t = G.gameTime or 0
    local deadTreeImg = G.mapDeadTreeImg
    local pineTreeImg = G.mapPineTreeImg
    local greenTreeImg = G.mapGreenTreeImg
    local stoneImg = G.mapStoneImg
    local oreImg = G.mapOreImg
    local bushImg = G.mapBushImg
    local pebbleImg = G.mapPebbleImg
    local woodImgs = { deadTreeImg, pineTreeImg, greenTreeImg }

    -- 当前攻击目标引用（用于画红色光圈）
    local atkTargetRef = G.player and G.player.atkTarget and G.player.atkTarget.ref or nil

    -- 资源类型 → 掉落图标映射
    local dropIconMap = {
        wood   = G.hudIconWood,
        stone  = G.hudIconStone,
        ore    = G.hudIconGem,
        bush   = G.hudIconWood,     -- 灌木掉木材
        pebble = G.hudIconStone,    -- 碎石掉石头
    }

    for _, r in ipairs(G.resources) do
        if r.dead then goto continue_res end
        if r.y < G.renderTopY - 30 or r.y > G.screenH + 30 then goto continue_res end

        local rx = r.x
        local ry = r.y
        -- 纵深缩放：远处(上方)更小
        local depthRatio = math.max(0, math.min(1, (r.y - G.renderTopY) / math.max(1, G.screenH - G.renderTopY)))
        local depthScale = 0.65 + depthRatio * 0.35
        local sc = (r.scale or 1.0) * depthScale
        local sz = C.RES_SIZE / 2 * sc

        -- 受击闪白
        local hitFlash = (r.hitAnim or 0) > 0
        -- 受击晃动
        local shakeX = 0
        if hitFlash then
            shakeX = math.sin(t * 40) * 2.5
        end

        local drawX = rx + shakeX
        local drawSz = sz * 3.2  -- 精灵绘制尺寸

        -- 选择对应精灵
        local img = nil
        local treeIdx = 0
        if r.rtype == "wood" then
            treeIdx = (math.floor(r.bobPhase * 10) % 3) + 1
            img = woodImgs[treeIdx]
            drawSz = sz * 7.2
        elseif r.rtype == "stone" then
            img = stoneImg
        elseif r.rtype == "ore" then
            img = oreImg
        elseif r.rtype == "bush" then
            img = bushImg
            drawSz = sz * 4.0
        elseif r.rtype == "pebble" then
            img = pebbleImg
            drawSz = sz * 3.0
        end

        -- ① 被攻击时：脚底红色光圈（类似玩家金色光圈）
        local isBeingAttacked = (atkTargetRef == r)
        if isBeingAttacked then
            -- 基于碰撞尺寸而非精灵尺寸，避免树木等高精灵圈太大
            local haloBase = sz * 2.2
            if r.rtype == "pebble" then
                haloBase = sz * 1.4      -- 小石头：光圈缩小
            end
            local haloRX = haloBase
            local haloRY = haloRX * 0.38
            -- 红圈画在树根/石头底部（精灵以ry为中心，底部在 ry+drawSz/2）
            local haloCY
            if r.rtype == "wood" and treeIdx == 2 then
                haloCY = drawSz * 0.32   -- 松树
            elseif r.rtype == "wood" and treeIdx == 3 then
                haloCY = drawSz * 0.28   -- 绿树：树冠大，光环不宜太低
            elseif r.rtype == "wood" then
                haloCY = drawSz * 0.24   -- 枯树
            elseif r.rtype == "bush" then
                haloCY = drawSz * 0.2    -- 灌木
            elseif r.rtype == "pebble" then
                haloCY = drawSz * 0.15   -- 小石头
            elseif r.rtype == "ore" then
                haloCY = drawSz * 0.2    -- 矿石
            else
                haloCY = drawSz * 0.35   -- 其他资源
            end
            local orbAngle = t * 2.0

            nvgSave(vg)
            nvgTranslate(vg, rx, ry + haloCY)

            -- 底层红色椭圆环
            nvgBeginPath(vg)
            nvgEllipse(vg, 0, 0, haloRX, haloRY)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 40, 80))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 两个对称环绕红色亮点 + 拖尾
            for s = 0, 1 do
                local baseAngle = orbAngle + s * math.pi
                for ti = 1, 4 do
                    local ta = baseAngle - ti * 0.2
                    local tx = haloRX * math.cos(ta)
                    local ty = haloRY * math.sin(ta)
                    local alpha = math.floor(120 * (1 - ti / 5))
                    local cr = 2.0 - ti * 0.3
                    nvgBeginPath(vg)
                    nvgCircle(vg, tx, ty, cr)
                    nvgFillColor(vg, nvgRGBA(255, 80, 50, alpha))
                    nvgFill(vg)
                end
                local sx = haloRX * math.cos(baseAngle)
                local sy = haloRY * math.sin(baseAngle)
                -- 辉光
                local gp = nvgRadialGradient(vg, sx, sy, 1, 6,
                    nvgRGBA(255, 70, 40, 180), nvgRGBA(255, 50, 30, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, 6)
                nvgFillPaint(vg, gp)
                nvgFill(vg)
                -- 核心亮点
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, 1.8)
                nvgFillColor(vg, nvgRGBA(255, 200, 150, 240))
                nvgFill(vg)
            end

            nvgRestore(vg)
        end

        -- ② 受击压缩动画（squash & stretch）
        local squash = r.squashAnim or 0
        local scaleX = 1.0
        local scaleY = 1.0
        if squash > 0 then
            -- 压扁：宽变大、高变小，弹性恢复
            local phase = (1.0 - squash) * math.pi  -- 0→π
            local squashAmount = math.sin(phase) * 0.25 * squash
            scaleX = 1.0 + squashAmount
            scaleY = 1.0 - squashAmount
        end

        if img and img ~= 0 then
            nvgSave(vg)
            nvgTranslate(vg, drawX, ry)
            nvgScale(vg, scaleX, scaleY)

            -- 绘制精灵（原点居中）
            local halfSz = drawSz / 2
            local imgPaint = nvgImagePattern(vg, -halfSz, -halfSz, drawSz, drawSz, 0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -halfSz, -halfSz, drawSz, drawSz)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)



            -- ③ 攻击爆点特效（受击瞬间的冲击波）
            if hitFlash and (r.hitAnim or 0) > 0.12 then
                local burstR = drawSz * 0.5 * (1.0 - (r.hitAnim - 0.12) / 0.08)
                local burstAlpha = math.floor(200 * ((r.hitAnim - 0.12) / 0.08))
                if burstR > 0 and burstAlpha > 0 then
                    local bp = nvgRadialGradient(vg, 0, -drawSz * 0.15, 2, burstR,
                        nvgRGBA(255, 240, 180, burstAlpha), nvgRGBA(255, 180, 60, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, 0, -drawSz * 0.15, burstR)
                    nvgFillPaint(vg, bp)
                    nvgFill(vg)
                    -- 星形碎片线条
                    nvgStrokeColor(vg, nvgRGBA(255, 220, 100, burstAlpha))
                    nvgStrokeWidth(vg, 1.2)
                    for si = 0, 5 do
                        local sa = si * math.pi * 2 / 6 + r.bobPhase
                        local sr1 = burstR * 0.3
                        local sr2 = burstR * 0.9
                        nvgBeginPath(vg)
                        nvgMoveTo(vg, math.cos(sa) * sr1, -drawSz * 0.15 + math.sin(sa) * sr1)
                        nvgLineTo(vg, math.cos(sa) * sr2, -drawSz * 0.15 + math.sin(sa) * sr2)
                        nvgStroke(vg)
                    end
                end
            end

            nvgRestore(vg)

            -- 矿石保留发光效果
            if r.rtype == "ore" and not hitFlash then
                local oreClr = {C.CLR.ore_color[1], C.CLR.ore_color[2], C.CLR.ore_color[3]}
                local glow = math.sin(t * 3 + r.bobPhase) * 0.3 + 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, drawX, ry - sz * 0.3, sz * 0.55)
                local glowPaint = nvgRadialGradient(vg, drawX, ry - sz * 0.3, sz * 0.05, sz * 0.55,
                    nvgRGBA(oreClr[1], oreClr[2], oreClr[3], math.floor(glow * 30)),
                    nvgRGBA(oreClr[1], oreClr[2], oreClr[3], 0))
                nvgFillPaint(vg, glowPaint)
                nvgFill(vg)

                local sparkle = math.sin(t * 5 + r.bobPhase) * 0.5 + 0.5
                local sLen = 3 * sparkle * sc
                nvgBeginPath(vg)
                nvgMoveTo(vg, drawX - sLen, ry - sz * 0.55)
                nvgLineTo(vg, drawX + sLen, ry - sz * 0.55)
                nvgMoveTo(vg, drawX, ry - sz * 0.55 - sLen)
                nvgLineTo(vg, drawX, ry - sz * 0.55 + sLen)
                nvgStrokeColor(vg, nvgRGBA(160, 200, 240, math.floor(sparkle * 100)))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end
        end

        ::continue_res::
    end
end

------------------------------------------------------------------------
-- 6b. 绘制资源 UI 覆盖层（血条 + 掉落信息）— 在玩家之后绘制，保证最高层级
------------------------------------------------------------------------
function R.DrawResourceUI(vg, G)
    -- 资源类型 → 掉落图标映射
    local dropIconMap = {
        wood   = G.hudIconWood,
        stone  = G.hudIconStone,
        ore    = G.hudIconGem,
        bush   = G.hudIconWood,
        pebble = G.hudIconStone,
    }

    for _, r in ipairs(G.resources) do
        if r.dead then goto continue_rui end
        if r.y < G.renderTopY - 30 or r.y > G.screenH + 30 then goto continue_rui end

        local rx = r.x
        local ry = r.y
        -- 纵深缩放（与 DrawResources 保持一致）
        local depthRatio = math.max(0, math.min(1, (r.y - G.renderTopY) / math.max(1, G.screenH - G.renderTopY)))
        local depthScale = 0.65 + depthRatio * 0.35
        local sc = (r.scale or 1.0) * depthScale
        local sz = C.RES_SIZE / 2 * sc

        -- 计算 drawSz（与 DrawResources 一致）
        local drawSz = sz * 3.2
        if r.rtype == "wood" then
            drawSz = sz * 7.2
        elseif r.rtype == "bush" then
            drawSz = sz * 4.0
        elseif r.rtype == "pebble" then
            drawSz = sz * 3.0
        end

        -- ④ 血条（HP < maxHp 时显示）+ 延时扣除效果
        if r.hp and r.maxHp and r.hp < r.maxHp and r.hp > 0 then
            local barW = 36
            local barH = 5
            local bx = rx - barW / 2
            local by = ry - drawSz / 2 - 8
            local ratio = r.hp / r.maxHp
            local displayRatio = (r.displayHp or r.hp) / r.maxHp

            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx - 1, by - 1, barW + 2, barH + 2, 3)
            nvgFillColor(vg, nvgRGBA(20, 20, 20, 200))
            nvgFill(vg)

            -- 延时扣除部分（橙色/黄色，显示即将消失的HP）
            if displayRatio > ratio then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, bx, by, barW * displayRatio, barH, 2)
                nvgFillColor(vg, nvgRGBA(255, 180, 50, 200))
                nvgFill(vg)
            end

            -- 当前 HP（绿色）
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, barW * ratio, barH, 2)
            nvgFillColor(vg, nvgRGBA(80, 210, 80, 230))
            nvgFill(vg)

            -- ⑤ 血条上方：掉落资源图标 + 数量
            local resInfo = C.RES[r.rtype]
            local dropAmount = resInfo and resInfo.drop or 1
            local dropIcon = dropIconMap[r.rtype]
            if dropIcon and dropIcon ~= 0 then
                local iconSz = 18
                local iconX = rx
                local iconY = by - iconSz / 2 - 2

                -- 资源图标
                drawSprite(vg, dropIcon, iconX - 8, iconY, iconSz, iconSz, 1.0)

                -- 数量文字
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 12)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                -- 描边
                nvgFillColor(vg, nvgRGBA(0, 0, 0, 220))
                nvgText(vg, iconX + 2, iconY + 1, "x" .. dropAmount)
                -- 正文
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
                nvgText(vg, iconX + 1, iconY, "x" .. dropAmount)
            end
        end

        ::continue_rui::
    end
end

------------------------------------------------------------------------
-- 6c. 绘制携带资源跟随队列（排成队跟在玩家屁股后面）
------------------------------------------------------------------------
function R.DrawCarryQueue(vg, G)
    local p = G.player
    local queue = p.carryQueue
    local count = #queue
    if count <= 0 then return end
    if G.mounted then return end  -- 上车时不显示

    local trail = p.trail
    if #trail < 2 then return end

    -- 资源类型→图片映射（小灌木丛算木头，小石头算石头）
    local imgMap = {
        wood   = G.hudIconWood,
        stone  = G.hudIconStone,
        ore    = G.hudIconGem,
        bush   = G.hudIconWood,
        pebble = G.hudIconStone,
    }

    local iconSize = 16          -- 每个资源图标大小
    local spacing  = 14          -- 轨迹点间距（与TRAIL_STEP匹配）
    local t = G.gameTime or 0

    local smooth = p.carrySmooth

    -- 沿轨迹放置每个资源图标（使用平滑插值位置）
    for i = 1, count do
        if i > #smooth then break end
        local trailIdx = i + 1
        if trailIdx > #trail then break end

        local sp = smooth[i]
        local rtype = queue[i]
        local img = imgMap[rtype]

        -- 轻微上下浮动，依序错开相位
        local bobY = math.sin(t * 3 + i * 0.8) * 1.5

        nvgSave(vg)
        nvgTranslate(vg, sp.x, sp.y + bobY)

        if img and img ~= 0 then
            -- 用资源图标
            local sz = iconSize
            local imgPaint = nvgImagePattern(vg, -sz / 2, -sz / 2, sz, sz, 0, img, 0.95)
            nvgBeginPath(vg)
            nvgRect(vg, -sz / 2, -sz / 2, sz, sz)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            -- 无图标时用彩色圆点
            local rc = C.CLR[rtype .. "_color"] or {150, 150, 150}
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, 5)
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 220))
            nvgFill(vg)
        end

        nvgRestore(vg)
    end


end

------------------------------------------------------------------------
-- 7. 绘制玩家 (末日幸存者：脏旧破损、伤疤、疲惫)
------------------------------------------------------------------------
function R.DrawPlayer(vg, G)
    local p = G.player
    local px = p.x
    local py = p.y
    local t = G.gameTime or 0

    -- 无敌闪烁（提前声明，Spine 和帧图都需要，也避免 goto 跳过 local）
    local stunAlpha = 255
    if p.stunTimer and p.stunTimer > 0 then
        stunAlpha = math.sin(t * 16) > 0 and 255 or 100
    end

    -- ========== Spine 渲染（优先，在 translate 之前，使用绝对设计坐标） ==========
    local heroSpInst = G.heroSpineInst
    if heroSpInst then
        -- shaun spine: skeleton height=379.54, root bone at y=0 (near feet)
        -- 缩放匹配帧图视觉大小(~53px)，与僵尸 drawScale=0.14 保持一致
        local sc = 0.35
        local footDesignY = py + C.PLAYER_H * 0.5  -- 脚底对齐碰撞盒底部
        local facingScale = sc * p.facing  -- facing: 1=右, -1=左
        nvgSave(vg)
        heroSpInst:SetPosition(px, footDesignY)
        heroSpInst:SetScale(facingScale, -sc)
        if stunAlpha < 255 then
            nvgGlobalAlpha(vg, stunAlpha / 255.0)
        end
        ---@diagnostic disable-next-line: undefined-global
        nvgSpineRender(vg, heroSpInst)
        if stunAlpha < 255 then
            nvgGlobalAlpha(vg, 1.0)
        end
        nvgRestore(vg)
    end

    nvgSave(vg)
    nvgTranslate(vg, px, py)

    -- 如果 spine 已渲染，跳过帧图但保留后续效果（光圈、阴影、背包等）
    if heroSpInst then
        goto hero_after_body
    end

    -- 柔阴影 (径向渐变)
    do
        local shadowPaint = nvgRadialGradient(vg, 3, C.PLAYER_H / 2 + 3, 2, 16,
            nvgRGBA(10, 12, 8, 70), nvgRGBA(10, 12, 8, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, 3, C.PLAYER_H / 2 + 3, 16, 7)
        nvgFillPaint(vg, shadowPaint)
        nvgFill(vg)
    end

    -- 下车状态：脚底金色光圈（光点沿椭圆轨道环绕）
    if not G.mounted then
        local haloRX = 18          -- 椭圆水平半径
        local haloRY = 7           -- 椭圆垂直半径（扁椭圆）
        local haloCY = C.PLAYER_H / 2 + 2  -- 脚底位置
        local orbAngle = t * 1.5   -- 环绕速度

        nvgSave(vg)
        nvgTranslate(vg, 0, haloCY)

        -- 底层椭圆环（半透明底色）
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, haloRX, haloRY)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 70))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 两个对称环绕亮点 + 拖尾
        for s = 0, 1 do
            local baseAngle = orbAngle + s * math.pi

            -- 拖尾（5个逐渐变淡的小点）
            for ti = 1, 5 do
                local ta = baseAngle - ti * 0.18
                local tx = haloRX * math.cos(ta)
                local ty = haloRY * math.sin(ta)
                local alpha = math.floor(100 * (1 - ti / 6))
                local r = 2.0 - ti * 0.25
                nvgBeginPath(vg)
                nvgCircle(vg, tx, ty, r)
                nvgFillColor(vg, nvgRGBA(255, 210, 60, alpha))
                nvgFill(vg)
            end

            -- 亮点位置
            local sx = haloRX * math.cos(baseAngle)
            local sy = haloRY * math.sin(baseAngle)

            -- 辉光
            local glow = nvgRadialGradient(vg, sx, sy, 1, 8,
                nvgRGBA(255, 220, 60, 160), nvgRGBA(255, 200, 40, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, 8)
            nvgFillPaint(vg, glow)
            nvgFill(vg)

            -- 核心亮点
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, 2.0)
            nvgFillColor(vg, nvgRGBA(255, 245, 170, 240))
            nvgFill(vg)
        end

        nvgRestore(vg)
    end

    -- 上车射击状态：炮塔模式，纯旋转控制方向（跳过 facing 翻转）
    if G.mounted and G.mountedShootImg and G.mountedShootImg ~= 0 then
        local imgW, imgH = imgSize(vg, G.mountedShootImg)
        if imgW <= 0 or imgH <= 0 then imgW, imgH = 542, 1103 end
        local ratio = imgH / imgW  -- ~2.03
        local drawW = C.PLAYER_W      -- 上车状态角色
        local drawH = drawW * ratio

        -- 原图枪口朝下(π/2)，旋转到瞄准方向
        local aimAngle = G.mountedAimDir or 0
        local rot = aimAngle - math.pi / 2

        nvgSave(vg)
        nvgRotate(vg, rot)

        local dx = -drawW / 2
        local dy = -drawH / 2
        local imgPaint = nvgImagePattern(vg, dx, dy, drawW, drawH, 0, G.mountedShootImg, stunAlpha / 255.0)
        nvgBeginPath(vg)
        nvgRect(vg, dx, dy, drawW, drawH)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgRestore(vg)

        -- 枪口开火帧动画（在角色坐标系内绘制）
        local mf = G.muzzleFlash
        local mfFrames = G.muzzleFlashFrames
        if mf and mfFrames and #mfFrames >= 4 then
            local progress = mf.elapsed / mf.timer  -- 0~1
            local frameIdx = math.min(4, math.floor(progress * 4) + 1)
            local flashImg = mfFrames[frameIdx]
            if flashImg and flashImg ~= 0 then
                local fImgW, fImgH = imgSize(vg, flashImg)
                if fImgW > 0 and fImgH > 0 then
                    local flashSize = 18
                    local scl = 0.3 + 0.7 * progress
                    local fDrawW = flashSize * scl
                    local fDrawH = fDrawW * (fImgH / fImgW)
                    -- 枪口在角色图片底部（原图朝下），偏移 = drawH/2
                    local muzzleDist = drawH / 2

                    nvgSave(vg)
                    -- 与角色同旋转基准：原图朝下(π/2)旋转到瞄准方向
                    nvgRotate(vg, rot)
                    -- 沿旋转后的+Y轴（原图朝下方向）偏移到枪口
                    -- 开火帧原图朝右，需额外旋转+π/2使其沿枪管方向
                    nvgTranslate(vg, 0, muzzleDist)
                    nvgRotate(vg, math.pi / 2)
                    -- 火焰从枪口向外延伸
                    local fx = -fDrawW * 0.2
                    local fy = -fDrawH / 2
                    local imgPaintF = nvgImagePattern(vg, fx, fy, fDrawW, fDrawH, 0, flashImg, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, fx, fy, fDrawW, fDrawH)
                    nvgFillPaint(vg, imgPaintF)
                    nvgFill(vg)
                    nvgRestore(vg)
                end
            end
        end

        nvgRestore(vg)
        return
    end

    -- 翻转（仅非上车状态）
    if p.facing < 0 then nvgScale(vg, -1, 1) end

    -- ========== 帧图渲染（Fallback） ==========
    do
    -- 主角序列帧动画绘制
    -- 攻击帧: 1=idle, 2=raise, 3=swing, 4=hit, 5=recover
    -- 行走帧: walk1~walk4 (4帧循环)
    local frames = G.heroAnimFrames
    local walkFrames = G.heroWalkFrames
    local frameImg = G.heroImg  -- 默认idle帧
    local nFrames = frames and #frames or 0
    if nFrames >= 2 then
        if p.atkSwingAnim and p.atkSwingAnim > 0 then
            if nFrames >= 5 then
                -- 经典5帧: idle/raise/swing/hit/recover
                if p.atkSwingAnim > 0.7 then
                    frameImg = frames[2]
                elseif p.atkSwingAnim > 0.4 then
                    frameImg = frames[3]
                elseif p.atkSwingAnim > 0.1 then
                    frameImg = frames[4]
                else
                    frameImg = frames[5]
                end
            else
                -- 动态帧数: 按 atkSwingAnim(1→0) 等分映射到所有帧
                local progress = 1.0 - p.atkSwingAnim  -- 0→1
                local idx = math.floor(progress * nFrames) + 1
                if idx > nFrames then idx = nFrames end
                frameImg = frames[idx]
            end
        elseif p.collectAnim and p.collectAnim > 0 then
            if nFrames >= 3 then
                local collectProgress = 1.0 - p.collectAnim / 0.3
                if collectProgress < 0.5 then
                    frameImg = frames[2]
                else
                    frameImg = frames[3]
                end
            else
                frameImg = frames[nFrames]
            end
        elseif walkFrames and #walkFrames >= 1 and p.isWalking then
            -- 行走动画: 仅在实际移动时播放帧，停下立即回 idle
            local wCount = #walkFrames
            local walkIdx = (math.floor(p.walkAnim) % wCount) + 1
            frameImg = walkFrames[walkIdx]
        else
            -- idle: 保持 G.heroImg（待机图），不用 frames[1]
        end
    end

    if frameImg and frameImg ~= 0 then
        -- 统一画布：所有帧用相同大小绘制，每帧按原图比例居中 fit
        local canvasW = G.heroCanvasW or 512
        local canvasH = G.heroCanvasH or 636
        local canvasRatio = canvasH / canvasW
        local drawW = C.PLAYER_W + 18  -- 比碰撞框稍大，让角色显眼
        local drawH = drawW * canvasRatio

        -- 计算当前帧在统一画布内的居中 fit 位置
        local imgW, imgH = imgSize(vg, frameImg)
        if imgW <= 0 or imgH <= 0 then imgW, imgH = canvasW, canvasH end
        local frameRatio = imgH / imgW
        local fitW, fitH, fitX, fitY
        if frameRatio >= canvasRatio then
            -- 帧更高，按高度 fit
            fitH = drawH
            fitW = fitH / frameRatio
        else
            -- 帧更宽，按宽度 fit
            fitW = drawW
            fitH = fitW * frameRatio
        end
        fitX = -fitW / 2
        fitY = -fitH / 2 - 2 + (drawH - fitH) / 2  -- 底部对齐（脚部贴地）

        -- 程序化行走补间：弹跳 + 倾斜 + 轻微挤压拉伸
        local isWalking = (p.isWalking and not (p.atkSwingAnim and p.atkSwingAnim > 0) and not (p.collectAnim and p.collectAnim > 0))
        local walkBobY = 0        -- 垂直弹跳偏移
        local walkTilt = 0        -- 身体倾斜角度
        local walkScaleX = 1.0    -- 水平缩放 (挤压拉伸)
        local walkScaleY = 1.0    -- 垂直缩放

        if isWalking then
            -- walkAnim 以 dt*10 递增，用连续的 sin/cos 做平滑插值
            -- 每2步一个完整周期 (左脚迈→交叉→右脚迈→交叉)
            local phase = p.walkAnim * math.pi * 0.5  -- 每4帧一个完整正弦周期
            -- 弹跳：迈步时身体下压，交叉时弹起 (2倍频率，每步一弹)
            walkBobY = -math.abs(math.sin(phase)) * 1.8
            -- 身体左右倾斜：跟随步伐重心偏移
            walkTilt = math.sin(phase) * 0.04  -- 约2.3度左右摇摆
            -- 挤压拉伸：弹起时略拉长，下压时略变宽
            local squash = math.sin(phase * 2) * 0.03
            walkScaleX = 1.0 + squash
            walkScaleY = 1.0 - squash
        end

        nvgSave(vg)
        -- 应用行走变换：先平移到角色脚底，再旋转/缩放，再平移回来
        nvgTranslate(vg, 0, walkBobY)
        if walkTilt ~= 0 then
            -- 绕脚底旋转（而非中心），让摇摆更自然
            nvgTranslate(vg, 0, drawH * 0.4)
            nvgRotate(vg, walkTilt)
            nvgTranslate(vg, 0, -drawH * 0.4)
        end
        if walkScaleX ~= 1.0 then
            nvgScale(vg, walkScaleX, walkScaleY)
        end

        local imgPaint = nvgImagePattern(vg, fitX, fitY, fitW, fitH, 0, frameImg, stunAlpha / 255.0)
        nvgBeginPath(vg)
        nvgRect(vg, fitX, fitY, fitW, fitH)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgRestore(vg)
    end
    end -- do block

    ::hero_after_body::

    -- 收集光效 (暗化，偏冷色)
    if p.collectAnim and p.collectAnim > 0 then
        local alpha = p.collectAnim / 0.3 * 50
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, 18 + (0.3 - p.collectAnim) * 35)
        nvgStrokeColor(vg, nvgRGBA(150, 170, 200, math.floor(alpha)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- 攻击挥砍弧光已移除 (角色序列帧自带挥斧动画)

    -- 背包数量显示（下车且有携带资源时显示 "当前/上限"）
    if not G.mounted and p.carrying and p.carrying > 0 then
        -- 抵消角色朝向翻转，保持文字正向
        if p.facing < 0 then nvgScale(vg, -1, 1) end

        local maxC = G.maxCarry or C.MAX_CARRY
        local bagStr = p.carrying .. "/" .. maxC
        local bagX = 0
        local bagY = -C.PLAYER_H / 2 - 12

        -- 背景小药丸
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tw = nvgTextBounds(vg, 0, 0, bagStr)
        local pw = tw + 8
        local ph = 13

        nvgBeginPath(vg)
        nvgRoundedRect(vg, bagX - pw / 2, bagY - ph / 2, pw, ph, ph / 2)
        if p.carrying >= maxC then
            nvgFillColor(vg, nvgRGBA(200, 50, 30, 200))
        else
            nvgFillColor(vg, nvgRGBA(40, 40, 40, 180))
        end
        nvgFill(vg)

        -- 白色边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bagX - pw / 2, bagY - ph / 2, pw, ph, ph / 2)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 160))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 文字
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, bagX, bagY, bagStr)

        -- 恢复翻转
        if p.facing < 0 then nvgScale(vg, -1, 1) end
    end

    nvgRestore(vg)
end

------------------------------------------------------------------------
-- 8. 绘制丧尸
------------------------------------------------------------------------
function R.DrawZombies(vg, G)
    local t = G.gameTime or 0

    -- 当前攻击目标引用（用于画红色锁定光圈）
    local atkTargetRef = G.player and G.player.atkTarget and G.player.atkTarget.ref or nil

    for _, z in ipairs(G.zombies or {}) do
        if z.spawnDelay and z.spawnDelay > 0 then goto continue_z end
        if z.dead and not z.dying then goto continue_z end
        if z.deadDone then goto continue_z end
        if z.y < G.renderTopY - 40 or z.y > G.screenH + 10 then goto continue_z end

        local zx = z.x
        local zy = z.y
        local hitFlash = (z.hitAnim or 0) > 0

        -- 被攻击时：脚底红色锁定光圈
        if atkTargetRef == z then
            local haloRX = 16
            local haloRY = 6
            local haloCY = C.ZOMBIE_SIZE * 0.9
            local orbAngle = t * 2.0

            nvgSave(vg)
            nvgTranslate(vg, zx, zy + haloCY)

            -- 底层红色椭圆环
            nvgBeginPath(vg)
            nvgEllipse(vg, 0, 0, haloRX, haloRY)
            nvgStrokeColor(vg, nvgRGBA(255, 60, 40, 80))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 两个对称环绕红色亮点 + 拖尾
            for s = 0, 1 do
                local baseAngle = orbAngle + s * math.pi
                for ti = 1, 4 do
                    local ta = baseAngle - ti * 0.2
                    local tx = haloRX * math.cos(ta)
                    local ty = haloRY * math.sin(ta)
                    local alpha = math.floor(120 * (1 - ti / 5))
                    local cr = 2.0 - ti * 0.3
                    nvgBeginPath(vg)
                    nvgCircle(vg, tx, ty, cr)
                    nvgFillColor(vg, nvgRGBA(255, 80, 50, alpha))
                    nvgFill(vg)
                end
                local sx = haloRX * math.cos(baseAngle)
                local sy = haloRY * math.sin(baseAngle)
                -- 辉光
                local gp = nvgRadialGradient(vg, sx, sy, 1, 6,
                    nvgRGBA(255, 70, 40, 180), nvgRGBA(255, 50, 30, 0))
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, 6)
                nvgFillPaint(vg, gp)
                nvgFill(vg)
                -- 核心亮点
                nvgBeginPath(vg)
                nvgCircle(vg, sx, sy, 1.8)
                nvgFillColor(vg, nvgRGBA(255, 200, 150, 240))
                nvgFill(vg)
            end

            nvgRestore(vg)
        end

        -- Spine 渲染（Spine 自带阴影，不再手动画）
        local spInst = z.spineInst
        if spInst then
            local sc = z.drawScale or 0.14
            -- 水平翻转：facing < 0 时 scaleX 取反
            local scX = (z.facing and z.facing < 0) and -sc or sc
            -- Spine 原点在脚底，设置 Y 到丧尸脚底位置
            local footY = zy + C.ZOMBIE_SIZE * 0.9

            nvgSave(vg)
            spInst:SetPosition(zx, footY)
            spInst:SetScale(scX, -sc)
            -- 受击闪白效果
            if hitFlash then
                nvgGlobalAlpha(vg, 0.5)
            end
            ---@diagnostic disable-next-line: undefined-global
            nvgSpineRender(vg, spInst)
            if hitFlash then
                nvgGlobalAlpha(vg, 1.0)
            end
            nvgRestore(vg)
        else
            -- Fallback: Spine实例缺失时画简易僵尸轮廓
            local r = C.ZOMBIE_SIZE * 0.8
            nvgBeginPath(vg)
            nvgCircle(vg, zx, zy - r * 0.3, r)
            nvgFillColor(vg, nvgRGBA(80, 120, 60, 200))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, zx, zy - r * 1.2, r * 0.6)
            nvgFillColor(vg, nvgRGBA(100, 140, 70, 200))
            nvgFill(vg)
        end

        -- 血条 (HP < maxHp 时显示, restore后绘制避免翻转影响)
        if z.hp and z.maxHp and z.hp < z.maxHp and z.hp > 0 then
            local barW = 24
            local barH = 3
            local bx = zx - barW / 2
            local by = zy - C.ZOMBIE_SIZE - 6
            local ratio = z.hp / z.maxHp
            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, barW, barH, 1)
            nvgFillColor(vg, nvgRGBA(15, 12, 10, 180))
            nvgFill(vg)
            -- 血量 (暗红)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, barW * ratio, barH, 1)
            nvgFillColor(vg, nvgRGBA(180, 30, 20, 230))
            nvgFill(vg)
        end

        ::continue_z::
    end
end

------------------------------------------------------------------------
-- 9. 绘制浮动文字
------------------------------------------------------------------------
function R.DrawFloatTexts(vg, G)
    nvgFontFace(vg, "sans")
    for _, ft in ipairs(G.floatTexts) do
        local alpha = ft.life / ft.maxLife
        local a255 = math.floor(alpha * 255)
        local isDmg = (ft.rtype == "damage" or ft.rtype == "crit" or ft.rtype == "train_damage")
        local isSubmit = (ft.rtype == "submit")
        local col
        if ft.rtype == "submit" then
            col = {255, 255, 255} -- 提交+1：白色
        elseif ft.rtype == "gold" then
            col = C.CLR.gold_color
        elseif ft.rtype == "wood" then
            col = C.CLR.wood_color
        elseif ft.rtype == "stone" then
            col = C.CLR.stone_color
        elseif ft.rtype == "ore" then
            col = C.CLR.ore_color
        elseif ft.rtype == "bush" then
            col = C.CLR.bush_color
        elseif ft.rtype == "pebble" then
            col = C.CLR.pebble_color
        elseif ft.rtype == "crit" then
            col = {255, 60, 50}   -- 暴击：红色
        elseif ft.rtype == "train_damage" then
            col = {255, 50, 40}   -- 火车受击：红色
        elseif ft.rtype == "heal" then
            col = {80, 255, 120}  -- 治疗：绿色
        elseif ft.rtype == "damage" then
            col = {255, 255, 255} -- 普通伤害：白色
        else
            col = C.CLR.text_white
        end
        local fontSize = 14
        local scale = 0.8 + (1 - alpha) * 0.4
        if isDmg then fontSize = 16 end
        if ft.rtype == "crit" then fontSize = 20 end  -- 暴击更大
        if isSubmit then fontSize = 16 end  -- 提交+1
        nvgFontSize(vg, fontSize * scale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 伤害/暴击/提交：8方向粗黑描边
        if isDmg or isSubmit then
            local o = 1.5  -- 描边厚度
            nvgFillColor(vg, nvgRGBA(0, 0, 0, a255))
            nvgText(vg, ft.x - o, ft.y, ft.text, nil)
            nvgText(vg, ft.x + o, ft.y, ft.text, nil)
            nvgText(vg, ft.x, ft.y - o, ft.text, nil)
            nvgText(vg, ft.x, ft.y + o, ft.text, nil)
            nvgText(vg, ft.x - o, ft.y - o, ft.text, nil)
            nvgText(vg, ft.x + o, ft.y - o, ft.text, nil)
            nvgText(vg, ft.x - o, ft.y + o, ft.text, nil)
            nvgText(vg, ft.x + o, ft.y + o, ft.text, nil)
        end
        -- 主体文字多次绘制模拟加粗
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], a255))
        if isDmg or isSubmit then
            nvgText(vg, ft.x - 0.5, ft.y, ft.text, nil)
            nvgText(vg, ft.x + 0.5, ft.y, ft.text, nil)
        end
        nvgText(vg, ft.x, ft.y, ft.text, nil)
    end
end

------------------------------------------------------------------------
-- 10. 绘制粒子
------------------------------------------------------------------------
function R.DrawParticles(vg, G)
    for _, p in ipairs(G.particles) do
        local alpha = p.life / p.maxLife
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, p.size * alpha)
        nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 255)))
        nvgFill(vg)
    end
end

------------------------------------------------------------------------
-- 10.2 烟雾特效
------------------------------------------------------------------------
function R.DrawPuffs(vg, G)
    for _, p in ipairs(G.puffs) do
        local frames = p.smokeType == 1 and G.smokeAFrames or G.smokeBFrames
        local img = frames[p.frame]
        if img and img ~= 0 then
            local iw, ih = imgSize(vg, img)
            nvgSave(vg)
            nvgTranslate(vg, p.x, p.y)
            nvgBeginPath(vg)
            nvgRect(vg, -iw / 2, -ih / 2, iw, ih)
            nvgFillPaint(vg, nvgImagePattern(vg, -iw / 2, -ih / 2, iw, ih, 0, img, 1.0))
            nvgFill(vg)
            nvgRestore(vg)
        end
    end
end

function R.DrawBursts(vg, G)
    local frames = G.burstFrames
    if not frames then return end
    local sc = 0.4
    for _, b in ipairs(G.bursts) do
        local img = frames[b.frame]
        if img and img ~= 0 then
            local iw, ih = imgSize(vg, img)
            local dw, dh = iw * sc, ih * sc
            nvgSave(vg)
            nvgTranslate(vg, b.x, b.y)
            nvgBeginPath(vg)
            nvgRect(vg, -dw / 2, -dh / 2, dw, dh)
            nvgFillPaint(vg, nvgImagePattern(vg, -dw / 2, -dh / 2, dw, dh, 0, img, 1.0))
            nvgFill(vg)
            nvgRestore(vg)
        end
    end
end

------------------------------------------------------------------------
-- 10.3 弹出资源图标
------------------------------------------------------------------------
function R.DrawDropItems(vg, G)
    local imgMap = {
        wood   = G.hudIconWood,
        stone  = G.hudIconStone,
        ore    = G.hudIconGem,
        bush   = G.hudIconWood,
        pebble = G.hudIconStone,
    }
    local sz = 14
    for _, d in ipairs(G.dropItems) do
        local img = imgMap[d.rtype]
        if img and img ~= 0 then
            local sc = d.scale or 1.0
            local sqX, sqY = 1.0, 1.0
            if d.squash and d.squash > 0 then
                sqX = 1.0 + d.squash   -- 着地时横向拉伸
                sqY = 1.0 - d.squash   -- 着地时纵向压扁
            end
            nvgSave(vg)
            nvgTranslate(vg, d.x, d.y)
            nvgScale(vg, sc * sqX, sc * sqY)
            nvgRotate(vg, d.rot)
            local imgPaint = nvgImagePattern(vg, -sz / 2, -sz / 2, sz, sz, 0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -sz / 2, -sz / 2, sz, sz)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
            nvgRestore(vg)
        else
            local rc = C.CLR[(d.rtype or "") .. "_color"] or {150, 150, 150}
            nvgBeginPath(vg)
            nvgCircle(vg, d.x, d.y, 5)
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 230))
            nvgFill(vg)
        end
    end
end

------------------------------------------------------------------------
-- 10.4 提交资源飞行动画
------------------------------------------------------------------------
function R.DrawSubmitFlyItems(vg, G)
    local imgMap = {
        wood   = G.hudIconWood,
        stone  = G.hudIconStone,
        ore    = G.hudIconGem,
        bush   = G.hudIconWood,    -- 小灌木丛算木头
        pebble = G.hudIconStone,   -- 小石头算石头
    }
    local sz = 24
    for _, item in ipairs(G.submitFlyItems) do
        local img = imgMap[item.rtype]
        local t = math.min(1, item.timer / item.duration)
        -- 逐渐缩小 + 透明
        local sc = 1.0 - t * 0.4
        local alpha = 1.0 - t * 0.3
        nvgSave(vg)
        nvgTranslate(vg, item.x, item.y)
        nvgScale(vg, sc, sc)
        nvgRotate(vg, item.rot)
        nvgGlobalAlpha(vg, alpha)
        if img and img ~= 0 then
            local imgPaint = nvgImagePattern(vg, -sz / 2, -sz / 2, sz, sz, 0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -sz / 2, -sz / 2, sz, sz)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            local rc = C.CLR[(item.rtype or "") .. "_color"] or {150, 150, 150}
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, 5)
            nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 230))
            nvgFill(vg)
        end
        nvgRestore(vg)
    end
end

------------------------------------------------------------------------
-- 10.4a2 左侧获得提示 toast（带图标）
------------------------------------------------------------------------
function R.DrawRewardToasts(vg, G)
    if not G.rewardToasts or #G.rewardToasts == 0 then return end
    local s = G.uiScale or 1
    local H = G.screenH
    local baseY = H * 0.38  -- 屏幕左侧偏上位置

    local iconMap = {
        gem   = G.hudIconGem,
        wood  = G.hudIconWood,
        stone = G.hudIconStone,
        gold  = G.hudIconGold,
    }

    for idx, toast in ipairs(G.rewardToasts) do
        local t = toast.timer / toast.life
        -- 入场滑入(0~0.15) + 停留 + 出场淡出(0.75~1.0)
        local slideIn = math.min(1, toast.timer / 0.25)
        local fadeOut = t > 0.75 and (1 - (t - 0.75) / 0.25) or 1.0
        local easeIn = 1 - (1 - slideIn) * (1 - slideIn)

        local iSz = 18 * s
        local padX = 8 * s
        local padY = 5 * s
        local fontSize = 13 * s

        -- 测量文字宽度
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        local tw = nvgTextBounds(vg, 0, 0, toast.text)
        local contentW = padX + iSz + 6 * s + tw + padX  -- 内容实际宽度
        local tailW = 20 * s  -- 渐变尾巴额外宽度
        local boxW = contentW + tailW
        local boxH = iSz + padY * 2

        local offX = -boxW * (1 - easeIn)  -- 从左侧滑入
        local posX = 10 * s + offX
        local posY = baseY + (idx - 1) * (boxH + 6 * s)
        local alpha = fadeOut

        nvgSave(vg)
        nvgGlobalAlpha(vg, alpha)

        -- 半透明黑底，右侧渐变消失（渐变从内容末尾开始）
        local gradStart = posX + contentW
        local gradEnd   = posX + boxW
        local bgPaint = nvgLinearGradient(vg, gradStart, posY, gradEnd, posY,
            nvgRGBA(0, 0, 0, 160), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, posX, posY, boxW, boxH, 6 * s)
        nvgFillPaint(vg, bgPaint)
        nvgFill(vg)

        -- 图标
        local img = iconMap[toast.icon]
        local iconX = posX + padX
        local iconY = posY + padY
        if img and img ~= 0 then
            local ip = nvgImagePattern(vg, iconX, iconY, iSz, iSz, 0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, iconX, iconY, iSz, iSz)
            nvgFillPaint(vg, ip)
            nvgFill(vg)
        end

        -- 文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, iconX + iSz + 6 * s, posY + boxH / 2, toast.text)

        nvgRestore(vg)
    end
end

------------------------------------------------------------------------
-- 10.4b 金币飞行动画（击杀僵尸掉落金币飞向HUD）
------------------------------------------------------------------------
function R.DrawGoldFlyItems(vg, G)
    local img = G.hudIconGold
    local sz = 20
    for _, item in ipairs(G.goldFlyItems) do
        local dur = item.phase == 1 and item.popDur or item.flyDur or 0.4
        local t = math.min(1, item.timer / dur)
        local sc = item.scale or 1.0
        local alpha = item.phase == 1 and 1.0 or (1.0 - t * 0.3)
        nvgSave(vg)
        nvgTranslate(vg, item.x, item.y)
        nvgScale(vg, sc, sc)
        nvgGlobalAlpha(vg, alpha)
        if img and img ~= 0 then
            local imgPaint = nvgImagePattern(vg, -sz / 2, -sz / 2, sz, sz, 0, img, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, -sz / 2, -sz / 2, sz, sz)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)
        else
            nvgBeginPath(vg)
            nvgCircle(vg, 0, 0, 6)
            nvgFillColor(vg, nvgRGBA(255, 215, 0, 230))
            nvgFill(vg)
        end
        nvgRestore(vg)
    end
end

------------------------------------------------------------------------
-- 10.5 右侧面板：炮塔图标 + 行驶距离条
------------------------------------------------------------------------
function R.DrawRightPanel(vg, G)
    local W = G.screenW
    local H = G.screenH
    local t = G.gameTime or 0
    local s = G.uiScale or 1

    -- ========== 参数 ==========
    local panelRight = W - 6 * s       -- 面板右边距
    local iconSize = 42 * s            -- 图标方块边长
    local iconGap = 6 * s              -- 图标间距
    local iconCorner = 8 * s            -- 圆角半径
    local startY = G.hudH + 12 * s     -- 第一个图标顶部Y

    -- ========== 1) 炮塔图标槽位（始终显示4个，锁定/解锁） ==========
    local turrets = G.turrets or {}
    local totalSlots = #Turret.SLOTS  -- 4

    -- 建立 slotId → turret 映射
    local slotMap = {}
    for _, turret in ipairs(turrets) do
        slotMap[turret.slotId] = turret
    end

    -- ========== 炮塔底三段拼接背景 ==========
    do
        local basePad = 5 * s
        local baseW = iconSize + basePad * 2         -- 52
        local baseX = panelRight - iconSize - basePad -- 图标居中
        local baseScale = baseW / 139

        local topCapH  = math.floor(28 * baseScale)   -- 顶帽高
        local midSliceH = 29 * baseScale               -- 中部单片高（用于平铺）
        local botCapH  = math.floor(32 * baseScale)    -- 底帽高

        local slotsAreaH = totalSlots * (iconSize + iconGap) - iconGap  -- 4*48-6=186
        local baseTopY   = startY - basePad            -- 顶帽起点
        local midStartY  = baseTopY + topCapH
        local midTotalH  = slotsAreaH + basePad * 2    -- 覆盖所有槽位+上下padding
        local botStartY  = midStartY + midTotalH

        -- 顶部帽
        if G.turretBaseTop and G.turretBaseTop ~= 0 then
            local p = nvgImagePattern(vg, baseX, baseTopY, baseW, topCapH, 0, G.turretBaseTop, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, baseX, baseTopY, baseW, topCapH)
            nvgFillPaint(vg, p)
            nvgFill(vg)
        end
        -- 中部拉伸（不平铺，避免接缝线）
        if G.turretBaseMid and G.turretBaseMid ~= 0 then
            local p = nvgImagePattern(vg, baseX, midStartY, baseW, midTotalH, 0, G.turretBaseMid, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, baseX, midStartY, baseW, midTotalH)
            nvgFillPaint(vg, p)
            nvgFill(vg)
        end
        -- 底部帽
        if G.turretBaseBot and G.turretBaseBot ~= 0 then
            local p = nvgImagePattern(vg, baseX, botStartY, baseW, botCapH, 0, G.turretBaseBot, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, baseX, botStartY, baseW, botCapH)
            nvgFillPaint(vg, p)
            nvgFill(vg)
        end
    end

    -- 内框尺寸（炮塔上锁 134x119, 炮塔显示框 134x124，缩放到与 iconSize 匹配）
    local frameScale = iconSize / 134      -- 使内框宽 = iconSize
    local lockedFH   = 119 * frameScale    -- 锁定框高度
    local unlockedFH = 124 * frameScale    -- 解锁框高度

    for slotIdx = 1, totalSlots do
        local ix = panelRight - iconSize
        local iy = startY + (slotIdx - 1) * (iconSize + iconGap)
        local turret = slotMap[slotIdx]

        if turret then
            -- ===== 已解锁槽位：炮塔显示框 + 炮塔图标 =====
            local def = Turret.TYPES[turret.typeKey]

            -- 绘制炮塔显示框背景
            local fImg = G.turretFrameImg
            if fImg and fImg ~= 0 then
                local fh = unlockedFH
                local fy = iy + (iconSize - fh) / 2  -- 垂直居中
                local fp = nvgImagePattern(vg, ix, fy, iconSize, fh, 0, fImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, ix, fy, iconSize, fh)
                nvgFillPaint(vg, fp)
                nvgFill(vg)
            end

            -- 炮塔精灵图标（按实际图片比例渲染）
            if def then
                local img = G.turretImgs and G.turretImgs[def.imgKey]
                if img and img ~= 0 then
                    local iw, ih = imgSize(vg, img)
                    local ratio = (iw > 0 and ih > 0) and (ih / iw) or 1.33
                    local sprW = iconSize - 10 * s
                    local sprH = sprW * ratio
                    if sprH > iconSize - 8 * s then
                        sprH = iconSize - 8 * s
                        sprW = sprH / ratio
                    end
                    local ccx = ix + iconSize / 2
                    local ccy = iy + iconSize / 2
                    local dx = ccx - sprW / 2
                    local dy = ccy - sprH / 2
                    local paint = nvgImagePattern(vg, dx, dy, sprW, sprH, 0, img, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, dx, dy, sprW, sprH)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                end
            end

            -- 右下角圆形CD指示器
            if def then
                local cdR = 7 * s
                local cx = ix + iconSize - cdR - 2 * s
                local cy = iy + iconSize - cdR - 2 * s

                if turret.phase == "resting" and turret.phaseTimer then
                    -- ===== 冷却阶段：橙红色大冷却 + 暗色遮罩 =====
                    local restTotal = def.restDuration or 3
                    local ratio = turret.phaseTimer / restTotal
                    if ratio > 1 then ratio = 1 end
                    if ratio < 0 then ratio = 0 end

                    -- 半透明暗色遮罩覆盖炮塔图标
                    nvgBeginPath(vg)
                    nvgRect(vg, ix, iy, iconSize, iconSize)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
                    nvgFill(vg)

                    -- 底圆
                    nvgBeginPath(vg)
                    nvgCircle(vg, cx, cy, cdR)
                    nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
                    nvgFill(vg)

                    -- 扇形
                    local startAngle = -math.pi / 2
                    local endAngle   = startAngle + ratio * math.pi * 2
                    nvgBeginPath(vg)
                    nvgMoveTo(vg, cx, cy)
                    nvgArc(vg, cx, cy, cdR, startAngle, endAngle, NVG_CW)
                    nvgClosePath(vg)
                    nvgFillColor(vg, nvgRGBA(255, 100, 60, 200))
                    nvgFill(vg)

                    -- 外圈
                    nvgBeginPath(vg)
                    nvgCircle(vg, cx, cy, cdR)
                    nvgStrokeColor(vg, nvgRGBA(255, 100, 60, 220))
                    nvgStrokeWidth(vg, 1.0)
                    nvgStroke(vg)

                end
            end

        else
            -- ===== 锁定槽位：炮塔上锁图片 =====
            local lImg = G.turretLockedImg
            if lImg and lImg ~= 0 then
                local fh = lockedFH
                local fy = iy + (iconSize - fh) / 2  -- 垂直居中
                local lp = nvgImagePattern(vg, ix, fy, iconSize, fh, 0, lImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, ix, fy, iconSize, fh)
                nvgFillPaint(vg, lp)
                nvgFill(vg)
            end
        end
    end

    -- ========== 2) 行驶距离竖条（当前关卡进度，从上往下） ==========
    -- 基于炮塔底底部位置计算，避免重叠
    local basePadBar = 5 * s
    local baseScaleBar = (iconSize + basePadBar * 2) / 139
    local topCapHBar  = math.floor(28 * baseScaleBar)
    local botCapHBar  = math.floor(32 * baseScaleBar)
    local slotsAreaHBar = totalSlots * (iconSize + iconGap) - iconGap
    local midTotalHBar  = slotsAreaHBar + basePadBar * 2
    local turretBaseBottom = (startY - basePadBar) + topCapHBar + midTotalHBar + botCapHBar
    local barTopY = turretBaseBottom + 10 * s
    local barH = 150 * s           -- 固定高度，参照参考图比例
    local barW = 10 * s
    local barCenterX = panelRight - iconSize / 2  -- 与图标列居中对齐
    local barX = barCenterX - barW / 2

    -- 波次进度（平滑插值：战斗阶段+间歇阶段连续推进，最后一波结束时到达终点）
    local curWave = math.max(1, G.currentWave or 1)
    local maxWave = G.maxWaves or 10
    local waveDur = G.waveDuration or 30   -- 每波战斗时长
    local restDur = 10                      -- 间歇时长
    local cycleDur = waveDur + restDur      -- 每波完整周期

    -- 已完成的完整波数（当前波之前的波）
    local completedWaves = curWave - 1
    -- 当前波内进度（0~1）
    local inWaveProgress = 0
    if G.waveActive then
        -- 战斗阶段：占周期的前 waveDur/cycleDur 部分
        local wt = G.waveTimer or 0
        inWaveProgress = math.min(1, wt / waveDur) * (waveDur / cycleDur)
    else
        -- 间歇阶段：战斗部分已完成 + 间歇倒计时剩余
        local cd = G.waveCountdown or 0
        local restElapsed = restDur - cd
        inWaveProgress = (waveDur / cycleDur) + math.min(1, restElapsed / restDur) * (restDur / cycleDur)
    end
    local progress = math.min(1, math.max(0, (completedWaves + inWaveProgress) / maxWave))

    -- 条背景（暗色圆角）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barTopY, barW, barH, barW / 2)
    nvgFillColor(vg, nvgRGBA(20, 22, 28, 180))
    nvgFill(vg)

    -- 金色填充（从顶部往下填充）
    local fillH = barH * progress
    if fillH > 1 then
        local goldGrad = nvgLinearGradient(vg, 0, barTopY, 0, barTopY + fillH,
            nvgRGBA(220, 185, 55, 255),
            nvgRGBA(180, 150, 40, 220))
        nvgBeginPath(vg)
        nvgSave(vg)
        nvgScissor(vg, barX, barTopY, barW, fillH)
        nvgRoundedRect(vg, barX, barTopY, barW, barH, barW / 2)
        nvgFillPaint(vg, goldGrad)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 条边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barTopY, barW, barH, barW / 2)
    nvgStrokeColor(vg, nvgRGBA(100, 95, 60, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 白色圆点标记（当前进度位置，在填充末端）
    local dotY = barTopY + fillH
    local dotR = 6 * s
    dotY = math.max(barTopY + dotR, math.min(barTopY + barH - dotR, dotY))
    nvgBeginPath(vg)
    nvgCircle(vg, barCenterX, dotY, dotR)
    nvgFillColor(vg, nvgRGBA(245, 248, 255, 240))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, barCenterX, dotY, dotR)
    nvgStrokeColor(vg, nvgRGBA(160, 165, 180, 180))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)

    -- 波次文字（条下方）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10 * s)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 195, 170, 200))
    local stageNum = G.stage or 1
    nvgText(vg, barCenterX, barTopY + barH + 6 * s, "第" .. stageNum .. "关 " .. curWave .. "/" .. maxWave)
end

------------------------------------------------------------------------
-- 11. 绘制 HUD (深色末日风)
------------------------------------------------------------------------
function R.DrawHUD(vg, G)
    local W = G.screenW
    local hudH = G.hudH
    local cy = hudH / 2
    local s = G.uiScale or 1

    nvgFontFace(vg, "sans")

    -- 资源项定义（直接读取saveData持久化数据，与局外一致）
    local sd = G.saveData
    local items = {
        { img = G.hudIconGold,  count = sd and sd.gold or 0     },
        { img = G.hudIconWood,  count = sd and sd.wood or 0     },
        { img = G.hudIconStone, count = sd and sd.stone or 0    },
        { img = G.hudIconGem,   count = sd and sd.diamond or 0  },
    }

    -- 内框尺寸：统一固定宽度，紧凑排列
    local innerImg = G.hudInnerFrame
    local innerH = hudH - 6 * s       -- 内框高度略小于外框
    local innerW = 68 * s             -- 每个内框统一宽度
    local iconSz = 15 * s
    local gap = 2 * s
    local startX = 6 * s

    -- 资源区域总宽度 = 4个内框 + 3个间距
    local totalResW = innerW * #items + gap * (#items - 1)

    -- 1) 外框底：端盖(局内资源外框) + 中间平铺(图层_7) 组装
    local capImg = G.hudFrameCap
    local midImg = G.hudFrameMid
    local outerPad = 4 * s
    local outerX = startX - outerPad
    local outerW = totalResW + outerPad * 2
    local outerY = 0
    local outerH = hudH

    if capImg and capImg ~= 0 then
        -- 获取端盖原始尺寸，按高度等比缩放
        local capImgW, capImgH = imgSize(vg, capImg)
        local capScale = outerH / capImgH
        local capW = capImgW * capScale

        -- 中间平铺段
        if midImg and midImg ~= 0 then
            local midX = outerX + capW
            local midW = outerW - capW * 2
            if midW > 0 then
                local midImgW, midImgH = imgSize(vg, midImg)
                local midTileW = midImgW * capScale
                local midTileH = midImgH * capScale
                local midPaint = nvgImagePattern(vg, midX, outerY, midTileW, midTileH, 0, midImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, midX, outerY, midW, outerH)
                nvgFillPaint(vg, midPaint)
                nvgFill(vg)
            end
        end

        -- 左端盖
        local capPaint = nvgImagePattern(vg, outerX, outerY, capW, outerH, 0, capImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, outerX, outerY, capW, outerH)
        nvgFillPaint(vg, capPaint)
        nvgFill(vg)

        -- 右端盖（水平镜像）
        nvgSave(vg)
        nvgTranslate(vg, outerX + outerW, 0)
        nvgScale(vg, -1, 1)
        local rCapPaint = nvgImagePattern(vg, 0, outerY, capW, outerH, 0, capImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, outerY, capW, outerH)
        nvgFillPaint(vg, rCapPaint)
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 2) 逐个绘制资源内框 + 图标 + 数字（统一宽度）
    local cx = startX
    for _, item in ipairs(items) do
        local iSz = item.sz or iconSz
        local numStr = tostring(item.count)

        local bx = cx
        local by = cy - innerH / 2

        -- 内框图片作为背景
        if innerImg and innerImg ~= 0 then
            local paint = nvgImagePattern(vg, bx, by, innerW, innerH, 0, innerImg, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, bx, by, innerW, innerH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end

        -- 图标（居左）
        local iconX = bx + 6 * s + iSz / 2
        if item.img and item.img ~= 0 then
            drawSprite(vg, item.img, iconX, cy, iSz, iSz, 1.0)
        end

        -- 数量文字（图标右侧）
        local textX = bx + 6 * s + iSz + 3 * s
        nvgFontSize(vg, 13 * s)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 90))
        nvgText(vg, textX + 0.8, cy + 0.8, numStr, nil)
        nvgFillColor(vg, nvgRGBA(235, 235, 228, 255))
        nvgText(vg, textX, cy, numStr, nil)

        cx = cx + innerW + gap
    end

    -- 3) 设置框底 + 齿轮图标
    local settingsFrameImg = G.hudSettingsFrame
    local sfScale = (hudH - 6 * s) / 60  -- 设置框略小于外框
    local sfSz = 60 * sfScale
    local sfX = W - sfSz - 4 * s
    local sfY = cy - sfSz / 2

    if settingsFrameImg and settingsFrameImg ~= 0 then
        local paint = nvgImagePattern(vg, sfX, sfY, sfSz, sfSz, 0, settingsFrameImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, sfX, sfY, sfSz, sfSz)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    -- 齿轮图标居中在设置框内
    if G.hudSettings and G.hudSettings ~= 0 then
        local gearDrawSz = sfSz * 1.0
        drawSprite(vg, G.hudSettings, sfX + sfSz / 2, cy, gearDrawSz * (658/494), gearDrawSz, 1.0)
    end

    -- 缓存齿轮按钮区域供点击检测
    G.hudSettingBtn = { x = sfX, y = sfY, w = sfSz, h = sfSz }
end

------------------------------------------------------------------------
-- 11b. 绘制波次面板 (左上角，HUD下方)
------------------------------------------------------------------------
function R.DrawWavePanel(vg, G)
    local s = G.uiScale or 1
    -- 面板尺寸按原图 208×119 等比缩放
    local scale = 0.34 * s
    local panelW = 208 * scale
    local panelH = 119 * scale
    local px = 4 * s
    local py = G.hudH + 4 * s

    -- 背景面板图片
    local waveImg = G.waveUIImg
    if waveImg and waveImg ~= 0 then
        local paint = nvgImagePattern(vg, px, py, panelW, panelH, 0, waveImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py, panelW, panelH, 6 * scale)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    end

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 第一行: "波次  3/20"
    local lineY1 = py + panelH * 0.35
    local textX = px + 8 * s

    nvgFontSize(vg, 8 * s)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, textX, lineY1, "波次", nil)

    nvgFontSize(vg, 10 * s)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 255))
    nvgText(vg, textX + 20 * s, lineY1, tostring(math.max(1, G.currentWave or 1)) .. "/" .. tostring(G.maxWaves or 20), nil)

    -- 第二行: "下一波  00:23"
    local lineY2 = py + panelH * 0.7
    local cdLabel = "下一波"
    local cd = G.waveCountdown or 0
    local mins = math.floor(cd / 60)
    local secs = math.floor(cd % 60)
    local timeStr = string.format("%02d:%02d", mins, secs)

    nvgFontSize(vg, 8 * s)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, textX, lineY2, cdLabel .. "  " .. timeStr, nil)

    -- === 击杀数面板（紧贴波次面板下方）===
    local killScale = panelW / 207   -- 与波次面板等宽
    local killW = panelW
    local killH = 70 * killScale
    local killX = px
    local killY = py + panelH + 3 * s

    local killImg = G.killUIImg
    if killImg and killImg ~= 0 then
        local kPaint = nvgImagePattern(vg, killX, killY, killW, killH, 0, killImg, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, killX, killY, killW, killH, 4 * killScale)
        nvgFillPaint(vg, kPaint)
        nvgFill(vg)
    end

    -- 骷髅图标 + "击杀数" + 数字
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local kcY = killY + killH / 2

    nvgFontSize(vg, 8 * s)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, killX + 18 * s, kcY, "击杀数", nil)

    nvgFontSize(vg, 9 * s)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, killX + 44 * s, kcY, tostring(G.killCount or 0), nil)
end

------------------------------------------------------------------------
-- 12. 绘制提示
------------------------------------------------------------------------
function R.DrawHint(vg, G)
    if not G.hintText or G.hintTimer <= 0 then return end
    local W = G.screenW
    local s = G.uiScale or 1
    local alpha = math.min(1, G.hintTimer / 0.5)

    nvgFontFace(vg, "sans")

    local tw = 240 * s
    local th = 28 * s
    local tx = (W - tw) / 2
    local ty = G.hudH + 6 * s

    -- 背景渐变
    local a = math.floor(alpha * 200)
    local bgP = nvgLinearGradient(vg, tx, ty, tx + tw, ty,
        nvgRGBA(30, 38, 52, a), nvgRGBA(40, 48, 60, a))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tx, ty, tw, th, th / 2)
    nvgFillPaint(vg, bgP)
    nvgFill(vg)
    -- 微光边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, tx, ty, tw, th, th / 2)
    nvgStrokeColor(vg, nvgRGBA(80, 100, 140, math.floor(alpha * 60)))
    nvgStrokeWidth(vg, 0.8)
    nvgStroke(vg)

    nvgFontSize(vg, 13 * s)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 212, 235, math.floor(alpha * 245)))
    nvgText(vg, W / 2, ty + th / 2, G.hintText, nil)
end

------------------------------------------------------------------------
-- 13. 绘制菜单
------------------------------------------------------------------------
function R.DrawMenu(vg, G)
    local W, H = G.screenW, G.screenH
    local t = G.gameTime or 0

    -- ======== 1. 全屏背景图 ========
    local bgImg = G.titleBg
    if bgImg and bgImg ~= 0 then
        -- 按宽度铺满，垂直居中偏上（让列车位于画面中间偏下）
        local imgW, imgH = 540, 968
        local scale = math.max(W / imgW, H / imgH)
        local dw = imgW * scale
        local dh = imgH * scale
        local dx = (W - dw) / 2
        local dy = (H - dh) / 2
        local paint = nvgImagePattern(vg, dx, dy, dw, dh, 0, bgImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
    else
        -- 兜底纯色
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillColor(vg, nvgRGBA(12, 14, 22, 255))
        nvgFill(vg)
    end

    -- ======== 2. 上方暗角（让标题更突出）========
    local topVig = nvgLinearGradient(vg, 0, 0, 0, H * 0.25,
        nvgRGBA(8, 10, 18, 200), nvgRGBA(8, 10, 18, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H * 0.25)
    nvgFillPaint(vg, topVig)
    nvgFill(vg)

    -- 下方暗角（按钮区域）
    local botVig = nvgLinearGradient(vg, 0, H * 0.65, 0, H,
        nvgRGBA(8, 10, 18, 0), nvgRGBA(8, 10, 18, 220))
    nvgBeginPath(vg)
    nvgRect(vg, 0, H * 0.65, W, H * 0.35)
    nvgFillPaint(vg, botVig)
    nvgFill(vg)

    -- ======== 3. 飘雪粒子（预生成数据，不污染随机种子）========
    if not R._snowData then
        local _rdt = os.date("*t")
        local oldSeed = ((_rdt.hour or 0) * 3600 + (_rdt.min or 0) * 60 + (_rdt.sec or 0))
                      * ((_rdt.yday or 1) + 1)
        math.randomseed(42)
        R._snowData = {}
        for i = 1, 30 do
            R._snowData[i] = {
                xr = math.random() * 1.0,
                yr = math.random() * 1.0,
                spd = 15 + math.random() * 20,
                sr = 1 + math.random() * 2,
                sa = 80 + math.random(80),
            }
        end
        math.randomseed(oldSeed)
    end
    for i = 1, 30 do
        local sd = R._snowData[i]
        local sx = sd.xr * W
        local sy = (sd.yr * H + t * sd.spd) % (H + 10) - 5
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, sd.sr)
        nvgFillColor(vg, nvgRGBA(210, 225, 240, sd.sa))
        nvgFill(vg)
    end

    local s = G.uiScale or 1
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- ======== 4. 游戏标题 ========
    local titleY = H * 0.12

    -- 大标题阴影
    nvgFontSize(vg, 28 * s)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgText(vg, W / 2 + 2, titleY + 2, "末世：我开火车送快递")

    -- 大标题
    nvgFillColor(vg, nvgRGBA(230, 240, 255, 255))
    nvgText(vg, W / 2, titleY, "末世：我开火车送快递")

    -- 装饰分割线
    local lineW = 90 * s
    nvgBeginPath(vg)
    nvgMoveTo(vg, W / 2 - lineW / 2, titleY + 24 * s)
    nvgLineTo(vg, W / 2 + lineW / 2, titleY + 24 * s)
    nvgStrokeColor(vg, nvgRGBA(200, 70, 50, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 菱形装饰
    local diaY = titleY + 24 * s
    nvgBeginPath(vg)
    nvgMoveTo(vg, W / 2, diaY - 3.5 * s)
    nvgLineTo(vg, W / 2 + 3.5 * s, diaY)
    nvgLineTo(vg, W / 2, diaY + 3.5 * s)
    nvgLineTo(vg, W / 2 - 3.5 * s, diaY)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(200, 70, 50, 200))
    nvgFill(vg)

    -- 副标题
    nvgFontSize(vg, 18 * s)
    nvgFillColor(vg, nvgRGBA(220, 80, 60, 255))
    nvgText(vg, W / 2, titleY + 46 * s, "末日求生")

    -- 描述
    nvgFontSize(vg, 11 * s)
    nvgFillColor(vg, nvgRGBA(160, 175, 200, 200))
    nvgText(vg, W / 2, titleY + 68 * s, "搜集物资 · 驱赶丧尸 · 升级强化")

    -- ======== 5. 开始按钮 ========
    local btnW = 170 * s
    local btnH = 48 * s
    local btnX = (W - btnW) / 2
    local btnY = H * 0.78
    local pulse = 0.88 + math.sin(t * 2.5) * 0.12

    -- 按钮外发光
    local glowP = nvgRadialGradient(vg, W / 2, btnY + btnH / 2, btnW * 0.3, btnW * 0.7,
        nvgRGBA(60, 130, 220, math.floor(pulse * 40)), nvgRGBA(60, 130, 220, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX - 20, btnY - 12, btnW + 40, btnH + 24, 22)
    nvgFillPaint(vg, glowP)
    nvgFill(vg)

    -- 按钮渐变填充
    local btnP = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
        nvgRGBA(55, 120, 210, math.floor(pulse * 255)),
        nvgRGBA(35, 85, 165, math.floor(pulse * 255)))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 12)
    nvgFillPaint(vg, btnP)
    nvgFill(vg)

    -- 按钮描边
    nvgStrokeColor(vg, nvgRGBA(110, 180, 255, math.floor(pulse * 90)))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    -- 按钮高光
    nvgBeginPath(vg)
    nvgMoveTo(vg, btnX + 22, btnY + 1)
    nvgLineTo(vg, btnX + btnW - 22, btnY + 1)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 50))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 按钮文字
    nvgFontSize(vg, 20 * s)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, W / 2, btnY + btnH / 2, "开始生存")

    G.menuBtn = { x = btnX, y = btnY, w = btnW, h = btnH }

    -- ======== 6. 底部版本号 ========
    nvgFontSize(vg, 10 * s)
    nvgFillColor(vg, nvgRGBA(100, 110, 130, 120))
    nvgText(vg, W / 2, H - 16, "v1.0.0")
end

------------------------------------------------------------------------
-- 14. 绘制 Game Over 屏幕
------------------------------------------------------------------------
function R.DrawGameOver(vg, G)
    local W, H = G.screenW, G.screenH
    local t = G.gameTime or 0
    local s = G.uiScale or 1

    -- ===== 胜利画面 =====
    if G.gameWin then
        -- 金色光晕覆盖
        local overlayP = nvgRadialGradient(vg, W / 2, H * 0.3, 40, H * 0.7,
            nvgRGBA(80, 60, 10, 200), nvgRGBA(10, 12, 8, 235))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, W, H)
        nvgFillPaint(vg, overlayP)
        nvgFill(vg)

        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        local titleY = H * 0.16
        local pulse = 0.85 + math.sin(t * 1.8) * 0.15

        -- 标题阴影
        nvgFontSize(vg, 32 * s)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 140))
        nvgText(vg, W / 2 + 2, titleY + 2, "列车幸存！", nil)
        -- 标题金色
        nvgFillColor(vg, nvgRGBA(255, 210, 60, 255))
        nvgText(vg, W / 2, titleY, "列车幸存！", nil)

        -- 装饰线
        local lineW = 80 * s
        nvgBeginPath(vg)
        nvgMoveTo(vg, W / 2 - lineW / 2, titleY + 20 * s)
        nvgLineTo(vg, W / 2 + lineW / 2, titleY + 20 * s)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 60, 100))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        nvgFontSize(vg, 13 * s)
        nvgFillColor(vg, nvgRGBA(200, 230, 170, 210))
        nvgText(vg, W / 2, titleY + 38 * s, "成功抵御所有" .. (G.maxWaves or 10) .. "波攻击，列车平安抵达！", nil)

        -- 统计卡片
        local stats = {
            { "存活波次", "全部 " .. (G.maxWaves or 10) .. " 波" },
            { "行驶距离", math.floor((G.distance or 0) / 10) .. "m" },
            { "金币获得", tostring(G.gold or 0) },
            { "木材采集", tostring((G.totalRes and G.totalRes.wood) or 0) },
            { "岩石采集", tostring((G.totalRes and G.totalRes.stone) or 0) },
            { "矿石采集", tostring((G.totalRes and G.totalRes.ore) or 0) },
        }

        local lineH = 22 * s
        local cardW = math.min(W * 0.65, 300 * s)
        local cardH = #stats * lineH + 16 * s
        local cardX = (W - cardW) / 2
        local cardY = titleY + 55 * s

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 8)
        nvgFillColor(vg, nvgRGBA(15, 18, 10, 160))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 8)
        nvgStrokeColor(vg, nvgRGBA(180, 160, 60, 60))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        for i, st in ipairs(stats) do
            local sy = cardY + 8 * s + (i - 1) * lineH + lineH / 2
            if i % 2 == 0 then
                nvgBeginPath(vg)
                nvgRect(vg, cardX + 4, sy - lineH / 2, cardW - 8, lineH)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 6))
                nvgFill(vg)
            end
            nvgFontSize(vg, 12 * s)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(170, 160, 130, 200))
            nvgText(vg, W / 2 - 6 * s, sy, st[1], nil)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 230, 130, 240))
            nvgText(vg, W / 2 + 6 * s, sy, st[2], nil)
        end

        -- 返回大厅按钮（金色）
        local btnW = 155 * s
        local btnH = 44 * s
        local btnX = (W - btnW) / 2
        local btnY = cardY + cardH + 20 * s

        local glowP = nvgRadialGradient(vg, W / 2, btnY + btnH / 2, btnW * 0.3, btnW * 0.7,
            nvgRGBA(200, 170, 50, math.floor(pulse * 35)), nvgRGBA(200, 170, 50, 0))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX - 15, btnY - 10, btnW + 30, btnH + 20, 20)
        nvgFillPaint(vg, glowP)
        nvgFill(vg)

        local btnP = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
            nvgRGBA(195, 160, 40, math.floor(pulse * 255)),
            nvgRGBA(150, 120, 25, math.floor(pulse * 255)))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 10)
        nvgFillPaint(vg, btnP)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 10)
        nvgStrokeColor(vg, nvgRGBA(255, 220, 80, math.floor(pulse * 80)))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)

        nvgFontSize(vg, 19 * s)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, W / 2, btnY + btnH / 2, "返回大厅", nil)

        G.restartBtn = { x = btnX, y = btnY, w = btnW, h = btnH }
        return
    end

    -- ===== 失败画面 =====
    -- 暗红色径向覆盖
    local overlayP = nvgRadialGradient(vg, W / 2, H * 0.3, 40, H * 0.6,
        nvgRGBA(55, 18, 18, 200), nvgRGBA(15, 8, 8, 235))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, H)
    nvgFillPaint(vg, overlayP)
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local titleY = H * 0.18

    -- 标题阴影
    nvgFontSize(vg, 30 * s)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 120))
    nvgText(vg, W / 2 + 1.5, titleY + 1.5, "列车沦陷", nil)
    -- 标题
    nvgFillColor(vg, nvgRGBA(230, 65, 55, 255))
    nvgText(vg, W / 2, titleY, "列车沦陷", nil)

    -- 装饰线
    local lineW = 70 * s
    nvgBeginPath(vg)
    nvgMoveTo(vg, W / 2 - lineW / 2, titleY + 18 * s)
    nvgLineTo(vg, W / 2 + lineW / 2, titleY + 18 * s)
    nvgStrokeColor(vg, nvgRGBA(200, 80, 60, 80))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)

    nvgFontSize(vg, 13 * s)
    nvgFillColor(vg, nvgRGBA(190, 170, 150, 200))
    nvgText(vg, W / 2, titleY + 34 * s, "装甲列车被丧尸摧毁了...", nil)

    -- 统计卡片背景
    local stats = {
        { "存活记录", "第" .. (G.stage or 1) .. "关 第" .. math.max(1, G.currentWave or 1) .. "波" },
        { "行驶距离", math.floor((G.distance or 0) / 10) .. "m" },
        { "金币获得", tostring(G.gold or 0) },
        { "木材采集", tostring((G.totalRes and G.totalRes.wood) or 0) },
        { "岩石采集", tostring((G.totalRes and G.totalRes.stone) or 0) },
        { "矿石采集", tostring((G.totalRes and G.totalRes.ore) or 0) },
        { "灌木采集", tostring((G.totalRes and G.totalRes.bush) or 0) },
        { "碎石采集", tostring((G.totalRes and G.totalRes.pebble) or 0) },
    }

    local lineH = 22 * s
    local cardW = math.min(W * 0.65, 300 * s)
    local cardH = #stats * lineH + 16 * s
    local cardX = (W - cardW) / 2
    local cardY = titleY + 52 * s
    -- 卡片背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 8)
    nvgFillColor(vg, nvgRGBA(20, 18, 15, 160))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 8)
    nvgStrokeColor(vg, nvgRGBA(160, 80, 60, 50))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 统计行
    for i, st in ipairs(stats) do
        local sy = cardY + 8 * s + (i - 1) * lineH + lineH / 2
        -- 奇偶行微差异
        if i % 2 == 0 then
            nvgBeginPath(vg)
            nvgRect(vg, cardX + 4, sy - lineH / 2, cardW - 8, lineH)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 6))
            nvgFill(vg)
        end
        nvgFontSize(vg, 12 * s)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(170, 160, 145, 200))
        nvgText(vg, W / 2 - 6 * s, sy, st[1], nil)

        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 225, 170, 240))
        nvgText(vg, W / 2 + 6 * s, sy, st[2], nil)
    end

    -- 重新开始按钮（与菜单按钮风格统一）
    local btnW = 155 * s
    local btnH = 44 * s
    local btnX = (W - btnW) / 2
    local btnY = cardY + cardH + 20 * s
    local pulse = 0.88 + math.sin(t * 2.5) * 0.12

    -- 外发光
    local glowP = nvgRadialGradient(vg, W / 2, btnY + btnH / 2, btnW * 0.3, btnW * 0.7,
        nvgRGBA(190, 65, 50, math.floor(pulse * 30)), nvgRGBA(190, 65, 50, 0))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX - 15, btnY - 10, btnW + 30, btnH + 20, 20)
    nvgFillPaint(vg, glowP)
    nvgFill(vg)

    -- 渐变填充
    local btnP = nvgLinearGradient(vg, btnX, btnY, btnX, btnY + btnH,
        nvgRGBA(195, 65, 50, math.floor(pulse * 255)),
        nvgRGBA(155, 45, 35, math.floor(pulse * 255)))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 10)
    nvgFillPaint(vg, btnP)
    nvgFill(vg)
    -- 描边
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 10)
    nvgStrokeColor(vg, nvgRGBA(230, 110, 90, math.floor(pulse * 70)))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)
    -- 顶部高光
    nvgBeginPath(vg)
    nvgMoveTo(vg, btnX + 20, btnY + 1)
    nvgLineTo(vg, btnX + btnW - 20, btnY + 1)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 35))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontSize(vg, 19 * s)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, W / 2, btnY + btnH / 2, "再次挑战", nil)

    G.restartBtn = { x = btnX, y = btnY, w = btnW, h = btnH }
end

------------------------------------------------------------------------
-- 技能按钮 (摇杆左右两侧)
-- 结构：外框(skillFrameImg) → 内部图标(铺满) → 冷却遮罩
------------------------------------------------------------------------
function R.DrawSkillButtons(vg, G)
    local W = G.screenW or 390
    local H = G.screenH or 844

    local frameImg = G.skillFrameImg       -- 金属环形外框（两按钮共用）
    local boardImg = G.skillBoardTrainImg   -- 上车图标（绿色圆）
    local bombImg  = G.skillBombImg         -- 炸弹图标（红色圆）

    -- ===== 统一尺寸与对称布局 =====
    local btnSize   = 58                   -- 按钮整体尺寸（外框 = 图标 = 同尺寸）
    local margin    = 28                   -- 距屏幕边缘
    local btnY      = H - 128             -- 垂直位置（底部摇杆区域）
    local leftX     = margin + btnSize / 2           -- 左按钮中心 X
    local rightX    = W - margin - btnSize / 2       -- 右按钮中心 X（对称）

    -- ===== 通用按钮绘制 =====
    local function drawSkillBtn(cx, cy, icon, cd, cdMax, glowColor, isActive, label)
        local alpha = (cd > 0 and not isActive) and 0.45 or 1.0

        -- 阴影
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy + 2, btnSize / 2 + 1)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 50))
        nvgFill(vg)

        -- 激活发光
        if isActive then
            local pulse = 0.6 + math.sin((G.gameTime or 0) * 5) * 0.4
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy, btnSize / 2 + 8)
            nvgFillColor(vg, nvgRGBA(glowColor[1], glowColor[2], glowColor[3], math.floor(pulse * 90)))
            nvgFill(vg)
        end

        -- 1) 图标铺满（底层）
        if icon and icon ~= 0 then
            drawSprite(vg, icon, cx, cy, btnSize, btnSize, alpha)
        end

        -- 2) 金属外框叠加（顶层）
        if frameImg and frameImg ~= 0 then
            drawSprite(vg, frameImg, cx, cy, btnSize, btnSize, alpha)
        end

        -- 3) 冷却扇形遮罩
        if cd > 0 then
            local ratio = cd / cdMax
            local startA = -math.pi / 2
            local sweepA = ratio * math.pi * 2
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx, cy)
            nvgArc(vg, cx, cy, btnSize / 2 - 4, startA, startA + sweepA, NVG_CW)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
            nvgFill(vg)
            -- CD 数字
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 20)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgText(vg, cx, cy, string.format("%.0f", math.ceil(cd)), nil)
        end

        -- 4) 底部标签
        if label then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgText(vg, cx, cy + btnSize / 2 + 3, label, nil)
        end
    end

    -- ===== 左侧：上车按钮 =====
    local boardCD    = G.skillBoardCD or 0
    local boardCDMax = G.skillBoardCDMax or 5

    -- 靠近列车呼吸提示
    if G.nearTrain and not G.mounted and boardCD <= 0 then
        local pulse = 0.7 + math.sin((G.gameTime or 0) * 4) * 0.3
        nvgBeginPath(vg)
        nvgCircle(vg, leftX, btnY, btnSize / 2 + 8)
        nvgFillColor(vg, nvgRGBA(80, 220, 120, math.floor(pulse * 80)))
        nvgFill(vg)
    end

    local leftCD    = G.mounted and 0 or boardCD
    local leftLabel = G.mounted and "下车" or nil
    -- 已上车：下车图标；靠近火车：绿色上车图标；否则：不可用灰色图标
    local leftIcon
    if G.mounted then
        leftIcon = G.skillDismountImg or boardImg
    elseif G.nearTrain then
        leftIcon = boardImg
    else
        leftIcon = G.skillBoardDisabledImg
    end
    drawSkillBtn(leftX, btnY, leftIcon, leftCD, boardCDMax, {80, 220, 120}, false, leftLabel)

    G.skillBoardBtn = { x = leftX - btnSize / 2, y = btnY - btnSize / 2, w = btnSize, h = btnSize }

    -- ===== 右侧：角色技能按钮 =====
    local charCD    = G.skillCharCD or 0
    local charCDMax = G.skillCharCDMax or 15

    -- 按当前角色选择对应技能图标
    local charSkillIcon = bombImg  -- 默认（warrior）
    local charId = G.activeCharId or "warrior"
    if G.skillIconImgs and G.skillIconImgs[charId] and G.skillIconImgs[charId] ~= 0 then
        charSkillIcon = G.skillIconImgs[charId]
    end

    drawSkillBtn(rightX, btnY, charSkillIcon, charCD, charCDMax, {255, 180, 50}, G.skillCharActive, nil)

    -- 技能持续时间条
    if G.skillCharActive and G.skillCharDuration > 0 and G.skillCharDurationMax > 0 then
        local barW = btnSize
        local barH = 5
        local barX = rightX - barW / 2
        local barY = btnY + btnSize / 2 + 4
        local ratio = G.skillCharDuration / G.skillCharDurationMax
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 2)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * ratio, barH, 2)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 220))
        nvgFill(vg)
    end

    G.skillCharBtn = { x = rightX - btnSize / 2, y = btnY - btnSize / 2, w = btnSize, h = btnSize }
end

------------------------------------------------------------------------
-- 瞄准锥形（上车状态，从玩家位置向瞄准方向展开夹角扇形）
------------------------------------------------------------------------
function R.DrawAimLine(vg, G)
    if not G.mounted or not G.mountedAimActive then return end

    local p = G.player
    local angle = G.mountedAimDir or 0
    local cx = p.x
    local cy = p.y

    local coneLen    = 140    -- 锥形长度
    local halfAngle  = 0.22   -- 半角（弧度，约12.5°）
    local startDist  = 14     -- 起始偏移

    local fillAlpha  = 40
    local lineAlpha  = 160

    -- 两条边线角度
    local a1 = angle - halfAngle
    local a2 = angle + halfAngle

    -- 扇形填充（半透明）
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + math.cos(a1) * startDist, cy + math.sin(a1) * startDist)
    nvgLineTo(vg, cx + math.cos(a1) * coneLen, cy + math.sin(a1) * coneLen)
    -- 弧线连接
    local arcSteps = 8
    for i = 1, arcSteps do
        local t = i / arcSteps
        local a = a1 + (a2 - a1) * t
        nvgLineTo(vg, cx + math.cos(a) * coneLen, cy + math.sin(a) * coneLen)
    end
    nvgLineTo(vg, cx + math.cos(a2) * startDist, cy + math.sin(a2) * startDist)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 255, 200, fillAlpha))
    nvgFill(vg)

    -- 两条边线
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 220, lineAlpha))
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + math.cos(a1) * startDist, cy + math.sin(a1) * startDist)
    nvgLineTo(vg, cx + math.cos(a1) * coneLen,   cy + math.sin(a1) * coneLen)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + math.cos(a2) * startDist, cy + math.sin(a2) * startDist)
    nvgLineTo(vg, cx + math.cos(a2) * coneLen,   cy + math.sin(a2) * coneLen)
    nvgStroke(vg)
end

------------------------------------------------------------------------
-- 炸弹绘制 (落地炸弹 + 倒计时抖动)
------------------------------------------------------------------------
function R.DrawBombs(vg, G)
    local img = G.bombImg
    if not img or img == 0 then return end
    local t = G.gameTime or 0

    -- 获取炸弹图片原始尺寸（保持比例）
    local imgW, imgH = imgSize(vg, img)
    if imgW <= 0 then imgW = 1 end
    if imgH <= 0 then imgH = 1 end
    local aspect = imgW / imgH  -- 宽高比

    for _, b in ipairs(G.bombs or {}) do
        if b.y < (G.renderTopY or 0) - 80 or b.y > G.screenH + 80 then goto cont_bomb end
        local radius = b.radius or 45  -- 爆炸范围半径
        local bombH = 12               -- 炸弹绘制高度（半值）
        local bombW = bombH * aspect   -- 按原始比例计算宽度

        -- 倒计时进度 0→1
        local fuseRatio = math.max(0, math.min(1, 1 - b.fuseTimer / 1.5))

        -- 倒计时抖动：剩余时间越短越剧烈
        local shake = 0
        if b.fuseTimer < 0.6 then
            shake = math.sin((b.bobPhase or 0) * 3) * (1 - b.fuseTimer / 0.6) * 3
        end
        local dx = b.x + shake
        local dy = b.y

        -- 1) 爆炸范围圈（半透明填充 + 边缘光环）
        local pulse = 1.0 + math.sin(t * 8) * 0.03 * fuseRatio
        local drawR = radius * pulse

        local alpha = math.floor(20 + fuseRatio * 30)
        nvgBeginPath(vg)
        nvgCircle(vg, b.x, b.y, drawR)
        nvgFillColor(vg, nvgRGBA(255, 80, 60, alpha))
        nvgFill(vg)

        local ringAlpha = math.floor(60 + fuseRatio * 120)
        nvgBeginPath(vg)
        nvgCircle(vg, b.x, b.y, drawR)
        nvgStrokeWidth(vg, 1.5 + fuseRatio * 1.0)
        nvgStrokeColor(vg, nvgRGBA(255, 120, 100, ringAlpha))
        nvgStroke(vg)

        -- 2) 炸弹小图标（保持原始比例）
        nvgBeginPath(vg)
        nvgEllipse(vg, dx, dy + bombH * 0.4, bombW * 0.45, bombH * 0.1)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 40))
        nvgFill(vg)

        -- 选择当前帧：普通 or 红帧交替闪烁
        local curImg = img
        if fuseRatio > 0.2 then
            local freq = 4 + fuseRatio * 8
            local flash = math.sin(t * freq * 6.28)
            if flash > 0 and G.bombRedImg and G.bombRedImg ~= 0 then
                curImg = G.bombRedImg
            end
        end

        local paint = nvgImagePattern(vg, dx - bombW, dy - bombH, bombW * 2, bombH * 2, 0, curImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, dx - bombW, dy - bombH, bombW * 2, bombH * 2)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        ::cont_bomb::
    end
end

------------------------------------------------------------------------
-- 爆炸特效绘制 (帧动画)
------------------------------------------------------------------------
function R.DrawExplosions(vg, G)
    local frames = G.explosionFrames
    if not frames or #frames == 0 then return end
    for _, e in ipairs(G.explosions or {}) do
        local fi = math.max(1, math.min(e.frame, #frames))
        local fimg = frames[fi]
        if not fimg or fimg == 0 then goto cont_exp end
        local sz = (e.radius or 45) * 3.0  -- 爆炸特效比范围圈更大
        local paint = nvgImagePattern(vg, e.x - sz, e.y - sz, sz * 2, sz * 2, 0, fimg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, e.x - sz, e.y - sz, sz * 2, sz * 2)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        ::cont_exp::
    end
end

return R

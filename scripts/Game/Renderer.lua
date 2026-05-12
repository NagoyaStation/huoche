-- Game/Renderer.lua - NanoVG 渲染：雪国列车末日求生
local C = require "Game.Config"
local Ent = require "Game.Entities"
local Turret = require "Game.Turret"
local R = {}

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
    G.cartW = 90
    G.cartH = 215
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

    -- 预计算采样点
    local pts = {}
    for sy = G.renderTopY, H + step, step do
        local worldY = sy + scrollY
        local pathL, pathR, cx = Ent.GetPathBounds(W, worldY)
        pts[#pts + 1] = { y = sy, l = pathL, r = pathR, cx = cx }
    end
    local n = #pts
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
    local railSep = G.railSep or 36
    local railW = 3.5

    -- 道碴底层 → 横向渐变路基（中间稍亮，两侧暗）
    local ballastW = railSep + 24
    local blR, blG, blB = C.CLR.ballast_color[1], C.CLR.ballast_color[2], C.CLR.ballast_color[3]
    do
        local ballastPaint = nvgLinearGradient(vg, cx - ballastW / 2, 0, cx + ballastW / 2, 0,
            nvgRGBA(blR - 5, blG - 5, blB - 5, 50),
            nvgRGBA(blR + 5, blG + 5, blB + 3, 70))
        nvgBeginPath(vg)
        nvgRect(vg, cx - ballastW / 2, G.renderTopY, ballastW, H - G.renderTopY)
        nvgFillPaint(vg, ballastPaint)
        nvgFill(vg)
    end

    -- 枕木 (随世界滚动) → 渐变 + 轮廓
    local sleeperW = railSep + 20
    local sleeperH = 7
    local sleeperSpacing = 26
    local offset = sleeperSpacing - (scrollY % sleeperSpacing)
    local slR, slG, slB = C.CLR.sleeper_color[1], C.CLR.sleeper_color[2], C.CLR.sleeper_color[3]

    for sy = G.renderTopY - sleeperH + offset, H + sleeperH, sleeperSpacing do
        -- 枕木主体 → 上亮下暗渐变
        do
            local sleeperPaint = nvgLinearGradient(vg, 0, sy, 0, sy + sleeperH,
                nvgRGBA(slR + 12, slG + 10, slB + 8, 255),
                nvgRGBA(slR - 10, slG - 12, slB - 8, 255))
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx - sleeperW / 2, sy, sleeperW, sleeperH, 1.5)
            nvgFillPaint(vg, sleeperPaint)
            nvgFill(vg)
            -- 枕木轮廓
            nvgStrokeColor(vg, nvgRGBA(slR - 20, slG - 22, slB - 18, 60))
            nvgStrokeWidth(vg, 0.6)
            nvgStroke(vg)
        end
    end

    -- 钢轨 (两根平行) → 横向渐变 + 高光条
    for _, side in ipairs({-1, 1}) do
        local rx = cx + side * railSep / 2 - railW / 2
        -- 轨道主体 → 横向渐变（左亮右暗，柱面感）
        do
            local railPaint = nvgLinearGradient(vg, rx, 0, rx + railW, 0,
                nvgRGBA(C.CLR.rail_color[1] + 10, C.CLR.rail_color[2] + 8, C.CLR.rail_color[3] + 6, 255),
                nvgRGBA(C.CLR.rail_color[1] - 8, C.CLR.rail_color[2] - 10, C.CLR.rail_color[3] - 8, 255))
            nvgBeginPath(vg)
            nvgRect(vg, rx, G.renderTopY, railW, H - G.renderTopY)
            nvgFillPaint(vg, railPaint)
            nvgFill(vg)
        end
        -- 轨道高光条（偏左中心亮线，金属反光）
        nvgBeginPath(vg)
        nvgRect(vg, rx + 0.8, G.renderTopY, 0.8, H - G.renderTopY)
        nvgFillColor(vg, nvgRGBA(C.CLR.rail_light[1], C.CLR.rail_light[2], C.CLR.rail_light[3], 90))
        nvgFill(vg)
        -- 轨道右侧暗边
        nvgBeginPath(vg)
        nvgRect(vg, rx + railW - 0.5, G.renderTopY, 0.5, H - G.renderTopY)
        nvgFillColor(vg, nvgRGBA(C.CLR.rail_color[1] - 20, C.CLR.rail_color[2] - 22, C.CLR.rail_color[3] - 18, 80))
        nvgFill(vg)
    end

    -- 碎石纹理点缀 → 径向渐变微光斑
    local gSeed = math.floor(scrollY * 0.05) % 50
    for i = 0, 10 do
        local gx = cx + ((i * 11 + gSeed * 7) % math.floor(ballastW)) - ballastW / 2
        local gy = G.renderTopY + ((i * 53 + gSeed * 19) % math.floor(H - G.renderTopY))
        local gr = 1 + (i % 3) * 0.6
        do
            local gravelPaint = nvgRadialGradient(vg, gx, gy, 0, gr,
                nvgRGBA(blR + 10, blG + 8, blB + 5, 55),
                nvgRGBA(blR, blG, blB, 0))
            nvgBeginPath(vg)
            nvgCircle(vg, gx, gy, gr * 1.4)
            nvgFillPaint(vg, gravelPaint)
            nvgFill(vg)
        end
    end

    -- 铁轨两侧碎石边缘渐变
    local edgeW = 8
    for _, side in ipairs({-1, 1}) do
        local bx = cx + side * ballastW / 2
        do
            local grad
            if side == -1 then
                grad = nvgLinearGradient(vg, bx - edgeW, 0, bx, 0,
                    nvgRGBA(blR, blG, blB, 0),
                    nvgRGBA(blR, blG, blB, 40))
            else
                grad = nvgLinearGradient(vg, bx, 0, bx + edgeW, 0,
                    nvgRGBA(blR, blG, blB, 40),
                    nvgRGBA(blR, blG, blB, 0))
            end
            nvgBeginPath(vg)
            nvgRect(vg, side == -1 and (bx - edgeW) or bx, G.renderTopY, edgeW, H - G.renderTopY)
            nvgFillPaint(vg, grad)
            nvgFill(vg)
        end
    end
end

------------------------------------------------------------------------
-- 3. 绘制装饰物 (枯树、雪堆、残骸)
------------------------------------------------------------------------
function R.DrawDecorations(vg, G)
    -- 装饰物已移除
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
        local cDrawX = cx - cDrawW / 2 + cVibeX
        local cDrawY = topY - 5 - cDrawH + 32 + cVibeY

        local cPaint = nvgImagePattern(vg, cDrawX, cDrawY, cDrawW, cDrawH, 0, carriageImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, cDrawX, cDrawY, cDrawW, cDrawH)
        nvgFillPaint(vg, cPaint)
        nvgFill(vg)
    end

    -- === 火车精灵 ===
    local trainImg = G.trainImg
    if trainImg and trainImg ~= 0 then
        -- 保持原图比例 (207x308)
        local drawH = ch + 20
        local drawW = drawH * 207 / 308

        -- 引擎震动效果 (微小抖动，模拟蒸汽机运转)
        local vibeX = math.sin(t * 25) * 0.4
        local vibeY = math.sin(t * 30) * 0.3

        local drawX = cx - drawW / 2 + vibeX
        local drawY = topY - 5 + vibeY

        local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, trainImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, drawX, drawY, drawW, drawH)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    end

    -- === 程序化烟雾粒子 (绘制在火车上层，向车尾后方飘散) ===
    do
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
-- 5. 绘制提交方块 (固定正方形方块 — 列车下方)
------------------------------------------------------------------------
function R.DrawSubmitBox(vg, G)
    local sb = G.submitBox
    local t = G.gameTime or 0
    local sw = C.SUBMIT_BOX_W
    local sh = C.SUBMIT_BOX_H
    local sx = sb.x - sw / 2
    local sy = sb.y - sh / 2
    local pulse = math.sin(t * 3) * 0.15 + 0.85

    -- 投影
    do
        local shP = nvgRadialGradient(vg, sb.x, sb.y + sh / 2 + 3, 4, sw * 0.4,
            nvgRGBA(0, 0, 0, 40), nvgRGBA(0, 0, 0, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, sb.x, sb.y + sh / 2 + 3, sw * 0.4, 4)
        nvgFillPaint(vg, shP)
        nvgFill(vg)
    end

    -- 方块背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, 8)
    nvgFillColor(vg, clr(C.CLR.submit_bg))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, 8)
    nvgStrokeColor(vg, clr(C.CLR.submit_border, math.floor(pulse * 180)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 进度条
    local ratio = math.min(1, G.levelProgress / math.max(1, G.levelTarget))
    local barH = 4
    local barW = sw - 8
    local barX = sx + 4
    local barY = sy + sh - barH - 4

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 2)
    nvgFillColor(vg, nvgRGBA(15, 15, 15, 160))
    nvgFill(vg)

    if ratio > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * ratio, barH, 2)
        nvgFillColor(vg, clr(C.CLR.submit_full))
        nvgFill(vg)
    end

    -- 进度文字
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, clr(C.CLR.text_white))
    nvgText(vg, sb.x, sb.y - 2, G.levelProgress .. "/" .. G.levelTarget, nil)
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
        if r.rtype == "wood" then
            -- 用bobPhase决定随机选哪棵树
            local treeIdx = (math.floor(r.bobPhase * 10) % 3) + 1
            img = woodImgs[treeIdx]
            drawSz = sz * 7.2  -- 树木再放大1.5倍 (4.8 * 1.5)
        elseif r.rtype == "stone" then
            img = stoneImg
        elseif r.rtype == "ore" then
            img = oreImg
        elseif r.rtype == "bush" then
            img = bushImg
            drawSz = sz * 4.0  -- 灌木比树小
        elseif r.rtype == "pebble" then
            img = pebbleImg
            drawSz = sz * 3.0  -- 小石头更小
        end

        if img and img ~= 0 then
            -- 受击闪白效果：叠加白色半透明层
            if hitFlash then
                -- 先绘制精灵
                drawSprite(vg, img, drawX, ry, drawSz, drawSz, 1.0)
                -- 叠加白色闪光
                nvgBeginPath(vg)
                nvgCircle(vg, drawX, ry, drawSz * 0.45)
                nvgFillColor(vg, nvgRGBA(255, 255, 255, 140))
                nvgFill(vg)
            else
                drawSprite(vg, img, drawX, ry, drawSz, drawSz, 1.0)
            end

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

                -- 十字微光
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

        -- 血条 (HP < maxHp 时显示)
        if r.hp and r.maxHp and r.hp < r.maxHp and r.hp > 0 then
            local barW = 24 * sc
            local barH = 3
            local bx = drawX - barW / 2
            local by = ry - drawSz / 2 - 4
            local ratio = r.hp / r.maxHp
            -- 背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, barW, barH, 1)
            nvgFillColor(vg, nvgRGBA(30, 30, 30, 160))
            nvgFill(vg)
            -- 填充
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, barW * ratio, barH, 1)
            nvgFillColor(vg, nvgRGBA(80, 200, 80, 220))
            nvgFill(vg)
        end

        ::continue_res::
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

    nvgSave(vg)
    nvgTranslate(vg, px, py)

    -- 柔阴影 (径向渐变)
    do
        local shadowPaint = nvgRadialGradient(vg, 3, C.PLAYER_H / 2 + 3, 2, 16,
            nvgRGBA(10, 12, 8, 70), nvgRGBA(10, 12, 8, 0))
        nvgBeginPath(vg)
        nvgEllipse(vg, 3, C.PLAYER_H / 2 + 3, 16, 7)
        nvgFillPaint(vg, shadowPaint)
        nvgFill(vg)
    end

    -- 翻转
    if p.facing < 0 then nvgScale(vg, -1, 1) end

    -- 无敌闪烁
    local stunAlpha = 255
    if p.stunTimer and p.stunTimer > 0 then
        stunAlpha = math.sin(t * 16) > 0 and 255 or 100
    end

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
        local imgW, imgH = nvgImageSize(vg, frameImg)
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

    -- 背包 (携带物品时显示，渐变 + 描边)
    if p.carrying > 0 then
        local bagX = -C.PLAYER_W / 2 - 6
        local bagPaint = nvgLinearGradient(vg, bagX, -2, bagX + 7, -2,
            nvgRGBA(75, 68, 58, math.floor(stunAlpha * 0.9)),
            nvgRGBA(50, 44, 36, math.floor(stunAlpha * 0.9)))
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bagX, -2, 7, 14, 3)
        nvgFillPaint(vg, bagPaint)
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(40, 35, 28, math.floor(stunAlpha * 0.7)))
        nvgStrokeWidth(vg, 0.7)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 195, 185, stunAlpha))
        nvgText(vg, -C.PLAYER_W / 2 - 3, 5, tostring(p.carrying), nil)
    end

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

    nvgRestore(vg)
end

------------------------------------------------------------------------
-- 8. 绘制丧尸
------------------------------------------------------------------------
function R.DrawZombies(vg, G)
    local t = G.gameTime or 0
    local idleImg1 = G.zombieIdleImg
    local walkFrames1 = G.zombieWalkFrames
    local idleImg2 = G.zombie2IdleImg
    local walkFrames2 = G.zombie2WalkFrames
    local idleImg3 = G.crawlerIdleImg
    local walkFrames3 = G.crawlerWalkFrames

    for _, z in ipairs(G.zombies or {}) do
        if z.dead then goto continue_z end
        if z.y < G.renderTopY - 20 or z.y > G.screenH + 20 then goto continue_z end

        local zx = z.x
        local zy = z.y
        local hitFlash = (z.hitAnim or 0) > 0

        nvgSave(vg)
        nvgTranslate(vg, zx, zy)

        -- 根据僵尸类型选择精灵集
        local zType = z.zombieType or 1

        -- 柔阴影 (径向渐变，爬行僵尸阴影贴地)
        do
            local shY, shRx, shRy
            if zType == 3 then
                -- 爬行僵尸：阴影在身体正下方，更扁更宽（贴地）
                shY = 6
                shRx = 20
                shRy = 7
            else
                shY = C.ZOMBIE_SIZE * 0.9
                shRx = 14
                shRy = 5
            end
            local shPaint = nvgRadialGradient(vg, 2, shY, 2, shRx,
                nvgRGBA(8, 10, 5, 75), nvgRGBA(8, 10, 5, 0))
            nvgBeginPath(vg)
            nvgEllipse(vg, 2, shY, shRx, shRy)
            nvgFillPaint(vg, shPaint)
            nvgFill(vg)
        end

        -- 翻转（俯视角爬行僵尸朝上，不做水平翻转）
        if zType ~= 3 and z.facing < 0 then nvgScale(vg, -1, 1) end

        -- 选择精灵集
        local idleImg, walkFrames
        if zType == 3 then
            idleImg = idleImg3
            walkFrames = walkFrames3
        elseif zType == 2 then
            idleImg = idleImg2
            walkFrames = walkFrames2
        else
            idleImg = idleImg1
            walkFrames = walkFrames1
        end

        -- 选择精灵帧（支持动态帧数）
        local frameImg = idleImg  -- 默认idle
        local wa = z.walkAnim or 0
        local frameCount = walkFrames and #walkFrames or 0
        if walkFrames and frameCount >= 1 and z.isWalking then
            local walkIdx = (math.floor(wa) % frameCount) + 1
            frameImg = walkFrames[walkIdx]
        end

        if frameImg and frameImg ~= 0 then
            -- 僵尸精灵尺寸：比碰撞框稍大
            local drawW, drawH
            if zType == 3 then
                -- 爬行僵尸：更扁平，贴地（放大）
                drawW = C.ZOMBIE_SIZE + 28
                drawH = drawW * 1.0  -- 正方形比例(爬行姿态)
            else
                drawW = C.ZOMBIE_SIZE + 16
                drawH = drawW * 1.24  -- 保持512x636原图比例
            end

            -- 程序化行走摇晃：弹跳 + 倾斜（僵尸比玩家更夸张）
            local isMoving = z.isWalking
            local wobbleY = 0
            local wobbleTilt = 0

            if zType == 3 then
                -- 爬行僵尸：快速左右摇摆，不弹跳
                if isMoving then
                    local phase = wa * math.pi * 0.5
                    wobbleTilt = math.sin(phase) * 0.10  -- 爬行时身体左右大幅摇摆
                else
                    wobbleTilt = math.sin(t * 3 + z.phase) * 0.04  -- 蠕动感
                end
            elseif isMoving then
                local phase = wa * math.pi * 0.5
                wobbleY = -math.abs(math.sin(phase)) * 2.0
                wobbleTilt = math.sin(phase) * 0.06  -- 僵尸摇摆更大
            else
                -- 站立时轻微呼吸摇动
                wobbleTilt = math.sin(t * 2 + z.phase) * 0.02
            end

            nvgSave(vg)
            nvgTranslate(vg, 0, wobbleY)
            if wobbleTilt ~= 0 then
                nvgTranslate(vg, 0, drawH * 0.4)
                nvgRotate(vg, wobbleTilt)
                nvgTranslate(vg, 0, -drawH * 0.4)
            end

            local drawX = -drawW / 2
            local drawY
            if zType == 3 then
                -- 爬行僵尸：贴地绘制，中心偏下
                drawY = -drawH / 2 + 4
            else
                drawY = -drawH / 2 - 2
            end
            local alpha = hitFlash and 0.5 or 1.0
            local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, frameImg, alpha)
            nvgBeginPath(vg)
            nvgRect(vg, drawX, drawY, drawW, drawH)
            nvgFillPaint(vg, imgPaint)
            nvgFill(vg)

            nvgRestore(vg)
        end

        nvgRestore(vg)

        -- 血条 (HP < maxHp 时显示, restore后绘制避免翻转影响)
        if z.hp and z.maxHp and z.hp < z.maxHp and z.hp > 0 then
            local barW = 24
            local barH = 3
            local bx = zx - barW / 2
            local by
            if zType == 3 then
                -- 爬行僵尸血条：在身体上方（爬行姿态更矮）
                by = zy - (C.ZOMBIE_SIZE + 28) * 0.5 / 2 - 6
            else
                by = zy - (C.ZOMBIE_SIZE + 16) * 1.24 / 2 - 6
            end
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
        local scale = 0.8 + (1 - alpha) * 0.4
        local col
        if ft.rtype == "gold" then
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
        elseif ft.rtype == "damage" then
            col = C.CLR.text_red
        else
            col = C.CLR.text_white
        end
        nvgFontSize(vg, 14 * scale)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(col[1], col[2], col[3], math.floor(alpha * 255)))
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

            -- 炮塔精灵图标
            if def then
                local img = G.turretImgs and G.turretImgs[def.imgKey]
                if img and img ~= 0 then
                    local sprW = iconSize - 10 * s
                    local sprH = sprW * 1.33
                    if sprH > iconSize - 8 * s then
                        sprH = iconSize - 8 * s
                        sprW = sprH / 1.33
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
    local curWave = G.currentWave or 1
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

    -- 资源项定义
    local items = {
        { img = G.hudIconGold,  count = G.gold          },
        { img = G.hudIconWood,  count = G.totalRes.wood },
        { img = G.hudIconStone, count = G.totalRes.stone },
        { img = G.hudIconGem,   count = G.totalRes.ore   },
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

    -- 1) 外框底：端盖(70×78) + 中间平铺(136×78) 组装，只罩资源区域
    local capImg = G.hudFrameCap
    local midImg = G.hudFrameMid
    local outerPad = 4 * s
    local outerX = startX - outerPad
    local outerW = totalResW + outerPad * 2
    local outerY = 0
    local outerH = hudH
    local capScale = outerH / 78
    local capW = 70 * capScale

    if capImg and capImg ~= 0 and midImg and midImg ~= 0 then
        local midX = outerX + capW
        local midW = outerW - capW * 2
        if midW < 0 then midW = 0 end

        -- 中间平铺段
        local midTileH = 78 * capScale
        local midTileW = 136 * capScale
        local midPaint = nvgImagePattern(vg, midX, outerY, midTileW, midTileH, 0, midImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, midX, outerY, midW, outerH)
        nvgFillPaint(vg, midPaint)
        nvgFill(vg)

        -- 左端盖
        local capPaint = nvgImagePattern(vg, outerX, outerY, capW, outerH, 0, capImg, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, outerX, outerY, capW, outerH)
        nvgFillPaint(vg, capPaint)
        nvgFill(vg)

        -- 右端盖（水平镜像）
        local rightCapX = outerX + outerW - capW
        nvgSave(vg)
        nvgTranslate(vg, rightCapX + capW, 0)
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
    local scale = 0.55 * s
    local panelW = 208 * scale       -- ≈114*s
    local panelH = 119 * scale       -- ≈65*s
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
    local textX = px + 12 * s

    nvgFontSize(vg, 13 * s)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, textX, lineY1, "波次", nil)

    nvgFontSize(vg, 16 * s)
    nvgFillColor(vg, nvgRGBA(255, 210, 80, 255))
    nvgText(vg, textX + 32 * s, lineY1, tostring(G.currentWave or 1) .. "/" .. tostring(G.maxWaves or 20), nil)

    -- 第二行: "下一波  00:23"
    local lineY2 = py + panelH * 0.7
    local cdLabel = "下一波"
    local cd = G.waveCountdown or 0
    local mins = math.floor(cd / 60)
    local secs = math.floor(cd % 60)
    local timeStr = string.format("%02d:%02d", mins, secs)

    nvgFontSize(vg, 12 * s)
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

    nvgFontSize(vg, 12 * s)
    nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
    nvgText(vg, killX + 28 * s, kcY, "击杀数", nil)

    nvgFontSize(vg, 14 * s)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, killX + 70 * s, kcY, tostring(G.killCount or 0), nil)
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

    -- ======== 3. 飘雪粒子（程序化）========
    math.randomseed(42)  -- 固定种子，粒子位置稳定
    for i = 1, 30 do
        local sx = math.random() * W
        local sy = (math.random() * H + t * (15 + math.random() * 20)) % (H + 10) - 5
        local sr = 1 + math.random() * 2
        local sa = 80 + math.random(80)
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, sr)
        nvgFillColor(vg, nvgRGBA(210, 225, 240, sa))
        nvgFill(vg)
    end
    math.randomseed(math.floor(os.clock() * 1000))  -- 恢复随机种子

    local s = G.uiScale or 1
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- ======== 4. 游戏标题 ========
    local titleY = H * 0.12

    -- 大标题阴影
    nvgFontSize(vg, 38 * s)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
    nvgText(vg, W / 2 + 2, titleY + 2, "雪国列车")

    -- 大标题
    nvgFillColor(vg, nvgRGBA(230, 240, 255, 255))
    nvgText(vg, W / 2, titleY, "雪国列车")

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
        { "存活记录", "第" .. (G.stage or 1) .. "关 第" .. (G.currentWave or 1) .. "波" },
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
    local btnSize   = 72                   -- 按钮整体尺寸（外框 = 图标 = 同尺寸）
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

    drawSkillBtn(rightX, btnY, bombImg, charCD, charCDMax, {255, 180, 50}, G.skillCharActive, nil)

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

return R

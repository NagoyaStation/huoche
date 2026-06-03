-- Editor/UIEditor.lua - 轻量级 UI 编辑器覆盖层
-- F2 开关，选中元素蓝色高亮框，拖拽移动，自动保存偏移

local Def = require("Editor.UIElementDef")

local M = {}

------------------------------------------------------------------------
-- 编辑器状态
------------------------------------------------------------------------
local enabled = false       -- 编辑器是否开启
local selectedId = nil      -- 当前选中的元素 ID
local dragging = false      -- 是否正在拖拽
local dragStartX = 0        -- 拖拽起始鼠标/触摸 X
local dragStartY = 0        -- 拖拽起始鼠标/触摸 Y
local dragOrigDX = 0        -- 拖拽开始时元素的 dx
local dragOrigDY = 0        -- 拖拽开始时元素的 dy
local hoverElem = nil       -- 用于高亮提示（可选）

------------------------------------------------------------------------
-- 开关
------------------------------------------------------------------------
function M.IsEnabled()
    return enabled
end

function M.Toggle()
    enabled = not enabled
    if enabled then
        Def.Load()  -- 首次打开时加载持久化数据
        print("[UIEditor] Enabled - 点击选中元素，拖拽移动位置")
    else
        selectedId = nil
        dragging = false
        print("[UIEditor] Disabled")
    end
end

------------------------------------------------------------------------
-- 覆盖层绘制（在所有 UI 之上）
------------------------------------------------------------------------
function M.DrawOverlay(vg, W, H)
    if not enabled then return end

    local elements = Def.GetElements()

    -- 顶部提示条
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, W, 24)
    nvgFillColor(vg, nvgRGBA(30, 120, 220, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    local hint = "UI 编辑模式 | 点击选中 | 拖拽移动 | 再按 F2 关闭"
    if selectedId then
        hint = "选中: " .. selectedId .. " | 拖拽移动 | 按 R 重置此元素"
    end
    nvgText(vg, W / 2, 12, hint)

    -- 绘制所有注册元素的边框
    for _, elem in ipairs(elements) do
        local isSelected = (elem.id == selectedId)

        if isSelected then
            -- 选中：亮蓝色框 + 半透明填充
            nvgBeginPath(vg)
            nvgRect(vg, elem.x, elem.y, elem.w, elem.h)
            nvgFillColor(vg, nvgRGBA(30, 140, 255, 40))
            nvgFill(vg)

            nvgBeginPath(vg)
            nvgRect(vg, elem.x, elem.y, elem.w, elem.h)
            nvgStrokeColor(vg, nvgRGBA(30, 140, 255, 255))
            nvgStrokeWidth(vg, 2.5)
            nvgStroke(vg)

            -- 标签
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
            -- 标签背景
            local labelText = elem.label
            local lw = nvgTextBounds(vg, 0, 0, labelText)
            nvgBeginPath(vg)
            nvgRect(vg, elem.x, elem.y - 14, lw + 8, 14)
            nvgFillColor(vg, nvgRGBA(30, 140, 255, 220))
            nvgFill(vg)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgText(vg, elem.x + 4, elem.y - 2, labelText)

            -- 偏移信息
            if elem.dx ~= 0 or elem.dy ~= 0 then
                local offsetText = string.format("dx=%.0f dy=%.0f", elem.dx, elem.dy)
                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
                nvgText(vg, elem.x + 2, elem.y + elem.h + 2, offsetText)
            end
        else
            -- 未选中：淡色虚线框
            nvgBeginPath(vg)
            nvgRect(vg, elem.x, elem.y, elem.w, elem.h)
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, 100))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end
end

------------------------------------------------------------------------
-- 输入处理
------------------------------------------------------------------------

--- 点击/触摸开始 — 返回 true 表示编辑器消费了这次输入
function M.HandlePointerDown(x, y)
    if not enabled then return false end

    local elements = Def.GetElements()

    -- 逆序遍历（上层元素优先）
    for i = #elements, 1, -1 do
        local e = elements[i]
        if x >= e.x and x <= e.x + e.w and y >= e.y and y <= e.y + e.h then
            selectedId = e.id
            dragging = true
            dragStartX = x
            dragStartY = y
            dragOrigDX = e.dx
            dragOrigDY = e.dy
            return true
        end
    end

    -- 点击空白区域：取消选择
    selectedId = nil
    return true  -- 编辑模式下消费所有点击
end

--- 拖拽移动
function M.HandlePointerMove(x, y)
    if not enabled then return false end
    if not dragging or not selectedId then return false end

    local ddx = x - dragStartX
    local ddy = y - dragStartY

    Def.SetOffset(selectedId, dragOrigDX + ddx, dragOrigDY + ddy)
    return true
end

--- 释放
function M.HandlePointerUp()
    if not enabled then return false end
    if dragging and selectedId then
        dragging = false
        Def.Save()  -- 松手自动保存
        return true
    end
    dragging = false
    return false
end

--- 键盘处理（R 重置选中元素）— 在 HandleUpdate 中调用
function M.HandleKeyboard()
    if not enabled then return end

    if input:GetKeyPress(KEY_R) and selectedId then
        Def.ResetOne(selectedId)
        print("[UIEditor] Reset element: " .. selectedId)
    end
end

return M

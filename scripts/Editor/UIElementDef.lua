-- Editor/UIElementDef.lua - UI 元素注册表
-- 每个可编辑 UI 元素在绘制时 Register，编辑器根据注册信息绘制覆盖层

local M = {}

--- 每帧重置的元素列表
---@type table[]
local elements = {}

--- 持久化的偏移量 { [id] = {dx=number, dy=number} }
---@type table<string, table>
local offsets = {}

--- 是否已加载过持久化数据
local loaded = false

------------------------------------------------------------------------
-- 持久化 (JSON)
------------------------------------------------------------------------
local SAVE_FILE = "ui_editor_layout.json"

function M.Save()
    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(offsets))
        file:Close()
        print("[UIEditor] Layout saved (" .. M._countTable(offsets) .. " elements)")
    end
end

function M.Load()
    if loaded then return end
    loaded = true
    if fileSystem:FileExists(SAVE_FILE) then
        local file = File(SAVE_FILE, FILE_READ)
        if file:IsOpen() then
            local ok, data = pcall(cjson.decode, file:ReadString())
            file:Close()
            if ok and type(data) == "table" then
                offsets = data
                print("[UIEditor] Layout loaded (" .. M._countTable(offsets) .. " elements)")
            end
        end
    end
end

function M._countTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

------------------------------------------------------------------------
-- 核心 API
------------------------------------------------------------------------

--- 每帧开始时清空注册列表（在 Draw 入口调用）
function M.BeginFrame()
    elements = {}
end

--- 注册一个可编辑元素（在 Draw 函数中，每帧调用）
--- @param id string 唯一标识 "battle.scene_card"
--- @param x number 原始绘制 x
--- @param y number 原始绘制 y
--- @param w number 宽度
--- @param h number 高度
--- @param label string|nil 显示名称
function M.Register(id, x, y, w, h, label)
    local off = offsets[id]
    local dx = off and off.dx or 0
    local dy = off and off.dy or 0
    elements[#elements + 1] = {
        id = id,
        x = x + dx,
        y = y + dy,
        w = w,
        h = h,
        ox = x,  -- 原始位置
        oy = y,
        dx = dx,
        dy = dy,
        label = label or id,
    }
end

--- 获取某个元素的偏移后位置（在绘制代码中调用以应用偏移）
--- @param id string
--- @param x number 原始 x
--- @param y number 原始 y
--- @return number, number 偏移后的 x, y
function M.Apply(id, x, y)
    local off = offsets[id]
    if off then
        return x + off.dx, y + off.dy
    end
    return x, y
end

--- 设置某个元素的偏移
function M.SetOffset(id, dx, dy)
    if not offsets[id] then
        offsets[id] = {}
    end
    offsets[id].dx = dx
    offsets[id].dy = dy
end

--- 获取当前帧所有注册的元素
function M.GetElements()
    return elements
end

--- 重置所有偏移
function M.ResetAll()
    offsets = {}
    M.Save()
    print("[UIEditor] All offsets reset")
end

--- 重置单个元素的偏移
function M.ResetOne(id)
    offsets[id] = nil
    M.Save()
end

return M

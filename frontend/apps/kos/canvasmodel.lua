--[[--
Endless page model: items placed anywhere on an unbounded plane, a viewport that pans over it.
No drawing here, so it can be tested without a screen.

    local c = Canvas.new({ w = 1000, h = 1800 })
    c:add{ x = 0, y = 0, text = "hello" }          -- or  app = "pendulums"
    c:pan(dx, dy)                                    -- finger moved by dx, dy: the page moves with it
    c:visible()                                      -- items touching the viewport, with screen positions
    c:toData() / Canvas.fromData(t, viewport)        -- kept in the setting kos_canvas
    c:fitAll()                                       -- viewport that shows every item

Depth (z) is stored per item for later; layers are not drawn yet.
]]

local Canvas = {}
Canvas.__index = Canvas

function Canvas.new(viewport)
    return setmetatable({ vp = { w = viewport.w, h = viewport.h }, ox = 0, oy = 0, items = {}, nextId = 1 }, Canvas)
end

function Canvas:add(it)
    it.id = self.nextId; self.nextId = self.nextId + 1
    it.x = it.x or 0; it.y = it.y or 0
    it.w = it.w or 240; it.h = it.h or 64
    it.z = it.z or 0
    self.items[#self.items + 1] = it
    return it
end

function Canvas:remove(id)
    for i, it in ipairs(self.items) do
        if it.id == id then table.remove(self.items, i); return true end
    end
    return false
end

--- The page follows the finger.
function Canvas:pan(dx, dy) self.ox = self.ox - dx; self.oy = self.oy - dy end

function Canvas:moveTo(x, y) self.ox, self.oy = x, y end

function Canvas:visible()
    local out = {}
    for _, it in ipairs(self.items) do
        local sx, sy = it.x - self.ox, it.y - self.oy
        if sx < self.vp.w and sy < self.vp.h and sx + it.w > 0 and sy + it.h > 0 then
            out[#out + 1] = { item = it, x = sx, y = sy }
        end
    end
    table.sort(out, function(a, b) if a.item.z ~= b.item.z then return a.item.z < b.item.z end return a.item.id < b.item.id end)
    return out
end

--- Item under a screen point (topmost), or nil.
function Canvas:hit(sx, sy)
    local v = self:visible()
    for i = #v, 1, -1 do
        local e = v[i]
        if sx >= e.x and sx < e.x + e.item.w and sy >= e.y and sy < e.y + e.item.h then return e.item end
    end
end

--- Move an item by a screen-space drag.
function Canvas:drag(item, dx, dy) item.x = item.x + dx; item.y = item.y + dy end

function Canvas:bounds()
    if #self.items == 0 then return nil end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, it in ipairs(self.items) do
        x0 = math.min(x0, it.x); y0 = math.min(y0, it.y)
        x1 = math.max(x1, it.x + it.w); y1 = math.max(y1, it.y + it.h)
    end
    return x0, y0, x1, y1
end

function Canvas:fitAll()
    local x0, y0 = self:bounds()
    if not x0 then self:moveTo(0, 0) else self:moveTo(x0, y0) end
end

function Canvas:toData()
    local items = {}
    for _, it in ipairs(self.items) do
        items[#items + 1] = { x = it.x, y = it.y, w = it.w, h = it.h, z = it.z, text = it.text, app = it.app }
    end
    return { ox = self.ox, oy = self.oy, items = items }
end

function Canvas.fromData(t, viewport)
    local c = Canvas.new(viewport)
    if type(t) ~= "table" then return c end
    c.ox, c.oy = tonumber(t.ox) or 0, tonumber(t.oy) or 0
    for _, it in ipairs(t.items or {}) do c:add(it) end
    return c
end

return Canvas

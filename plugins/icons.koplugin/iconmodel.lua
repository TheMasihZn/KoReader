--[[--
The drawing behind the icon editor: shapes on a 48 x 48 sheet, undo/redo,
erasing, the ready-made stamps, and saving as SVG. No screen code here, so it
can be tested on its own.

A shape: { kind = "path"|"line"|"rect"|"ellipse"|"poly", points = { {x, y}, … },
           width = n, fill = bool, closed = bool }
  line     two points
  rect     two opposite corners
  ellipse  two opposite corners of its box
  path     a freehand line through the points
  poly     a closed shape through the points (stamps are polys)
]]

local Model = {
    SIZE = 48,
    WIDTHS = { 1, 2, 3, 4, 6 },
}
Model.__index = Model

local floor, sqrt, cos, sin, pi, max, min = math.floor, math.sqrt, math.cos, math.sin, math.pi, math.max, math.min

function Model.new()
    return setmetatable({ shapes = {}, undo_stack = {}, redo_stack = {} }, Model)
end

--- Snap to the nearest whole unit (halves for fine work), inside the sheet.
function Model.snap(v, fine)
    local step = fine and 0.5 or 1
    v = floor(v / step + 0.5) * step
    return max(0, min(Model.SIZE, v))
end

local function copyShapes(shapes)
    local out = {}
    for i, s in ipairs(shapes) do
        local pts = {}
        for j, p in ipairs(s.points) do pts[j] = { p[1], p[2] } end
        out[i] = { kind = s.kind, points = pts, width = s.width, fill = s.fill }
    end
    return out
end

function Model:checkpoint()
    table.insert(self.undo_stack, copyShapes(self.shapes))
    if #self.undo_stack > 100 then table.remove(self.undo_stack, 1) end
    self.redo_stack = {}
end

function Model:undo()
    local prev = table.remove(self.undo_stack)
    if not prev then return false end
    table.insert(self.redo_stack, copyShapes(self.shapes))
    self.shapes = prev
    return true
end

function Model:redo()
    local nxt = table.remove(self.redo_stack)
    if not nxt then return false end
    table.insert(self.undo_stack, copyShapes(self.shapes))
    self.shapes = nxt
    return true
end

function Model:add(shape)
    self:checkpoint()
    table.insert(self.shapes, shape)
    return shape
end

function Model:clear()
    if #self.shapes == 0 then return end
    self:checkpoint()
    self.shapes = {}
end

--- A freehand line, thinned so it doesn't hold a point for every pixel.
function Model.simplify(points, min_dist)
    min_dist = min_dist or 0.75
    local out = {}
    for _, p in ipairs(points) do
        local last = out[#out]
        if not last or (p[1] - last[1]) ^ 2 + (p[2] - last[2]) ^ 2 >= min_dist ^ 2 then
            out[#out + 1] = { p[1], p[2] }
        end
    end
    local last_in = points[#points]
    if last_in and out[#out] and (out[#out][1] ~= last_in[1] or out[#out][2] ~= last_in[2]) then
        out[#out + 1] = { last_in[1], last_in[2] }
    end
    return out
end

---------------------------------------------------------------------------
-- Stamps: ready-made shapes, centred on (cx, cy), `r` units from the middle to the edge
---------------------------------------------------------------------------

local function regular(cx, cy, r, n, rotation)
    local pts = {}
    for i = 0, n - 1 do
        local a = rotation + 2 * pi * i / n
        pts[#pts + 1] = { cx + r * cos(a), cy + r * sin(a) }
    end
    return pts
end

local function star(cx, cy, r)
    local pts = {}
    for i = 0, 9 do
        local a = -pi / 2 + pi * i / 5
        local rr = (i % 2 == 0) and r or r * 0.42
        pts[#pts + 1] = { cx + rr * cos(a), cy + rr * sin(a) }
    end
    return pts
end

local function heart(cx, cy, r)
    local pts = {}
    for i = 0, 31 do
        local t = 2 * pi * i / 32
        local x = 16 * sin(t) ^ 3
        local y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        pts[#pts + 1] = { cx + x * r / 17, cy - y * r / 17 }
    end
    return pts
end

Model.STAMPS = {
    { id = "circle",   name = "Circle",   make = function(cx, cy, r) return { kind = "ellipse", points = { { cx - r, cy - r }, { cx + r, cy + r } } } end },
    { id = "dot",      name = "Dot",      fill = true, make = function(cx, cy, r) r = r * 0.45 return { kind = "ellipse", points = { { cx - r, cy - r }, { cx + r, cy + r } } } end },
    { id = "square",   name = "Square",   make = function(cx, cy, r) return { kind = "rect", points = { { cx - r, cy - r }, { cx + r, cy + r } } } end },
    { id = "triangle", name = "Triangle", make = function(cx, cy, r) return { kind = "poly", points = regular(cx, cy + r * 0.15, r, 3, -pi / 2) } end },
    { id = "diamond",  name = "Diamond",  make = function(cx, cy, r) return { kind = "poly", points = regular(cx, cy, r, 4, -pi / 2) } end },
    { id = "hexagon",  name = "Hexagon",  make = function(cx, cy, r) return { kind = "poly", points = regular(cx, cy, r, 6, 0) } end },
    { id = "star",     name = "Star",     make = function(cx, cy, r) return { kind = "poly", points = star(cx, cy, r) } end },
    { id = "heart",    name = "Heart",    make = function(cx, cy, r) return { kind = "poly", points = heart(cx, cy, r) } end },
    { id = "plus",     name = "Plus",     make = function(cx, cy, r) return { kind = "path", points = { { cx, cy - r }, { cx, cy + r }, { cx, cy }, { cx - r, cy }, { cx + r, cy } } } end },
    { id = "cross",    name = "Cross",    make = function(cx, cy, r) return { kind = "path", points = { { cx - r, cy - r }, { cx + r, cy + r }, { cx, cy }, { cx + r, cy - r }, { cx - r, cy + r } } } end },
    { id = "check",    name = "Check",    make = function(cx, cy, r) return { kind = "path", points = { { cx - r, cy }, { cx - r * 0.3, cy + r * 0.7 }, { cx + r, cy - r * 0.7 } } } end },
    { id = "chevron",  name = "Chevron",  make = function(cx, cy, r) return { kind = "path", points = { { cx - r * 0.5, cy - r }, { cx + r * 0.5, cy }, { cx - r * 0.5, cy + r } } } end },
    { id = "arrow",    name = "Arrow",    make = function(cx, cy, r) return { kind = "path", points = { { cx - r, cy }, { cx + r, cy }, { cx + r * 0.4, cy - r * 0.6 }, { cx + r, cy }, { cx + r * 0.4, cy + r * 0.6 } } } end },
    { id = "line",     name = "Line",     make = function(cx, cy, r) return { kind = "line", points = { { cx - r, cy }, { cx + r, cy } } } end },
    { id = "wave",     name = "Wave",     make = function(cx, cy, r)
        local pts = {}
        for i = 0, 16 do
            local t = i / 16
            pts[#pts + 1] = { cx - r + 2 * r * t, cy + r * 0.4 * sin(t * 2 * pi) }
        end
        return { kind = "path", points = pts }
    end },
}

--- Puts a stamp on the sheet. Returns the new shape.
function Model:stamp(id, cx, cy, r, width, fill)
    for _, st in ipairs(Model.STAMPS) do
        if st.id == id then
            local shape = st.make(Model.snap(cx, true), Model.snap(cy, true), r)
            shape.width = width
            shape.fill = (fill or st.fill) and true or false
            for _, p in ipairs(shape.points) do
                p[1], p[2] = max(0, min(Model.SIZE, p[1])), max(0, min(Model.SIZE, p[2]))
            end
            return self:add(shape)
        end
    end
end

---------------------------------------------------------------------------
-- Geometry: what a shape looks like as lines (used for drawing and for erasing)
---------------------------------------------------------------------------

--- The outline of a shape as a list of points; `closed` says whether the last joins the first.
function Model.outline(shape)
    local p = shape.points
    if shape.kind == "line" or shape.kind == "path" then
        return p, false
    elseif shape.kind == "poly" then
        return p, true
    elseif shape.kind == "rect" then
        local x1, y1, x2, y2 = p[1][1], p[1][2], p[2][1], p[2][2]
        return { { x1, y1 }, { x2, y1 }, { x2, y2 }, { x1, y2 } }, true
    elseif shape.kind == "ellipse" then
        local cx, cy = (p[1][1] + p[2][1]) / 2, (p[1][2] + p[2][2]) / 2
        local rx, ry = math.abs(p[2][1] - p[1][1]) / 2, math.abs(p[2][2] - p[1][2]) / 2
        local pts = {}
        for i = 0, 47 do
            local a = 2 * pi * i / 48
            pts[#pts + 1] = { cx + rx * cos(a), cy + ry * sin(a) }
        end
        return pts, true
    end
    return {}, false
end

local function distToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
    local qx, qy = ax + t * dx, ay + t * dy
    return sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

local function insidePolygon(px, py, pts)
    local inside = false
    local j = #pts
    for i = 1, #pts do
        local xi, yi, xj, yj = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
        if (yi > py) ~= (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi then
            inside = not inside
        end
        j = i
    end
    return inside
end

--- Is the point on (or, for filled shapes, in) this shape?
function Model.hits(shape, x, y, reach)
    reach = (reach or 1.5) + (shape.width or 2) / 2
    local pts, closed = Model.outline(shape)
    if #pts == 1 then
        return sqrt((x - pts[1][1]) ^ 2 + (y - pts[1][2]) ^ 2) <= reach
    end
    for i = 1, #pts - 1 do
        if distToSegment(x, y, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]) <= reach then return true end
    end
    if closed and #pts > 2 then
        local a, b = pts[#pts], pts[1]
        if distToSegment(x, y, a[1], a[2], b[1], b[2]) <= reach then return true end
        if shape.fill and insidePolygon(x, y, pts) then return true end
    end
    return false
end

--- Removes the topmost shape under the point. Returns true if one was removed.
function Model:eraseAt(x, y, reach)
    for i = #self.shapes, 1, -1 do
        if Model.hits(self.shapes[i], x, y, reach) then
            self:checkpoint()
            table.remove(self.shapes, i)
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------

local function num(v)
    local s = string.format("%.2f", v)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

--- The icon as SVG text (black on transparent, like KOReader's own icons).
function Model:toSVG()
    local out = {
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        string.format('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n',
            Model.SIZE, Model.SIZE, Model.SIZE, Model.SIZE),
    }
    for _, s in ipairs(self.shapes) do
        local attrs = string.format('stroke="#000" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round" fill="%s"',
            num(s.width or 2), s.fill and "#000" or "none")
        local p = s.points
        if s.kind == "rect" then
            local x, y = math.min(p[1][1], p[2][1]), math.min(p[1][2], p[2][2])
            local w, h = math.abs(p[2][1] - p[1][1]), math.abs(p[2][2] - p[1][2])
            out[#out + 1] = string.format('<rect x="%s" y="%s" width="%s" height="%s" %s/>\n', num(x), num(y), num(w), num(h), attrs)
        elseif s.kind == "ellipse" then
            local cx, cy = (p[1][1] + p[2][1]) / 2, (p[1][2] + p[2][2]) / 2
            local rx, ry = math.abs(p[2][1] - p[1][1]) / 2, math.abs(p[2][2] - p[1][2]) / 2
            out[#out + 1] = string.format('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" %s/>\n', num(cx), num(cy), num(rx), num(ry), attrs)
        else
            local d = {}
            for i, pt in ipairs(p) do
                d[#d + 1] = (i == 1 and "M" or "L") .. num(pt[1]) .. " " .. num(pt[2])
            end
            if s.kind == "poly" then d[#d + 1] = "Z" end
            if #p == 1 then -- a single point: draw it as a dot
                d[#d + 1] = "L" .. num(p[1][1]) .. " " .. num(p[1][2])
            end
            out[#out + 1] = string.format('<path d="%s" %s/>\n', table.concat(d, " "), attrs)
        end
    end
    out[#out + 1] = "</svg>\n"
    return table.concat(out)
end

--- The drawing as Lua text, so an icon can be opened and changed again later.
function Model:toLua()
    local out = { "return {\n" }
    for _, s in ipairs(self.shapes) do
        local pts = {}
        for _, p in ipairs(s.points) do pts[#pts + 1] = string.format("{%s,%s}", num(p[1]), num(p[2])) end
        out[#out + 1] = string.format('  { kind = %q, width = %s, fill = %s, points = { %s } },\n',
            s.kind, num(s.width or 2), s.fill and "true" or "false", table.concat(pts, ", "))
    end
    out[#out + 1] = "}\n"
    return table.concat(out)
end

--- Reads a drawing saved by toLua. Returns a Model, or nil + error.
function Model.fromLua(text)
    -- Run in an empty environment: a saved drawing is data and can't do anything else.
    local chunk, err
    if setfenv and loadstring then      -- LuaJIT / Lua 5.1
        chunk, err = loadstring(text, "=drawing")
        if chunk then setfenv(chunk, {}) end
    else                                -- Lua 5.2+
        chunk, err = load(text, "=drawing", "t", {})
    end
    if not chunk then return nil, err end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil, "not a drawing" end
    local m = Model.new()
    for _, s in ipairs(data) do
        if type(s) == "table" and type(s.points) == "table" and #s.points > 0 then
            local shape = { kind = s.kind, width = tonumber(s.width) or 2, fill = s.fill and true or false, points = {} }
            for _, p in ipairs(s.points) do
                shape.points[#shape.points + 1] = { tonumber(p[1]) or 0, tonumber(p[2]) or 0 }
            end
            m.shapes[#m.shapes + 1] = shape
        end
    end
    return m
end

--- Icon names: letters, digits, dot, dash, underscore. Returns nil if nothing usable is left.
function Model.cleanName(name)
    name = (name or ""):gsub("%.svg$", ""):gsub("[^%w_%.%-]", "")
    if name == "" or name:sub(1, 1) == "." then return nil end
    return name
end

return Model

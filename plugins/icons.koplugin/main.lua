--[[--
Icons: a small icon editor for KOReader OS.

* Draw on a blank sheet (48 x 48 units, snapped to a grid so lines stay clean),
  or open an existing icon as a faint guide and trace/correct it.
* Tools: pen, line, rectangle, oval, eraser, and ready-made stamps (circle, star,
  heart, arrow, …). Width, fill, undo/redo, grid.
* Save: writes koreader/icons/<name>.svg. KOReader uses icons from that folder
  before its built-in ones, so saving as "home" replaces the home icon
  everywhere after a restart. Your drawings are kept in koreader/icons-src/
  so you can open and change them later. Deleting your icon brings the
  built-in one back.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Font = require("ui/font")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Model = require("iconmodel")
local Screen = Device.screen

local Icons = WidgetContainer:extend{
    name = "icons",
}

local function iconsDir() return DataStorage:getDataDir() .. "/icons" end
local function sourceDir() return DataStorage:getDataDir() .. "/icons-src" end

local function ensureDir(path)
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        lfs.mkdir(acc)
    end
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local function writeFile(path, content)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(content)
    f:close()
    return os.rename(tmp, path) and true or false
end

---------------------------------------------------------------------------
-- Drawing a shape on the screen
---------------------------------------------------------------------------

local function dot(bb, x, y, w, color)
    local half = math.floor(w / 2)
    bb:paintRect(math.floor(x - half), math.floor(y - half), w, w, color)
end

local function stroke(bb, ax, ay, bx, by, w, color)
    local dx, dy = bx - ax, by - ay
    local steps = math.max(1, math.floor(math.max(math.abs(dx), math.abs(dy))))
    for i = 0, steps do
        dot(bb, ax + dx * i / steps, ay + dy * i / steps, w, color)
    end
end

-- Fills a polygon (points in pixels) one row at a time. `more`: extra rings (holes or islands), even-odd.
local function fillPolygon(bb, pts, color, more)
    local miny, maxy = math.huge, -math.huge
    for _, p in ipairs(pts) do
        miny, maxy = math.min(miny, p[2]), math.max(maxy, p[2])
    end
    for y = math.floor(miny), math.ceil(maxy) do
        local xs = {}
        local j = #pts
        for i = 1, #pts do
            local yi, yj = pts[i][2], pts[j][2]
            if (yi <= y + 0.5) ~= (yj <= y + 0.5) then
                local t = (y + 0.5 - yi) / (yj - yi)
                xs[#xs + 1] = pts[i][1] + t * (pts[j][1] - pts[i][1])
            end
            j = i
        end
        for _, ring in ipairs(more or {}) do
            local rj = #ring
            for i = 1, #ring do
                local yi, yj = ring[i][2], ring[rj][2]
                if (yi <= y + 0.5) ~= (yj <= y + 0.5) then
                    local t = (y + 0.5 - yi) / (yj - yi)
                    xs[#xs + 1] = ring[i][1] + t * (ring[rj][1] - ring[i][1])
                end
                rj = i
            end
        end
        table.sort(xs)
        for k = 1, #xs - 1, 2 do
            local x1, x2 = math.floor(xs[k]), math.ceil(xs[k + 1])
            if x2 > x1 then bb:paintRect(x1, y, x2 - x1, 1, color) end
        end
    end
end

local function drawShape(bb, shape, ox, oy, scale, color)
    local pts, closed = Model.outline(shape)
    if #pts == 0 then return end
    local px = {}
    for i, p in ipairs(pts) do px[i] = { ox + p[1] * scale, oy + p[2] * scale } end
    local more
    if shape.rings then
        more = {}
        for k, ring in ipairs(shape.rings) do
            more[k] = {}
            for i, p in ipairs(ring) do more[k][i] = { ox + p[1] * scale, oy + p[2] * scale } end
        end
    end
    if shape.fill and closed and #px > 2 then fillPolygon(bb, px, color, more) end
    local w = math.max(1, math.floor((shape.width or 2) * scale + 0.5))
    if #px == 1 then
        dot(bb, px[1][1], px[1][2], w, color)
        return
    end
    for i = 1, #px - 1 do
        stroke(bb, px[i][1], px[i][2], px[i + 1][1], px[i + 1][2], w, color)
    end
    if closed then
        stroke(bb, px[#px][1], px[#px][2], px[1][1], px[1][2], w, color)
    end
    for _, ring in ipairs(more or {}) do
        for i = 1, #ring do
            local a, b = ring[i], ring[i % #ring + 1]
            stroke(bb, a[1], a[2], b[1], b[2], w, color)
        end
    end
end

---------------------------------------------------------------------------
-- The drawing sheet (a widget)
---------------------------------------------------------------------------

local Canvas = InputContainer:extend{
    size = 300,
    session = nil,
}

function Canvas:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    local range = function() return self.dimen end
    self.ges_events = {
        CanvasTap = { GestureRange:new{ ges = "tap", range = range } },
        CanvasPan = { GestureRange:new{ ges = "pan", range = range } },
        CanvasPanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
    }
    local s = self.session
    if s.reference then
        local ok, IconWidget = pcall(require, "ui/widget/iconwidget")
        if ok then
            local ok2, w = pcall(IconWidget.new, IconWidget, { icon = s.reference, width = self.size, height = self.size, alpha = true })
            if ok2 then self.reference_widget = w end
        end
    end
end

function Canvas:getSize() return self.dimen end

function Canvas:toUnits(pos)
    local u = Model.SIZE / self.dimen.w
    return (pos.x - self.dimen.x) * u, (pos.y - self.dimen.y) * u
end

function Canvas:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local s = self.session
    local size = self.size
    local scale = size / Model.SIZE
    bb:paintRect(x, y, size, size, Blitbuffer.COLOR_WHITE)
    -- Guide: the icon being corrected, very faint.
    if s.show_reference and self.reference_widget then
        pcall(function()
            self.reference_widget:paintTo(bb, x, y)
            bb:lightenRect(x, y, size, size, 0.78)
        end)
    end
    -- Grid: faint lines every 4 units, a little stronger every 12.
    if s.grid then
        for i = 0, Model.SIZE, 4 do
            local c = (i % 12 == 0) and Blitbuffer.Color8(0xD0) or Blitbuffer.Color8(0xE8)
            local p = math.floor(i * scale)
            bb:paintRect(x + p, y, 1, size, c)
            bb:paintRect(x, y + p, size, 1, c)
        end
    end
    bb:paintBorder(x, y, size, size, 1, Blitbuffer.Color8(0x90))
    for _, shape in ipairs(s.model.shapes) do
        pcall(drawShape, bb, shape, x, y, scale, Blitbuffer.COLOR_BLACK)
    end
    if s.draft then
        pcall(drawShape, bb, s.draft, x, y, scale, Blitbuffer.COLOR_DARK_GRAY)
    end
end

function Canvas:dirty()
    UIManager:setDirty(self.session.window, "fast", self.dimen)
end

local function draftFor(s, points)
    local tool = s.tool
    local shape = { width = s.width, fill = s.fill, points = points }
    if tool == "pen" then
        shape.kind = "path"
    elseif tool == "line" then
        shape.kind = "line"
    elseif tool == "rect" then
        shape.kind = "rect"
    elseif tool == "oval" then
        shape.kind = "ellipse"
    else
        return nil
    end
    return shape
end

function Canvas:onCanvasTap(_, ges)
    local s = self.session
    local x, y = self:toUnits(ges.pos)
    if s.tool == "erase" then
        if s.model:eraseAt(x, y, 2) then
            s.dirty = true
            self:dirty()
        end
    elseif s.tool == "stamp" then
        s.model:stamp(s.stamp, x, y, s.stamp_size, s.width, s.fill)
        s.dirty = true
        self:dirty()
    elseif s.tool == "pen" then
        s.model:add{ kind = "path", width = s.width, fill = false,
            points = { { Model.snap(x, true), Model.snap(y, true) } } }
        s.dirty = true
        self:dirty()
    end
    return true
end

function Canvas:onCanvasPan(_, ges)
    local s = self.session
    local x, y = self:toUnits(ges.pos)
    if s.tool == "erase" then
        if s.model:eraseAt(x, y, 2) then
            s.dirty = true
            self:dirty()
        end
        return true
    end
    if s.tool == "stamp" then return true end
    local fine = s.tool == "pen"
    local cur = { Model.snap(x, fine), Model.snap(y, fine) }
    if not s.drag then
        local sx, sy = self:toUnits(ges.start_pos or ges.pos)
        s.drag = { start = { Model.snap(sx, fine), Model.snap(sy, fine) }, points = {} }
        if fine then s.drag.points[1] = { s.drag.start[1], s.drag.start[2] } end
    end
    if fine then
        local last = s.drag.points[#s.drag.points]
        if not last or last[1] ~= cur[1] or last[2] ~= cur[2] then
            s.drag.points[#s.drag.points + 1] = cur
        end
        s.draft = draftFor(s, s.drag.points)
    else
        s.draft = draftFor(s, { s.drag.start, cur })
    end
    self:dirty()
    return true
end

function Canvas:onCanvasPanRelease()
    local s = self.session
    local draft, drag = s.draft, s.drag
    s.draft, s.drag = nil, nil
    if draft and drag then
        if draft.kind == "path" then
            draft.points = Model.simplify(draft.points, 0.75)
        end
        local p = draft.points
        local empty = draft.kind ~= "path" and p[1][1] == p[2][1] and p[1][2] == p[2][2]
        if not empty then
            s.model:add(draft)
            s.dirty = true
        end
    end
    self:dirty()
    return true
end

---------------------------------------------------------------------------
-- The app
---------------------------------------------------------------------------

local TOOLS = {
    { id = "pen", text = _("Pen") },
    { id = "line", text = _("Line") },
    { id = "rect", text = _("Box") },
    { id = "oval", text = _("Oval") },
    { id = "erase", text = _("Erase") },
}
local STAMP_SIZES = { 4, 6, 9, 12, 18 }

local function newSession()
    return {
        model = Model.new(),
        tool = "pen",
        width = 3,
        fill = false,
        grid = true,
        stamp = "star",
        stamp_size = 9,
        name = nil,
        reference = nil,
        show_reference = true,
        dirty = false,
    }
end

local function stampName(id)
    for _, st in ipairs(Model.STAMPS) do
        if st.id == id then return st.name end
    end
    return id
end

local function cycle(list, current)
    for i, v in ipairs(list) do
        if v == current then return list[i % #list + 1] end
    end
    return list[1]
end

function Icons:build(window, width, height)
    local s = window.icon_session
    s.window = window
    local margin = Size.padding.default
    local inner = width - 2 * margin

    local title = TextWidget:new{
        text = s.name and (s.name .. (s.dirty and " •" or "")) or _("New icon") .. (s.dirty and " •" or ""),
        face = Font:getFace("smallinfofontbold"),
        max_width = inner,
    }

    local function tool_button(t)
        local on = s.tool == t.id
        return {
            text = (on and "● " or "") .. t.text,
            font_bold = on,
            callback = function() s.tool = t.id; window:refresh() end,
        }
    end
    local row1 = {}
    for _, t in ipairs(TOOLS) do table.insert(row1, tool_button(t)) end

    local row2 = {
        {
            text = (s.tool == "stamp" and "● " or "") .. _("Stamp") .. ": " .. stampName(s.stamp),
            font_bold = s.tool == "stamp",
            callback = function() s.tool = "stamp"; self:chooseStamp(window) end,
        },
        { text = T(_("Size %1"), s.stamp_size), callback = function()
            s.stamp_size = cycle(STAMP_SIZES, s.stamp_size); window:refresh() end },
        { text = T(_("Width %1"), s.width), callback = function()
            s.width = cycle(Model.WIDTHS, s.width); window:refresh() end },
        { text = s.fill and _("Fill: on") or _("Fill: off"), callback = function()
            s.fill = not s.fill; window:refresh() end },
    }
    local row3 = {
        { text = _("Undo"), enabled = #s.model.undo_stack > 0, callback = function()
            s.model:undo(); s.dirty = true; window:refresh() end },
        { text = _("Redo"), enabled = #s.model.redo_stack > 0, callback = function()
            s.model:redo(); s.dirty = true; window:refresh() end },
        { text = s.grid and _("Grid: on") or _("Grid: off"), callback = function()
            s.grid = not s.grid; window:refresh() end },
    }
    if s.reference then
        table.insert(row3, { text = s.show_reference and _("Guide: on") or _("Guide: off"), callback = function()
            s.show_reference = not s.show_reference; window:refresh() end })
    else
        table.insert(row3, { text = _("Clear"), enabled = #s.model.shapes > 0, callback = function()
            s.model:clear(); s.dirty = true; window:refresh() end })
    end
    local row4 = {
        { text = _("New"), callback = function() self:askDiscard(window, function() self:resetSession(window) end) end },
        { text = _("Open…"), callback = function() self:askDiscard(window, function() self:chooseIcon(window) end) end },
        { text = _("Suits…"), callback = function() self:askDiscard(window, function() self:chooseSuit(window) end) end },
        { text = _("Save"), font_bold = true, callback = function() self:save(window) end },
    }
    local buttons = ButtonTable:new{
        width = inner,
        show_parent = window,
        buttons = { row1, row2, row3, row4 },
    }

    local room = height - 2 * margin - title:getSize().h - buttons:getSize().h - 3 * Size.padding.small
    local sheet = math.max(120, math.min(inner, room))
    local canvas = Canvas:new{ size = sheet, session = s }

    return FrameContainer:new{
        padding = margin,
        margin = 0,
        bordersize = 0,
        width = width,
        height = height,
        VerticalGroup:new{
            align = "center",
            title,
            VerticalSpan:new{ width = Size.padding.small },
            CenterContainer:new{ dimen = Geom:new{ w = inner, h = sheet }, canvas },
            VerticalSpan:new{ width = Size.padding.small },
            buttons,
        },
    }
end

function Icons:resetSession(window)
    window.icon_session = newSession()
    window:refresh()
end

function Icons:askDiscard(window, proceed)
    local s = window.icon_session
    if not s.dirty or #s.model.shapes == 0 then return proceed() end
    UIManager:show(ConfirmBox:new{
        text = _("Throw away the changes you haven't saved?"),
        ok_text = _("Discard"),
        ok_callback = proceed,
    })
end

function Icons:chooseStamp(window)
    local s = window.icon_session
    local dialog
    local rows, row = {}, {}
    for _, st in ipairs(Model.STAMPS) do
        table.insert(row, { text = st.name, callback = function()
            UIManager:close(dialog)
            s.stamp, s.tool = st.id, "stamp"
            window:refresh()
        end })
        if #row == 3 then table.insert(rows, row); row = {} end
    end
    if #row > 0 then table.insert(rows, row) end
    dialog = ButtonDialog:new{ title = _("Stamps: tap the sheet to place one"), buttons = rows }
    UIManager:show(dialog)
end

--- Names of the icons KOReader has built in (for tracing).
local function builtinIcons()
    local names = {}
    local dir = "resources/icons/mdlight"
    if lfs.attributes(dir, "mode") == "directory" then
        for f in lfs.dir(dir) do
            local n = f:match("^(.+)%.svg$")
            if n then names[#names + 1] = n end
        end
    end
    table.sort(names)
    return names
end

local function mine()
    local names = {}
    if lfs.attributes(sourceDir(), "mode") == "directory" then
        for f in lfs.dir(sourceDir()) do
            local n = f:match("^(.+)%.lua$")
            if n then names[#names + 1] = n end
        end
    end
    table.sort(names)
    return names
end

function Icons:chooseIcon(window)
    local items = {}
    local my = mine()
    if #my > 0 then
        table.insert(items, { text = _("Your icons"), bold = true, dim = true })
        for _, n in ipairs(my) do
            table.insert(items, { text = n, mandatory = _("hold to delete"), kind = "mine", name = n })
        end
    end
    table.insert(items, { text = _("Built-in icons: open one to trace over it"), bold = true, dim = true })
    for _, n in ipairs(builtinIcons()) do
        table.insert(items, { text = n, kind = "builtin", name = n })
    end
    local menu
    menu = Menu:new{
        title = _("Open an icon"),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_, item)
            if not item.kind then return end
            UIManager:close(menu)
            self:openIcon(window, item.kind, item.name)
        end,
        onMenuHold = function(_, item)
            if item.kind ~= "mine" then return true end
            UIManager:show(ConfirmBox:new{
                text = T(_("Delete your icon “%1”?\nThe built-in icon of that name (if any) is used again after a restart."), item.name),
                ok_text = _("Delete"),
                ok_callback = function()
                    os.remove(sourceDir() .. "/" .. item.name .. ".lua")
                    os.remove(iconsDir() .. "/" .. item.name .. ".svg")
                    UIManager:close(menu)
                    self:chooseIcon(window)
                end,
            })
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

--- The Holy Cart library: 302 suit symbols, each made by a formula. Tap to open one as a drawing you
-- can change; hold to read its formula.
function Icons:chooseSuit(window)
    local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]*$") or "."
    local chunk = loadfile(here .. "/holycart.lua")
    local ok, suits = false, nil
    if chunk then ok, suits = pcall(chunk) end
    if not ok or type(suits) ~= "table" then
        UIManager:show(InfoMessage:new{ text = _("The Holy Cart suits are not installed (holycart.lua is missing)."), icon = "notice-warning" })
        return
    end
    local items = {}
    for _, su in ipairs(suits) do
        table.insert(items, { text = su.id:gsub("^suit%-", "") .. "  " .. su.name, mandatory = su.family, suit = su })
    end
    local menu
    menu = Menu:new{
        title = T(_("Holy Cart suits (%1)"), #suits),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_, item)
            if not item.suit then return end
            UIManager:close(menu)
            local s = newSession()
            s.name = "suit" .. item.suit.id:gsub("^suit%-", "")
            s.model = Model.fromSuit(item.suit)
            s.dirty = true
            window.icon_session = s
            window:refresh()
        end,
        onMenuHold = function(_, item)
            if not item.suit then return true end
            UIManager:show(InfoMessage:new{
                text = item.suit.id .. ": " .. item.suit.name .. "\n" .. _("Formula") .. ": " .. item.suit.formula
                    .. "\n" .. _("Parameters") .. ": " .. item.suit.params,
            })
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function Icons:openIcon(window, kind, name)
    local s = newSession()
    s.name = name
    if kind == "mine" then
        local text = readFile(sourceDir() .. "/" .. name .. ".lua")
        local model = text and Model.fromLua(text)
        if model then
            s.model = model
        else
            UIManager:show(InfoMessage:new{ text = _("Could not read that drawing."), icon = "notice-warning" })
            return
        end
    else
        -- A built-in icon: shown as a faint guide to trace over; saving replaces it.
        s.reference = name
    end
    window.icon_session = s
    window:refresh()
end

function Icons:save(window)
    local s = window.icon_session
    if #s.model.shapes == 0 then
        UIManager:show(InfoMessage:new{ text = _("The sheet is empty. A blank icon is fine too: draw one dot, or keep it as it is."), timeout = 4 })
    end
    local dialog
    dialog = InputDialog:new{
        title = _("Save icon as"),
        description = _("Use a built-in icon's name (for example “home”) to replace it everywhere."),
        input = s.name or "",
        input_hint = _("icon name"),
        kos_toolbar = false,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local name = Model.cleanName(dialog:getInputText())
                if not name then
                    UIManager:show(InfoMessage:new{ text = _("Use letters, digits, dash or underscore."), timeout = 3 })
                    return
                end
                UIManager:close(dialog)
                ensureDir(iconsDir())
                ensureDir(sourceDir())
                local ok1 = writeFile(iconsDir() .. "/" .. name .. ".svg", s.model:toSVG())
                local ok2 = writeFile(sourceDir() .. "/" .. name .. ".lua", s.model:toLua())
                if ok1 and ok2 then
                    s.name, s.dirty = name, false
                    window:refresh()
                    UIManager:askForRestart(T(_("Saved “%1”.\n\nRestart KOReader to see it in the menus and on the Home screen."), name))
                else
                    UIManager:show(InfoMessage:new{ text = _("Could not save the icon."), icon = "notice-warning" })
                end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Icons:launchApp()
    local AppWindow = require("apps/kos/appwindow")
    local plugin = self
    local window
    window = AppWindow:open{
        title = _("Icons"),
        confirm_close = function(win, do_close)
            local s = win.icon_session
            if s and s.dirty and #s.model.shapes > 0 then
                UIManager:show(ConfirmBox:new{
                    text = _("Close without saving this icon?"),
                    ok_text = _("Close"),
                    ok_callback = do_close,
                })
            else
                do_close()
            end
        end,
        build = function(win, width, height)
            win.icon_session = win.icon_session or newSession()
            return plugin:build(win, width, height)
        end,
    }
end

Icons._drawShape = drawShape -- for tests
return Icons

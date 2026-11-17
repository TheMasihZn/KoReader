--[[--
3D viewer: STL files and design scripts, drawn as outlines (few redraws, good on e-paper).

* Models live in <home folder>/kosModels: `.stl` files, and `.lua` design scripts.
* A design script returns a mesh built from `box`, `cylinder`, `join`, `move` (see apps/kos/mesh.lua),
  e.g.  return join(box(40, 20, 4), cylinder(6, 12, 48, 20, 10, 4))
  The assistant writes these from a spoken description; "Export STL" saves the result for a slicer.
* The numbers (volume, area, mass, overhang) come from apps/kos/mesh.lua, which states each formula.
]]

local AppWindow = require("apps/kos/appwindow")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Home = require("apps/kos/home")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local Mesh = require("apps/kos/mesh")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local Viewer = WidgetContainer:extend{ name = "viewer3d", is_doc_only = false }

local MAX_EDGES = 6000

local function modelsDir()
    local d = Home.get() .. "/kosModels"
    if lfs.attributes(d, "mode") ~= "directory" then lfs.mkdir(d) end
    return d
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local EXAMPLE = [[-- A plate with a post: 40 x 20 x 4 mm, post 12 mm tall. Change the numbers and open it again.
return join(box(40, 20, 4), cylinder(6, 12, 48, 20, 10, 4))
]]

---------------------------------------------------------------------------
-- The picture
---------------------------------------------------------------------------

local View = Widget:extend{ state = nil }

function View:getSize() return self.dimen end

local function line(bb, x1, y1, x2, y2, color)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps < 1 then bb:paintRect(math.floor(x1), math.floor(y1), 1, 1, color) return end
    steps = math.floor(steps)
    for i = 0, steps do
        bb:paintRect(math.floor(x1 + dx * i / steps), math.floor(y1 + dy * i / steps), 1, 1, color)
    end
end

function View:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local size = self.dimen.w
    bb:paintRect(x, y, size, self.dimen.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, size, self.dimen.h, 1, Blitbuffer.Color8(0xA0))
    local st = self.state
    if not st.mesh then return end
    local project = Mesh.projector(st.mesh, st.yaw, st.pitch, size, st.zoom)
    local edges = st.edges
    local step = math.max(1, math.ceil(#edges / MAX_EDGES))
    for i = 1, #edges, step do
        local e = edges[i]
        local ax, ay = project(e[1])
        local bx, by = project(e[2])
        line(bb, x + ax, y + ay, x + bx, y + by, Blitbuffer.COLOR_BLACK)
    end
end

---------------------------------------------------------------------------
-- State and report
---------------------------------------------------------------------------

local function newState()
    return { mesh = nil, name = nil, yaw = 35, pitch = 60, zoom = 1, material = 1, edges = {}, source = nil }
end

local function setMesh(st, mesh, name, source)
    st.mesh, st.name, st.source = mesh, name, source
    local _n, _bad, feature = Mesh.edges(mesh, 30)
    st.edges = feature
    st.report = nil
end

local function reportLines(st)
    if not st.mesh then
        return { _("Open a model: STL file or design script (Lua) from the kosModels folder.") }
    end
    local mat = Mesh.MATERIALS[st.material]
    local r = Mesh.report(st.mesh, mat.density)
    local lines = {
        string.format("%s  (%d triangles)", st.name or "?", r.triangles),
        string.format(_("Size %.1f × %.1f × %.1f mm"), r.size[1], r.size[2], r.size[3]),
        string.format(_("Volume %.2f cm³   Surface %.1f cm²"), math.abs(r.volume_mm3) / 1000, r.area_mm2 / 100),
        string.format(_("Weight in %s: %.1f g (solid)"), mat.name, r.mass_g),
        r.closed and _("Closed shape: printable") or string.format(_("Not closed: %d open edges, a slicer may refuse it"), r.open_edges),
        string.format(_("Overhang over 45°: %.1f cm²"), r.overhang_mm2 / 100),
    }
    if r.inside_out then table.insert(lines, _("The triangles face inward (inside out).")) end
    return lines
end

---------------------------------------------------------------------------
-- Opening and saving
---------------------------------------------------------------------------

local function listModels()
    local items = {}
    local dir = modelsDir()
    for f in lfs.dir(dir) do
        local ext = f:match("%.(%w+)$")
        if ext and (ext:lower() == "stl" or ext:lower() == "lua") then
            table.insert(items, f)
        end
    end
    table.sort(items)
    return items, dir
end

local function openPath(st, path)
    local name = path:match("([^/]+)$")
    local data = readFile(path)
    if not data then
        UIManager:show(InfoMessage:new{ text = _("Could not read that file."), icon = "notice-warning" })
        return false
    end
    local mesh, err
    if name:lower():match("%.lua$") then
        mesh, err = Mesh.runScript(data)
    else
        mesh, err = Mesh.parseSTL(data)
    end
    if not mesh then
        UIManager:show(InfoMessage:new{ text = _("Could not open ") .. name .. ":\n" .. tostring(err), icon = "notice-warning" })
        return false
    end
    setMesh(st, mesh, name, path)
    return true
end

function Viewer:chooseModel(win, st)
    local names, dir = listModels()
    if #names == 0 then
        local path = dir .. "/example.lua"
        local f = io.open(path, "w")
        if f then f:write(EXAMPLE); f:close() end
        names = { "example.lua" }
    end
    local items = {}
    for _i, n in ipairs(names) do items[#items + 1] = { text = n, name = n } end
    local menu
    menu = Menu:new{
        title = _("Models in ") .. dir,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            if openPath(st, dir .. "/" .. item.name) then win:refresh() end
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function Viewer:exportSTL(st)
    if not st.mesh then return end
    local base = (st.name or "design"):gsub("%.%w+$", "")
    local path = modelsDir() .. "/" .. base .. ".stl"
    local f = io.open(path, "wb")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Could not write the file."), icon = "notice-warning" })
        return
    end
    f:write(Mesh.toSTL(st.mesh, base))
    f:close()
    UIManager:show(InfoMessage:new{ text = _("Saved ") .. path })
end

---------------------------------------------------------------------------
-- The app
---------------------------------------------------------------------------

function Viewer:launchApp()
    local st = newState()
    local face = Font:getFace("infont", 15)
    local function build(win, width, height)
        local side = math.min(width, math.floor(height * 0.5))
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, View:new{ state = st, dimen = Geom:new{ w = side, h = side } })
        for _i, text in ipairs(reportLines(st)) do
            table.insert(group, TextWidget:new{ text = text, face = face, max_width = width })
        end
        local function turn(dyaw, dpitch)
            return function()
                st.yaw = (st.yaw + dyaw) % 360
                st.pitch = math.max(-90, math.min(90, st.pitch + dpitch))
                win:refresh()
            end
        end
        local rows = {
            {
                { text = _("Open…"), callback = function() self:chooseModel(win, st) end },
                { text = _("Export STL"), enabled = st.mesh ~= nil, callback = function() self:exportSTL(st) end },
                { text = Mesh.MATERIALS[st.material].name, callback = function()
                    st.material = st.material % #Mesh.MATERIALS + 1
                    win:refresh()
                end },
            },
            {
                { text = "◀", callback = turn(-15, 0) },
                { text = "▶", callback = turn(15, 0) },
                { text = "▲", callback = turn(0, -15) },
                { text = "▼", callback = turn(0, 15) },
            },
            {
                { text = "＋", callback = function() st.zoom = math.min(8, st.zoom * 1.25); win:refresh() end },
                { text = "－", callback = function() st.zoom = math.max(0.25, st.zoom / 1.25); win:refresh() end },
                { text = _("Reset view"), callback = function() st.yaw, st.pitch, st.zoom = 35, 60, 1; win:refresh() end },
                { text = _("Top"), callback = function() st.yaw, st.pitch = 0, 0; win:refresh() end },
            },
        }
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = win })
        return group
    end
    AppWindow:open{ title = _("3D viewer"), build = build }
end

return Viewer

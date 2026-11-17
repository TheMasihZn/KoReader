--[[--
Pendulums: N point-mass pendulums on rigid rods (exact equations, RK4 steps).
The picture is a LaTeX-art scene (apps/kos/latexart); each frame also lists its own formulas.
]]
local InfoMessage = require("ui/widget/infomessage")
local LatexArt = require("apps/kos/latexart")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Physlab = require("apps/kos/physlab")
local SimWindow = require("apps/kos/simwindow")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Pendulums = WidgetContainer:extend{ name = "pendulums", is_doc_only = false }

local cfg = { n = 3, length = 1.0, mass = 1.0, g = 9.81, angle = 120, dt = 0.004, substeps = 6 }

local function make()
    local lengths, masses, angles = {}, {}, {}
    for i = 1, cfg.n do
        lengths[i] = cfg.length
        masses[i] = cfg.mass
        angles[i] = math.rad(cfg.angle) + 0.002 * i -- a tiny difference: this is where chaos shows
    end
    return Physlab.pendulum.new{ n = cfg.n, lengths = lengths, masses = masses, angles = angles, g = cfg.g }
end

local function scene(p)
    local reach = 0
    for i = 1, p.n do reach = reach + p.l[i] end
    reach = reach * 1.1
    local S = LatexArt.scene{ xmin = -reach, xmax = reach, ymin = -reach, ymax = reach }
    S:rect(-0.1 * reach, 0, 0.2 * reach, 0.03 * reach, { fill = true })
    local px, py = 0, 0
    local pos = p:positions()
    for i = 1, p.n do
        S:line(px, py, pos[i][1], pos[i][2], { width = 2, gray = 0.25 })
        px, py = pos[i][1], pos[i][2]
    end
    for i = 1, p.n do
        S:circle(pos[i][1], pos[i][2], 0.04 * reach * (1 + 0.4 * p.m[i] / (p.m[1])), { fill = true, gray = i == p.n and 0 or 0.35 })
    end
    S:dot(0, 0)
    -- the last bob's path (a few recent positions) shows the chaos
    p.trail = p.trail or {}
    table.insert(p.trail, { pos[p.n][1], pos[p.n][2] })
    if #p.trail > 60 then table.remove(p.trail, 1) end
    if #p.trail > 1 then S:path(p.trail, { gray = 0.6 }) end
    return S
end

local function advance(p)
    for _i = 1, cfg.substeps do p:step(cfg.dt) end
end

function Pendulums:params(p, apply)
    local d
    d = MultiInputDialog:new{
        title = _("Pendulum parameters"),
        fields = {
            { description = _("How many pendulums (1 to 12)"), text = tostring(cfg.n), input_type = "number" },
            { description = _("Rod length (m)"), text = tostring(cfg.length), input_type = "number" },
            { description = _("Mass of each bob (kg)"), text = tostring(cfg.mass), input_type = "number" },
            { description = _("Gravity g (m/s²)"), text = tostring(cfg.g), input_type = "number" },
            { description = _("Start angle of every rod (degrees from straight down)"), text = tostring(cfg.angle), input_type = "number" },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Apply"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                local n = math.floor(tonumber(f[1]) or cfg.n)
                cfg.n = math.max(1, math.min(12, n))
                cfg.length = math.max(0.05, tonumber(f[2]) or cfg.length)
                cfg.mass = math.max(0.01, tonumber(f[3]) or cfg.mass)
                cfg.g = math.max(0.1, tonumber(f[4]) or cfg.g)
                cfg.angle = tonumber(f[5]) or cfg.angle
                apply(make())
            end },
        }},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function Pendulums:launchApp()
    SimWindow.open{
        title = _("Pendulums"),
        make = make,
        advance = advance,
        scene = scene,
        formulas = function(p) return p:formulas() end,
        params = function(p, apply) self:params(p, apply) end,
        export = function(p) return LatexArt.tikz(scene(p)) end,
        fps = 4,
    }
end

return Pendulums

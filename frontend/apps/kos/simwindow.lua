--[[--
Simulation window: a picture drawn from a LaTeX-art scene, the formulas of the current frame
underneath, and Play / Step / Reset / Parameters / LaTeX buttons.

    SimWindow.open{
        title = "Pendulums",
        make = function() return sim end,              -- a fresh simulation (also on Reset)
        advance = function(sim) end,                   -- one frame
        scene = function(sim) return LatexArt scene end,
        formulas = function(sim) return { "tex", ... } end,
        params = function(sim, apply) ... end,         -- optional: ask for new values, then apply(new_sim)
        fps = 4,                                       -- e-ink friendly
        export = function(sim) return tex source end,  -- optional: LaTeX source of this frame
    }

A frame is one step of the simulation: the picture and the formulas always describe the same frame.
]]

local AppWindow = require("apps/kos/appwindow")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local LatexArt = require("apps/kos/latexart")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

local SimWindow = {}

local SceneWidget = Widget:extend{ scene = nil, formulas_face = nil }

function SceneWidget:getSize() return self.dimen end

function SceneWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, self.dimen.w, self.dimen.h, 1, Blitbuffer.Color8(0xA0))
    local face = Font:getFace("smallinfofont")
    LatexArt.paint(self.scene, bb, x, y, self.dimen.w, self.dimen.h, Blitbuffer, function(b, tx, ty, text)
        local tw = TextWidget:new{ text = text, face = face }
        tw:paintTo(b, math.floor(tx - tw:getSize().w / 2), math.floor(ty - tw:getSize().h / 2))
        tw:free()
    end)
end

function SimWindow.open(o)
    local state = { sim = o.make(), playing = false }
    local window

    local function tick()
        if not state.playing or not window or window.closed then return end
        pcall(o.advance, state.sim)
        window:refresh()
        UIManager:scheduleIn(1 / (o.fps or 4), tick)
    end

    local function setPlaying(on)
        state.playing = on
        if on then UIManager:scheduleIn(0.05, tick) end
        window:refresh()
    end

    local function build(win, width, height)
        local scene_h = math.floor(height * 0.5)
        local face = Font:getFace("infont", 15)
        local group = VerticalGroup:new{ align = "left" }
        local ok, scene = pcall(o.scene, state.sim)
        if ok and scene then
            table.insert(group, SceneWidget:new{ scene = scene, dimen = Geom:new{ w = width, h = scene_h } })
        else
            table.insert(group, TextWidget:new{ text = tostring(scene), face = face, max_width = width })
        end
        local okf, formulas = pcall(o.formulas, state.sim)
        for _i, tex in ipairs(okf and formulas or {}) do
            table.insert(group, TextWidget:new{ text = LatexArt.unicode(tex), face = face, max_width = width })
        end
        local rows = {{
            { text = state.playing and _("Pause") or _("Play"), callback = function() setPlaying(not state.playing) end },
            { text = _("Step"), callback = function() pcall(o.advance, state.sim) win:refresh() end },
            { text = _("Reset"), callback = function() state.sim = o.make() win:refresh() end },
        }, {
            { text = _("Parameters"), enabled = o.params ~= nil, callback = function()
                setPlaying(false)
                o.params(state.sim, function(new_sim) state.sim = new_sim win:refresh() end)
            end },
            { text = _("LaTeX source"), enabled = o.export ~= nil, callback = function()
                setPlaying(false)
                local InfoMessage = require("ui/widget/infomessage")
                local path = require("datastorage"):getDataDir() .. "/" .. (o.title or "frame"):lower():gsub("%W", "") .. "-frame.tex"
                local f = io.open(path, "w")
                if f then
                    f:write("\\documentclass{standalone}\n\\usepackage{tikz}\n\\begin{document}\n", o.export(state.sim), "\n\\end{document}\n")
                    f:close()
                    UIManager:show(InfoMessage:new{ text = _("Saved this frame as LaTeX:\n") .. path })
                end
            end },
        }}
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = win })
        return group
    end

    window = AppWindow:open{
        title = o.title,
        build = build,
        on_close = function() state.playing = false end,
    }
    return window
end

return SimWindow

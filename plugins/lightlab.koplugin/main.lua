--[[--
Light lab: photons through one or two slits (Young's experiment).
Every frame adds a few photons, each landing where chance and the intensity formula say.
The picture is a LaTeX-art scene; the formulas under it describe that very frame, including
the entropy of the pattern so far.
]]
local LatexArt = require("apps/kos/latexart")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Physlab = require("apps/kos/physlab")
local SimWindow = require("apps/kos/simwindow")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local LightLab = WidgetContainer:extend{ name = "lightlab", is_doc_only = false }

local cfg = { slits = 2, wavelength_nm = 500, separation_um = 20, width_um = 5, distance_m = 1.0, per_frame = 40 }

local function make()
    return Physlab.slits.new{
        slits = cfg.slits, wavelength = cfg.wavelength_nm * 1e-9, separation = cfg.separation_um * 1e-6,
        width = cfg.width_um * 1e-6, distance = cfg.distance_m,
    }
end

local function scene(s)
    local S = LatexArt.scene{ xmin = -1, xmax = 1, ymin = 0, ymax = 1 }
    -- left: the barrier with its slit(s); right: the screen's histogram
    S:line(-0.9, 0.05, -0.9, 0.95, { width = 1, gray = 0.5 })
    S:text(-0.9, 0.98, "$\\mathrm{source}$")
    S:line(-0.45, 0.05, -0.45, 0.42, { width = 4 })
    S:line(-0.45, 0.58, -0.45, 0.95, { width = 4 })
    if s.slits == 2 then
        S:line(-0.45, 0.47, -0.45, 0.53, { width = 4 })
        S:line(-0.9, 0.5, -0.45, 0.46, { width = 1, gray = 0.7 })
        S:line(-0.9, 0.5, -0.45, 0.54, { width = 1, gray = 0.7 })
    else
        S:line(-0.9, 0.5, -0.45, 0.5, { width = 1, gray = 0.7 })
    end
    S:text(-0.45, 0.98, s.slits == 2 and "$\\mathrm{two\\ slits}$" or "$\\mathrm{one\\ slit}$")
    S:line(0.2, 0.05, 0.2, 0.95, { width = 2 })
    local peak = 1
    for i = 1, s.bins do if s.counts[i] > peak then peak = s.counts[i] end end
    local bin_h = 0.9 / s.bins
    for i = 1, s.bins do
        local c = s.counts[i]
        if c > 0 then
            local y = 0.05 + (i - 1) * bin_h
            S:rect(0.2, y, 0.75 * c / peak, bin_h * 0.9, { fill = true, gray = 0.2 })
        end
    end
    return S
end

local function advance(s) s:addPhotons(cfg.per_frame) end

function LightLab:params(s, apply)
    local d
    d = MultiInputDialog:new{
        title = _("Experiment parameters"),
        fields = {
            { description = _("Slits: 1 or 2"), text = tostring(cfg.slits), input_type = "number" },
            { description = _("Wavelength (nm)"), text = tostring(cfg.wavelength_nm), input_type = "number" },
            { description = _("Slit spacing d (µm)"), text = tostring(cfg.separation_um), input_type = "number" },
            { description = _("Slit width a (µm)"), text = tostring(cfg.width_um), input_type = "number" },
            { description = _("Distance to screen L (m)"), text = tostring(cfg.distance_m), input_type = "number" },
            { description = _("Photons per frame"), text = tostring(cfg.per_frame), input_type = "number" },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Apply"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                cfg.slits = (tonumber(f[1]) or 2) <= 1 and 1 or 2
                cfg.wavelength_nm = math.max(100, math.min(1500, tonumber(f[2]) or cfg.wavelength_nm))
                cfg.separation_um = math.max(1, tonumber(f[3]) or cfg.separation_um)
                cfg.width_um = math.max(0.5, math.min(cfg.separation_um, tonumber(f[4]) or cfg.width_um))
                cfg.distance_m = math.max(0.05, tonumber(f[5]) or cfg.distance_m)
                cfg.per_frame = math.max(1, math.min(500, math.floor(tonumber(f[6]) or cfg.per_frame)))
                apply(make())
            end },
        }},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function LightLab:launchApp()
    SimWindow.open{
        title = _("Light lab"),
        make = make,
        advance = advance,
        scene = scene,
        formulas = function(s) return s:formulas() end,
        params = function(s, apply) self:params(s, apply) end,
        export = function(s) return LatexArt.tikz(scene(s)) end,
        fps = 3,
    }
end

return LightLab

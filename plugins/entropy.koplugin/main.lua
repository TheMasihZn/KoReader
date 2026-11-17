local AppWindow = require("apps/kos/appwindow")
local ButtonTable = require("ui/widget/buttontable")
local Entropy = require("apps/kos/entropycalc")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Plugin = WidgetContainer:extend{ name = "kosEntropy", is_doc_only = false }

local AXES = { { "events", _("Events") }, { "positions", _("Positions") }, { "frames", _("Frames") } }

local function weights()
    local w = G_reader_settings:readSetting("kos_entropy_weights")
    if type(w) ~= "table" then w = { events = { 1, 1 }, positions = { 1, 1, 1, 1 }, frames = { 1 } } end
    return w
end

local function parse(text)
    local t = {}
    for n in text:gmatch("[%d%.]+") do t[#t + 1] = tonumber(n) end
    if #t == 0 then t[1] = 1 end
    return t
end

function Plugin:launchApp()
    local win
    local function build(w, width, height)
        local W = weights()
        local h, max, parts = Entropy.frame(W)
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, TextBoxWidget:new{ face = Font:getFace("infont", 15), width = width,
            text = _("This is Shannon entropy, standing in for Framal Entropy. Tap an axis to change its weights, for example 1, 1, 2.") })
        table.insert(group, TextBoxWidget:new{ face = Font:getFace("infont", 14), width = width, text = Entropy.latex(h, max, parts) })
        local rows = {}
        for _i, ax in ipairs(AXES) do
            local id, label = ax[1], ax[2]
            rows[#rows + 1] = {{ text = label .. ":  " .. table.concat(W[id], ", "), callback = function()
                local d
                d = InputDialog:new{ title = label, input = table.concat(W[id], ", "), buttons = {{
                    { text = _("Cancel"), callback = function() UIManager:close(d) end },
                    { text = _("Set"), is_enter_default = true, callback = function()
                        W[id] = parse(d:getInputText()); G_reader_settings:saveSetting("kos_entropy_weights", W)
                        UIManager:close(d); if win then win:refresh() end
                    end },
                }} }
                UIManager:show(d); d:onShowKeyboard()
            end }}
        end
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = w })
        return group
    end
    win = AppWindow:open{ title = _("Entropy"), build = build }
end

return Plugin

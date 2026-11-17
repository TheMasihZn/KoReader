local AppRegistry = require("apps/kos/appregistry")
local AppWindow = require("apps/kos/appwindow")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Theme = require("apps/kos/theme")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Plugin = WidgetContainer:extend{ name = "kosThemes", is_doc_only = false }

local CHOICES = {
    fontSize = { 14, 17, 20, 24 }, lineWidth = { 1, 2, 3, 4 }, cornerRadius = { 0, 6, 12, 20 }, spacing = { 4, 8, 12, 16 },
    iconSize = { "small", "medium", "large" }, invert = { true, false }, accent = { "black", "gray" },
}
local ORDER = { "fontSize", "lineWidth", "cornerRadius", "spacing", "iconSize", "invert", "accent" }

function Plugin:launchApp()
    local scope = "default"
    local win
    local function pick(key)
        local dlg
        local rows = {}
        for _i, v in ipairs(CHOICES[key]) do
            rows[#rows + 1] = {{ text = tostring(v), callback = function() UIManager:close(dlg); Theme.set(scope, key, v); win:refresh() end }}
        end
        rows[#rows + 1] = {{ text = _("Back to default"), callback = function() UIManager:close(dlg); Theme.clear(scope, key); win:refresh() end }}
        dlg = ButtonDialog:new{ title = key, buttons = rows }
        UIManager:show(dlg)
    end
    local function build(w, width, height)
        local theme = scope == "default" and Theme.default() or Theme.forApp(scope)
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, TextBoxWidget:new{ face = Font:getFace("infont", 15), width = width,
            text = (scope == "default") and _("Default look for every app.") or (_("Look for ") .. scope .. _(" only; anything not set here follows the default.")) })
        local rows = {{{ text = _("Editing: ") .. scope, callback = function()
            local dlg; local r = {{ { text = _("Default (every app)"), callback = function() UIManager:close(dlg); scope = "default"; win:refresh() end } }}
            for _i, a in ipairs(AppRegistry:getApps()) do r[#r + 1] = {{ text = a.title, callback = function() UIManager:close(dlg); scope = a.title; win:refresh() end }} end
            dlg = ButtonDialog:new{ title = _("Which app?"), buttons = r }; UIManager:show(dlg)
        end }}}
        for _i, key in ipairs(ORDER) do rows[#rows + 1] = {{ text = key .. ":  " .. tostring(theme[key]), callback = function() pick(key) end }} end
        rows[#rows + 1] = {{ text = _("Save as…"), callback = function()
            local d; d = InputDialog:new{ title = _("Theme name"), buttons = {{ { text = _("Cancel"), callback = function() UIManager:close(d) end },
                { text = _("Save"), is_enter_default = true, callback = function() local n = d:getInputText(); UIManager:close(d); if n ~= "" then Theme.saveAs(n) end end } }} }
            UIManager:show(d); d:onShowKeyboard()
        end }, { text = _("Use saved…"), callback = function()
            local dlg; local r = {}
            for _i, n in ipairs(Theme.names()) do r[#r + 1] = {{ text = n, callback = function() UIManager:close(dlg); Theme.use(n); win:refresh() end }} end
            if #r == 0 then r[1] = {{ text = _("None saved yet"), enabled = false }} end
            dlg = ButtonDialog:new{ title = _("Saved themes"), buttons = r }; UIManager:show(dlg)
        end }}
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = w })
        return group
    end
    win = AppWindow:open{ title = _("Themes"), build = build }
end

return Plugin

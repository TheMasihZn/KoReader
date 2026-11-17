local Device = require("device")
local IdeHandoff = require("apps/kos/idehandoff")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Plugin = WidgetContainer:extend{ name = "kosIdeHandoff", is_doc_only = false }

function Plugin:init()
    if not Device:isAndroid() then return end
    self.ui.menu:registerToMainMenu(self)
    local fm = self.ui.file_chooser and self.ui or nil
    if fm and fm.addFileDialogButtons then
        fm:addFileDialogButtons("kos_ide", function(file, is_file)
            if not is_file or not IdeHandoff.supported(file) then return end
            return {{ text = _("Open in IDE"), callback = function()
                local ok, msg = IdeHandoff.open(file, G_reader_settings:readSetting("kos_ide_package"))
                if not ok then UIManager:show(InfoMessage:new{ text = msg, timeout = 6 }) end
            end }}
        end)
    end
end

function Plugin:addToMainMenu(menu_items)
    menu_items.kos_ide = {
        text = _("IDE for Open in IDE"),
        sorting_hint = "tools",
        keep_menu_open = true,
        callback = function()
            local d
            d = InputDialog:new{
                title = _("IDE package name"),
                input = G_reader_settings:readSetting("kos_ide_package") or "",
                input_hint = _("empty = let Android ask"),
                buttons = {{
                    { text = _("Cancel"), callback = function() UIManager:close(d) end },
                    { text = _("Save"), is_enter_default = true, callback = function()
                        G_reader_settings:saveSetting("kos_ide_package", d:getInputText())
                        UIManager:close(d)
                    end },
                }},
            }
            UIManager:show(d); d:onShowKeyboard()
        end,
    }
end

return Plugin

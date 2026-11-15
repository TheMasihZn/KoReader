--[[--
Preview: "Preview" in the long-press menu of any file (File manager, History, Collections).
Pictures come from apps/kos/thumbs (cached, size-capped); text shows its first lines.
]]
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local Preview = WidgetContainer:extend{ name = "preview", is_doc_only = false }

local function show(file)
    local Thumbs = require("apps/kos/thumbs")
    local Screen = require("device").screen
    local kind = Thumbs.kind(file)
    if kind == "text" then
        local s = Thumbs.textSnippet(file, 14)
        UIManager:show(InfoMessage:new{ text = s or _("The file is empty."), show_icon = false })
        return
    end
    if not kind then
        UIManager:show(InfoMessage:new{ text = _("No preview for this kind of file yet.") })
        return
    end
    local px = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.8)
    local bb = Thumbs.get(file, px)
    if not bb then
        UIManager:show(InfoMessage:new{ text = _("This file has no picture to show.") })
        return
    end
    UIManager:show(InfoMessage:new{ text = " ", show_icon = true, image = bb, image_width = bb:getWidth(), image_height = bb:getHeight() })
end

function Preview:init()
    local fm = self.ui
    if fm and fm.addFileDialogButtons then
        fm:addFileDialogButtons("kos_preview", function(file, is_file)
            if not is_file then return end
            local Thumbs = require("apps/kos/thumbs")
            if not Thumbs.kind(file) then return end
            return {{
                text = _("Preview"),
                callback = function()
                    local fc = fm.file_chooser
                    if fc and fc.file_dialog then UIManager:close(fc.file_dialog) end
                    local ok, err = pcall(show, file)
                    if not ok then
                        UIManager:show(InfoMessage:new{ text = T(_("Preview failed: %1"), tostring(err)) })
                    end
                end,
            }}
        end)
    end
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
end

function Preview:addToMainMenu(menu_items)
    menu_items.kos_preview_cache = {
        text = _("Preview cache"),
        sorting_hint = "tools",
        keep_menu_open = true,
        callback = function()
            local Thumbs = require("apps/kos/thumbs")
            local i = Thumbs.cacheInfo()
            UIManager:show(ConfirmBox:new{
                text = T(_("%1 pictures, %2 MB of %3 MB.\n\nClear the cache?"), i.files, math.floor(i.bytes / 1048576), math.floor(i.cap / 1048576)),
                ok_text = _("Clear"),
                ok_callback = function() Thumbs.clear() end,
            })
        end,
    }
end

return Preview

local FolderFile = require("apps/kos/folderfile")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Plugin = WidgetContainer:extend{ name = "kosFolderFile", is_doc_only = false }

function Plugin:init()
    local fm = self.ui and self.ui.file_chooser and self.ui or nil
    if not (fm and fm.addFileDialogButtons) then return end
    fm:addFileDialogButtons("kos_folderfile", function(file, is_file)
        if not is_file then return end
        local parent = file:match("^(.*)/[^/]+$") or ""
        local name = file:match("([^/]+)$") or ""
        local base = name:match("^(.+)%.[^%.]+$") or name
        local inside = parent:match("([^/]+)$") == base      -- already in a folder with its name
        return {{ text = inside and _("Unwrap from its folder") or _("Wrap in its own folder"), callback = function()
            local ok, res = (inside and FolderFile.unwrap or FolderFile.wrap)(file)
            UIManager:show(InfoMessage:new{ text = ok and _("Done.") or tostring(res), timeout = 3 })
            if ok and fm.file_chooser then fm.file_chooser:refreshPath() end
        end }}
    end)
end

return Plugin

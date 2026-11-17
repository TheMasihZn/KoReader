--[[--
The right-click of a touch screen: hold something and a small menu opens right there, with buttons big enough for a finger.

    ContextMenu.show{ title = "Light", items = { { text = "Change", callback = fn }, { text = "Reset", callback = fn } } }
    ContextMenu.size()          -> button height in pixels, from the setting kos_context_size (small, medium, large)

Every item is one wide row; the menu closes before the callback runs. Used by Settings (hold a setting) and Home (hold an app).
]]

local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local UIManager = require("ui/uimanager")

local C = {}
local SIZES = { small = 44, medium = 60, large = 80 }

function C.size()
    local name = G_reader_settings and G_reader_settings:readSetting("kos_context_size") or "large"
    return Device.screen:scaleBySize(SIZES[name] or SIZES.large)
end

function C.show(o)
    local dlg
    local rows = {}
    local face_pt = (G_reader_settings and G_reader_settings:readSetting("kos_context_size") == "small") and 18 or 24
    for _, it in ipairs(o.items or {}) do
        rows[#rows + 1] = {{
            text = it.text,
            font_size = face_pt,
            height = C.size(),
            enabled = it.enabled ~= false,
            callback = function()
                UIManager:close(dlg)
                if it.callback then it.callback() end
            end,
        }}
    end
    dlg = ButtonDialog:new{ title = o.title, title_align = "center", buttons = rows, shrink_unneeded_width = false }
    UIManager:show(dlg)
    return dlg
end

return C

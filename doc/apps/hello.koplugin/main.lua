--[[--
Hello: a template KOReader OS app.

An app is a normal KOReader plugin plus:
  * an `app` table (here in _meta.lua) so it shows up on the home screen,
  * a launchApp() method that opens your window.

Copy this folder to koreader/plugins/, rename it (e.g. notes.koplugin),
change `name` below to match, and restart KOReader.
]]

local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local LuaSettings = require("luasettings")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local Hello = WidgetContainer:extend{
    name = "hello", -- must match the folder name without .koplugin
}

function Hello:init()
    -- Your app's own settings file: koreader/settings/hello.lua
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/hello.lua")
end

-- Called by the home screen when the app is tapped.
function Hello:launchApp()
    -- Require KOReader OS modules here, not at the top of the file:
    -- that keeps the app loadable no matter which plugin is loaded first.
    local AppWindow = require("apps/kos/appwindow")
    AppWindow:open{
        title = _("Hello"),
        -- Called on open and again whenever the window size changes
        -- (rotation, split-screen, unfolding): always lay out for width x height.
        build = function(window, width, height)
            local count = self.settings:readSetting("count", 0)
            return CenterContainer:new{
                dimen = Geom:new{ w = width, h = height },
                VerticalGroup:new{
                    align = "center",
                    TextBoxWidget:new{
                        text = T(_("Window: %1 × %2\nTapped %3 times."), width, height, count),
                        face = Font:getFace("cfont", 22),
                        width = math.floor(width * 0.8),
                        alignment = "center",
                    },
                    VerticalSpan:new{ width = 24 },
                    Button:new{
                        text = _("Tap me"),
                        width = math.floor(width * 0.5),
                        show_parent = window,
                        callback = function()
                            self.settings:saveSetting("count", count + 1)
                            self.settings:flush()
                            window:refresh() -- rebuild with the new state
                        end,
                    },
                },
            }
        end,
    }
end

return Hello

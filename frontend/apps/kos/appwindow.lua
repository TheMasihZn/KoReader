--[[--
A full-screen window for KOReader OS apps.

It gives every app the same frame: a title bar with Home and Close buttons,
the Back key closes it, and it rebuilds itself when the screen size changes
(rotation, split-screen, freeform windows, unfolding a foldable).

You only provide a `build` function that returns your content for a given
size. It is called again on every resize, so never cache sizes yourself.

@usage
    local AppWindow = require("apps/kos/appwindow")
    local TextWidget = require("ui/widget/textwidget")
    local Font = require("ui/font")

    AppWindow:open{
        title = "Hello",
        build = function(window, width, height)
            return TextWidget:new{ text = "Hello world", face = Font:getFace("cfont") }
        end,
    }

Call `window:refresh()` after changing your own state to rebuild the content,
and `window:close()` to close it.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local Screen = Device.screen

local AppWindow = InputContainer:extend{
    title = "",
    subtitle = nil,
    --- function(window, width, height) -> widget; called on open and on every resize
    build = nil,
    --- function(window); called once the window is closed
    on_close = nil,
    --- show the Home button (goes back to the app launcher)
    home_button = true,
    covers_fullscreen = true, -- UIManager optimisation: nothing below needs repainting
}

--- Set by AppRegistry:launch() when the user chose "Open beside":
-- the next window opened goes into the Workspace instead of full screen.
AppWindow.pending_target = nil

--- Creates and shows a window. Returns it.
-- (Inside a split view this returns a Workspace pane, which has the same methods.)
function AppWindow:open(params)
    local target = AppWindow.pending_target
    if target then
        AppWindow.pending_target = nil
        local Workspace = require("apps/kos/workspace")
        return Workspace:getInstance():addPane(params, target)
    end
    local window = self:new(params)
    UIManager:show(window)
    return window
end

function AppWindow:init()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:_layout()
end

function AppWindow:_layout()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    self.title_bar = TitleBar:new{
        width = width,
        fullscreen = true,
        with_bottom_line = true,
        title = self.title,
        subtitle = self.subtitle,
        left_icon = self.home_button and "home" or nil,
        left_icon_tap_callback = self.home_button and function() self:goHome() end or nil,
        close_callback = function() self:close() end,
        show_parent = self,
    }
    local content_height = height - self.title_bar:getHeight()
    local content
    if self.build then
        local ok, result = pcall(self.build, self, width, content_height)
        if ok then
            content = result
        else
            logger.err("AppWindow: build failed for", self.title, result)
        end
    end
    self.content_width, self.content_height = width, content_height
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            content,
        },
    }
end

--- Rebuild the content (call after changing your app's state).
function AppWindow:refresh()
    self:_layout()
    UIManager:setDirty(self, "ui")
end

function AppWindow:setTitle(title, subtitle)
    self.title = title
    self.title_bar:setTitle(title, true)
    if subtitle ~= nil then
        self.subtitle = subtitle
        self.title_bar:setSubTitle(subtitle, true)
    end
    UIManager:setDirty(self, "ui", self.title_bar.dimen)
end

function AppWindow:onScreenResize()
    self:_layout()
    UIManager:setDirty(self, "full")
end

function AppWindow:close()
    UIManager:close(self)
    if self.on_close then
        self.on_close(self)
        self.on_close = nil
    end
end

function AppWindow:onClose()
    self:close()
    return true
end

--- Close this window and show the app launcher.
function AppWindow:goHome()
    self:close()
    UIManager:nextTick(function()
        UIManager:broadcastEvent(Event:new("ShowAppLauncher"))
    end)
end

return AppWindow

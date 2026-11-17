--[[--
The Windows 11 style title bar of every app window: the app's name on the left, then
minimize, maximize (or restore) and close on the right. Home stays at the far left.

    local bar = WinTitleBar:new{
        width = 800, title = "Gemma", subtitle = nil, show_parent = window,
        home = true, on_home = fn, on_home_hold = fn,
        on_minimize = fn, on_maximize = fn, on_close = fn,
        maximized = false,          -- which icon the middle button shows
    }
    bar:getHeight(); bar:setTitle(t); bar:setSubTitle(t)

It has the same few methods AppWindow used from KOReader's TitleBar, so nothing else changes.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconButton = require("ui/widget/iconbutton")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local WinTitleBar = WidgetContainer:extend{
    width = 0,
    title = "",
    subtitle = nil,
    home = false,
    maximized = false,
    show_parent = nil,
}

local BAR_DP = 44     -- height of the bar
local BUTTON_DP = 48  -- width of one caption button (the tap area)
local ICON_DP = 24

function WinTitleBar:init()
    self.bar_h = Screen:scaleBySize(BAR_DP)
    self:_build()
end

function WinTitleBar:_button(icon, callback, hold)
    local size = Screen:scaleBySize(ICON_DP)
    local w = Screen:scaleBySize(BUTTON_DP)
    return IconButton:new{
        icon = icon,
        width = size,
        height = size,
        padding = 0,
        padding_left = math.floor((w - size) / 2),
        padding_right = w - size - math.floor((w - size) / 2),
        padding_top = math.floor((self.bar_h - size) / 2),
        padding_bottom = self.bar_h - size - math.floor((self.bar_h - size) / 2),
        allow_flash = false,
        callback = callback,
        hold_callback = hold,
        show_parent = self.show_parent or self,
    }
end

function WinTitleBar:_build()
    local buttons = {}
    local left_w = 0
    if self.home then
        local b = self:_button("home", self.on_home, self.on_home_hold)
        table.insert(buttons, b)
        left_w = Screen:scaleBySize(BUTTON_DP)
    end
    local right = {
        self:_button("kos.minimize", self.on_minimize),
        self:_button(self.maximized and "kos.restore" or "kos.maximize", self.on_maximize),
        self:_button("close", self.on_close),
    }
    local right_w = 3 * Screen:scaleBySize(BUTTON_DP)
    local pad = Size.padding.large
    local text_w = math.max(40, self.width - left_w - right_w - 2 * pad)

    local lines = VerticalGroup:new{ align = "left" }
    table.insert(lines, TextWidget:new{
        text = self.title or "",
        face = Font:getFace("x_smalltfont"),
        bold = true,
        max_width = text_w,
    })
    if self.subtitle and self.subtitle ~= "" then
        table.insert(lines, TextWidget:new{
            text = self.subtitle,
            face = Font:getFace("xx_smallinfofont"),
            max_width = text_w,
        })
    end
    local row = HorizontalGroup:new{ align = "center" }
    for _, b in ipairs(buttons) do table.insert(row, b) end
    table.insert(row, LeftContainer:new{
        dimen = Geom:new{ w = self.width - left_w - right_w, h = self.bar_h },
        FrameContainer:new{ bordersize = 0, margin = 0, padding = 0, padding_left = pad, lines },
    })
    for _, b in ipairs(right) do table.insert(row, b) end

    local line = LineWidget:new{
        dimen = Geom:new{ w = self.width, h = Size.line.medium },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }
    self[1] = VerticalGroup:new{ align = "left", row, line }
    self.dimen = Geom:new{ w = self.width, h = self.bar_h + Size.line.medium }
end

function WinTitleBar:getHeight()
    return self.bar_h + Size.line.medium
end

function WinTitleBar:getSize()
    return self.dimen
end

function WinTitleBar:setTitle(title, no_refresh)
    self.title = title
    self:_build()
    if not no_refresh then UIManager:setDirty(self.show_parent or self, "ui", self.dimen) end
end

function WinTitleBar:setSubTitle(subtitle, no_refresh)
    self.subtitle = subtitle
    self:_build()
    if not no_refresh then UIManager:setDirty(self.show_parent or self, "ui", self.dimen) end
end

return WinTitleBar

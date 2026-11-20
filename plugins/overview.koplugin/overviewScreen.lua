--[[--
The Overview home screen: a wallpaper, pinned apps (none by default), and one search field.

Built only from KOReader's own widgets and fonts (Noto Sans, the "cfont" face), so it
looks like the rest of the shell and any restyle of KOReader restyles it too.
Long-press is switched off everywhere on this screen.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local Screen = Device.screen

--- One tappable line in the results list.
local Row = InputContainer:extend{
    width = nil,
    title = nil, -- small grey line: app · chat · time
    body = "",
    bold = false,
    callback = nil,
}

function Row:init()
    local inner_w = self.width - 2 * Size.padding.large
    local group = VerticalGroup:new{ align = "left" }
    if self.title then
        table.insert(group, TextWidget:new{
            text = self.title,
            face = Font:getFace("x_smallinfofont"),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = inner_w,
        })
    end
    table.insert(group, TextBoxWidget:new{
        text = self.body,
        face = Font:getFace(self.bold and "smallinfofontbold" or "smallinfofont"),
        width = inner_w,
    })
    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.large,
        padding_top = Size.padding.default,
        padding_bottom = Size.padding.default,
        width = self.width,
        background = Blitbuffer.COLOR_WHITE,
        group,
    }
    self.dimen = Geom:new{ w = self.width, h = self[1]:getSize().h }
    self.ges_events = {
        TapRow = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Row:onTapRow()
    if self.callback then self.callback() end
    return true
end

local OverviewScreen = InputContainer:extend{
    name = "overview_screen",
    covers_fullscreen = true,
    plugin = nil,
    results = nil, -- array of row specs { title, body, bold, callback }
}

function OverviewScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local everywhere = function() return self.dimen end
    self.ges_events = {
        TapBackground = { GestureRange:new{ ges = "tap", range = everywhere } },
        -- long-press is not enabled on the home screen: swallow it
        HoldAnywhere = { GestureRange:new{ ges = "hold", range = everywhere } },
        HoldReleaseAnywhere = { GestureRange:new{ ges = "hold_release", range = everywhere } },
    }
    if Device:hasKeys() then
        self.key_events = { ClearOrStay = { { Device.input.group.Back } } }
    end

    self.input = InputText:new{
        text = "",
        hint = _("Search"),
        width = self.dimen.w - 2 * Size.margin.default - 2 * Size.padding.default,
        face = Font:getFace("cfont", 20),
        scroll = false,
        focused = true,
        parent = self,
        edit_callback = function() self:scheduleSearch() end,
        enter_callback = function() self:openFirstResult() end,
    }
    -- no long-press menu (clipboard, selection) on the field either
    self.input.onHoldTextBox = function() return true end
    self.input.onHoldReleaseTextBox = function() return true end

    self:layout()
end

function OverviewScreen:wallpaper(w, h)
    local path = G_reader_settings:readSetting("overview_wallpaper")
    if path and lfs.attributes(path, "mode") == "file" then
        local ok, img = pcall(ImageWidget.new, ImageWidget, {
            file = path, width = w, height = h, scale_factor = 0, file_do_cache = false,
        })
        if ok and img then
            return FrameContainer:new{
                bordersize = 0, padding = 0, background = Blitbuffer.COLOR_WHITE,
                CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, img },
            }
        end
    end
    return FrameContainer:new{
        bordersize = 0, padding = 0, background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, TextWidget:new{ text = "", face = Font:getFace("cfont") } },
    }
end

function OverviewScreen:pinnedWidgets(w, h)
    local list = {}
    for _, pin in ipairs(self.plugin.layout.pinned or {}) do
        local app = self.plugin:findKoreaderApp(pin.action)
        if app then
            local widget = Row:new{
                width = math.floor(w * (pin.width or 0.4)),
                body = app.label,
                callback = function() self.plugin:runKoreaderApp(app) end,
            }
            widget.overlap_offset = { math.floor(w * pin.x), math.floor(h * pin.y) }
            table.insert(list, widget)
        end
    end
    return list
end

function OverviewScreen:layout()
    local w, h = self.dimen.w, self.dimen.h
    local keyboard_h = self.input:isKeyboardVisible() and self.input:getKeyboardDimen().h or 0
    local margin = Size.margin.default

    local field = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.default,
        background = Blitbuffer.COLOR_WHITE,
        self.input,
    }
    local field_h = field:getSize().h
    local field_y = h - keyboard_h - field_h - margin
    field.overlap_offset = { margin, field_y }

    local layers = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        self:wallpaper(w, h),
    }
    for _, pin in ipairs(self:pinnedWidgets(w, h)) do
        table.insert(layers, pin)
    end

    self.scroller = nil
    if self.results and #self.results > 0 then
        local list_w = w - 2 * margin
        local group = VerticalGroup:new{ align = "left" }
        local row_w = list_w - ScrollableContainer:getScrollbarWidth()
        for i, spec in ipairs(self.results) do
            if i > 1 then
                table.insert(group, LineWidget:new{
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    dimen = Geom:new{ w = row_w, h = Size.line.thin },
                })
            end
            table.insert(group, Row:new{
                width = row_w, title = spec.title, body = spec.body, bold = spec.bold, callback = spec.callback,
            })
        end
        local available_h = field_y - 2 * margin
        local list_h = math.min(group:getSize().h, available_h)
        self.scroller = ScrollableContainer:new{
            dimen = Geom:new{ w = list_w, h = list_h },
            show_parent = self,
            ignore_events = { "hold", "hold_pan", "hold_release" },
            group,
        }
        local panel = FrameContainer:new{
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_BLACK,
            padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            self.scroller,
        }
        panel.overlap_offset = { margin, math.max(margin, field_y - margin - list_h) }
        table.insert(layers, panel)
    end

    table.insert(layers, FrameContainer:new{
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        padding = 0,
        overlap_offset = field.overlap_offset,
        field,
    })
    self[1] = layers
    UIManager:setDirty(self, "ui")
end

function OverviewScreen:scheduleSearch()
    if self._search_pending then return end
    self._search_pending = true
    UIManager:scheduleIn(0.2, function()
        self._search_pending = false
        self.results = self.plugin:search(self.input:getText())
        self:layout()
    end)
end

function OverviewScreen:openFirstResult()
    local first = self.results and self.results[1]
    if first and first.callback then first.callback() end
end

function OverviewScreen:clear()
    self.input:setText("")
    self.results = nil
    self:layout()
end

-- InputText calls this when the field is tapped (instead of opening the keyboard itself)
function OverviewScreen:onSwitchFocus()
    self.input:onShowKeyboard()
    self:layout()
end

-- VirtualKeyboard calls this when its own close key hides it
function OverviewScreen:onKeyboardClosed()
    self:layout()
end

function OverviewScreen:onTapBackground()
    if self.input:isKeyboardVisible() then
        self.input:onCloseKeyboard()
        self:layout()
    end
    return true
end

function OverviewScreen:onHoldAnywhere() return true end
function OverviewScreen:onHoldReleaseAnywhere() return true end

-- Back clears the search; on an empty home screen it does nothing (this is Home)
function OverviewScreen:onClearOrStay()
    if self.input:getText() ~= "" or self.input:isKeyboardVisible() then
        self.input:onCloseKeyboard()
        self:clear()
    end
    return true
end

function OverviewScreen:onCloseWidget()
    self.input:onCloseKeyboard()
    self.plugin:onScreenClosed()
end

-- the screen has its own keyboard handling; make sure KOReader's focus logic leaves it alone
function OverviewScreen:onFocus() return true end

return OverviewScreen

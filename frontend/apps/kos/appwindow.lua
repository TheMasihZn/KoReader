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


-- On wide screens, keep content at a readable width instead of stretching it
-- (Android's "expanded" layouts): max_content_dp, centred.
local function contentWidth(width, max_dp)
    if not max_dp then return width end
    return math.min(width, Screen:scaleBySize(max_dp))
end

local function centred(content, width, content_w, height)
    if not content or content_w >= width then return content end
    local CenterContainer = require("ui/widget/container/centercontainer")
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, ignore_if_over = "height", content }
end

local AppWindow = InputContainer:extend{
    title = "",
    subtitle = nil,
    --- function(window, width, height) -> widget; called on open and on every resize
    build = nil,
    --- function(window); called once the window is closed
    on_close = nil,
    --- function(window, do_close): optional; called instead of closing, so an app
    -- can ask "Save changes?" first. Call do_close() to really close.
    confirm_close = nil,
    --- show the Home button (goes back to the app launcher)
    home_button = true,
    --- optional: widest the content gets, in dp; wider windows centre it
    max_content_dp = nil,
    covers_fullscreen = true, -- UIManager optimisation: nothing below needs repainting
}

-- Your Gestures keep working while an app is open (apps/kos/gestureforward.lua).
function AppWindow:handleEvent(event)
    return require("apps/kos/gestureforward").handle(self, event, InputContainer.handleEvent)
end

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
    require("apps/kos/windows").add(window)
    local saved = window.kos_app and AppWindow.ratioFor(window.kos_app.id)
    if saved and not window.ratio then window.ratio = saved window:_layout() end
    UIManager:show(window)
    return window
end

function AppWindow:init()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:_layout()
end

--- Saved window shape of an app: width / height as a number, or nil (fill the screen).
function AppWindow.ratioFor(app_id)
    if not app_id or not G_reader_settings then return nil end
    return G_reader_settings:readSetting("kos_ratio_" .. app_id)
end

function AppWindow:_layout()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local width, height = screen_w, screen_h
    -- Any aspect ratio: the window keeps its shape and sits centred on a quiet backdrop.
    local ratio = self.ratio
    if ratio and ratio > 0 then
        if screen_w / screen_h > ratio then
            width = math.floor(screen_h * ratio)
        else
            height = math.floor(screen_w / ratio)
        end
    end
    self.dimen = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h }
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    local Windows = require("apps/kos/windows")
    local use_win11 = true
    if G_reader_settings and G_reader_settings:readSetting("kos_win11_titlebar") == false then use_win11 = false end
    if use_win11 then
        local ok, bar = pcall(function()
            return require("apps/kos/wintitlebar"):new{
                width = width,
                title = Windows.displayTitle(self),
                subtitle = self.subtitle,
                home = self.home_button and true or false,
                on_home = function() self:goHome() end,
                on_home_hold = function() Windows.windowMenu(self) end,
                on_minimize = function() Windows.minimize(self) end,
                on_maximize = function() self:toggleMaximize() end,
                on_close = function() self:close() end,
                maximized = not (self.ratio and self.ratio > 0),
                show_parent = self,
            }
        end)
        if ok then
            self.title_bar = bar
        else
            logger.err("AppWindow: Windows 11 title bar failed, using the classic one:", bar)
        end
    end
    if not self.title_bar then
        self.title_bar = TitleBar:new{
            width = width,
            fullscreen = true,
            with_bottom_line = true,
            title = Windows.displayTitle(self),
            subtitle = self.subtitle,
            left_icon = self.home_button and "home" or nil,
            -- long-press Home: this window's menu (split view, new window, all windows)
            left_icon_hold_callback = function() Windows.windowMenu(self) end,
            left_icon_tap_callback = self.home_button and function() self:goHome() end or nil,
            close_callback = function() self:close() end,
            show_parent = self,
        }
    end
    local content_height = height - self.title_bar:getHeight()
    local content
    local content_w = contentWidth(width, self.max_content_dp)
    if self.build then
        local ok, result = pcall(self.build, self, content_w, content_height)
        if ok then
            content = centred(result, width, content_w, content_height)
        else
            logger.err("AppWindow: build failed for", self.title, result)
        end
    end
    self.content_width, self.content_height = content_w, content_height
    local frame = FrameContainer:new{
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
    if width < screen_w or height < screen_h then
        local CenterContainer = require("ui/widget/container/centercontainer")
        local back = Blitbuffer.Color8(0xE6)
        pcall(function() back = require("apps/kos/flatstyle").surface_back end)
        self[1] = FrameContainer:new{
            width = screen_w, height = screen_h, padding = 0, margin = 0, bordersize = 0,
            background = back,
            CenterContainer:new{ dimen = Geom:new{ w = screen_w, h = screen_h }, frame },
        }
    else
        self[1] = frame
    end
end

--- Sets this window's shape (width / height, or nil for the whole screen) and redraws it.
function AppWindow:setRatio(ratio)
    self.ratio = ratio
    self:refresh()
    UIManager:setDirty(nil, "full")
end

--- Rebuild the content (call after changing your app's state).
function AppWindow:refresh()
    self:_layout()
    UIManager:setDirty(self, "ui")
end

function AppWindow:setTitle(title, subtitle)
    self.title = title
    self.title_bar:setTitle(require("apps/kos/windows").displayTitle(self), true)
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

function AppWindow:close(force)
    if self.confirm_close and not force then
        self.confirm_close(self, function() self:close(true) end)
        return
    end
    UIManager:close(self)
    require("apps/kos/windows").remove(self)
    if self.on_close then
        self.on_close(self)
        self.on_close = nil
    end
    -- Closing the last app lands on Home, not on the file browser (setting kos_home_landing).
    if self.in_switcher ~= false and not self._leaving_for_home
            and G_reader_settings and G_reader_settings:nilOrTrue("kos_home_landing") then
        UIManager:nextTick(function()
            if #require("apps/kos/windows").list == 0 then
                UIManager:broadcastEvent(Event:new("ShowAppLauncher", { only_if_closed = true }))
            end
        end)
    end
end

-- However the window goes away (also UIManager:close), it leaves the window list.
function AppWindow:onCloseWidget()
    if self._keep_in_list then -- minimized: off the screen, still in the window list
        self._keep_in_list = nil
        return
    end
    require("apps/kos/windows").remove(self)
end

--- Maximize or restore. A shaped window (see Window shape…) goes full screen and remembers its shape;
-- a full-screen window goes back to the remembered shape, or opens the shape menu when there is none.
function AppWindow:toggleMaximize()
    if self.ratio and self.ratio > 0 then
        self._restore_ratio = self.ratio
        self:setRatio(nil)
    elseif self._restore_ratio then
        local r = self._restore_ratio
        self._restore_ratio = nil
        self:setRatio(r)
    else
        require("apps/kos/windows").shapeMenu(self.kos_app and self.kos_app.id, self)
    end
end

function AppWindow:onClose()
    self:close()
    return true
end

--- Close this window and show the app launcher.
function AppWindow:goHome()
    self._leaving_for_home = true
    if self.confirm_close then
        -- Don't lose unsaved work: ask first, go home only once closed.
        self.confirm_close(self, function()
            self:close(true)
            UIManager:nextTick(function() UIManager:broadcastEvent(Event:new("ShowAppLauncher")) end)
        end)
        return
    end
    self:close()
    UIManager:nextTick(function()
        UIManager:broadcastEvent(Event:new("ShowAppLauncher"))
    end)
end

return AppWindow

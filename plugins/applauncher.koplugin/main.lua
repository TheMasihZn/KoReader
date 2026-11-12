--[[--
KOReader OS home screen: a clock and a grid of apps.

Apps are found by apps/kos/appregistry (built-ins + any plugin with an `app` table).
Open it from the menu, from a gesture (Dispatcher action "Home screen"),
from the Home button of any AppWindow, or automatically at startup.
]]

local AppRegistry = require("apps/kos/appregistry")
local AppWindow = require("apps/kos/appwindow")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

-- One app icon + label. Tap opens it, hold shows what it is.
local AppTile = InputContainer:extend{
    app = nil,
    width = nil,
    icon_size = nil,
    callback = nil,
    hold_callback = nil,
}

function AppTile:init()
    local icon_args = { width = self.icon_size, height = self.icon_size }
    for k, v in pairs(self.app.icon_args) do icon_args[k] = v end
    local icon_box = FrameContainer:new{
        bordersize = Size.border.thick,
        radius = Size.radius.window * 2,
        padding = math.floor(self.icon_size / 4),
        margin = 0,
        IconWidget:new(icon_args),
    }
    local label = TextWidget:new{
        text = self.app.title,
        face = Font:getFace("smallinfofont"),
        max_width = self.width - 2 * Size.padding.small,
    }
    local group = VerticalGroup:new{
        align = "center",
        icon_box,
        VerticalSpan:new{ width = Size.padding.default },
        label,
    }
    local h = group:getSize().h + 2 * Size.padding.default
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = h }
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = h }, group }
    self.ges_events = {
        TapTile = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        HoldTile = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
end

function AppTile:onTapTile()
    if self.callback then self.callback(self.app) end
    return true
end

function AppTile:onHoldTile()
    if self.hold_callback then
        self.hold_callback(self.app)
        return true
    end
    UIManager:show(InfoMessage:new{
        text = self.app.description and T("%1\n\n%2", self.app.title, self.app.description) or self.app.title,
    })
    return true
end

local AppLauncher = WidgetContainer:extend{
    name = "applauncher",
    page = 1,
}

local started_once = false

function AppLauncher:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    -- "Open with…" in the long-press menu of files that apps can open.
    local ok, FileHandlers = pcall(require, "apps/kos/filehandlers")
    if ok and not self.ui.document then
        FileHandlers:addFileDialogButton(self.ui)
    end
    if not started_once and G_reader_settings:isTrue("applauncher_at_startup")
            and not self.ui.document then -- the file browser, not a book
        started_once = true
        UIManager:nextTick(function() self:onShowAppLauncher() end)
    end
end

function AppLauncher:onDispatcherRegisterActions()
    Dispatcher:registerAction("show_app_launcher", {
        category = "none", event = "ShowAppLauncher", title = _("Home screen"), general = true,
    })
end

function AppLauncher:addToMainMenu(menu_items)
    menu_items.app_launcher = {
        text = _("Home screen"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open home screen"),
                callback = function() self:onShowAppLauncher() end,
            },
            {
                text = _("Open at startup"),
                checked_func = function() return G_reader_settings:isTrue("applauncher_at_startup") end,
                callback = function() G_reader_settings:flipNilOrFalse("applauncher_at_startup") end,
            },
        },
    }
end

local function clockText()
    return datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
end

local function dateText()
    local text = os.date("%A, %d %B")
    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        local ok, level = pcall(powerd.getCapacity, powerd)
        if ok and level then
            text = T(_("%1 · Battery %2%"), text, level)
        end
    end
    return text
end

-- @param args optional { split = { next_to = Pane, dir = "row"|"column" } }:
-- the app picked next opens beside that window.
function AppLauncher:onShowAppLauncher(args)
    self.split_target = args and args.split or nil
    if self.window then
        UIManager:close(self.window)
        self.window = nil
    end
    self.page = 1
    self.window = AppWindow:open{
        title = clockText(),
        subtitle = self.split_target and _("Pick an app for the new window") or dateText(),
        home_button = false,
        build = function(window, width, height) return self:buildGrid(window, width, height) end,
        on_close = function()
            UIManager:unschedule(self.tick)
            self.window = nil
        end,
    }
    -- Keep the clock current while the home screen is open.
    self.tick = self.tick or function()
        if not self.window then return end
        self.window:setTitle(clockText(), dateText())
        UIManager:scheduleIn(60 - tonumber(os.date("%S")), self.tick)
    end
    UIManager:unschedule(self.tick)
    UIManager:scheduleIn(60 - tonumber(os.date("%S")), self.tick)
    return true
end

function AppLauncher:launch(app, split)
    split = split or self.split_target
    self.split_target = nil
    if self.window then
        self.window:close()
    end
    -- Let the window close first, so the app's events reach the file browser or reader.
    UIManager:nextTick(function()
        AppRegistry:launch(app, split and { split = split } or nil)
    end)
end

function AppLauncher:showAppMenu(app)
    local dialog
    local can_split = AppRegistry:canSplit(app)
    dialog = ButtonDialog:new{
        title = app.description and T("%1\n\n%2", app.title, app.description) or app.title,
        buttons = {
            {
                { text = _("Open"), callback = function()
                    UIManager:close(dialog)
                    self:launch(app)
                end },
            },
            {
                { text = _("Open beside"), enabled = can_split, callback = function()
                    UIManager:close(dialog)
                    self:launch(app, self.split_target or { dir = "row" })
                end },
                { text = _("Open below"), enabled = can_split, callback = function()
                    UIManager:close(dialog)
                    self:launch(app, self.split_target or { dir = "column" })
                end },
            },
        },
    }
    UIManager:show(dialog)
end

function AppLauncher:buildGrid(window, width, height)
    local apps = AppRegistry:getApps()
    local margin = Size.padding.fullscreen
    local inner_w = width - 2 * margin
    local min_tile_w = Screen:scaleBySize(96)
    local cols = math.max(3, math.floor(inner_w / min_tile_w))
    local tile_w = math.floor(inner_w / cols)
    local icon_size = math.min(Screen:scaleBySize(36), math.floor(tile_w / 2))

    local make_tile = function(app)
        return AppTile:new{
            app = app,
            width = tile_w,
            icon_size = icon_size,
            callback = function(a) self:launch(a) end,
            hold_callback = function(a) self:showAppMenu(a) end,
        }
    end

    -- Measure one tile to know how many rows fit.
    local nav_h = Screen:scaleBySize(56)
    local probe = make_tile(apps[1] or { title = "", icon_args = { icon = "appbar.tools" } })
    local tile_h = probe:getSize().h
    probe:free()
    local rows = math.max(1, math.floor((height - 2 * margin - nav_h) / tile_h))
    local per_page = rows * cols
    local pages = math.max(1, math.ceil(#apps / per_page))
    if self.page > pages then self.page = pages end

    local grid = VerticalGroup:new{ align = "left" }
    local first = (self.page - 1) * per_page + 1
    for r = 0, rows - 1 do
        local row = HorizontalGroup:new{}
        local any = false
        for c = 1, cols do
            local app = apps[first + r * cols + c - 1]
            if app then
                table.insert(row, make_tile(app))
                any = true
            else
                table.insert(row, HorizontalSpan:new{ width = tile_w })
            end
        end
        if not any then break end
        table.insert(grid, row)
    end

    local nav = HorizontalGroup:new{ align = "center" }
    if pages > 1 then
        local btn_w = Screen:scaleBySize(64)
        table.insert(nav, Button:new{
            text = "‹", width = btn_w, show_parent = window, enabled = self.page > 1,
            callback = function() self.page = self.page - 1; window:refresh() end,
        })
        table.insert(nav, CenterContainer:new{
            dimen = Geom:new{ w = Screen:scaleBySize(140), h = nav_h },
            TextWidget:new{ text = T(_("Page %1 of %2"), self.page, pages), face = Font:getFace("smallinfofont") },
        })
        table.insert(nav, Button:new{
            text = "›", width = btn_w, show_parent = window, enabled = self.page < pages,
            callback = function() self.page = self.page + 1; window:refresh() end,
        })
    end

    local grid_h = height - 2 * margin - nav_h
    return FrameContainer:new{
        padding = margin,
        margin = 0,
        bordersize = 0,
        VerticalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = grid_h },
                grid,
            },
            CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = nav_h },
                nav,
            },
        },
    }
end

return AppLauncher

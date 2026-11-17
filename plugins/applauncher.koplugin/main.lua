--[[--
KOReader OS home screen: a clock and a grid of apps.

Apps are found by apps/kos/appregistry (built-ins + any plugin with an `app` table).
Open it from the menu, from a gesture (Dispatcher action "Home screen"),
from the Home button of any AppWindow, or automatically at startup.
]]

local AppRegistry = require("apps/kos/appregistry")
local AppWindow = require("apps/kos/appwindow")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local LineWidget = require("ui/widget/linewidget")
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
local TextBoxWidget = require("ui/widget/textboxwidget")
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
    -- Readable names: a proper size, up to two lines, centred, "…" only if longer.
    local face = Font:getFace("cfont", 17)
    local probe = TextWidget:new{ text = "Ag", face = face }
    local line_h = probe:getSize().h
    probe:free()
    local label = TextBoxWidget:new{
        text = self.app.title,
        face = face,
        width = self.width - 2 * Size.padding.small,
        alignment = "center",
        height = line_h * 2 + Size.padding.small,
        height_overflow_show_ellipsis = true,
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

-- Chat style Home: one app per line, plain text, no bubbles (name, then what it does).
local ChatRow = InputContainer:extend{ app = nil, width = nil, callback = nil, hold_callback = nil }

function ChatRow:init()
    local title_face = Font:getFace("cfont", 20)
    local sub_face = Font:getFace("smallinfofont")
    local pad = Size.padding.large
    local text_w = self.width - 2 * pad
    local first = (self.app.description or ""):match("^([^%.%\n]+)") or ""
    local group = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = self.app.title, face = title_face, bold = true, max_width = text_w },
    }
    if first ~= "" then
        table.insert(group, TextWidget:new{ text = first, face = sub_face, max_width = text_w, fgcolor = Blitbuffer.COLOR_DARK_GRAY })
    end
    local h = group:getSize().h + 2 * Size.padding.default
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = h + Size.line.thin }
    self[1] = VerticalGroup:new{
        align = "left",
        FrameContainer:new{ bordersize = 0, padding = Size.padding.default, padding_left = pad, padding_right = pad, margin = 0, group },
        LineWidget:new{ dimen = Geom:new{ w = self.width, h = Size.line.thin }, background = Blitbuffer.COLOR_LIGHT_GRAY },
    }
    self.ges_events = {
        TapRow = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        HoldRow = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
end

function ChatRow:onTapRow()
    if self.callback then self.callback(self.app) end
    return true
end

function ChatRow:onHoldRow()
    if self.hold_callback then self.hold_callback(self.app) end
    return true
end

local AppLauncher = WidgetContainer:extend{
    name = "applauncher",
    page = 1,
}

local started_once = false

function AppLauncher:init()
    require("apps/kos/flatstyle").install()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    -- "Open with…" in the long-press menu of files that apps can open.
    local ok, FileHandlers = pcall(require, "apps/kos/filehandlers")
    if ok and not self.ui.document then
        FileHandlers:addFileDialogButton(self.ui)
    end
    -- Closing a book lands on Home (once; the reader's own onHome is wrapped for everyone).
    if not self.ui.document then
        pcall(function()
            local ReaderUI = require("apps/reader/readerui")
            if not ReaderUI._kos_home_wrapped then
                ReaderUI._kos_home_wrapped = true
                local orig = ReaderUI.onHome
                ReaderUI.onHome = function(reader, ...)
                    local ret = orig(reader, ...)
                    if G_reader_settings:nilOrTrue("kos_home_landing") then
                        UIManager:nextTick(function()
                            UIManager:broadcastEvent(require("ui/event"):new("ShowAppLauncher", { only_if_closed = true }))
                        end)
                    end
                    return ret
                end
            end
        end)
    end
    -- Debugger: layout bounds come back; was an app starting when KOReader last died?
    if not started_once then
        pcall(function()
            local Debugger = require("apps/kos/debugger")
            Debugger.restore()
            local id, times = Debugger.checkLastStart()
            if id then
                local InfoMessage = require("ui/widget/infomessage")
                local ConfirmBox = require("ui/widget/confirmbox")
                UIManager:nextTick(function()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("KOReader closed while \"%1\" was starting (%2 time(s)).\n\nSwitch that app off until you turn it on again?"), id, times),
                        ok_text = _("Switch off"), cancel_text = _("Keep it on"),
                        ok_callback = function() Debugger.setDisabled(id, true) end,
                    })
                end)
            end
        end)
    end
    if not started_once and G_reader_settings:nilOrTrue("applauncher_at_startup")
            and not self.ui.document then -- the file browser, not a book
        started_once = true
        UIManager:nextTick(function() self:onShowAppLauncher() end)
    end
end

function AppLauncher:onDispatcherRegisterActions()
    Dispatcher:registerAction("show_app_launcher", {
        category = "none", event = "ShowAppLauncher", title = _("Home screen"), general = true,
    })
    Dispatcher:registerAction("show_search", {
        category = "none", event = "ShowSearch", title = _("Search apps and files"), general = true,
    })
    Dispatcher:registerAction("show_open_windows", {
        category = "none", event = "ShowOpenWindows", title = _("Open windows (switch app)"), general = true,
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
                text = _("Home view"),
                sub_item_table = {
                    { text = _("Chat (plain lines, input at the bottom)"), radio = true,
                      checked_func = function() return (G_reader_settings:readSetting("kos_home_view") or "chat") == "chat" end,
                      callback = function() G_reader_settings:saveSetting("kos_home_view", "chat") end },
                    { text = _("Grid of icons"), radio = true,
                      checked_func = function() return G_reader_settings:readSetting("kos_home_view") == "grid" end,
                      callback = function() G_reader_settings:saveSetting("kos_home_view", "grid") end },
                },
            },
            require("apps/kos/usearch").settingsMenu(),
            {
                text = _("Open at startup"),
                checked_func = function() return G_reader_settings:nilOrTrue("applauncher_at_startup") end,
                callback = function() G_reader_settings:flipNilOrTrue("applauncher_at_startup") end,
            },
            {
                text = _("Home after closing a book or app"),
                help_text = _("Closing a book or the last app opens the Home screen instead of the file browser."),
                checked_func = function() return G_reader_settings:nilOrTrue("kos_home_landing") end,
                callback = function() G_reader_settings:flipNilOrTrue("kos_home_landing") end,
            },
            {
                text = _("Home layout"),
                sub_item_table = {
                    { text = _("Order: my order (hold an icon, then Move)"), radio = true,
                      checked_func = function() return AppRegistry.sortMode() == "custom" end,
                      callback = function() G_reader_settings:saveSetting("kos_home_sort", "custom") end },
                    { text = _("Order: A to Z (like One UI's app drawer)"), radio = true,
                      checked_func = function() return AppRegistry.sortMode() == "az" end,
                      callback = function() G_reader_settings:saveSetting("kos_home_sort", "az") end },
                    { text = _("Order: built-in"), radio = true,
                      checked_func = function() return AppRegistry.sortMode() == "default" end,
                      callback = function() G_reader_settings:saveSetting("kos_home_sort", "default") end },
                    { text = _("Forget my order"), keep_menu_open = true,
                      callback = function()
                          G_reader_settings:delSetting("kos_home_order")
                          G_reader_settings:saveSetting("kos_home_sort", "default")
                          UIManager:show(InfoMessage:new{ text = _("Home order reset."), timeout = 2 })
                      end },
                    { text = _("Columns"), sub_item_table = (function()
                        local items = {}
                        for _i, n in ipairs({ 0, 3, 4, 5, 6 }) do
                            items[#items + 1] = { text = n == 0 and _("Automatic") or tostring(n), radio = true,
                                checked_func = function() return (G_reader_settings:readSetting("kos_home_cols") or 0) == n end,
                                callback = function() G_reader_settings:saveSetting("kos_home_cols", n) end }
                        end
                        return items
                    end)() },
                    { text = _("Icon size"), sub_item_table = {
                        { text = _("Small"), radio = true, checked_func = function() return G_reader_settings:readSetting("kos_home_icon") == "small" end,
                          callback = function() G_reader_settings:saveSetting("kos_home_icon", "small") end },
                        { text = _("Medium"), radio = true, checked_func = function() return (G_reader_settings:readSetting("kos_home_icon") or "medium") == "medium" end,
                          callback = function() G_reader_settings:saveSetting("kos_home_icon", "medium") end },
                        { text = _("Large"), radio = true, checked_func = function() return G_reader_settings:readSetting("kos_home_icon") == "large" end,
                          callback = function() G_reader_settings:saveSetting("kos_home_icon", "large") end },
                    } },
                },
                help_text = _("Hold an icon on Home and choose Move, then tap where it should go. Columns and icon size show next time Home opens."),
            },
            {
                text = _("Debug"),
                sub_item_table_func = function()
                    local Debugger = require("apps/kos/debugger")
                    local items = {
                        {
                            text = _("Show layout bounds"),
                            help_text = _("Draws a thin box around every container, like Android's Show layout bounds. Colours: red frames, blue vertical groups, green horizontal groups, orange centred."),
                            checked_func = function() return Debugger.boundsOn() end,
                            callback = function() Debugger.setBounds(not Debugger.boundsOn()) end,
                        },
                        {
                            text = _("Show debug trail"),
                            help_text = _("Which app started, and which one was starting when KOReader closed. Opens in Logcat."),
                            keep_menu_open = true,
                            callback = function()
                                UIManager:broadcastEvent(require("ui/event"):new("ShowLogcat", "debug"))
                            end,
                        },
                    }
                    for id in pairs(Debugger.disabledApps()) do
                        items[#items + 1] = {
                            text = T(_("Switch on again: %1"), id),
                            callback = function() Debugger.setDisabled(id, false) end,
                        }
                    end
                    return items
                end,
            },
            {
                text = _("Menu look"),
                sub_item_table = {
                    {
                        text = _("Line strength"),
                        sub_item_table = {
                            { text = _("Faint"), radio = true, checked_func = function() return (G_reader_settings:readSetting("kos_flat_lines") or 2) == 1 end,
                              callback = function() G_reader_settings:saveSetting("kos_flat_lines", 1) end },
                            { text = _("Soft"), radio = true, checked_func = function() return (G_reader_settings:readSetting("kos_flat_lines") or 2) == 2 end,
                              callback = function() G_reader_settings:saveSetting("kos_flat_lines", 2) end },
                            { text = _("Clear"), radio = true, checked_func = function() return (G_reader_settings:readSetting("kos_flat_lines") or 2) == 3 end,
                              callback = function() G_reader_settings:saveSetting("kos_flat_lines", 3) end },
                        },
                    },
                    {
                        text = _("Corners"),
                        sub_item_table = {
                            { text = _("Square"), radio = true, checked_func = function() return (G_reader_settings:readSetting("kos_flat_radius") or 1) == 0 end,
                              callback = function() G_reader_settings:saveSetting("kos_flat_radius", 0) end },
                            { text = _("Soft"), radio = true, checked_func = function() return (G_reader_settings:readSetting("kos_flat_radius") or 1) == 1 end,
                              callback = function() G_reader_settings:saveSetting("kos_flat_radius", 1) end },
                            { text = _("Round"), radio = true, checked_func = function() return (G_reader_settings:readSetting("kos_flat_radius") or 1) == 2 end,
                              callback = function() G_reader_settings:saveSetting("kos_flat_radius", 2) end },
                        },
                    },
                },
                help_text = _("How strong the outlines of menus and dialogs are, and how round their corners. Restart KOReader to see the change."),
            },
            {
                text = _("Flat design"),
                help_text = _("Softer outlines and tonal depth: the window in front is lightest, the ones behind it are darker. Restart to apply to dialogs. Turn off on black-and-white e-ink screens."),
                checked_func = function() return G_reader_settings:nilOrTrue("kos_flat_design") end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("kos_flat_design")
                    require("ui/uimanager"):askForRestart(_("Restart KOReader to apply the design change."))
                end,
            },
            {
                text = _("Paste and audio row on the keyboard"),
                help_text = _("A row on top of every keyboard: Paste, ▶ (read aloud, in apps that can) and ⟲ (repeat the last clip; hold for recent ones)."),
                checked_func = function() return G_reader_settings:nilOrTrue("kos_keyboard_toolbar") end,
                callback = function() G_reader_settings:flipNilOrTrue("kos_keyboard_toolbar") end,
            },
        },
    }
end

local function clockText()
    return datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
end

local function dateText()
    -- If Focus has a task (or a timer running), show that: it's what matters now.
    local ok, PluginLoader = pcall(require, "pluginloader")
    local focus = ok and PluginLoader:getPluginInstance("focus")
    if focus and focus.getNowText then
        local ok2, now = pcall(focus.getNowText, focus)
        if ok2 and now then return now end
    end
    local text = os.date("%A, %d %B")
    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        local ok_level, level = pcall(powerd.getCapacity, powerd)
        if ok_level and level then
            text = T(_("%1 · Battery %2%"), text, level)
        end
    end
    return text
end

-- @param args optional { split = { next_to = Pane, dir = "row"|"column" } }:
-- the app picked next opens beside that window.
function AppLauncher:onShowSearch()
    require("apps/kos/usearch").show()
    return true
end

function AppLauncher:onShowOpenWindows()
    require("apps/kos/windows").showSwitcher()
    return true
end

function AppLauncher:onShowAppLauncher(args)
    if args and args.only_if_closed and self.window then return true end
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
        in_switcher = false,
        build = function(window, width, height) return self:buildHome(window, width, height) end,
        on_close = function()
            UIManager:unschedule(self.tick)
            self.window = nil
        end,
    }
    self:listenForTyping(self.window)
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

local function openCount(app)
    local n = 0
    for _, w in ipairs(require("apps/kos/windows").list) do
        if w.kos_app and w.kos_app.id == app.id then n = n + 1 end
    end
    return n
end

--- Tap on Home: opens the app, or, while moving one, drops the moved app before this one.
--- Event KosOpenApp (from REST calls, voice, pipelines): open an app by id or name.
function AppLauncher:onKosOpenApp(name)
    local want = tostring(name):lower()
    for _i, a in ipairs(AppRegistry:getApps()) do
        if a.id == name or a.title:lower() == want then
            self.moving = nil
            self:launch(a)
            return true
        end
    end
    return false
end

function AppLauncher:tapApp(app, window)
    local moving = self.moving
    if not moving then
        self:launch(app)
        return
    end
    self.moving = nil
    if moving ~= app.id then AppRegistry:moveApp(moving, app.id) end
    self.window:setTitle(clockText(), dateText())
    window:refresh()
end

function AppLauncher:showAppMenu(app, window)
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
                { text = T(_("Open windows (%1)"), openCount(app)), enabled = openCount(app) > 0, callback = function()
                    UIManager:close(dialog)
                    if self.window then self.window:close() end
                    UIManager:nextTick(function() require("apps/kos/windows").showSwitcher() end)
                end },
            },
            {
                { text = _("Move…"), callback = function()
                    UIManager:close(dialog)
                    self.moving = app.id
                    self.window:setTitle(clockText(), T(_("Moving %1: tap where it goes (tap it again to cancel)"), app.title))
                end },
                { text = _("To the start"), callback = function()
                    UIManager:close(dialog)
                    local first = AppRegistry:getApps()[1]
                    if first and first.id ~= app.id then AppRegistry:moveApp(app.id, first.id) end
                    if window then window:refresh() end
                end },
                { text = _("To the end"), callback = function()
                    UIManager:close(dialog)
                    AppRegistry:moveApp(app.id, nil)
                    if window then window:refresh() end
                end },
            },
            {
                { text = _("Window shape…"), callback = function()
                    UIManager:close(dialog)
                    require("apps/kos/windows").shapeMenu(app.id, nil)
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

--- Home view: "chat" (default) or "grid". If the chat view fails for any reason the grid is shown.
function AppLauncher:buildHome(window, width, height)
    if (G_reader_settings:readSetting("kos_home_view") or "chat") == "chat" then
        local ok, result = pcall(self.buildChat, self, window, width, height)
        if ok then return result end
        require("logger").err("Home chat view failed, showing the grid:", result)
    end
    return self:buildGrid(window, width, height)
end

function AppLauncher:buildChat(window, width, height)
    local apps = AppRegistry:getApps()
    local margin = Size.padding.fullscreen
    local inner_w = width - 2 * margin
    local nav_h = Screen:scaleBySize(56)
    local input_h = Screen:scaleBySize(56)
    local avail = height - 2 * margin - nav_h - input_h
    local probe = ChatRow:new{ app = apps[1] or { title = "Ag", description = "Ag" }, width = inner_w }
    local row_h = probe:getSize().h
    probe:free()
    local per_page = math.max(1, math.floor(avail / row_h))
    local pages = math.max(1, math.ceil(#apps / per_page))
    if self.page > pages then self.page = pages end

    local list = VerticalGroup:new{ align = "left" }
    for i = (self.page - 1) * per_page + 1, math.min(#apps, self.page * per_page) do
        table.insert(list, ChatRow:new{
            app = apps[i], width = inner_w,
            callback = function(a) self:tapApp(a, window) end,
            hold_callback = function(a) self:showAppMenu(a, window) end,
        })
    end

    local nav = HorizontalGroup:new{ align = "center" }
    if pages > 1 then
        local btn_w = Screen:scaleBySize(64)
        table.insert(nav, Button:new{ text = "‹", width = btn_w, show_parent = window, enabled = self.page > 1,
            callback = function() self.page = self.page - 1; window:refresh() end })
        table.insert(nav, CenterContainer:new{ dimen = Geom:new{ w = Screen:scaleBySize(140), h = nav_h },
            TextWidget:new{ text = T(_("Page %1 of %2"), self.page, pages), face = Font:getFace("smallinfofont") } })
        table.insert(nav, Button:new{ text = "›", width = btn_w, show_parent = window, enabled = self.page < pages,
            callback = function() self.page = self.page + 1; window:refresh() end })
    end

    -- The input line: always at the bottom. Tap it, or just type on a connected keyboard.
    local input = Button:new{
        text = _("Type here — search, open an app, or send to a bot"),
        width = inner_w, bordersize = Size.border.default, radius = Size.radius.window,
        show_parent = window, align = "left",
        callback = function() self:openInput("") end,
    }
    return FrameContainer:new{
        padding = margin, margin = 0, bordersize = 0,
        VerticalGroup:new{
            align = "left",
            CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = avail }, list },
            CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = nav_h }, nav },
            input,
        },
    }
end

--- The text goes through a pipeline (apps/kos/pipeline.lua): a first word that names a pipeline picks it
-- ("bot hello"), otherwise it is a search.
function AppLauncher:runInput(text)
    local Pipeline = require("apps/kos/pipeline")
    local Search = require("apps/kos/usearch")
    local pipelines = Pipeline.load()
    local p, rest = Pipeline.dispatch(text, pipelines)
    local steps = p and p.steps or { "trim", "search" }
    local ctx = {
        search = function(t) Search.show(t) end,
        findApp = function(t)
            local items = {}
            for _i, a in ipairs(AppRegistry:getApps()) do
                items[#items + 1] = { name = a.title, lname = a.title:lower(), app = a }
            end
            local hit = Search.match(items, t, 1)[1]
            return hit and hit.app
        end,
        openApp = function(a) self:tapApp(a, self.window) end,
    }
    local out, trace, err = Pipeline.run(rest, steps, ctx)
    for _i, line in ipairs(trace) do require("logger").dbg("pipeline:", line) end
    if out == nil then
        UIManager:show(InfoMessage:new{ text = tostring(err), icon = "notice-warning", timeout = 5 })
    elseif p and p.name == "bot" then
        UIManager:show(InfoMessage:new{ text = _("Sent."), timeout = 2 })
    end
end

function AppLauncher:openInput(prefill)
    local InputDialog = require("ui/widget/inputdialog")
    local d
    d = InputDialog:new{
        title = _("Type"),
        input = prefill or "",
        input_hint = _("words to search, “open gemma”, “bot hello”"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(d) end },
            { text = _("Go"), is_enter_default = true, callback = function()
                local text = d:getInputText()
                UIManager:close(d)
                if text ~= "" then self:runInput(text) end
            end },
        }},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- A connected hardware keyboard: the first letter pressed on Home opens the input line with it typed.
function AppLauncher:listenForTyping(window)
    if not window or not Device.input or not Device.input.group or not Device.input.group.Alphabet then return end
    window.key_events = window.key_events or {}
    window.key_events.StartTyping = { { Device.input.group.Alphabet }, event = "StartTyping" }
    window.onStartTyping = function(_w, _args, ev)
        local name = ev and ev.key and ev.key.key
        if type(name) ~= "string" or #name ~= 1 then return false end
        self:openInput(name:lower())
        return true
    end
end

function AppLauncher:buildGrid(window, width, height)
    local apps = AppRegistry:getApps()
    local margin = Size.padding.fullscreen
    local inner_w = width - 2 * margin
    local min_tile_w = Screen:scaleBySize(112) -- room for names
    local cols = G_reader_settings:readSetting("kos_home_cols")
    if not cols or cols < 2 then cols = math.max(3, math.floor(inner_w / min_tile_w)) end
    local tile_w = math.floor(inner_w / cols)
    local size_dp = ({ small = 28, medium = 36, large = 48 })[G_reader_settings:readSetting("kos_home_icon") or "medium"] or 36
    local icon_size = math.min(Screen:scaleBySize(size_dp), math.floor(tile_w / 2))

    local make_tile = function(app)
        return AppTile:new{
            app = app,
            width = tile_w,
            icon_size = icon_size,
            callback = function(a) self:tapApp(a, window) end,
            hold_callback = function(a) self:showAppMenu(a, window) end,
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

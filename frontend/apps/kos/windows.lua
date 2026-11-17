--[[--
Every open app window, full screen or in the split view: a list, a switcher,
and several windows (instances) of the same app.

* Each window remembers which app opened it; a second window of the same app
  is titled "Gemma 2", a third "Gemma 3", …
* Windows.showSwitcher(): all open windows. Tap = bring to front.
  Hold = bring to front / put in the split view / new window of that app / close.
* Windows.newInstance(win): another window of the same app (beside it in split view).
* Windows.toSplit(win): moves a full-screen window into the split view, keeping
  its state (the app keeps talking to the same window object).

AppWindow and Workspace call add/remove themselves; apps do nothing.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local Windows = {
    list = {},
    --- set by AppRegistry:launch() while an app is starting
    launching_app = nil,
}

function Windows.add(win, app)
    if win.in_switcher == false then return end -- e.g. the Home screen itself
    app = app or Windows.launching_app
    if app then
        win.kos_app = app
        local highest = 0
        for _, w in ipairs(Windows.list) do
            if w.kos_app and w.kos_app.id == app.id then
                highest = math.max(highest, w.kos_instance or 1)
            end
        end
        win.kos_instance = highest + 1
    end
    table.insert(Windows.list, win)
end

function Windows.remove(win)
    for i = #Windows.list, 1, -1 do
        if Windows.list[i] == win then table.remove(Windows.list, i) end
    end
end

--- The title to draw: "Gemma" for the first window, "Gemma 2" for the next…
function Windows.displayTitle(win)
    local title = win.title or ""
    if win.kos_instance and win.kos_instance > 1 then
        title = title .. " " .. win.kos_instance
    end
    return title
end

local function isPane(win)
    return win.workspace ~= nil
end

local function raiseWidget(widget)
    local stack = UIManager._window_stack
    if type(stack) == "table" then
        for i, entry in ipairs(stack) do
            if entry.widget == widget then
                if i ~= #stack then
                    table.remove(stack, i)
                    table.insert(stack, entry)
                end
                UIManager:setDirty(widget, "full")
                return true
            end
        end
    end
    return false
end

--- Takes a window off the screen but keeps it in the window list, then shows the app launcher.
-- Bring it back from the window switcher (Windows.raise).
function Windows.minimize(win)
    if isPane(win) or win._minimized then return end
    win._minimized = true
    win._keep_in_list = true
    UIManager:close(win)
    UIManager:nextTick(function()
        UIManager:broadcastEvent(Event:new("ShowAppLauncher"))
    end)
end

--- Brings a window to the front (and focuses it, in the split view).
function Windows.raise(win)
    if win._minimized then
        win._minimized = nil
        UIManager:show(win)
        UIManager:setDirty(win, "full")
        return
    end
    if isPane(win) then
        local ws = win.workspace
        ws.focused = win
        if ws.maximized and ws.maximized ~= win then ws.maximized = nil end
        if not raiseWidget(ws) then ws:show() end
        ws:relayout()
    else
        raiseWidget(win)
    end
end

--- Another window of the same app. In the split view it opens beside `win`.
function Windows.newInstance(win)
    local app = win.kos_app
    if not app then
        UIManager:show(InfoMessage:new{ text = _("This window wasn't opened from the Home screen, so I don't know its app."), timeout = 3 })
        return
    end
    local AppRegistry = require("apps/kos/appregistry")
    if isPane(win) then
        AppRegistry:launch(app, { split = { next_to = win } })
    else
        AppRegistry:launch(app)
    end
end

--- Moves a full-screen window into the split view, without restarting the app.
function Windows.toSplit(win)
    if isPane(win) then return win end
    local Workspace = require("apps/kos/workspace")
    local params = {
        title = win.title, subtitle = win.subtitle, build = win.build,
        on_close = win.on_close, confirm_close = win.confirm_close,
        max_content_dp = win.max_content_dp,
    }
    win.on_close = nil
    Windows.remove(win)
    UIManager:close(win)
    local pane = Workspace:getInstance():addPane(params, {})
    pane.kos_app = win.kos_app
    pane.kos_instance = win.kos_instance
    pane:refresh()
    -- The app still holds the old window: send its calls to the pane.
    for _, method in ipairs{ "refresh", "setTitle", "close", "goHome" } do
        win[method] = function(_, ...) return pane[method](pane, ...) end
    end
    win.moved_to = pane
    return pane
end

--- Puts every full-screen app window into the split view.
function Windows.allToSplit()
    local full = {}
    for _, w in ipairs(Windows.list) do
        if not isPane(w) then table.insert(full, w) end
    end
    for _, w in ipairs(full) do Windows.toSplit(w) end
    if #full == 0 then
        UIManager:show(InfoMessage:new{ text = _("No full-screen windows."), timeout = 2 })
    end
end

--- Window shape picker for an app (and `win` right now). Any aspect ratio.
function Windows.shapeMenu(app_id, win)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function apply(ratio)
        if app_id then
            if ratio then G_reader_settings:saveSetting("kos_ratio_" .. app_id, ratio)
            else G_reader_settings:delSetting("kos_ratio_" .. app_id) end
            G_reader_settings:flush()
        end
        for _i, w in ipairs(Windows.list) do
            if (win and w == win) or (app_id and w.kos_app and w.kos_app.id == app_id) then if w.setRatio then w:setRatio(ratio) end end
        end
    end
    local function opt(text, r)
        return { text = text, callback = function() UIManager:close(dialog) apply(r) end }
    end
    dialog = ButtonDialog:new{
        title = _("Window shape"),
        buttons = {
            { opt(_("Fill the screen"), nil) },
            { opt("1:1", 1), opt("4:3", 4 / 3), opt("3:2", 3 / 2) },
            { opt("3:4", 3 / 4), opt("2:3", 2 / 3), opt("9:16", 9 / 16) },
            { opt("16:9", 16 / 9), opt("21:9", 21 / 9), opt("32:9", 32 / 9) },
            { { text = _("Other…"), callback = function()
                UIManager:close(dialog)
                local MultiInputDialog = require("ui/widget/multiinputdialog")
                local d
                d = MultiInputDialog:new{
                    title = _("Window shape: width : height"),
                    fields = {
                        { description = _("Width"), text = "16", input_type = "number" },
                        { description = _("Height"), text = "10", input_type = "number" },
                    },
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
                        { text = _("Apply"), is_enter_default = true, callback = function()
                            local f = d:getFields()
                            UIManager:close(d)
                            local w, h = tonumber(f[1]), tonumber(f[2])
                            if w and h and h > 0 and w / h >= 0.1 and w / h <= 10 then apply(w / h) end
                        end },
                    }},
                }
                UIManager:show(d)
                d:onShowKeyboard()
            end } },
        },
    }
    UIManager:show(dialog)
end

local function windowMenu(win, after)
    local dialog
    local function act(fn) return function() UIManager:close(dialog); fn(); if after then after() end end end
    dialog = ButtonDialog:new{
        title = Windows.displayTitle(win),
        buttons = {
            {{ text = _("Bring to front"), callback = act(function() Windows.raise(win) end) }},
            {{ text = _("Put in split view"), enabled = not isPane(win), callback = act(function() Windows.toSplit(win) end) }},
            {{ text = _("New window of this app"), enabled = win.kos_app ~= nil, callback = act(function() Windows.newInstance(win) end) }},
            {{ text = _("Window shape…"), callback = act(function() Windows.shapeMenu(win.kos_app and win.kos_app.id, win) end) }},
            {{ text = _("Close"), callback = act(function() win:close() end) }},
        },
    }
    UIManager:show(dialog)
end
Windows.windowMenu = windowMenu

--- All open windows: tap one to bring it to the front, hold it for more.
function Windows.showSwitcher()
    if #Windows.list == 0 then
        UIManager:show(InfoMessage:new{ text = _("No app windows are open."), timeout = 2 })
        return
    end
    local Menu = require("ui/widget/menu")
    local menu
    local function items()
        local t = {}
        for i = #Windows.list, 1, -1 do -- newest first
            local w = Windows.list[i]
            table.insert(t, {
                text = Windows.displayTitle(w),
                mandatory = w._minimized and _("minimized") or (isPane(w) and _("split view") or _("full screen")),
                win = w,
            })
        end
        table.insert(t, {
            text = _("Put all full-screen windows side by side"),
            separator_before = true,
            all = true,
        })
        return t
    end
    menu = Menu:new{
        title = T(_("Open windows (%1)"), #Windows.list),
        item_table = items(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            if item.all then
                Windows.allToSplit()
            else
                Windows.raise(item.win)
            end
        end,
        onMenuHold = function(_, item)
            if item.win then windowMenu(item.win, function() UIManager:close(menu) end) end
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function Windows.count()
    return #Windows.list
end

logger.dbg("Windows: loaded")
return Windows

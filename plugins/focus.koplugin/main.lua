--[[--
Focus: ADHD-friendly helpers for KOReader OS.

* Now: one task at a time, broken into small steps you can tick off.
  It's also shown on the home screen, so you always see what you chose.
* Focus timer: 15 / 25 / 45 minutes, then a break. Updates once a minute
  (gentle on e-ink), and works while you read or use other apps.
* Jot it down: catch a stray thought in one tap, then get back to what you
  were doing. Assign "Focus: jot it down" to a gesture to use it anywhere.
  Thoughts go to koreader/focus-inbox.md.
* Break reminders while reading (off by default): a nudge every 30–90 min.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = require("device").screen

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/focus.lua"
local INBOX_FILE = DataStorage:getDataDir() .. "/focus-inbox.md"

-- Shared by every instance of the plugin (file browser and reader each get
-- one), so the timer keeps running when you open or close a book.
local State = {
    settings = nil,
    timer = nil, -- { mode = "focus"|"break", minutes, ends_at, paused_left }
    window = nil,
}

local function settings()
    if not State.settings then State.settings = LuaSettings:open(SETTINGS_FILE) end
    return State.settings
end

local function save()
    settings():flush()
end

------------------------------------------------------------------------
-- Timer (module-level so it survives switching between Files and a book)
------------------------------------------------------------------------

local function minutesLeft()
    local t = State.timer
    if not t then return nil end
    local left = t.paused_left or (t.ends_at - os.time())
    return math.max(0, math.ceil(left / 60)), left
end

local tick, finish

local function refreshWindow()
    if State.window then State.window:refresh() end
end

finish = function()
    UIManager:unschedule(tick)
    UIManager:unschedule(finish)
    local t = State.timer
    State.timer = nil
    if not t then return end
    if t.mode == "focus" then
        local s = settings()
        local today = os.date("%Y-%m-%d")
        if s:readSetting("stats_day") ~= today then
            s:saveSetting("stats_day", today)
            s:saveSetting("stats_sessions", 0)
            s:saveSetting("stats_minutes", 0)
        end
        s:saveSetting("stats_sessions", (s:readSetting("stats_sessions") or 0) + 1)
        s:saveSetting("stats_minutes", (s:readSetting("stats_minutes") or 0) + t.minutes)
        save()
        local break_min = t.minutes >= 45 and 10 or 5
        UIManager:show(ConfirmBox:new{
            text = T(_("Focus time done: %1 minutes.\n\nNice work. Take a %2-minute break: stand up, look away from the screen, drink some water."), t.minutes, break_min),
            ok_text = T(_("Start %1-min break"), break_min),
            cancel_text = _("Skip break"),
            ok_callback = function() State.startTimer("break", break_min) end,
        })
    else
        UIManager:show(ConfirmBox:new{
            text = _("Break's over. Ready for another round?"),
            ok_text = _("Focus 25 min"),
            cancel_text = _("Not now"),
            ok_callback = function() State.startTimer("focus", 25) end,
        })
    end
    refreshWindow()
end

tick = function()
    if not State.timer or State.timer.paused_left then return end
    local _, left = minutesLeft()
    if left <= 0 then
        finish()
        return
    end
    refreshWindow()
    -- Wake up on the next minute boundary, or right at the end.
    UIManager:scheduleIn(math.min(left, (left - 1) % 60 + 1), tick)
end

function State.startTimer(mode, minutes)
    UIManager:unschedule(tick)
    UIManager:unschedule(finish)
    State.timer = { mode = mode, minutes = minutes, ends_at = os.time() + minutes * 60 }
    settings():saveSetting("last_minutes", mode == "focus" and minutes or settings():readSetting("last_minutes"))
    save()
    tick()
    refreshWindow()
end

function State.pauseTimer()
    local t = State.timer
    if not t then return end
    if t.paused_left then
        t.ends_at = os.time() + t.paused_left
        t.paused_left = nil
        tick()
    else
        t.paused_left = math.max(0, t.ends_at - os.time())
        UIManager:unschedule(tick)
    end
    refreshWindow()
end

function State.stopTimer()
    UIManager:unschedule(tick)
    UIManager:unschedule(finish)
    State.timer = nil
    refreshWindow()
end

------------------------------------------------------------------------
-- Inbox (jot it down)
------------------------------------------------------------------------

local function inboxCount()
    local f = io.open(INBOX_FILE, "r")
    if not f then return 0 end
    local n = 0
    for line in f:lines() do if line:match("^%- ") then n = n + 1 end end
    f:close()
    return n
end

local function capture(done)
    local dialog
    dialog = InputDialog:new{
        title = _("Jot it down"),
        description = _("Write it, then get back to what you were doing."),
        input_hint = _("Call the dentist…"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local text = util.trim(dialog:getInputText() or "")
                UIManager:close(dialog)
                if text == "" then return end
                local f = io.open(INBOX_FILE, "a")
                if f then
                    f:write(string.format("- %s  (%s)\n", text:gsub("\n", " "), os.date("%d %b %H:%M")))
                    f:close()
                    UIManager:show(InfoMessage:new{ text = _("Saved to your inbox."), timeout = 1 })
                end
                refreshWindow()
                if done then done() end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

------------------------------------------------------------------------
-- Plugin
------------------------------------------------------------------------

local Focus = WidgetContainer:extend{
    name = "focus",
}

function Focus:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if self.ui.document then
        self:scheduleBreakReminder()
    end
end

function Focus:onDispatcherRegisterActions()
    Dispatcher:registerAction("focus_capture", { category = "none", event = "FocusCapture", title = _("Focus: jot it down"), general = true })
    Dispatcher:registerAction("focus_open", { category = "none", event = "ShowFocus", title = _("Focus: open"), general = true })
    Dispatcher:registerAction("focus_timer", { category = "none", event = "FocusTimer25", title = _("Focus: start 25-min timer"), general = true })
end

function Focus:onFocusCapture() capture() return true end
function Focus:onShowFocus() self:launchApp() return true end
function Focus:onFocusTimer25() State.startTimer("focus", 25) UIManager:show(InfoMessage:new{ text = _("Focus timer: 25 minutes."), timeout = 1 }) return true end

--- One line for the home screen: the task you chose, and the timer.
function Focus:getNowText()
    local task = settings():readSetting("now_task")
    local mins = minutesLeft()
    local parts = {}
    if task and task ~= "" then table.insert(parts, T(_("Now: %1"), task)) end
    if mins then
        table.insert(parts, State.timer.mode == "focus" and T(_("%1 min focus left"), mins) or T(_("break: %1 min"), mins))
    end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- Break reminders while reading -------------------------------------------

function Focus:scheduleBreakReminder()
    UIManager:unschedule(self.remind)
    local minutes = settings():readSetting("break_reminder") or 0
    if minutes <= 0 then return end
    self.remind = self.remind or function()
        UIManager:show(InfoMessage:new{
            text = T(_("You've been reading for %1 minutes.\n\nA short break? Look into the distance, stretch, drink some water."), minutes),
            timeout = 10,
        })
        UIManager:scheduleIn(minutes * 60, self.remind)
    end
    UIManager:scheduleIn(minutes * 60, self.remind)
end

function Focus:onResume()
    -- Time away from the device counts as a break: start counting again.
    if self.ui.document then self:scheduleBreakReminder() end
end

function Focus:onCloseWidget()
    if self.remind then UIManager:unschedule(self.remind) end
end

function Focus:addToMainMenu(menu_items)
    menu_items.focus = {
        text = _("Focus"),
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Open Focus"), callback = function() self:launchApp() end },
            { text = _("Jot it down"), callback = function() capture() end },
            {
                text_func = function()
                    local m = settings():readSetting("break_reminder") or 0
                    return m > 0 and T(_("Break reminder while reading: every %1 min"), m) or _("Break reminder while reading: off")
                end,
                sub_item_table = (function()
                    local items = {}
                    for _, m in ipairs({ 0, 30, 45, 60, 90 }) do
                        table.insert(items, {
                            text = m == 0 and _("Off") or T(_("Every %1 minutes"), m),
                            radio = true,
                            checked_func = function() return (settings():readSetting("break_reminder") or 0) == m end,
                            callback = function()
                                settings():saveSetting("break_reminder", m)
                                save()
                                if self.ui.document then self:scheduleBreakReminder() end
                            end,
                        })
                    end
                    return items
                end)(),
            },
        },
    }
end

-- The Focus window ---------------------------------------------------------

function Focus:editTask()
    local dialog
    dialog = InputDialog:new{
        title = _("What's the one thing to do now?"),
        input = settings():readSetting("now_task") or "",
        description = _("Keep it small and concrete. You can add steps after."),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Clear"), callback = function()
                UIManager:close(dialog)
                settings():delSetting("now_task")
                settings():saveSetting("steps", {})
                save()
                refreshWindow()
            end },
            { text = _("Set"), is_enter_default = true, callback = function()
                local text = util.trim(dialog:getInputText() or "")
                UIManager:close(dialog)
                if text ~= settings():readSetting("now_task") then
                    settings():saveSetting("now_task", text)
                    settings():saveSetting("steps", {})
                end
                save()
                refreshWindow()
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Focus:addStep()
    local dialog
    dialog = InputDialog:new{
        title = _("Add a small step"),
        description = _("Something you could start in under two minutes."),
        buttons = {{
            { text = _("Done"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Add another"), is_enter_default = true, callback = function()
                local text = util.trim(dialog:getInputText() or "")
                if text ~= "" then
                    local steps = settings():readSetting("steps") or {}
                    table.insert(steps, { text = text, done = false })
                    settings():saveSetting("steps", steps)
                    save()
                    dialog:setInputText("")
                    refreshWindow()
                end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Focus:showInbox()
    local f = io.open(INBOX_FILE, "r")
    local text = f and f:read("*all") or ""
    if f then f:close() end
    if text == "" then
        UIManager:show(InfoMessage:new{ text = _("Your inbox is empty. Use \"Jot it down\" to catch stray thoughts.") })
        return
    end
    local TextViewer = require("ui/widget/textviewer")
    local viewer
    viewer = TextViewer:new{
        title = T(_("Inbox (%1)"), inboxCount()),
        text = text,
        buttons_table = {{
            { text = _("Edit"), enabled = self.ui.texteditor ~= nil, callback = function()
                UIManager:close(viewer)
                self.ui.texteditor:openFile(INBOX_FILE, refreshWindow)
            end },
            { text = _("Clear all"), callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Clear the whole inbox?"),
                    ok_text = _("Clear"),
                    ok_callback = function()
                        os.remove(INBOX_FILE)
                        UIManager:close(viewer)
                        refreshWindow()
                    end,
                })
            end },
            { text = _("Close"), callback = function() UIManager:close(viewer) end },
        }},
    }
    UIManager:show(viewer)
end

function Focus:build(window, width, height)
    local s = settings()
    local margin = Size.padding.fullscreen
    local inner = width - 2 * margin
    local group = VerticalGroup:new{ align = "left" }
    local small = Font:getFace("smallinfofont")

    -- Now ----------------------------------------------------------------
    local task = s:readSetting("now_task")
    table.insert(group, TextWidget:new{ text = _("NOW"), face = Font:getFace("smallinfofontbold"), fgcolor = require("ffi/blitbuffer").COLOR_DARK_GRAY })
    table.insert(group, VerticalSpan:new{ width = Size.padding.small })
    table.insert(group, ButtonTable:new{
        width = inner,
        show_parent = window,
        buttons = {{ {
            text = (task and task ~= "") and task or _("Tap to choose one thing to do now"),
            font_bold = true,
            font_size = 22,
            callback = function() self:editTask() end,
        } }},
    })
    local steps = s:readSetting("steps") or {}
    if task and task ~= "" then
        local rows = {}
        local done_count = 0
        for i, step in ipairs(steps) do
            if step.done then done_count = done_count + 1 end
            table.insert(rows, {{
                text = (step.done and "☑  " or "☐  ") .. step.text,
                align = "left",
                callback = function()
                    step.done = not step.done
                    s:saveSetting("steps", steps)
                    save()
                    if not step.done then return refreshWindow() end
                    -- All steps done: celebrate and offer to clear.
                    local all = true
                    for _, st in ipairs(steps) do if not st.done then all = false end end
                    refreshWindow()
                    if all then
                        UIManager:show(ConfirmBox:new{
                            text = T(_("All steps done for:\n%1\n\nWell done! Pick the next thing?"), task),
                            ok_text = _("Next thing"),
                            cancel_text = _("Later"),
                            ok_callback = function()
                                s:delSetting("now_task"); s:saveSetting("steps", {}); save()
                                self:editTask()
                            end,
                        })
                    end
                end,
            }})
            if i >= 8 then break end -- more than this is a list, not "now"
        end
        table.insert(rows, {
            { text = _("+ Add a step"), callback = function() self:addStep() end },
            { text = _("Clear ticked"), enabled = done_count > 0, callback = function()
                local keep = {}
                for _, st in ipairs(steps) do if not st.done then table.insert(keep, st) end end
                s:saveSetting("steps", keep); save(); refreshWindow()
            end },
        })
        table.insert(group, VerticalSpan:new{ width = Size.padding.default })
        table.insert(group, ButtonTable:new{ width = inner, show_parent = window, buttons = rows })
    end

    -- Timer --------------------------------------------------------------
    table.insert(group, VerticalSpan:new{ width = Size.padding.large * 2 })
    table.insert(group, TextWidget:new{ text = _("FOCUS TIMER"), face = Font:getFace("smallinfofontbold"), fgcolor = require("ffi/blitbuffer").COLOR_DARK_GRAY })
    local mins, left = minutesLeft()
    local t = State.timer
    local big = TextWidget:new{
        text = mins and T(_("%1 min"), mins) or "—",
        face = Font:getFace("tfont", 44),
    }
    table.insert(group, CenterContainer:new{ dimen = Geom:new{ w = inner, h = big:getSize().h + Size.padding.large }, big })
    if t then
        local total = t.minutes * 60
        table.insert(group, ProgressWidget:new{
            width = inner,
            height = Screen:scaleBySize(14),
            percentage = math.min(1, math.max(0, (total - left) / total)),
        })
        local status = (t.mode == "focus" and _("Focusing") or _("Break")) ..
            (t.paused_left and (" · " .. _("paused")) or (" · " .. T(_("ends %1"), os.date("%H:%M", t.ends_at))))
        table.insert(group, CenterContainer:new{ dimen = Geom:new{ w = inner, h = Screen:scaleBySize(32) }, TextWidget:new{ text = status, face = small } })
        table.insert(group, ButtonTable:new{ width = inner, show_parent = window, buttons = {{
            { text = t.paused_left and _("Resume") or _("Pause"), callback = function() State.pauseTimer() end },
            { text = _("Stop"), callback = function() State.stopTimer() end },
        }}})
    else
        table.insert(group, ButtonTable:new{ width = inner, show_parent = window, buttons = {{
            { text = _("15 min"), callback = function() State.startTimer("focus", 15) end },
            { text = _("25 min"), callback = function() State.startTimer("focus", 25) end },
            { text = _("45 min"), callback = function() State.startTimer("focus", 45) end },
        }}})
    end
    local today = os.date("%Y-%m-%d")
    if s:readSetting("stats_day") == today and (s:readSetting("stats_sessions") or 0) > 0 then
        table.insert(group, CenterContainer:new{ dimen = Geom:new{ w = inner, h = Screen:scaleBySize(32) },
            TextWidget:new{ text = T(_("Today: %1 sessions, %2 min"), s:readSetting("stats_sessions"), s:readSetting("stats_minutes") or 0), face = small } })
    end

    -- Inbox --------------------------------------------------------------
    table.insert(group, VerticalSpan:new{ width = Size.padding.large * 2 })
    local n = inboxCount()
    table.insert(group, ButtonTable:new{ width = inner, show_parent = window, buttons = {{
        { text = _("Jot it down"), callback = function() capture() end },
        { text = n > 0 and T(_("Inbox (%1)"), n) or _("Inbox"), callback = function() self:showInbox() end },
    }}})

    return FrameContainer:new{
        padding = margin,
        margin = 0,
        bordersize = 0,
        width = width,
        height = height,
        group,
    }
end

function Focus:launchApp()
    local AppWindow = require("apps/kos/appwindow")
    if State.window then
        -- Only one Focus window: bring it up to date instead of opening another.
        State.window:refresh()
        return
    end
    State.window = AppWindow:open{
        title = _("Focus"),
        build = function(window, width, height) return self:build(window, width, height) end,
        on_close = function() State.window = nil end,
    }
end

return Focus

--[[--
Logcat: a colour-coded log viewer for KOReader OS.

Sources: the Android log (this app's own process, no permission needed),
koreader/fork-preview.log and koreader/crash.log. Filter by level and text.
Newest lines come first on screen; "Older" pages backwards.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local LogLines = require("loglines")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local Logcat = WidgetContainer:extend{ name = "logcat", is_doc_only = false }

local State = { source = "android", min_level = "V", text = "", back = 0, window = nil }

local SOURCES = {
    { id = "android", text = _("Android") },
    { id = "fork", text = _("Patch log") },
    { id = "crash", text = _("crash.log") },
    { id = "trace", text = _("Actions") },
    { id = "debug", text = _("Debug") },
}
local LEVELS = { V = _("All"), I = "I+", W = "W+", E = "E" }
local LEVEL_NEXT = { V = "I", I = "W", W = "E", E = "V" }

local function color(r, g, b)
    if Screen.isColorEnabled and Screen:isColorEnabled() and Blitbuffer.ColorRGB32 then
        return Blitbuffer.ColorRGB32(r, g, b, 0xFF)
    end
end
local COLORS = {
    F = color(0xB0, 0x00, 0x20) or Blitbuffer.COLOR_BLACK,
    E = color(0xC6, 0x28, 0x28) or Blitbuffer.COLOR_BLACK,
    W = color(0xC7, 0x6A, 0x00) or Blitbuffer.COLOR_DARK_GRAY,
    I = Blitbuffer.COLOR_BLACK,
    D = color(0x6B, 0x6B, 0x6B) or Blitbuffer.COLOR_DARK_GRAY,
    V = color(0x8A, 0x8A, 0x8A) or Blitbuffer.COLOR_GRAY_4,
}

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    return lines
end

local function readSource(id)
    if id == "android" then
        local p = io.popen("logcat -d -v time -t 3000 2>&1")
        if not p then return nil, _("Could not read the Android log.") end
        local lines = {}
        for line in p:lines() do lines[#lines + 1] = line end
        p:close()
        return lines
    end
    local name = id == "fork" and "fork-preview.log" or id == "trace" and "kos-trace.log" or id == "debug" and "kos-debug.log" or "crash.log"
    local lines = readFile(DataStorage:getDataDir() .. "/" .. name)
    if not lines then return nil, name .. " " .. _("does not exist yet.") end
    return lines
end

function Logcat:build(window, width, height)
    local lines, err = readSource(State.source)
    local entries = LogLines.filter(lines or {}, { min_level = State.min_level, text = State.text })
    local face = Font:getFace("infont", 14)
    local line_h = TextWidget:new{ text = "Ag", face = face }:getSize().h + 2
    local bar_h = Screen:scaleBySize(48) * 3
    local per_page = math.max(3, math.floor((height - bar_h) / line_h))
    local page, pages = LogLines.page(entries, per_page, State.back)

    local function src_button(s)
        return {
            text = (State.source == s.id and "● " or "") .. s.text,
            callback = function() State.source = s.id State.back = 0 window:refresh() end,
        }
    end
    local rows = {
        { src_button(SOURCES[1]), src_button(SOURCES[2]), src_button(SOURCES[3]), src_button(SOURCES[4]), src_button(SOURCES[5]) },
        {
            { text = _("Level: ") .. LEVELS[State.min_level], callback = function()
                State.min_level = LEVEL_NEXT[State.min_level] State.back = 0 window:refresh() end },
            { text = State.text ~= "" and ("🔍 " .. State.text) or _("Search"), callback = function()
                local dlg
                dlg = InputDialog:new{
                    title = _("Search the log"), input = State.text,
                    buttons = {{
                        { text = _("Clear"), callback = function() State.text = "" UIManager:close(dlg) window:refresh() end },
                        { text = _("Search"), is_enter_default = true, callback = function()
                            State.text = dlg:getInputText() State.back = 0 UIManager:close(dlg) window:refresh() end },
                    }},
                }
                UIManager:show(dlg) dlg:onShowKeyboard()
            end },
            { text = _("Refresh"), callback = function() State.back = 0 window:refresh() end },
        },
        {
            { text = _("Older"), enabled = State.back + 1 < pages, callback = function() State.back = State.back + 1 window:refresh() end },
            { text = (State.back + 1) .. " / " .. pages, enabled = false },
            { text = _("Newer"), enabled = State.back > 0, callback = function() State.back = State.back - 1 window:refresh() end },
        },
    }
    local group = VerticalGroup:new{
        align = "left",
        ButtonTable:new{ buttons = rows, width = width, shrink_unneeded_width = false },
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
    }
    if err and #entries == 0 then
        table.insert(group, TextWidget:new{ text = err, face = face, max_width = width })
    elseif #entries == 0 then
        table.insert(group, TextWidget:new{ text = _("No lines match."), face = face, max_width = width })
    end
    for _i, e in ipairs(page) do
        table.insert(group, TextWidget:new{
            text = e.text, face = face, fgcolor = COLORS[e.level] or Blitbuffer.COLOR_BLACK,
            max_width = width, truncate_with_ellipsis = true,
        })
    end
    return group
end

function Logcat:launchApp()
    local AppWindow = require("apps/kos/appwindow")
    if State.window then State.window:refresh() return end
    State.back = 0
    State.window = AppWindow:open{
        title = _("Logcat"),
        build = function(window, width, height) return self:build(window, width, height) end,
        on_close = function() State.window = nil end,
    }
end

function Logcat:onShowLogcat(source)
    if type(source) == "string" then State.source = source end
    self:launchApp()
    return true
end

function Logcat:addToMainMenu(menu_items)
    menu_items.kos_logcat = {
        text = _("Logcat"),
        sorting_hint = "tools",
        callback = function() self:launchApp() end,
    }
end

function Logcat:init()
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
end

return Logcat

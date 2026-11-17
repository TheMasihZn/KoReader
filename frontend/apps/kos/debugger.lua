--[[--
Debugger for KOReader OS apps.

1. Trail. Before an app starts, "launching <app>" is written to koreader/kosDebug.log; when it
   starts fine, "started"; when it raises an error, "error: ...". The note is cleared a few
   seconds after a good start. If KOReader dies while an app starts (a native crash no Lua code can
   catch), the note is still there at the next start: you are told which app did it, and it can
   be switched off until you re-enable it.
2. Layout bounds. Like Android's "Show layout bounds": a thin box around every container
   widget, colour by kind. Setting kos_layout_bounds; flip it from Home > Debug.

    local Debugger = require("apps/kos/debugger")
    Debugger.launching("httpinspector")   -- before starting an app
    Debugger.started("httpinspector")     -- after it came up
    Debugger.failed("httpinspector", err) -- when it raised an error
    Debugger.checkLastStart()             -- once, at start: tells about a crash
    Debugger.setBounds(true)
]]

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")

local Debugger = {}

local LOG = DataStorage:getDataDir() .. "/kosDebug.log"

function Debugger.log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local f = io.open(LOG, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S "), table.concat(parts, " "), "\n")
        f:close()
    end
end

local function settings() return G_reader_settings end

function Debugger.disabledApps()
    return settings():readSetting("kos_disabled_apps") or {}
end

function Debugger.isDisabled(id)
    return Debugger.disabledApps()[id] == true
end

function Debugger.setDisabled(id, value)
    local d = Debugger.disabledApps()
    d[id] = value or nil
    settings():saveSetting("kos_disabled_apps", d)
    settings():flush()
end

function Debugger.launching(id)
    Debugger.log("launching", id)
    settings():saveSetting("kos_launching", id)
    settings():flush() -- on disk NOW: a crash a moment later must still find it
end

local function clear(id)
    if settings():readSetting("kos_launching") == id then
        settings():delSetting("kos_launching")
        settings():flush()
    end
end

function Debugger.started(id)
    Debugger.log("started", id)
    UIManager:scheduleIn(4, function() clear(id) end) -- survived 4 s: not a start-up crash
end

function Debugger.failed(id, err)
    Debugger.log("error", id, err)
    clear(id)
end

--- At start: was an app starting when KOReader died last time?
-- Returns the app id (and records it), or nil.
function Debugger.checkLastStart()
    local id = settings():readSetting("kos_launching")
    if not id then return nil end
    settings():delSetting("kos_launching")
    Debugger.log("CRASH while starting", id)
    local count = (settings():readSetting("kos_crash_counts") or {})
    count[id] = (count[id] or 0) + 1
    settings():saveSetting("kos_crash_counts", count)
    settings():flush()
    return id, count[id]
end

---------------------------------------------------------------------------
-- Layout bounds
---------------------------------------------------------------------------

local bounds_on = false
local wrapped = false

local PALETTE = {
    FrameContainer = { 0xC6, 0x28, 0x28 },
    VerticalGroup = { 0x1E, 0x6F, 0xD9 },
    HorizontalGroup = { 0x2E, 0x8B, 0x57 },
    CenterContainer = { 0xB0, 0x6A, 0x00 },
    default = { 0x7A, 0x3E, 0xB0 },
}

local function colorFor(kind, Blitbuffer)
    local c = PALETTE[kind] or PALETTE.default
    if Blitbuffer.ColorRGB32 and require("device").screen:isColorEnabled() then
        return Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF)
    end
    return Blitbuffer.COLOR_DARK_GRAY
end

local MODULES = {
    { "ui/widget/container/framecontainer", "FrameContainer" },
    { "ui/widget/verticalgroup", "VerticalGroup" },
    { "ui/widget/horizontalgroup", "HorizontalGroup" },
    { "ui/widget/container/centercontainer", "CenterContainer" },
    { "ui/widget/container/leftcontainer", "LeftContainer" },
    { "ui/widget/container/rightcontainer", "RightContainer" },
    { "ui/widget/container/topcontainer", "TopContainer" },
    { "ui/widget/container/bottomcontainer", "BottomContainer" },
    { "ui/widget/container/widgetcontainer", "WidgetContainer" },
    { "ui/widget/container/inputcontainer", "InputContainer" },
}

local function install()
    if wrapped then return end
    wrapped = true
    local Blitbuffer = require("ffi/blitbuffer")
    for _i, m in ipairs(MODULES) do
        pcall(function()
            local class = require(m[1])
            local orig = rawget(class, "paintTo")
            if type(orig) ~= "function" then return end
            local kind = m[2]
            class.paintTo = function(self, bb, x, y)
                orig(self, bb, x, y)
                if bounds_on and self.dimen and self.dimen.w and self.dimen.w > 0 and self.dimen.h > 0 then
                    pcall(bb.paintBorder, bb, x, y, self.dimen.w, self.dimen.h, 1, colorFor(kind, Blitbuffer))
                end
            end
        end)
    end
end

function Debugger.setBounds(on)
    bounds_on = on and true or false
    if bounds_on then install() end
    settings():saveSetting("kos_layout_bounds", bounds_on)
    UIManager:setDirty("all", "full")
end

function Debugger.boundsOn() return bounds_on end

--- Re-applies the saved setting at start.
function Debugger.restore()
    if settings():isTrue("kos_layout_bounds") then Debugger.setBounds(true) end
end

return Debugger

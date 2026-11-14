--[[--
A DPI for each screen, for foldables (Galaxy Fold: cover screen vs unfolded).

Always on: the DPI you set (Screen DPI menu) is remembered for the screen
you're using, and applied automatically when the device switches screens
(folding / unfolding). A screen you never set a DPI for uses Auto.
Changes apply live, without a restart.

A screen is recognised by the shorter side of the physical display, which
doesn't change with rotation, notches or split-screen.
]]

local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local DisplayProfiles = {}


--- Key for a physical display size, e.g. "w900" (cover) or "w1810" (unfolded).
function DisplayProfiles.key(display_w, display_h)
    local short = math.min(display_w, display_h)
    return "w" .. math.floor(short / 10 + 0.5) * 10
end

--- A friendly name for a key, for menus.
function DisplayProfiles.label(display_w, display_h)
    local long, short = math.max(display_w, display_h), math.min(display_w, display_h)
    local kind = (long / short >= 1.8) and _("narrow screen") or _("wide screen")
    return T(_("%1 (%2 px)"), kind, short)
end

local function profiles()
    return G_reader_settings:readSetting("dpi_profiles") or {}
end

--- DPI stored for a key: a number, "auto", or nil if never set.
function DisplayProfiles.get(key)
    return profiles()[key]
end

function DisplayProfiles.set(key, dpi)
    local p = profiles()
    p[key] = dpi or "auto"
    G_reader_settings:saveSetting("dpi_profiles", p)
end

--- Recomputes ui/size (paddings, borders…) in place for the current DPI.
-- Widgets keep a reference to the same table, so they pick up the new values.
function DisplayProfiles.refreshSizes()
    local Size = package.loaded["ui/size"]
    if not Size then return end
    local path = package.searchpath("ui/size", package.path)
    local chunk = path and loadfile(path)
    if not chunk then return end
    local ok, fresh = pcall(chunk)
    if not ok or type(fresh) ~= "table" then return end
    for group, values in pairs(fresh) do
        local target = rawget(Size, group)
        if type(values) == "table" and type(target) == "table" then
            for k, v in pairs(values) do rawset(target, k, v) end
        end
    end
end

--- Sets DPI now. dpi = number, or nil for auto. Returns true if it changed.
function DisplayProfiles.applyDPI(Device, dpi)
    local Screen = Device.screen
    local current = Screen.dpi_override
    if current == dpi then return false end
    G_reader_settings:saveSetting("screen_dpi", dpi) -- also used at the next start
    Device:setScreenDPI(dpi)
    DisplayProfiles.refreshSizes()
    logger.info("DisplayProfiles: DPI now", dpi or "auto")
    return true
end

--- Called when the screen changes: applies the stored DPI for the new screen.
-- Returns true if the DPI changed (the caller then relayouts everything).
function DisplayProfiles.onDisplayChanged(Device, display_w, display_h)
    local want = DisplayProfiles.get(DisplayProfiles.key(display_w, display_h)) or "auto"
    return DisplayProfiles.applyDPI(Device, want ~= "auto" and want or nil)
end

--- At startup: the DPI for the screen in use. A screen seen for the first time
-- keeps the DPI already chosen (so updating doesn't change anything).
-- Returns the DPI to use (number or nil for auto).
function DisplayProfiles.startupDPI(display_w, display_h)
    local key = DisplayProfiles.key(display_w, display_h)
    local want = DisplayProfiles.get(key)
    if want == nil then
        local current = G_reader_settings:readSetting("screen_dpi")
        DisplayProfiles.set(key, current)
        return current
    end
    return want ~= "auto" and want or nil
end

--- The Screen DPI menu: set the DPI for the screen in use, live.
function DisplayProfiles.setForCurrentScreen(Device, display_w, display_h, dpi)
    DisplayProfiles.set(DisplayProfiles.key(display_w, display_h), dpi)
    if DisplayProfiles.applyDPI(Device, dpi) then
        DisplayProfiles.relayout(Device)
    end
end

--- After a DPI change: rebuild the UI, and resize book text (it's in pixels).
function DisplayProfiles.relayout(Device)
    local UIManager = require("ui/uimanager")
    local new_size = Device.screen:getSize()
    UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
    UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
    local ReaderUI = package.loaded["apps/reader/readerui"]
    local reader = ReaderUI and ReaderUI.instance
    if reader and reader.font and reader.document and reader.font.configurable then
        pcall(function()
            reader.document:setFontSize(Device.screen:scaleBySize(reader.font.configurable.font_size))
            reader:handleEvent(Event:new("UpdatePos"))
        end)
    end
    UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    if FileManager and FileManager.instance then
        FileManager.instance:reinit(FileManager.instance.path, FileManager.instance.focused_file)
    end
    UIManager:setDirty("all", "full")
end

return DisplayProfiles

--[[--
A DPI for each screen, for foldables (Galaxy Fold: cover screen vs unfolded).

When "Separate DPI for each screen" is on, the DPI you set is remembered for
the screen you're using, and applied automatically when the device switches
screens (folding / unfolding). It applies live, without a restart.

A screen is recognised by the shorter side of the physical display, which
doesn't change with rotation, notches or split-screen.
]]

local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local DisplayProfiles = {}

function DisplayProfiles.isEnabled()
    return G_reader_settings:isTrue("dpi_per_screen")
end

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
    if not DisplayProfiles.isEnabled() then return false end
    local want = DisplayProfiles.get(DisplayProfiles.key(display_w, display_h))
    if want == nil then return false end -- never set for this screen: leave as is
    return DisplayProfiles.applyDPI(Device, want ~= "auto" and want or nil)
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

--- Menu items for the Screen DPI menu.
-- getDisplaySize: function() -> w, h of the physical display
function DisplayProfiles.menuItems(Device, getDisplaySize)
    local UIManager = require("ui/uimanager")
    local function current()
        local w, h = getDisplaySize()
        return DisplayProfiles.key(w, h), DisplayProfiles.label(w, h)
    end
    return {
        {
            text = _("Separate DPI for each screen (foldables)"),
            help_text = _("For foldable phones and tablets: remember a DPI for the cover screen and another for the unfolded screen, and switch automatically when you fold or unfold. Set the DPI below while using each screen."),
            checked_func = DisplayProfiles.isEnabled,
            callback = function()
                G_reader_settings:flipNilOrFalse("dpi_per_screen")
                if DisplayProfiles.isEnabled() then
                    -- Start from what's in use now on this screen.
                    local key = current()
                    if DisplayProfiles.get(key) == nil then
                        DisplayProfiles.set(key, Device.screen.dpi_override)
                    end
                end
            end,
            separator = false,
        },
        {
            text_func = function()
                local key, label = current()
                local v = DisplayProfiles.get(key)
                local shown = v == nil and _("not set") or (v == "auto" and _("auto") or tostring(v))
                return T(_("DPI for this screen, %1: %2"), label, shown)
            end,
            enabled_func = DisplayProfiles.isEnabled,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                local key, label = current()
                local v = DisplayProfiles.get(key)
                UIManager:show(SpinWidget:new{
                    title_text = T(_("DPI for the %1"), label),
                    info_text = _("Higher makes text, icons and buttons bigger. Applied right away."),
                    value = (type(v) == "number" and v) or Device.screen:getDPI(),
                    value_min = 90,
                    value_max = 900,
                    value_step = 10,
                    value_hold_step = 50,
                    ok_text = _("Set"),
                    extra_text = _("Auto"),
                    extra_callback = function()
                        DisplayProfiles.set(key, nil)
                        if DisplayProfiles.applyDPI(Device, nil) then DisplayProfiles.relayout(Device) end
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    callback = function(spin)
                        DisplayProfiles.set(key, spin.value)
                        if DisplayProfiles.applyDPI(Device, spin.value) then DisplayProfiles.relayout(Device) end
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
    }
end

return DisplayProfiles

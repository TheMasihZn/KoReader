--[[--
dp / sp scaling for KOReader OS, the way Android does it.

KOReader normally scales the interface by the size of the screen (its shorter
side compared to a 600 px e-reader). On a foldable that means everything
doubles in size when you unfold: the screen "stretches".

Here, as on Android:

* dp (interface size): sizes follow the screen's real density, read again
  whenever the display changes. Unfolding gives you more room, not bigger
  buttons. "Interface size" scales all of it (like Android's display size).
* sp (text size): interface text is additionally scaled by "Text size"
  (like Android's font size), independent of the layout.

The first time it runs, the dp scale is calibrated so the screen you're on
looks exactly as before. Book text is not affected (books have their own
font size).

Window size classes (Android's compact / medium / expanded, by width in dp)
let apps adapt instead of stretching: Scaling.windowClass(width_px).
]]

local logger = require("logger")

local Scaling = {
    installed = false,
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function Scaling.uiPercent() return G_reader_settings:readSetting("kos_ui_scale") or 100 end
function Scaling.textPercent() return G_reader_settings:readSetting("kos_text_scale") or 100 end

--- KOReader's own formula, for calibration (see ffi/framebuffer.lua fb:scaleBySize).
local function legacyScale(fb)
    local size_scale = math.min(fb:getWidth(), fb:getHeight()) / 600
    local dpi_scale = fb.dpi_override and (fb:getDPI() / 160) or size_scale
    return (size_scale + dpi_scale) / 2
end

--- Pixels per "KOReader unit" per dp at 100 %: chosen once so nothing changes
-- on the screen in use the first time; after that, density alone decides.
function Scaling.calibration(fb)
    local c = G_reader_settings:readSetting("kos_dp_calibration")
    if not c then
        c = clamp(legacyScale(fb) / (fb:getDPI() / 160), 0.35, 2.0)
        G_reader_settings:saveSetting("kos_dp_calibration", c)
        logger.info("Scaling: calibrated dp scale", c)
    end
    return c
end

--- Pixels for one KOReader size unit (dp), all factors included.
function Scaling.factor(fb)
    return (fb:getDPI() / 160) * Scaling.calibration(fb) * Scaling.uiPercent() / 100
end

--- Android-like window size class from a width in pixels.
-- compact < 600dp ≤ medium < 840dp ≤ expanded
function Scaling.windowClass(width_px)
    local Screen = require("device").screen
    width_px = width_px or Screen:getWidth()
    -- Real Android dp (density only), like WindowSizeClass, not KOReader's units.
    local dp = width_px / (Screen:getDPI() / 160)
    if dp >= 840 then return "expanded", dp end
    if dp >= 600 then return "medium", dp end
    return "compact", dp
end

--- Replaces scaleBySize on the screen, and makes interface fonts follow sp.
function Scaling.install(Device)
    if Scaling.installed then return end
    local fb = Device.screen
    Scaling.calibration(fb) -- before replacing the formula it calibrates against
    Scaling.orig_scaleBySize = fb.scaleBySize
    fb.scaleBySize = function(self, px)
        return math.ceil(px * Scaling.factor(self))
    end

    -- sp: interface text gets the text size on top of dp.
    local Font = require("ui/font")
    local orig_getFace = Font.getFace
    Font.getFace = function(self, font, size, faceindex)
        if not size then size = self.sizemap[font] end
        local pct = Scaling.textPercent()
        if not size or pct == 100 then
            return orig_getFace(self, font, size, faceindex)
        end
        local face = orig_getFace(self, font, size * pct / 100, faceindex)
        -- Keep the unscaled size here: code that derives other faces from it
        -- (fallback fonts, "a bit smaller") calls getFace again, which scales once.
        if face then face.orig_size = size end
        return face
    end

    Scaling.installed = true
    -- ui/size may already have been computed with the old formula.
    local ok, DisplayProfiles = pcall(require, "apps/kos/displayprofiles")
    if ok then DisplayProfiles.refreshSizes() end
end

--- Android only: the display's density can change when the device folds or
-- unfolds. Returns true if it changed.
function Scaling.refreshDensity(Device)
    local ok, android = pcall(require, "android")
    if not ok or type(android) ~= "table" or not android.lib or not android.app then return false end
    local ok2, density = pcall(function() return android.lib.AConfiguration_getDensity(android.app.config) end)
    if not ok2 or not density or density <= 0 or density == Device.display_dpi then return false end
    logger.info("Scaling: display density", Device.display_dpi, "->", density)
    Device.display_dpi = density
    if not Device.screen.dpi_override then
        Device.screen:clearDPI() -- re-reads display_dpi
    end
    return true
end

--- Apply a change of interface or text size now.
function Scaling.apply(Device)
    local ok, DisplayProfiles = pcall(require, "apps/kos/displayprofiles")
    if ok then
        DisplayProfiles.refreshSizes()
        DisplayProfiles.relayout(Device)
    end
end

--- Menu items: Interface size (dp) and Text size (sp).
function Scaling.menuItems(Device)
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local function spin(title, info, key, current, touchmenu_instance)
        local SpinWidget = require("ui/widget/spinwidget")
        UIManager:show(SpinWidget:new{
            title_text = title,
            info_text = info,
            value = current,
            value_min = 50,
            value_max = 250,
            value_step = 5,
            value_hold_step = 25,
            unit = "%",
            default_value = 100,
            ok_text = _("Apply"),
            callback = function(s)
                G_reader_settings:saveSetting(key, s.value ~= 100 and s.value or nil)
                Scaling.apply(Device)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return {
        {
            text_func = function() return T(_("Interface size (dp): %1%"), Scaling.uiPercent()) end,
            help_text = _("Buttons, icons, spacing and text, all together. Sizes follow the screen's real density, so they stay the same physical size when you unfold: you get more room instead of bigger things."),
            keep_menu_open = true,
            callback = function(tmi)
                spin(_("Interface size"), _("Like Android's display size. Applies right away."), "kos_ui_scale", Scaling.uiPercent(), tmi)
            end,
        },
        {
            text_func = function() return T(_("Text size (sp): %1%"), Scaling.textPercent()) end,
            help_text = _("Only the text of menus, dialogs and apps, on top of the interface size. Book text has its own font size."),
            keep_menu_open = true,
            callback = function(tmi)
                spin(_("Text size"), _("Like Android's font size. Applies right away."), "kos_text_scale", Scaling.textPercent(), tmi)
            end,
            separator = true,
        },
    }
end

return Scaling

--[[--
Default home layout. Ships with the build; edit this file to change the defaults.

koreaderApps: KOReader plugins ("KOReader apps") that come installed with this build.
  Each one opens through its Dispatcher action, the same mechanism gestures use.
  All of them show up when you search their name.

pinned: apps drawn on the home screen at a fixed spot, by default.
  x and y are fractions of the screen (0 = left/top, 1 = right/bottom), so the same
  layout works folded and unfolded.
  Empty by default: the home screen is only the search field.
  Example:  { action = "terminal", x = 0.08, y = 0.10 },
--]]

local _ = require("gettext")

return {
    koreaderApps = {
        { action = "terminal",            label = _("Terminal") },
        { action = "edit_last_edited_file", label = _("Text editor (last file)") },
        { action = "cloudstorage",        label = _("Cloud storage") },
        { action = "opds_show_catalog",   label = _("OPDS catalog") },
        { action = "show_vocab_builder",  label = _("Vocabulary builder") },
        { action = "system_statistics",   label = _("System statistics") },
        { action = "battery_statistics",  label = _("Battery statistics") },
        { action = "stats_calendar_view", label = _("Reading calendar") },
        { action = "show_timer",          label = _("Timer") },
        { action = "show_alarm",          label = _("Alarm") },
        { action = "qr_from_clipboard",   label = _("QR from clipboard") },
        { action = "wallabag_download",   label = _("Wallabag") },
        { action = "toggle_ssh_server",   label = _("SSH server") },
    },
    pinned = {
    },
}

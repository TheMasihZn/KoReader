local _ = require("gettext")
return {
    fullname = _("Hello"),
    description = _([[A template app for KOReader OS. Copy this folder and rename it.]]),
    -- This table is what turns a plugin into an app on the home screen.
    app = {
        icon = "appbar.typeset", -- a KOReader icon name, or a file in this folder, e.g. "icon.svg"
    },
}

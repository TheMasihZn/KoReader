local _ = require("gettext")
return {
    fullname = _("Studio"),
    description = _([[Write KOReader OS apps on the device: create an app from a template, edit its files, check them for errors, read the log, and package the app as a .zip to share.]]),
    app = {
        icon = "appbar.typeset",
        order = 25,
    },
}

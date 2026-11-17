local _ = require("gettext")
return {
    name = "kosThemes",
    fullname = _("Themes"),
    description = _([[One default look for every app, and any app can have its own. Font size, line strength, corner roundness, spacing, icon size. Save a look under a name and switch to it later.]]),
    app = { icon = "appbar.settings", order = 10 },
}

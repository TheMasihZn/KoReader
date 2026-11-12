local _ = require("gettext")
return {
    fullname = _("App installer"),
    description = _([[Install apps and plugins from .zip files: tap a zip in the file browser. Also lists installed apps so you can remove them.]]),
    app = {
        icon = "plus",
        order = 30,
    },
}

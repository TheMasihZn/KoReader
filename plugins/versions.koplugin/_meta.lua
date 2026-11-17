local _ = require("gettext")
return {
    name = "versions",
    fullname = _("File versions"),
    description = _([[Keep every change of a file: a folder named after the file holds the file, a change log (who changed it, when, why, and only the part that changed) and a script that rebuilds any older version. Older versions are named with extra dots: photo..jpg is one change back, photo...jpg two.]]),
    app = {
        icon = "appbar.typeset",
        order = 38,
    },
}

local _ = require("gettext")
return {
    name = "icons",
    fullname = _("Icons"),
    description = _([[Draw icons, or correct the ones KOReader uses. Start from a blank page or trace over an existing icon, with lines, shapes and ready-made stamps. Saved icons replace the ones with the same name everywhere after a restart.]]),
    app = {
        icon = "edit",
        order = 35,
    },
}

local _ = require("gettext")
return {
    name = "updates",
    fullname = _("Updates"),
    description = _([[Install updates for KOReader's own apps from a .zip, and keep your own edited copies of built-in app files. Each replacement can be switched on and off. If KOReader stops starting, they switch themselves off.]]),
    app = {
        icon = "appbar.tools",
        order = 30,
    },
}

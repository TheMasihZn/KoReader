local _ = require("gettext")
return {
    name = "kosCanvas",
    fullname = _("Canvas"),
    description = _([[An endless page. Drag to move over it in every direction, hold an empty spot to put a note or an app there, hold an item to move or remove it.]]),
    app = { icon = "appbar.pageview", order = 6 },
}

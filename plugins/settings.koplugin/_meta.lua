local _ = require("gettext")
return {
    name = "kosSettings",
    fullname = _("Settings"),
    description = _([[Every setting under one of three heads: Time, Space, Energy. The first ones in each head are the ones that change the most. Search finds a setting by any name it has had (brightness leads to Light). The classic settings menu is still there, at the bottom.]]),
    app = {
        icon = "appbar.settings",
        order = 5,
    },
}

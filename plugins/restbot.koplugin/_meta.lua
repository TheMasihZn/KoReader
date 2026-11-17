local _ = require("gettext")
return {
    name = "kosRestBot",
    fullname = _("REST and bot"),
    description = _([[Telegram messages and HTTP requests become REST calls on this device: GET and SET settings, open apps, send events, add routes on the fly. New routes wait for your approval here. Only the chats and tokens you list are answered.]]),
    app = { icon = "appbar.tools", order = 8 },
}

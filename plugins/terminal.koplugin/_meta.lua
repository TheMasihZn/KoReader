local _ = require("gettext")
return {
    fullname = _("Terminal emulator"),
    description = _([[KOReader's terminal emulator. In KOReader OS it is also an app on Home; the title bar has minimize (the shell keeps running) and close.]]),
    app = { icon = "appbar.tools", order = 11 },
}

local _ = require("gettext")
return {
    name = "kosDebugger",
    fullname = _("Debugger"),
    description = _([[Debug session report (breakpoints, snapshots, most called functions) and ADB devices. Breakpoints are set from the laptop or a script and record the variables without stopping the screen.]]),
    app = { icon = "appbar.tools", order = 7 },
}

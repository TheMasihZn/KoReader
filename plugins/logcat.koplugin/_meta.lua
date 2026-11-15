local _ = require("gettext")
return {
    fullname = _("Logcat"),
    description = _([[A colour-coded log viewer like Android Studio's Logcat: errors red, warnings orange, debug grey. Reads the Android log, fork-preview.log and crash.log, filters by level and text, and pages from the newest line.]]),
    app = {
        icon = "appbar.search",
        order = 6,
    },
}

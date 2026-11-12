local _ = require("gettext")
return {
    fullname = _("Focus"),
    description = _([[ADHD-friendly helpers: one task "now" broken into small steps, a focus timer with breaks, a one-tap inbox to jot down stray thoughts (also from a gesture while reading), and gentle break reminders while reading.]]),
    app = {
        icon = "check",
        order = 3,
    },
}

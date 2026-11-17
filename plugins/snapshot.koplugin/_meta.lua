local _ = require("gettext")
return {
    name = "snapshot",
    fullname = _("Snapshots"),
    description = _([[Save where an unfinished discussion stands as one plain Markdown file: decisions, open questions, the next step and the formulas in play. Open it later here, or hand it to an assistant to continue from the same point.]]),
    app = {
        icon = "appbar.typeset",
        order = 37,
    },
}

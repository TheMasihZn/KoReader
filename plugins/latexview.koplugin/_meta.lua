local _ = require("gettext")
return {
    fullname = _("LaTeX view"),
    description = _([[Read .tex files as formatted pages: sections, lists, tables, footnotes and math (shown with Unicode symbols, fractions, sub- and superscripts). Not a full TeX engine: unusual packages and macros are skipped.]]),
    app = {
        icon = "appbar.textsize",
        order = 27,
    },
}

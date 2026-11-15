local _ = require("gettext")
return {
    fullname = _("Preview"),
    description = _([[Adds "Preview" to a file's long-press menu: a picture for images and book covers, the first lines for text files. Pictures are made only when you ask, and kept in one small shared cache (100 MB by default).]]),
}

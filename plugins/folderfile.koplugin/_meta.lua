local _ = require("gettext")
return {
    name = "kosFolderFile",
    fullname = _("Folder per file"),
    description = _([[Adds "Wrap in its own folder" to the file menu: the file moves into a folder with its name, with a plain text note beside it that holds the file's entropy in LaTeX. "Unwrap" puts it back and keeps the note.]]),
}

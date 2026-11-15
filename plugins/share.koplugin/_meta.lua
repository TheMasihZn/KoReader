local _ = require("gettext")
return {
    fullname = _("Share"),
    description = _([[Send files to your laptop's shared folder and fetch files from it, over Wi-Fi. Uses the same laptop address and PIN as the Gemma app. Also adds "Send to laptop" to a file's long-press menu.]]),
    app = {
        icon = "appbar.filebrowser",
        order = 7,
    },
}

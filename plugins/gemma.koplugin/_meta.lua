local _ = require("gettext")
return {
    name = "gemma",
    fullname = _("Gemma"),
    description = _([[Chat with the Gemma running on your laptop (Ollama). The same conversation on the laptop and the phone. Replies can be read aloud, repeated and replayed from the cache, through Bluetooth earbuds when connected.]]),
    app = {
        icon = "appbar.typeset",
        order = 4,
    },
}

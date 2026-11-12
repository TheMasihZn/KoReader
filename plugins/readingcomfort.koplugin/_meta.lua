local _ = require("gettext")
return {
    fullname = _("Reading comfort"),
    description = _([[Fonts and settings that many people with dyslexia or ADHD find easier to read: OpenDyslexic, Atkinson Hyperlegible, Lexend and Andika, for books and/or menus, plus a comfortable-spacing preset (more line and word space, a little letter spacing, left-aligned text).]]),
    app = {
        icon = "appbar.textsize",
        order = 28,
    },
}

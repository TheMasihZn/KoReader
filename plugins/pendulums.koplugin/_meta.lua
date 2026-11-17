local _ = require("gettext")
return {
    fullname = _("Pendulums"),
    description = _([[Double, triple and N pendulums swinging together, drawn as LaTeX art with the equations of each frame below. Change the number, lengths, masses, gravity and start angles under Parameters.]]),
    app = {
        icon = "appbar.typeset",
        order = 30,
    },
}

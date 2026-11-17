local _ = require("gettext")
return {
    name = "kosEntropy",
    fullname = _("Entropy"),
    description = _([[Type the weights of events, positions and frames. The formula appears in LaTeX with your numbers put in, with the lowest and highest possible value. Labelled Shannon entropy until Framal Entropy has a definition.]]),
    app = { icon = "appbar.pageview", order = 9 },
}

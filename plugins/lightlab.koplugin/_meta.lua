local _ = require("gettext")
return {
    fullname = _("Light lab"),
    description = _([[Young's experiment: photons arrive one frame at a time through one slit or two, and the pattern builds up on the screen. Each frame shows its own formulas. Change wavelength, slit width, spacing, distance and photons per frame under Parameters.]]),
    app = {
        icon = "appbar.search",
        order = 31,
    },
}

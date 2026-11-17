local _ = require("gettext")
return {
    name = "viewer3d",
    fullname = _("3D viewer"),
    description = _([[Open a 3D model (STL) or a design script (Lua), turn it, and read what a print needs to know: size, volume, surface, weight in PLA, PETG, ABS or resin, whether the shape is closed, and how much overhangs. Design scripts build shapes from boxes and cylinders; Export STL saves the result for a slicer.]]),
    app = {
        icon = "appbar.typeset",
        order = 36,
    },
}

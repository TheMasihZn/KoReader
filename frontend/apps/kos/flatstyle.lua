--[[--
Flat, Material-style look for KOReader OS.

* Depth comes from tone, not from heavy lines: the window in front is the
  lightest, windows behind it are slightly darker.
* Outlines (around dialogs, windows) are soft grey instead of black.

On by default; switch off in Home screen → "Flat design". Turn it off on
black-and-white e-ink screens, where grey outlines are hard to see.
]]

local Blitbuffer = require("ffi/blitbuffer")

local Flat = {
    surface = Blitbuffer.COLOR_WHITE,          -- window in front
    surface_back = Blitbuffer.Color8(0xE6),    -- windows behind it
    line_front = Blitbuffer.Color8(0x80),      -- outline of the front window
    line_back = Blitbuffer.Color8(0xCC),       -- outline of windows behind
    line_dialog = Blitbuffer.Color8(0xA6),     -- outline of dialogs and popups
}

function Flat.enabled()
    return G_reader_settings == nil or G_reader_settings:nilOrTrue("kos_flat_design")
end

local installed = false
--- Softens the outline of every dialog and popup (they use FrameContainer's default colour).
function Flat.install()
    if installed or not Flat.enabled() then return end
    installed = true
    local FrameContainer = require("ui/widget/container/framecontainer")
    FrameContainer.color = Flat.line_dialog
end

return Flat

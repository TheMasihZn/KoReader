--[[--
Flat, Material-style look for KOReader OS: calm "paper" tones, soft lines,
nothing that shouts. Meant for e-paper-like reading and developer tools.

* Depth comes from tone, not from heavy lines: the window in front is the
  lightest, windows behind it are slightly darker.
* Outlines (around dialogs, windows) are soft grey instead of black.
* Title bars end in a fine light line, lists are separated by faint lines,
  dialog corners are a little rounder.

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
    line_title = Blitbuffer.Color8(0xB8),      -- line under a title bar
    line_list = Blitbuffer.Color8(0xD6),       -- lines between list entries
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

    -- Every title bar, menu list and dialog follows the same quiet look.
    -- Each step is separate: a missing field in one version must not stop the rest.
    pcall(function()
        require("ui/widget/titlebar").bottom_line_color = Flat.line_title
    end)
    pcall(function()
        require("ui/widget/menu").line_color = Flat.line_list
    end)
    pcall(function()
        local Size = require("ui/size")
        local Screen = require("device").screen
        Size.radius.window = Screen:scaleBySize(10)
    end)
end

return Flat

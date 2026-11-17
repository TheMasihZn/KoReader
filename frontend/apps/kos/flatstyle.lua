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

--- Look settings (Home screen > Menu look). Applied at start, so a restart shows a change.
-- kos_flat_lines: 1 = faint, 2 = soft (default), 3 = clear     (outlines and rules)
-- kos_flat_radius: 0 = square, 1 = soft (default), 2 = round   (dialog corners)
Flat.LINE_LEVELS = {
    [1] = { dialog = 0xC8, title = 0xD6, list = 0xE4, front = 0xA0, back = 0xDD },
    [2] = { dialog = 0xA6, title = 0xB8, list = 0xD6, front = 0x80, back = 0xCC },
    [3] = { dialog = 0x70, title = 0x90, list = 0xB0, front = 0x50, back = 0xA8 },
}
Flat.RADIUS_DP = { [0] = 0, [1] = 10, [2] = 18 }

function Flat.lines() return (G_reader_settings and G_reader_settings:readSetting("kos_flat_lines")) or 2 end
function Flat.radius() return (G_reader_settings and G_reader_settings:readSetting("kos_flat_radius")) or 1 end

--- Fills the colour fields above from the chosen line strength.
function Flat.applyLevel()
    local l = Flat.LINE_LEVELS[Flat.lines()] or Flat.LINE_LEVELS[2]
    Flat.line_dialog = Blitbuffer.Color8(l.dialog)
    Flat.line_title = Blitbuffer.Color8(l.title)
    Flat.line_list = Blitbuffer.Color8(l.list)
    Flat.line_front = Blitbuffer.Color8(l.front)
    Flat.line_back = Blitbuffer.Color8(l.back)
end

local installed = false
--- Softens the outline of every dialog and popup (they use FrameContainer's default colour).
function Flat.install()
    if installed or not Flat.enabled() then return end
    installed = true
    Flat.applyLevel()
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
    pcall(function() -- the top menu's rule between tabs and list
        require("ui/widget/touchmenu").split_color = Flat.line_title
    end)
    pcall(function()
        local Size = require("ui/size")
        local Screen = require("device").screen
        Size.radius.window = Screen:scaleBySize(Flat.RADIUS_DP[Flat.radius()] or 10)
    end)
end

return Flat

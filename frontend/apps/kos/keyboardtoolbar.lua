--[[--
The row of quick buttons that sits on top of the keyboard, Samsung-keyboard
style: Paste, then the audio buttons (Play, Repeat, Recent), then whatever the
current app adds.

Today it goes into an InputDialog's button rows (those sit right above
KOReader's keyboard). When KOReader OS gets its own keyboard, the keyboard
shows this same row, so apps don't change.

    local KeyboardToolbar = require("apps/kos/keyboardtoolbar")
    -- an app's own buttons, shown while that app's input is open:
    local row = KeyboardToolbar.row{
        input = dialog,                         -- where Paste goes
        audio = { play = function() … end },    -- what "Play" plays in this app
        extra = { { text = "…", callback = … } },
    }

Buttons any app should have everywhere can be added once:

    KeyboardToolbar.register{ id = "jot", text = "✎", callback = function(ctx) … end }
]]

local Device = require("device")
local _ = require("gettext")

local KeyboardToolbar = {
    global = {},  -- id -> button spec, shown in every toolbar
    order = {},
}

function KeyboardToolbar.register(spec)
    if not KeyboardToolbar.global[spec.id] then
        table.insert(KeyboardToolbar.order, spec.id)
    end
    KeyboardToolbar.global[spec.id] = spec
end

function KeyboardToolbar.unregister(id)
    KeyboardToolbar.global[id] = nil
    for i, v in ipairs(KeyboardToolbar.order) do
        if v == id then table.remove(KeyboardToolbar.order, i) break end
    end
end

local function clipboardText()
    local input = Device.input
    if input and input.getClipboardText then
        local ok, text = pcall(input.getClipboardText)
        if ok then return text end
    end
end

--- Returns one button row (a list of button specs) for a ButtonTable/InputDialog.
-- ctx.input: an InputDialog (or anything with addTextToInput)
-- ctx.audio: { play = fn, label = "▶" } plays this app's current clip; Repeat/Recent come from AudioPipeline
-- ctx.extra: more buttons for this app
function KeyboardToolbar.row(ctx)
    ctx = ctx or {}
    local Audio = require("apps/kos/audiopipeline")
    local row = {}
    table.insert(row, {
        text = _("Paste"),
        callback = function()
            local text = clipboardText()
            if text and text ~= "" and ctx.input and ctx.input.addTextToInput then
                ctx.input:addTextToInput(text)
            end
        end,
    })
    if ctx.audio ~= false then
        if ctx.audio and ctx.audio.play then
            table.insert(row, { text = ctx.audio.label or "▶", callback = ctx.audio.play })
        end
        table.insert(row, { text = "⟲", callback = function() Audio.repeatLast() end,
            hold_callback = function() Audio.showRecent() end })
    end
    for _, id in ipairs(KeyboardToolbar.order) do
        local spec = KeyboardToolbar.global[id]
        table.insert(row, { text = spec.text, callback = function() spec.callback(ctx) end })
    end
    for _, b in ipairs(ctx.extra or {}) do
        table.insert(row, b)
    end
    return row
end

return KeyboardToolbar

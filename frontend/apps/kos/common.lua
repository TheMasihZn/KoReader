--[[--
Common library for KOReader OS apps (the Lua layer every app can use).

Rule for this file: nothing is added without the owner's say-so. Ask first.

What is in it now (asked for):

* Needs and "under development" notices. An app can say what it needs, and the OS tells the
  user when it is missing instead of failing:

    app = {
        title = _("Gemma"),
        needs = {
            { name = _("A laptop running the Gemma bridge"), ok = function() return bridgeIsSet() end },
        },
        status = "development",   -- optional: the whole app is still being built
    }

  `ok` returns true when the thing is there. A need without `ok` counts as missing.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local Common = {}

--- Returns the list of needs that are not met (empty = all fine).
function Common.unmet(needs)
    local missing = {}
    for _i, need in ipairs(needs or {}) do
        local ok = false
        if type(need.ok) == "function" then
            local good, res = pcall(need.ok)
            ok = good and res and true or false
        end
        if not ok then missing[#missing + 1] = need end
    end
    return missing
end

--- The words of the notice, without any UI (so they can be tested).
function Common.noticeText(title, missing, in_development)
    local lines = {}
    if in_development then
        lines[#lines + 1] = T(_("%1 is under development."), title)
    end
    if #missing > 0 then
        lines[#lines + 1] = T(_("%1 needs something that is not connected yet:"), title)
        for _i, need in ipairs(missing) do lines[#lines + 1] = "• " .. tostring(need.name) end
    end
    return table.concat(lines, "\n")
end

--- Shows the notice. `open_anyway` (optional) starts the app regardless.
function Common.notice(title, missing, in_development, open_anyway)
    local dialog
    local buttons = {{ { text = _("OK"), callback = function() UIManager:close(dialog) end } }}
    if open_anyway then
        table.insert(buttons[1], 1, { text = _("Open anyway"), callback = function()
            UIManager:close(dialog)
            open_anyway()
        end })
    end
    dialog = ButtonDialog:new{ title = Common.noticeText(title, missing, in_development), buttons = buttons }
    UIManager:show(dialog)
end

return Common

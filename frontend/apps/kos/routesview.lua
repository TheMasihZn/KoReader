--[[--
Shows the REST routes (built-in and added) on screen, beside the IDE and the embedded model.
A route that waits for approval gets Approve and Remove buttons: approval can only happen here, on the device.
]]
local Router = require("apps/kos/restrouter")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local View = {}

function View.show()
    Router.load()
    local dlg
    local rows = {}
    for _i, r in ipairs(Router.list()) do
        local label = string.format("%-6s %s%s", r.method, r.path, r.approved and "" or "  (waiting)")
        if r.kind == "custom" then
            rows[#rows + 1] = {{ text = label, callback = function()
                UIManager:close(dlg)
                local d2
                local buttons = {{ { text = _("Remove"), callback = function()
                    UIManager:close(d2); Router.dispatch{ method = "DELETE", path = "/routes/" .. r.id, client = "local" }; View.show()
                end } }}
                if not r.approved then
                    table.insert(buttons[1], 1, { text = _("Approve"), callback = function()
                        UIManager:close(d2)
                        Router._builtin("b10", { id = r.id }, { local_ui = true }); View.show()
                    end })
                end
                d2 = ButtonDialog:new{ title = r.method .. " " .. r.path .. "\n" .. (r.about or ""), buttons = buttons }
                UIManager:show(d2)
            end }}
        else
            rows[#rows + 1] = {{ text = label .. "  — " .. (r.about or ""), enabled = false }}
        end
    end
    dlg = ButtonDialog:new{ title = _("REST routes"), buttons = rows }
    UIManager:show(dlg)
end

return View

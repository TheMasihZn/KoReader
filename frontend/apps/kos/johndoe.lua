--[[--
John Doe: the unnamed starter app. A new project starts with a generated placeholder name and the default look;
you name it later, once you know what it is.

    JohnDoe.newName(seed)                 -> "johnDoeAmberFjord"      (camelCase, no hyphens)
    JohnDoe.files(name)                   -> { ["_meta.lua"] = text, ["main.lua"] = text }
    JohnDoe.create(pluginsDir, name, fs)  -> ok, folder or error     (refuses to overwrite)
    JohnDoe.rename(pluginsDir, old, new, fs)

The template uses the theme layer (apps/kos/theme.lua): the default theme unless the app sets its own.
]]

local J = {}

local adj = { "amber", "birch", "cedar", "delta", "ember", "fjord", "glade", "harbor", "iris", "juniper", "kelp", "lumen" }
local noun = { "Anchor", "Beacon", "Cobalt", "Dune", "Echo", "Fjord", "Grove", "Haze", "Isle", "Jade", "Kite", "Lark" }

local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end

function J.newName(seed)
    seed = seed or os.time()
    local a = adj[(seed % #adj) + 1]
    local n = noun[((seed // #adj) % #noun) + 1]
    return "johnDoe" .. cap(a) .. n
end

local META = [[
local _ = require("gettext")
return {
    name = "__NAME__",
    fullname = _("__NAME__"),
    description = _([=[Unnamed starter app. Rename it when you know what it is.]=]),
    app = { icon = "appbar.tools", order = 50 },
}
]]

local MAIN = [[
local AppWindow = require("apps/kos/appwindow")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Theme = require("apps/kos/theme")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Plugin = WidgetContainer:extend{ name = "__NAME__", is_doc_only = false }

function Plugin:launchApp()
    local function build(win, width, height)
        local theme = Theme.forApp("__NAME__")
        return TextBoxWidget:new{
            text = _("Nothing here yet. Edit main.lua in Studio."),
            face = theme.face, width = width,
        }
    end
    AppWindow:open{ title = _("__NAME__"), build = build }
end

return Plugin
]]

function J.files(name)
    return { ["_meta.lua"] = (META:gsub("__NAME__", name)), ["main.lua"] = (MAIN:gsub("__NAME__", name)) }
end

local function valid(name) return type(name) == "string" and name:match("^[%a][%w]*$") ~= nil end

function J.create(dir, name, fs)
    if not valid(name) then return false, "names are letters and digits, camelCase, no hyphens" end
    local folder = dir .. "/" .. name .. ".koplugin"
    if fs.exists(folder) then return false, "already exists: " .. folder end
    if not fs.mkdir(folder) then return false, "could not make " .. folder end
    for file, text in pairs(J.files(name)) do
        if not fs.write(folder .. "/" .. file, text) then return false, "could not write " .. file end
    end
    return true, folder
end

function J.rename(dir, old, new, fs)
    if not valid(new) then return false, "names are letters and digits, camelCase, no hyphens" end
    local from, to = dir .. "/" .. old .. ".koplugin", dir .. "/" .. new .. ".koplugin"
    if fs.exists(to) then return false, "already exists: " .. to end
    if not fs.rename(from, to) then return false, "could not rename" end
    for _, file in ipairs({ "_meta.lua", "main.lua" }) do
        local text = fs.read(to .. "/" .. file)
        if text then fs.write(to .. "/" .. file, (text:gsub(old, new))) end
    end
    return true, to
end

return J

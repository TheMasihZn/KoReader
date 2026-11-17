--[[--
Snapshots: write and read `<topic>.snapshot.md` files (apps/kos/snapshot.lua) in <home>/kosSnapshots.
Lists in the form are separated by semicolons. Formulas: write them as LaTeX, one per line of the
"Formulas" field separated by semicolons; add a note after " | ".
]]
local AppWindow = require("apps/kos/appwindow")
local ButtonTable = require("ui/widget/buttontable")
local Home = require("apps/kos/home")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Snapshot = require("apps/kos/snapshot")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local Snapshots = WidgetContainer:extend{ name = "snapshot", is_doc_only = false }

local function folder()
    local d = Home.get() .. "/kosSnapshots"
    if lfs.attributes(d, "mode") ~= "directory" then lfs.mkdir(d) end
    return d
end

local function split(text)
    local out = {}
    for part in (text or ""):gmatch("[^;]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

local function files()
    local names = {}
    for f in lfs.dir(folder()) do
        if f:match("%.snapshot%.md$") then names[#names + 1] = f end
    end
    table.sort(names, function(a, b) return a > b end)
    return names
end

function Snapshots:new(win)
    local d
    d = MultiInputDialog:new{
        title = _("New snapshot"),
        fields = {
            { description = _("Title"), text = "" },
            { description = _("Decisions made (separate with ;)"), text = "" },
            { description = _("Open questions (separate with ;)"), text = "" },
            { description = _("Next step"), text = "" },
            { description = _("Formulas in LaTeX (separate with ;, note after |)"), text = "" },
            { description = _("Notes"), text = "" },
        },
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(d) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                local formulas = {}
                for _i, item in ipairs(split(f[5])) do
                    local tex, note = item:match("^(.-)%s*|%s*(.*)$")
                    formulas[#formulas + 1] = { tex = tex or item, note = note }
                end
                local snap = Snapshot.new{ title = f[1] ~= "" and f[1] or _("Untitled"), decisions = split(f[2]),
                    open = split(f[3]), next_step = f[4], formulas = formulas, notes = f[6] }
                local path, err = Snapshot.save(snap, folder())
                UIManager:show(InfoMessage:new{ text = path and (_("Saved ") .. path) or tostring(err), timeout = 4 })
                win:refresh()
            end },
        }},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function Snapshots:read(name)
    local f = io.open(folder() .. "/" .. name, "r")
    if not f then return end
    local text = f:read("*a")
    f:close()
    UIManager:show(TextViewer:new{ title = name, text = text })
end

function Snapshots:launchApp()
    local face = Font:getFace("infont", 15)
    local function build(win, width, height)
        local group = VerticalGroup:new{ align = "left" }
        local names = files()
        table.insert(group, TextBoxWidget:new{
            text = #names == 0 and _("No snapshots yet. Tap New to write one.") or _("Tap a snapshot to read it."),
            face = face, width = width,
        })
        local rows = {{ { text = _("New…"), callback = function() self:new(win) end } }}
        for i = 1, math.min(#names, 10) do
            local n = names[i]
            table.insert(rows, {{ text = n, callback = function() self:read(n) end }})
        end
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = win })
        return group
    end
    AppWindow:open{ title = _("Snapshots"), build = build }
end

return Snapshots

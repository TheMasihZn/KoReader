--[[--
File versions: track a file, save a new version when it changed, read the timeline, go back.
The work is done by apps/kos/versions.lua (also usable by any other app: it only asks who and a signature).
The tracked list is the setting kos_tracked_versions: { { vdir =, name =, source = }, ... }.
]]
local AppWindow = require("apps/kos/appwindow")
local BridgeId = require("apps/kos/bridgeid")
local ButtonTable = require("ui/widget/buttontable")
local Home = require("apps/kos/home")
local InfoMessage = require("ui/widget/infomessage")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Versions = require("apps/kos/versions")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local App = WidgetContainer:extend{ name = "versions", is_doc_only = false }

local WHO = "File versions app"

local function tracked() return G_reader_settings:readSetting("kos_tracked_versions") or {} end
local function save(list) G_reader_settings:saveSetting("kos_tracked_versions", list) end
local function signature() return "user:" .. BridgeId.get() end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function App:track(win)
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new{
        title = _("Choose the file to keep versions of"),
        path = Home.get(),
        select_directory = false,
        onConfirm = function(path)
            local dir, name = path:match("^(.*)/([^/]+)$")
            local data = readFile(path)
            if not data then
                UIManager:show(InfoMessage:new{ text = _("Could not read that file."), icon = "notice-warning" })
                return
            end
            local vdir, err = Versions.track(dir, name, data, WHO, signature(), _("first version"))
            if not vdir then
                UIManager:show(InfoMessage:new{ text = tostring(err), icon = "notice-warning" })
                return
            end
            local list = tracked()
            list[#list + 1] = { vdir = vdir, name = name, source = path }
            save(list)
            UIManager:show(InfoMessage:new{ text = _("Tracking. Versions are in ") .. vdir, timeout = 4 })
            win:refresh()
        end,
    })
end

function App:timelineText(item)
    local lines = {}
    local tl = Versions.timeline(item.vdir)
    for i = #tl, 1, -1 do
        local e = tl[i]
        local back = #tl - e.n
        lines[#lines + 1] = string.format("%s  %s%s", Versions.dottedName(item.name, back), e.time, "")
        lines[#lines + 1] = string.format("   %s · %s%s", e.process, e.note ~= "" and e.note or "-",
            e.n > 1 and string.format(" · %d bytes changed", e.changed_bytes) or "")
    end
    return table.concat(lines, "\n")
end

function App:openItem(item, win)
    local dlg
    local function again() UIManager:close(dlg); win:refresh() end
    dlg = TextViewer:new{
        title = item.name,
        text = self:timelineText(item),
        buttons_table = {{
            { text = _("Save a new version"), callback = function()
                local data = readFile(item.source)
                if not data then UIManager:show(InfoMessage:new{ text = _("The original file is gone."), icon = "notice-warning" }) return end
                local n, err = Versions.change(item.vdir, item.name, data, WHO, signature(), _("saved from the file"))
                UIManager:show(InfoMessage:new{ text = n and (_("Version ") .. n) or tostring(err), timeout = 3 })
                again()
            end },
            { text = _("Go back one"), callback = function()
                local n, err = Versions.restore(item.vdir, item.name, 1, WHO, signature())
                if n then
                    local data = Versions.get(item.vdir, item.name, 0)
                    local f = io.open(item.source, "wb")
                    if f then f:write(data) f:close() end
                end
                UIManager:show(InfoMessage:new{ text = n and (_("Went back. Now version ") .. n) or tostring(err), timeout = 3 })
                again()
            end },
            { text = _("Make dotted copy"), callback = function()
                local n = #Versions.timeline(item.vdir) - 1
                local made = 0
                for k = 1, math.min(n, 5) do
                    if Versions.materialize(item.vdir, item.name, k) then made = made + 1 end
                end
                UIManager:show(InfoMessage:new{ text = string.format(_("Made %d dotted files in %s"), made, item.vdir), timeout = 4 })
            end },
        }},
    }
    UIManager:show(dlg)
end

function App:launchApp()
    local face = Font:getFace("infont", 15)
    local function build(win, width)
        local group = VerticalGroup:new{ align = "left" }
        local list = tracked()
        table.insert(group, TextBoxWidget:new{
            text = #list == 0 and _("No file is tracked yet. Tap Track a file.") or _("Tap a file to see its timeline."),
            face = face, width = width,
        })
        local rows = {{ { text = _("Track a file…"), callback = function() self:track(win) end } }}
        for _i, item in ipairs(list) do
            rows[#rows + 1] = {{ text = item.name .. "  (" .. #Versions.timeline(item.vdir) .. ")",
                callback = function() self:openItem(item, win) end }}
        end
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = win })
        return group
    end
    AppWindow:open{ title = _("File versions"), build = build }
end

return App

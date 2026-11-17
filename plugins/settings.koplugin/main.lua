--[[--
Settings by Time, Space and Energy (apps/kos/settingsmap.lua holds the list and the entropy order).
Tap a head, tap a setting: choices and toggles change here; "event" settings open the classic dialog for it.
]]
local AppWindow = require("apps/kos/appwindow")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local SettingsMap = require("apps/kos/settingsmap")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local App = WidgetContainer:extend{ name = "kosSettings", is_doc_only = false }

local function current(e)
    local v = G_reader_settings:readSetting(e.key)
    if v == nil then v = e.default end
    return v
end

local function valueLabel(e)
    if e.kind == "event" then return "›" end
    local v = current(e)
    if e.kind == "toggle" then return v ~= false and _("on") or _("off") end
    for _i, c in ipairs(e.choices or {}) do
        if c[1] == v then return c[2] end
    end
    return tostring(v)
end

function App:change(e, after)
    if e.kind == "event" then
        UIManager:broadcastEvent(Event:new(e.event))
        return
    elseif e.kind == "toggle" then
        G_reader_settings:saveSetting(e.key, not (current(e) ~= false))
        after()
        return
    end
    local dlg
    local rows = {}
    for _i, c in ipairs(e.choices) do
        rows[#rows + 1] = {{
            text = (c[1] == current(e) and "✓ " or "") .. c[2],
            callback = function()
                UIManager:close(dlg)
                G_reader_settings:saveSetting(e.key, c[1])
                after()
            end,
        }}
    end
    dlg = ButtonDialog:new{ title = e.title, buttons = rows }
    UIManager:show(dlg)
end

function App:showEntries(title, entries, win)
    local items = {}
    for _i, e in ipairs(entries) do
        items[#items + 1] = { text = e.title, mandatory = valueLabel(e), entry = e }
    end
    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = _("Nothing found."), timeout = 3 })
        return
    end
    local menu
    local function reopen() UIManager:close(menu); self:showEntries(title, entries, win) end
    menu = Menu:new{
        title = title,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_, item)
            if item.entry.note and item.entry.kind == "event" then
                UIManager:show(InfoMessage:new{ text = item.entry.note, timeout = 5 })
            end
            self:change(item.entry, reopen)
        end,
        onMenuHold = function(_, item)
            local e = item.entry
            require("apps/kos/contextmenu").show{
                title = e.title,
                items = {
                    { text = _("Change"), callback = function() self:change(e, reopen) end },
                    { text = _("Back to default"), enabled = e.kind ~= "event", callback = function()
                        if e.key then G_reader_settings:delSetting(e.key) end
                        reopen()
                    end },
                    { text = _("What is this?"), callback = function()
                        UIManager:show(InfoMessage:new{ text = (e.note or e.title) .. "\n" .. (e.key and ("(" .. e.key .. ")") or ""), timeout = 6 })
                    end },
                },
            }
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function App:search(win)
    local d
    d = InputDialog:new{
        title = _("Search settings"),
        input_hint = _("brightness, wifi, timeout…"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(d) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = d:getInputText()
                UIManager:close(d)
                local hits = SettingsMap.search(q)
                local entries = {}
                for _i, e in ipairs(hits) do entries[#entries + 1] = e end
                self:showEntries(_("Found: ") .. q, entries, win)
            end },
        }},
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

function App:classic()
    local ok = pcall(function()
        local FileManager = require("apps/filemanager/filemanager")
        local menu = FileManager.instance and FileManager.instance.menu
        if menu then menu:onShowMenu() else error("no file manager") end
    end)
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Open the classic menu from the file browser: tap the top of the screen."), timeout = 4 })
    end
end

function App:launchApp()
    local face = Font:getFace("infont", 15)
    local function build(win, width)
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, TextBoxWidget:new{ text = _("Time, Space or Energy. The first settings in each are the ones that change the most."), face = face, width = width })
        local rows = {}
        for _i, branch in ipairs(SettingsMap.tree()) do
            local entries = {}
            for _j, it in ipairs(branch.items) do entries[#entries + 1] = it.entry end
            rows[#rows + 1] = {{
                text = branch.group.title .. "  —  " .. branch.group.about,
                callback = function() self:showEntries(branch.group.title, entries, win) end,
            }}
        end
        rows[#rows + 1] = {{ text = _("Search settings…"), callback = function() self:search(win) end }}
        rows[#rows + 1] = {{ text = _("Classic settings menu"), callback = function() self:classic() end }}
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = win })
        return group
    end
    AppWindow:open{ title = _("Settings"), build = build }
end

return App

local ADB = require("apps/kos/adb")
local AppWindow = require("apps/kos/appwindow")
local ButtonTable = require("ui/widget/buttontable")
local Debug = require("apps/kos/debugsession")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Plugin = WidgetContainer:extend{ name = "kosDebugger", is_doc_only = false }

function Plugin:launchApp()
    local function show(title, text)
        UIManager:show(InfoMessage:new{ text = title .. "\n\n" .. text, width = require("device").screen:getWidth() * 0.95 })
    end
    local function build(win, width, height)
        local group = VerticalGroup:new{ align = "left" }
        local face = Font:getFace("infont", 15)
        table.insert(group, TextBoxWidget:new{ face = face, width = width,
            text = _("A session keeps what you ask it to: where the code was, the variables there, what ran most. It does not stop the screen.") })
        local rows = {
            {{ text = _("Start a session"), callback = function()
                Debug.start{ logfile = require("datastorage"):getDataDir() .. "/kosDebug.log" }
                show(_("Session"), _("Started. Log file: kosDebug.log in the koreader folder."))
            end }},
            {{ text = _("Show report"), callback = function() show(_("Report"), Debug.report()) end }},
            {{ text = _("Add breakpoint (file:line)"), callback = function()
                local d
                d = InputDialog:new{ title = _("Breakpoint"), input_hint = "wintitlebar.lua:120", buttons = {{
                    { text = _("Cancel"), callback = function() UIManager:close(d) end },
                    { text = _("Add"), is_enter_default = true, callback = function()
                        local f, l = d:getInputText():match("^(.-):(%d+)$"); UIManager:close(d)
                        if f then Debug.addBreakpoint(f, tonumber(l)) else show(_("Breakpoint"), _("Write it as file:line")) end
                    end },
                }} }
                UIManager:show(d); d:onShowKeyboard()
            end }},
            {{ text = _("ADB devices"), callback = function()
                local list = ADB.devices()
                local t = {}
                for _i, dv in ipairs(list) do t[#t + 1] = dv.serial .. "  " .. dv.state .. "  " .. dv.info end
                show(_("ADB"), #t > 0 and table.concat(t, "\n") or _("No devices, or no adb program (setting kos_adb_path)."))
            end }},
            {{ text = _("ADB connect (host:port)"), callback = function()
                local d
                d = InputDialog:new{ title = _("ADB connect"), input_hint = "192.168.1.20:5555", buttons = {{
                    { text = _("Cancel"), callback = function() UIManager:close(d) end },
                    { text = _("Connect"), is_enter_default = true, callback = function()
                        local hp = d:getInputText(); UIManager:close(d)
                        local ok, msg = ADB.connect(hp); show(ok and _("Connected") or _("Not connected"), msg)
                    end },
                }} }
                UIManager:show(d); d:onShowKeyboard()
            end }},
        }
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = win })
        return group
    end
    AppWindow:open{ title = _("Debugger"), build = build }
end

return Plugin

--[[--
Share: files between this device and the laptop's shared folder (~/KOS-Share).

Open it from Home, or long-press any file → "Send to laptop".
Downloads land in <home folder>/KOS-Share/. The laptop address and PIN are the
ones set in the Gemma app.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local U = require("shareutil")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = require("device").screen

local Share = WidgetContainer:extend{ name = "share", is_doc_only = false }

local function server()
    local s = LuaSettings:open(DataStorage:getSettingsDir() .. "/kos_gemma.lua")
    return s:readSetting("host"), s:readSetting("port") or 8765, s:readSetting("pin")
end

local function url(path)
    local host, port = server()
    return string.format("http://%s:%s%s", host, port, path)
end

--- Returns decoded JSON or (nil, error text).
local function getJSON(path)
    local host, _port, pin = server()
    if not host then return nil, _("No laptop set. Open the Gemma app and set it up first.") end
    local http, ltn12, socket = require("socket.http"), require("ltn12"), require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    socketutil:set_timeout(3, 8)
    local code = socket.skip(1, http.request{
        url = url(path), method = "GET", headers = { ["X-Bridge-Pin"] = pin or "" },
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if code == 401 then return nil, _("Wrong PIN.") end
    if code ~= 200 then return nil, T(_("The laptop did not answer (%1)."), tostring(code)) end
    local ok, data = pcall(require("json").decode, table.concat(sink))
    if not ok then return nil, _("Unreadable answer from the laptop.") end
    return data
end

function Share.download(rel, dest)
    local _h, _p, pin = server()
    local http, ltn12, socket = require("socket.http"), require("ltn12"), require("socket")
    local socketutil = require("socketutil")
    local part = dest .. ".part"
    local f = io.open(part, "wb")
    if not f then return false, _("Cannot write here.") end
    socketutil:set_timeout(5, 600)
    local code = socket.skip(1, http.request{
        url = url("/api/files/get?path=" .. U.encode(rel)), method = "GET",
        headers = { ["X-Bridge-Pin"] = pin or "" }, sink = ltn12.sink.file(f),
    })
    socketutil:reset_timeout()
    if code ~= 200 then os.remove(part) return false, T(_("Download failed (%1)."), tostring(code)) end
    os.remove(dest)
    os.rename(part, dest)
    return true
end

function Share.upload(file, rel)
    local _h, _p, pin = server()
    local size = lfs.attributes(file, "size")
    if not size then return false, _("File not found.") end
    local f = io.open(file, "rb")
    if not f then return false, _("Cannot read the file.") end
    local http, ltn12, socket = require("socket.http"), require("ltn12"), require("socket")
    local socketutil = require("socketutil")
    local sink = {}
    socketutil:set_timeout(5, 600)
    local code = socket.skip(1, http.request{
        url = url("/api/files/put?path=" .. U.encode(rel)), method = "PUT",
        headers = { ["X-Bridge-Pin"] = pin or "", ["Content-Length"] = tostring(size) },
        source = ltn12.source.file(f), sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if code ~= 200 then return false, T(_("Upload failed (%1)."), tostring(code)) end
    return true
end

local function downloadDir()
    local d = require("apps/kos/home").get() .. "/KOS-Share"
    if lfs.attributes(d, "mode") ~= "directory" then lfs.mkdir(d) end
    return d
end

local function say(text) UIManager:show(InfoMessage:new{ text = text, timeout = 4 }) end

--- Browse the laptop folder `dir` (relative to ~/KOS-Share).
function Share:browse(dir, menu)
    dir = dir or ""
    local data, err = getJSON("/api/files?path=" .. U.encode(dir))
    if not data then say(err) return end
    local items = {}
    if dir ~= "" then
        items[#items + 1] = { text = "⬆ ..", callback = function() self:browse(U.parent(dir), menu) end }
    end
    items[#items + 1] = {
        text = _("➕ Send a file from this device to this folder"),
        callback = function() self:pickAndSend(dir, menu) end,
    }
    for _i, it in ipairs(data.items or {}) do
        local rel = U.join(dir, it.name)
        if it.dir then
            items[#items + 1] = { text = "📁 " .. it.name, callback = function() self:browse(rel, menu) end }
        else
            items[#items + 1] = {
                text = it.name, mandatory = U.humanSize(it.size),
                callback = function() self:fetch(rel, it) end,
            }
        end
    end
    local title = _("Laptop: ") .. "/" .. dir
    if menu then
        menu:switchItemTable(title, items)
    else
        menu = Menu:new{
            title = title, item_table = items, is_borderless = true, is_popout = false,
            width = Screen:getWidth(), height = Screen:getHeight(),
            covers_fullscreen = true, close_callback = function() Share.menu = nil end,
        }
        Share.menu = menu
        UIManager:show(menu)
    end
end

function Share:fetch(rel, it)
    local dest = downloadDir() .. "/" .. U.safeName(rel:match("[^/]+$"))
    local function go()
        local info = InfoMessage:new{ text = T(_("Downloading %1…"), it.name) }
        UIManager:show(info)
        UIManager:nextTick(function()
            local ok, err = Share.download(rel, dest)
            UIManager:close(info)
            say(ok and T(_("Saved to %1"), dest) or err)
        end)
    end
    if lfs.attributes(dest, "mode") == "file" then
        UIManager:show(ConfirmBox:new{ text = T(_("%1 already exists here. Replace it?"), it.name), ok_text = _("Replace"), ok_callback = go })
    else
        go()
    end
end

function Share:pickAndSend(dir, menu)
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new{
        title = _("Choose a file to send"), select_directory = false, select_file = true,
        path = require("apps/kos/home").get(),
        onConfirm = function(file) self:send(file, dir, menu) end,
    })
end

function Share:send(file, dir, menu)
    local name = U.safeName(file:match("[^/]+$"))
    local info = InfoMessage:new{ text = T(_("Sending %1…"), name) }
    UIManager:show(info)
    UIManager:nextTick(function()
        local ok, err = Share.upload(file, U.join(dir or "", name))
        UIManager:close(info)
        say(ok and T(_("Sent %1 to the laptop."), name) or err)
        if ok and menu then self:browse(dir, menu) end
    end)
end

function Share:launchApp() self:browse("", nil) end
function Share:onShowShare() self:launchApp() return true end

function Share:init()
    local fm = self.ui
    if fm and fm.addFileDialogButtons then
        fm:addFileDialogButtons("kos_share_send", function(file, is_file)
            if not is_file then return end
            return {{
                text = _("Send to laptop"),
                callback = function()
                    local fc = fm.file_chooser
                    if fc and fc.file_dialog then UIManager:close(fc.file_dialog) end
                    self:send(file, "", nil)
                end,
            }}
        end)
    end
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
end

function Share:addToMainMenu(menu_items)
    menu_items.kos_share = { text = _("Share with laptop"), sorting_hint = "tools", callback = function() self:launchApp() end }
end

return Share

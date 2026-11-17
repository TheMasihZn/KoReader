local AppWindow = require("apps/kos/appwindow")
local ButtonTable = require("ui/widget/buttontable")
local Event = require("ui/event")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Router = require("apps/kos/restrouter")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Plugin = WidgetContainer:extend{ name = "kosRestBot", is_doc_only = false }
local running = { bot = false, http = nil }

local function setting(k, d) local v = G_reader_settings:readSetting(k); if v == nil then return d end return v end

local function hooks()
    return {
        sendEvent = function(name) UIManager:broadcastEvent(Event:new(name)) end,
        openApp = function(name)
            local AppRegistry = require("apps/kos/appregistry")
            for _i, a in ipairs(AppRegistry:getApps()) do
                if a.title:lower() == tostring(name):lower() or a.id == name then
                    UIManager:broadcastEvent(Event:new("KosOpenApp", a.id))
                    return true
                end
            end
            return false
        end,
        runPipeline = function(text) return text end,
        adapters = function()
            local ok, A = pcall(require, "apps/kos/adapters")
            return ok and A.names and A.names() or {}
        end,
    }
end

function Plugin:pollOnce()
    local Bot = require("apps/kos/telegrambot")
    local Pipeline = require("apps/kos/pipeline")
    local bot = Bot.new{
        token = setting("kos_telegram_token"), chats = setting("kos_telegram_chats", {}),
        router = Router, json = require("json"), transport = Pipeline.httpsGet or function(url)
            local https = require("ssl.https"); local ltn12 = require("ltn12"); local sink = {}
            local ok, code = https.request{ url = url, sink = ltn12.sink.table(sink) }
            return ok and code or nil, table.concat(sink)
        end,
        offset = setting("kos_telegram_offset", 0),
    }
    local n, err = bot:poll()
    G_reader_settings:saveSetting("kos_telegram_offset", bot.offset)
    return n, err
end

function Plugin:startBot()
    if running.bot then return end
    running.bot = true
    Router.load(); Router.setHooks(hooks())
    local function tick()
        if not running.bot then return end
        pcall(function() self:pollOnce() end)
        UIManager:scheduleIn(setting("kos_telegram_interval", 5), tick)
    end
    UIManager:scheduleIn(1, tick)
end

function Plugin:stopBot() running.bot = false end

--- HTTP on 127.0.0.1 only (setting kos_rest_port, default 8787). Needs X-Rest-Token from kos_rest_tokens.
function Plugin:startHttp()
    if running.http then return true end
    local ok, socket = pcall(require, "socket")
    if not ok then return false, "no socket library" end
    Router.load(); Router.setHooks(hooks())
    local server, err = socket.bind("127.0.0.1", setting("kos_rest_port", 8787))
    if not server then return false, err end
    server:settimeout(0)
    running.http = server
    local Http = require("apps/kos/httpadapter")
    local JSON = require("json")
    local function tick()
        if not running.http then return end
        local c = server:accept()
        if c then
            c:settimeout(1)
            local raw = c:receive(8192) or ""
            local req, bad = Http.parse(raw, setting("kos_rest_tokens", {}))
            local status, body
            if req then status, body = Router.dispatch(req) else status, body = bad, { error = "refused" } end
            c:send(Http.response(status, body, JSON)); c:close()
        end
        UIManager:scheduleIn(0.2, tick)
    end
    UIManager:scheduleIn(0.2, tick)
    return true
end

function Plugin:stopHttp() if running.http then running.http:close(); running.http = nil end end

local function ask(title, key, hint, transform)
    local d
    d = InputDialog:new{ title = title, input = tostring(G_reader_settings:readSetting(key) or ""), input_hint = hint, buttons = {{
        { text = _("Cancel"), callback = function() UIManager:close(d) end },
        { text = _("Save"), is_enter_default = true, callback = function()
            local v = d:getInputText(); UIManager:close(d)
            G_reader_settings:saveSetting(key, transform and transform(v) or v)
        end },
    }} }
    UIManager:show(d); d:onShowKeyboard()
end

function Plugin:launchApp()
    local plugin = self
    local function build(win, width, height)
        local group = VerticalGroup:new{ align = "left" }
        table.insert(group, TextBoxWidget:new{ face = Font:getFace("infont", 15), width = width,
            text = _("Messages from your Telegram bot and HTTP calls on this phone become REST calls. Nothing is open to the internet: the phone asks Telegram, and HTTP listens on this phone only.") })
        local rows = {
            {{ text = _("Bot token (from @BotFather)"), callback = function() ask(_("Bot token"), "kos_telegram_token", "123456:ABC…") end }},
            {{ text = _("Allowed chat ids (comma separated)"), callback = function()
                ask(_("Allowed chats"), "kos_telegram_chats", "123456789", function(v) local t = {}; for n in v:gmatch("%-?%d+") do t[#t + 1] = tonumber(n) end return t end)
            end }},
            {{ text = _("Start bot"), callback = function() plugin:startBot(); UIManager:show(InfoMessage:new{ text = _("Bot polling started."), timeout = 2 }) end },
             { text = _("Stop bot"), callback = function() plugin:stopBot() end }},
            {{ text = _("Start HTTP (this phone only)"), callback = function()
                local ok, err = plugin:startHttp()
                UIManager:show(InfoMessage:new{ text = ok and _("HTTP listening on 127.0.0.1.") or tostring(err), timeout = 3 })
            end }, { text = _("Stop HTTP"), callback = function() plugin:stopHttp() end }},
            {{ text = _("REST routes (approve or remove)"), callback = function() require("apps/kos/routesview").show() end }},
        }
        table.insert(group, ButtonTable:new{ buttons = rows, width = width, show_parent = win })
        return group
    end
    AppWindow:open{ title = _("REST and bot"), build = build }
end

return Plugin

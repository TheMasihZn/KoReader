--[[--
Gemma: the phone side of the Gemma bridge (tools/gemma-bridge/gemma_bridge.py
runs on the laptop, in front of Ollama).

* Same conversation as the laptop: both read and write the bridge's sessions.
* Several windows: each Gemma window shows one conversation. Open another
  window (Home → hold Gemma, or the window menu) and pick or start a
  different conversation there, or keep two windows on the same one.
* Nothing gets lost: a message is kept in an outbox (on disk) until the laptop
  confirms it; resending is safe because each message carries its own id.
* The conversation is cached on the phone, so it can be read offline.
* Audio: ▶ reads the last reply aloud (the laptop makes and caches the .wav),
  ⟲ repeats, hold ⟲ lists recent clips. Through Bluetooth when connected.
]]

local AppWindow = require("apps/kos/appwindow")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local _ = require("gettext")
local T = require("ffi/util").template

local DISCOVERY_PORT = 47801
local POLL_FAST = 1.5   -- seconds, while connected
local POLL_SLOW = 10    -- seconds, while the laptop can't be reached

-- Shared by all Gemma windows. Conversations are kept per session id, so two
-- windows on the same conversation show the same thing.
local State = {
    windows = {},   -- window -> true; each window has .gemma_sid
    convs = {},     -- sid -> { messages = {id -> msg}, rev = n, busy = bool, title = "…" }
    online = nil,   -- nil = not tried yet, true/false
    status = nil,
    info = nil,
    polling = false,
}

local store
local function settings()
    if not store then
        store = LuaSettings:open(DataStorage:getSettingsDir() .. "/kos_gemma.lua")
        -- older versions kept one conversation under "cache"
        if store:readSetting("cache") and not store:readSetting("convs") then
            store:saveSetting("convs", { main = { list = store:readSetting("cache"), rev = store:readSetting("cache_rev") or 0, title = "Main" } })
            store:delSetting("cache"); store:delSetting("cache_rev")
        end
        -- the phone's copy of each conversation, for offline reading
        for sid, c in pairs(store:readSetting("convs") or {}) do
            local conv = { messages = {}, rev = c.rev or 0, title = c.title }
            for _, m in ipairs(c.list or {}) do conv.messages[m.id] = m end
            State.convs[sid] = conv
        end
    end
    return store
end

local function conv(sid)
    settings()
    if not State.convs[sid] then
        State.convs[sid] = { messages = {}, rev = 0 }
    end
    return State.convs[sid]
end

local function saveCache(sid)
    local c = conv(sid)
    local list = {}
    for _, m in pairs(c.messages) do table.insert(list, m) end
    table.sort(list, function(a, b) return a.id < b.id end)
    while #list > 300 do table.remove(list, 1) end
    local all = settings():readSetting("convs") or {}
    all[sid] = { list = list, rev = c.rev, title = c.title }
    settings():saveSetting("convs", all)
    settings():flush()
end

local function server()
    local s = settings()
    return s:readSetting("host"), s:readSetting("port") or 8765, s:readSetting("pin")
end

local function newClientId()
    return string.format("phone-%d-%06d", os.time(), math.random(0, 999999))
end

local function convTitle(sid)
    local c = State.convs[sid]
    return (c and c.title) or (sid == "main" and _("Main") or sid)
end

---------------------------------------------------------------------------
-- Network
---------------------------------------------------------------------------

local function request(method, path, body)
    local host, port, pin = server()
    if not host then return nil, "no laptop set" end
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local JSON = require("json")
    local sink = {}
    local payload = body and JSON.encode(body) or nil
    socketutil:set_timeout(2, 5) -- short: the UI waits for this
    local code = socket.skip(1, http.request{
        url = string.format("http://%s:%s%s", host, port, path),
        method = method,
        headers = {
            ["X-Bridge-Pin"] = pin or "",
            ["Content-Type"] = payload and "application/json" or nil,
            ["Content-Length"] = payload and tostring(#payload) or nil,
        },
        source = payload and ltn12.source.string(payload) or nil,
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        local err = tostring(code)
        if code == 401 then err = _("wrong PIN") end
        return nil, err
    end
    local ok, data = pcall(JSON.decode, table.concat(sink))
    if not ok then return nil, "bad reply" end
    return data
end

--- Finds the laptop on the Wi-Fi (the bridge answers a broadcast).
local function discover()
    local socket = require("socket")
    local udp = socket.udp4 and socket.udp4() or socket.udp()
    if not udp then return end
    udp:setoption("broadcast", true)
    udp:settimeout(2)
    udp:sendto("GEMMA-BRIDGE?", "255.255.255.255", DISCOVERY_PORT)
    local data, host = udp:receivefrom()
    udp:close()
    if data and host then
        local ok, info = pcall(require("json").decode, data)
        if ok and type(info) == "table" then
            return host, info.port, info.name
        end
    end
end

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------

local function refreshWindows(sid)
    for w in pairs(State.windows) do
        if not sid or w.gemma_sid == sid then
            if w.subtitle ~= convTitle(w.gemma_sid) then
                w:setTitle(_("Gemma"), convTitle(w.gemma_sid))
            end
            w:refresh()
        end
    end
end

local function outbox()
    return settings():readSetting("outbox") or {}
end

--- Sends what is waiting in the outbox (every conversation). Each item keeps
-- its client_id, so a resend after a lost answer never doubles a message.
local function flushOutbox()
    local box = outbox()
    local changed = false
    while box[1] do
        local item = box[1]
        local sid = item.sid or "main"
        local res, err = request("POST", "/api/sessions/" .. sid .. "/messages",
            { text = item.text, from = "phone", client_id = item.client_id })
        if not res then
            if err == "404" then
                table.remove(box, 1) -- that conversation is gone on the laptop
                changed = true
            else
                State.online, State.status = false, err
                break
            end
        else
            table.remove(box, 1)
            changed = true
            if res.message then conv(sid).messages[res.message.id] = res.message end
        end
    end
    if changed then
        settings():saveSetting("outbox", box)
        settings():flush()
    end
end

local function sync(sid)
    local c = conv(sid)
    local res, err = request("GET", string.format("/api/sessions/%s/messages?since=%d", sid, c.rev))
    if not res then
        if State.online ~= false or State.status ~= err then
            State.online, State.status = false, err
            refreshWindows()
        end
        return false
    end
    local was_online = State.online
    State.online, State.status = true, nil
    if (res.rev or 0) < c.rev then
        -- the laptop's history was reset: start over
        c.messages, c.rev = {}, 0
        return sync(sid)
    end
    local news = #(res.messages or {}) > 0
    for _, m in ipairs(res.messages or {}) do
        c.messages[m.id] = m
    end
    c.rev = res.rev or c.rev
    if res.title and res.title ~= c.title then c.title = res.title; news = true end
    if news then saveCache(sid) end
    if news or was_online ~= true or c.busy ~= res.busy then
        c.busy = res.busy
        refreshWindows(was_online ~= true and nil or sid)
    end
    return true
end

local function syncAll()
    flushOutbox()
    local done = {}
    for w in pairs(State.windows) do
        local sid = w.gemma_sid
        if sid and not done[sid] then
            done[sid] = true
            if not sync(sid) then break end
        end
    end
end

local function poll()
    if not next(State.windows) then
        State.polling = false
        return
    end
    syncAll()
    UIManager:scheduleIn(State.online and POLL_FAST or POLL_SLOW, poll)
end

local function startPolling()
    if State.polling then return end
    State.polling = true
    UIManager:nextTick(poll)
end

---------------------------------------------------------------------------
-- Audio
---------------------------------------------------------------------------

local function sortedMessages(sid)
    local list = {}
    for _, m in pairs(conv(sid).messages) do table.insert(list, m) end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function clipFor(sid, m)
    local host, port, pin = server()
    if not host then return end
    return {
        url = string.format("http://%s:%s/api/audio/%s/%d.wav?pin=%s", host, port, sid, m.id, pin or ""),
        title = T(_("Gemma: %1"), (m.text or ""):gsub("%s+", " "):sub(1, 60)),
        source = "gemma",
    }
end

local function playLastReply(sid)
    sid = sid or State.last_sid or "main"
    local list = sortedMessages(sid)
    for i = #list, 1, -1 do
        local m = list[i]
        if m.role == "assistant" and m.status == "done" then
            local clip = clipFor(sid, m)
            if clip then require("apps/kos/audiopipeline").play(clip) end
            return
        end
    end
    UIManager:show(InfoMessage:new{ text = _("No finished reply yet."), timeout = 2 })
end

---------------------------------------------------------------------------
-- The app
---------------------------------------------------------------------------

local Gemma = WidgetContainer:extend{
    name = "gemma",
}

function Gemma:init()
    self:onDispatcherRegisterActions()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function Gemma:onDispatcherRegisterActions()
    require("dispatcher"):registerAction("gemma_open", {
        category = "none", event = "ShowGemma", title = _("Gemma"), general = true,
    })
    require("dispatcher"):registerAction("gemma_play_last", {
        category = "none", event = "GemmaPlayLast", title = _("Gemma: read the last reply aloud"), general = true,
    })
end

function Gemma:onShowGemma() self:launchApp() return true end
function Gemma:onGemmaPlayLast() playLastReply() return true end

function Gemma:addToMainMenu(menu_items)
    menu_items.gemma = {
        text = _("Gemma"),
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Open"), callback = function() self:launchApp() end },
            { text = _("Connect to laptop…"), keep_menu_open = true, callback = function() self:setup() end },
        },
    }
end

local function conversationText(sid)
    local parts = {}
    for _, m in ipairs(sortedMessages(sid)) do
        local who
        if m.role == "assistant" then
            who = "◆ Gemma"
        else
            who = "▸ " .. (m.from == "phone" and _("You (phone)") or m.from == "laptop" and _("You (laptop)") or _("You"))
        end
        local stamp = m.time and os.date(" · %H:%M", math.floor(m.time)) or ""
        local text = m.text or ""
        if m.status == "thinking" then text = (text ~= "" and text .. " …" or _("thinking…")) end
        table.insert(parts, who .. stamp .. "\n" .. text)
    end
    for _, item in ipairs(outbox()) do
        if (item.sid or "main") == sid then
            table.insert(parts, "▸ " .. _("You (phone)") .. " · " .. _("waiting to send") .. "\n" .. item.text)
        end
    end
    if #parts == 0 then
        return _("No messages yet. Tap Write to start.")
    end
    return table.concat(parts, "\n\n")
end

local function statusLine(sid)
    local host = server()
    if not host then return _("Not connected. Tap ⋯ → Connect to laptop.") end
    local waiting = 0
    for _, item in ipairs(outbox()) do
        if (item.sid or "main") == sid then waiting = waiting + 1 end
    end
    local line
    if State.online == nil then
        line = _("Connecting…")
    elseif State.online then
        line = T(_("Connected to %1"), (State.info and State.info.name) or host)
        if State.info and State.info.model then line = line .. " · " .. State.info.model end
        if conv(sid).busy then line = line .. " · " .. _("Gemma is writing") end
    else
        line = T(_("Laptop not reachable (%1). Showing the saved conversation."), State.status or "?")
    end
    if waiting > 0 then line = line .. " · " .. T(_("%1 waiting to send"), waiting) end
    return line
end

function Gemma:build(window, width, height)
    local sid = window.gemma_sid or "main"
    local margin = Size.padding.default
    local inner = width - 2 * margin
    local status = TextWidget:new{
        text = statusLine(sid),
        face = Font:getFace("smallinfofont"),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = inner,
    }
    local buttons = ButtonTable:new{
        width = inner,
        show_parent = window,
        buttons = {{
            { text = _("Write"), font_bold = true, callback = function() self:compose(window) end },
            { text = "▶", callback = function() playLastReply(sid) end },
            { text = "⟲", callback = function() require("apps/kos/audiopipeline").repeatLast() end,
              hold_callback = function() require("apps/kos/audiopipeline").showRecent() end },
            { text = _("Chats"), callback = function() self:chooseConversation(window) end },
            { text = "⋯", callback = function() self:moreMenu(window) end },
        }},
    }
    local text_h = height - 2 * margin - status:getSize().h - buttons:getSize().h - 2 * Size.padding.small
    local view = ScrollTextWidget:new{
        text = conversationText(sid),
        face = Font:getFace("cfont", 19),
        width = inner,
        height = math.max(text_h, 50),
        dialog = window,
    }
    view:scrollToBottom()
    return FrameContainer:new{
        padding = margin,
        margin = 0,
        bordersize = 0,
        width = width,
        height = height,
        VerticalGroup:new{
            align = "left",
            status,
            VerticalSpan:new{ width = Size.padding.small },
            view,
            VerticalSpan:new{ width = Size.padding.small },
            buttons,
        },
    }
end

function Gemma:compose(window, prefill)
    local sid = window.gemma_sid or "main"
    State.last_sid = sid
    local dialog
    dialog = InputDialog:new{
        title = T(_("Message Gemma · %1"), convTitle(sid)),
        input = prefill or "",
        allow_newline = true,
        input_height = 4, -- lines of text, not pixels -- unscaled_size_check: ignore
        -- the row on top of the keyboard (Paste, ⟲) gets ▶ = read Gemma's last reply
        kos_toolbar_audio = { play = function() playLastReply(sid) end },
        buttons = {
            {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Send"), is_enter_default = true, callback = function()
                    local text = dialog:getInputText()
                    UIManager:close(dialog)
                    self:send(sid, text)
                end },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Gemma:send(sid, text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "")
    if not text or text == "" then return end
    local box = outbox()
    table.insert(box, { sid = sid, text = text, client_id = newClientId() })
    settings():saveSetting("outbox", box)
    settings():flush()
    refreshWindows(sid)
    UIManager:nextTick(function()
        flushOutbox()
        sync(sid)
        refreshWindows(sid)
    end)
end

--- Shows this window another conversation.
function Gemma:switchTo(window, sid)
    window.gemma_sid = sid
    State.last_sid = sid
    settings():saveSetting("last_sid", sid)
    window:setTitle(_("Gemma"), convTitle(sid))
    window:refresh()
    UIManager:nextTick(function() sync(sid) end)
end

function Gemma:newConversation(window)
    local dialog
    dialog = InputDialog:new{
        title = _("New conversation"),
        input = "",
        input_hint = _("Name (optional)"),
        kos_toolbar = false,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Start"), is_enter_default = true, callback = function()
                local title = dialog:getInputText()
                UIManager:close(dialog)
                if title == "" then title = os.date("%d %b %H:%M") end
                local res, err = request("POST", "/api/sessions", { title = title })
                if not res then
                    UIManager:show(InfoMessage:new{ text = T(_("The laptop is needed to start a conversation: %1"), err or "?") })
                    return
                end
                conv(res.id).title = res.title
                saveCache(res.id)
                self:switchTo(window, res.id)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- All conversations (from the laptop, or the copies on the phone when offline).
function Gemma:chooseConversation(window)
    local list = request("GET", "/api/sessions")
    local entries = {}
    if list then
        for _, s in ipairs(list) do
            conv(s.id).title = s.title
            table.insert(entries, { id = s.id, title = s.title, count = s.count })
        end
    else
        for sid, c in pairs(State.convs) do
            table.insert(entries, { id = sid, title = c.title or sid })
        end
        table.sort(entries, function(a, b) return tostring(a.title) < tostring(b.title) end)
    end
    local Menu = require("ui/widget/menu")
    local items = {{ text = "+ " .. _("New conversation"), new = true }}
    for _, e in ipairs(entries) do
        local open_here = e.id == window.gemma_sid
        table.insert(items, {
            text = (open_here and "● " or "") .. tostring(e.title),
            mandatory = e.count and T(_("%1 msgs"), e.count) or nil,
            sid = e.id,
        })
    end
    local menu
    menu = Menu:new{
        title = list and _("Conversations") or _("Conversations (saved on the phone)"),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            if item.new then
                self:newConversation(window)
            else
                self:switchTo(window, item.sid)
            end
        end,
        onMenuHold = function(_, item)
            if not item.sid then return true end
            UIManager:close(menu)
            -- open that conversation in another window, beside this one
            self.next_sid = item.sid
            require("apps/kos/windows").newInstance(window)
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function Gemma:moreMenu(window)
    local dlg
    local function act(fn) return function() UIManager:close(dlg); fn() end end
    dlg = ButtonDialog:new{
        buttons = {
            {{ text = _("New conversation…"), callback = act(function() self:newConversation(window) end) }},
            {{ text = _("New Gemma window"), callback = act(function() require("apps/kos/windows").newInstance(window) end) }},
            {{ text = _("Connect to laptop…"), callback = act(function() self:setup() end) }},
            {{ text = _("Recently played audio"), callback = act(function() require("apps/kos/audiopipeline").showRecent() end) }},
            {{ text = _("Clear the copy on this phone"), callback = act(function()
                local sid = window.gemma_sid or "main"
                State.convs[sid] = { messages = {}, rev = 0, title = convTitle(sid) }
                saveCache(sid); refreshWindows(sid); UIManager:nextTick(function() sync(sid) end)
            end) }},
        },
    }
    UIManager:show(dlg)
end

function Gemma:setup()
    local host, port, pin = server()
    local function save(h, p, code)
        local s = settings()
        s:saveSetting("host", h); s:saveSetting("port", tonumber(p) or 8765); s:saveSetting("pin", code)
        s:flush()
        State.online, State.info = nil, nil
        local info, err = request("GET", "/api/info")
        if info then
            State.info, State.online = info, true
            UIManager:show(InfoMessage:new{ text = T(_("Connected to %1."), info.name or h), timeout = 3 })
            syncAll()
        else
            State.online, State.status = false, err
            UIManager:show(InfoMessage:new{ text = T(_("Could not reach the laptop: %1"), err or "?") })
        end
        refreshWindows()
    end
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Connect to laptop"),
        description = _("On the laptop run: python3 gemma_bridge.py\nIt prints the address and the PIN."),
        fields = {
            { description = _("Address"), text = host or "", hint = "192.168.1.20" },
            { description = _("Port"), text = tostring(port or 8765), input_type = "number" },
            { description = _("PIN"), text = pin or "", input_type = "number" },
        },
        buttons = {
            {
                { text = _("Find on Wi-Fi"), callback = function()
                    local h, p, name = discover()
                    if h then
                        local fields = dialog:getFields()
                        UIManager:close(dialog)
                        UIManager:show(InfoMessage:new{ text = T(_("Found %1 at %2."), name or "?", h), timeout = 2 })
                        -- keep the PIN typed so far
                        UIManager:nextTick(function()
                            local s = settings()
                            s:saveSetting("host", h); s:saveSetting("port", tonumber(p) or 8765)
                            if fields[3] ~= "" then s:saveSetting("pin", fields[3]) end
                            self:setup()
                        end)
                    else
                        UIManager:show(InfoMessage:new{ text = _("No laptop answered. Is gemma_bridge.py running, on the same Wi-Fi?") })
                    end
                end },
            },
            {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Connect"), is_enter_default = true, callback = function()
                    local f = dialog:getFields()
                    UIManager:close(dialog)
                    save(f[1], f[2], f[3])
                end },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Gemma:launchApp()
    settings()
    -- The first window opens the last conversation; "Chats" (hold) or the
    -- menu can open another one in a second window.
    local sid = self.next_sid or settings():readSetting("last_sid") or "main"
    self.next_sid = nil
    local window
    window = AppWindow:open{
        title = _("Gemma"),
        subtitle = convTitle(sid),
        max_content_dp = 720,
        build = function(w, width, height)
            w.gemma_sid = w.gemma_sid or (window and window.gemma_sid) or sid
            return self:build(w, width, height)
        end,
        on_close = function() State.windows[window] = nil end,
    }
    if window then
        window.gemma_sid = sid
        State.windows[window] = true
        window:refresh()
    end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenConnected(function()
        if not server() then
            self:setup()
            return
        end
        local info = request("GET", "/api/info")
        if info then State.info = info end
        startPolling()
    end)
end

return Gemma

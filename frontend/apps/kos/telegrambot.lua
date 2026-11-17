--[[--
Telegram bot as a front door to the REST router. The device asks Telegram for new messages (long polling from
the device outwards), so nothing on the device is open to the internet. Only chats listed in `chats` are answered;
everything else is ignored and counted.

    local bot = Bot.new{ token = "123:ABC", chats = { 42 }, router = Router, json = JSON, transport = fn }
    bot:poll()            -- one round: reads new messages, answers each, returns how many were handled

A message "GET /settings/kos_search_min_chars" or "SET /settings/kos_x 5" becomes a request from the client
"tg<chatId>", which needs scopes in the setting kos_rest_clients. A message that is not a request gets a short help line.
transport(url) -> http code, body text.
]]

local Bot = {}
Bot.__index = Bot

function Bot.new(o)
    return setmetatable({ token = o.token, chats = o.chats or {}, router = o.router, json = o.json, transport = o.transport,
        offset = o.offset or 0, ignored = 0, log = {} }, Bot)
end

local function allowed(self, id)
    for _, c in ipairs(self.chats) do if tonumber(c) == tonumber(id) then return true end end
    return false
end

local function urlEncode(s) return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)) end

function Bot:api(method, query)
    local url = "https://api.telegram.org/bot" .. self.token .. "/" .. method .. (query and ("?" .. query) or "")
    local code, body = self.transport(url)
    if code ~= 200 then return nil, "Telegram answered " .. tostring(code) end
    local ok, data = pcall(self.json.decode, body)
    if not ok or type(data) ~= "table" or not data.ok then return nil, "bad answer from Telegram" end
    return data.result
end

function Bot:say(chat, text)
    if #text > 3500 then text = text:sub(1, 3500) .. "\n…" end
    return self:api("sendMessage", "chat_id=" .. urlEncode(chat) .. "&text=" .. urlEncode(text))
end

function Bot:poll()
    if not self.token or self.token == "" then return 0, "no token" end
    local updates, err = self:api("getUpdates", "timeout=0&offset=" .. tostring(self.offset))
    if not updates then return 0, err end
    local handled = 0
    for _, u in ipairs(updates) do
        self.offset = math.max(self.offset, (u.update_id or 0) + 1)
        local m = u.message
        local chat = m and m.chat and m.chat.id
        if m and m.text and chat then
            if not allowed(self, chat) then
                self.ignored = self.ignored + 1
                self.log[#self.log + 1] = "ignored chat " .. tostring(chat)
            else
                local req, why = self.router.parseText(m.text)
                local reply
                if not req then reply = why
                else
                    req.client = "tg" .. tostring(chat)
                    local status, tbl = self.router.dispatch(req)
                    reply = self.router.render(status, tbl)
                end
                self:say(chat, reply)
                handled = handled + 1
            end
        end
    end
    return handled
end

return Bot

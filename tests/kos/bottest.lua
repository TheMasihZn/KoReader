local store = { kos_rest_clients = { tg42 = { "read", "write", "control" } } }
G_reader_settings = { readSetting = function(_, k) return store[k] end, saveSetting = function(_, k, v) store[k] = v end }
local R = dofile("frontend/apps/kos/restrouter.lua")
local Bot = dofile("frontend/apps/kos/telegrambot.lua")
local Http = dofile("frontend/apps/kos/httpadapter.lua")
-- tiny json for the test: decode from a Lua table registry, encode to a string
local sent, queue = {}, {}
local JSON = { decode = function(s) return queue[s] end, encode = function(t) local k = {} for a in pairs(t) do k[#k+1] = a end table.sort(k); local o = {} for _, a in ipairs(k) do o[#o+1] = a .. "=" .. tostring(t[a]) end return table.concat(o, ";") end }
local calls = 0
local function transport(url)
  if url:find("getUpdates") then
    calls = calls + 1
    if calls == 1 then queue.X = { ok = true, result = {
      { update_id = 10, message = { chat = { id = 42 }, text = "SET /settings/kos_search_min_chars 3" } },
      { update_id = 11, message = { chat = { id = 99 }, text = "GET /routes" } },
      { update_id = 12, message = { chat = { id = 42 }, text = "hello there" } },
      { update_id = 13, message = { chat = { id = 42 }, text = "GET /routes" } },
      { update_id = 14, message = { chat = { id = 42 } } } } }
    else queue.X = { ok = true, result = {} } end
    return 200, "X"
  end
  sent[#sent + 1] = url; queue.Y = { ok = true, result = {} }; return 200, "Y"
end
R.setHooks{}
local bot = Bot.new{ token = "1:A", chats = { 42 }, router = R, json = JSON, transport = transport }
local n = bot:poll(); assert(n == 3, n)
assert(store.kos_search_min_chars == "3")
assert(bot.ignored == 1 and bot.offset == 15)
assert(#sent == 3 and sent[1]:find("chat_id=42") and sent[2]:find("write%%20it%%20as"), sent[2])
assert(sent[3]:find("GET%%20%%2Froutes"))
assert(bot:poll() == 0 and bot.offset == 15)
assert(select(2, Bot.new{ token = "", chats = {} }:poll()) == "no token")
local b2 = Bot.new{ token = "1:A", chats = {42}, router = R, json = JSON, transport = function() return 401 end }
assert(select(2, b2:poll()):find("401"))
-- http
local tokens = { s3cret = "tg42" }
local raw = "PUT /settings/kos_x HTTP/1.1\r\nHost: x\r\nX-Rest-Token: s3cret\r\nContent-Length: 2\r\n\r\n77EXTRA"
local req = Http.parse(raw, tokens); assert(req.method == "PUT" and req.body == "77" and req.client == "tg42")
local st = R.dispatch(req); assert(st == 200 and store.kos_x == "77")
local _, code = Http.parse("GET /routes HTTP/1.1\r\n\r\n", tokens); assert(code == 401)
_, code = Http.parse("GET /routes HTTP/1.1\r\nX-Rest-Token: bad\r\n\r\n", tokens); assert(code == 401)
_, code = Http.parse("nonsense", tokens); assert(code == 400)
_, code = Http.parse("POST /x HTTP/1.1\r\nX-Rest-Token: s3cret\r\nContent-Length: 99999\r\n\r\n", tokens); assert(code == 413)
local resp = Http.response(404, { error = "no" }, JSON); assert(resp:find("^HTTP/1.1 404 Not Found") and resp:find("Content%-Length: 8"))
print("bot+http ok")

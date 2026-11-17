package.preload["json"] = function()
  return { encode = function(t) local k = {} for a in pairs(t) do k[#k+1] = a end table.sort(k)
    local o = {} for _, a in ipairs(k) do o[#o+1] = string.format('"%s":"%s"', a, tostring(t[a])) end return "{"..table.concat(o, ",").."}" end }
end
local P = dofile("frontend/apps/kos/pipeline.lua")
local out, trace = P.run("  Hello World  ", {"trim", "upper"}); assert(out == "HELLO WORLD" and #trace == 2)
assert(P.run("x", {"nope"}) == nil)
local o, tr, err = P.run("x", {"trim", "app"}, { findApp = function() return nil end }); assert(o == nil and err == "no app called x")
local searched; P.run("quantum", {"trim", "search"}, { search = function(t) searched = t end }); assert(searched == "quantum")
local opened; P.run(" pendulums ", {"trim", "app"}, { findApp = function(t) return t == "pendulums" and {id="p"} end, openApp = function(a) opened = a.id end }); assert(opened == "p")
-- dispatch
local pl = P.defaults()
local p, rest = P.dispatch("bot hello there", pl); assert(p.name == "bot" and rest == "hello there")
p, rest = P.dispatch("Open: gemma", pl); assert(p.name == "open" and rest == "gemma")
p, rest = P.dispatch("just words here", pl); assert(p == nil and rest == "just words here")
-- telegram with a fake transport
local seen
local ok = P.telegramSend("123:ABC", "42", "hi", function(url, body) seen = { url, body } return 200, "{}" end)
assert(ok and seen[1] == "https://api.telegram.org/bot123:ABC/sendMessage" and seen[2]:find('"chat_id":"42"') and seen[2]:find('"text":"hi"'))
local ok2, e2 = P.telegramSend("t", "c", "x", function() return 401, "unauthorized" end); assert(not ok2 and e2:find("401"))
assert(select(2, P.telegramSend("", "c", "x")):find("token")); assert(select(2, P.telegramSend("t", "", "x")):find("chat id"))
local o3 = P.run("hi", {"trim", "telegram"}, { telegram_token = "t", telegram_chat = "c", transport = function() return 200 end }); assert(o3 == "hi")
local o4, _, e4 = P.run("hi", {"telegram"}, { telegram_token = "", telegram_chat = "c" }); assert(o4 == nil and e4:find("token"))
P.register("shout", function(t) return t .. "!" end); assert(P.run("a", {"shout", "shout"}) == "a!!")
print("pipeline ok")

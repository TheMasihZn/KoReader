local store = {}
G_reader_settings = { readSetting = function(_, k) return store[k] end, saveSetting = function(_, k, v) store[k] = v end }
local J = dofile("frontend/apps/kos/johndoe.lua"); local T = dofile("frontend/apps/kos/theme.lua")
local n = J.newName(7); assert(n:match("^johnDoe%a+$") and not n:find("-")); assert(J.newName(7) == n and J.newName(8) ~= n)
local mem = {}
local fs = { exists = function(p) return mem[p] ~= nil end, mkdir = function(p) mem[p] = true; return true end, write = function(p, s) mem[p] = s; return true end,
  read = function(p) return mem[p] end, rename = function(a, b) for k, v in pairs(mem) do if k:sub(1, #a) == a then mem[b .. k:sub(#a + 1)] = v; mem[k] = nil end end return true end }
local ok, f = J.create("/plugins", n, fs); assert(ok and mem["/plugins/" .. n .. ".koplugin/main.lua"]:find('name = "' .. n .. '"', 1, true))
assert(load(mem["/plugins/" .. n .. ".koplugin/main.lua"]) and load(mem["/plugins/" .. n .. ".koplugin/_meta.lua"]))   -- generated files are valid Lua
assert(not J.create("/plugins", n, fs) and not J.create("/plugins", "bad-name", fs))
local ok2 = J.rename("/plugins", n, "tuner", fs); assert(ok2 and mem["/plugins/tuner.koplugin/main.lua"]:find("tuner") and not mem["/plugins/" .. n .. ".koplugin/main.lua"])
assert(not J.rename("/plugins", "x", "bad name", fs))
-- themes
assert(T.default().fontSize == 17 and T.forApp("tuner").fontSize == 17)
assert(T.set("default", "fontSize", 20) and T.forApp("tuner").fontSize == 20)
assert(T.set("tuner", "fontSize", 12) and T.forApp("tuner").fontSize == 12 and T.forApp("other").fontSize == 20)
assert(not T.set("tuner", "fontSize", "big") and not T.set("tuner", "nope", 1) and not T.set("tuner", "iconSize", "huge") and not T.set("tuner", "cornerRadius", 999))
T.clear("tuner", "fontSize"); assert(T.forApp("tuner").fontSize == 20)
T.saveAs("night"); T.set("default", "invert", true); assert(T.default().invert == true)
assert(T.use("night") and T.default().invert == false and not T.use("none")); assert(T.names()[1] == "night")
local text = T.export(); assert(text:find("fontSize = 20")); T.set("default", "fontSize", 9); assert(T.import(text) == 7 and T.default().fontSize == 20)
print("johndoe+theme ok")

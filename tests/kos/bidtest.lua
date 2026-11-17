package.preload["gettext"]=function() return function(s) return s end end
local store = {}
G_reader_settings = { readSetting=function(_,k) return store[k] end, saveSetting=function(_,k,v) store[k]=v end }
package.preload["device"]=function() return { model="SM-F946B" } end
local B = dofile("frontend/apps/kos/bridgeid.lua")
local id = B.get(); assert(id:match("^SMF946B%-%x%x%x%x$"), id); assert(B.get()==id, "kept")
local h = B.headers("123456", {X="y"}); assert(h["X-Bridge-Client"]==id and h["X-Bridge-Pin"]=="123456" and h.X=="y")
assert(B.explain(403, '{"error": "waiting for approval: run  python3 registry.py approve '..id..'", "client": "x"}'):find("approve "..id, 1, true))
assert(B.explain(403, '{"error": "no grant for files.read"}'):find("files.read"))
assert(B.explain(401)=="Wrong PIN." and B.explain(200)==nil)
print("bridgeid ok", id)

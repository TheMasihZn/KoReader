package.path = package.path
local real = {}
local function loader(name) local f = assert(loadfile("frontend/" .. name .. ".lua")); real[name] = f(); return real[name] end
_G.require = function(n) if real[n] then return real[n] end return loader(n) end
local A = require("apps/kos/adapters"); local L = require("apps/kos/linkproto"); local P = require("apps/kos/sandboxpolicy")
-- chain math
local out = {}
local c = A.chain{ name = "t", seed = 3, nodes = { { type = "gain", k = 2 }, { type = "offset", b = 1 }, { type = "clip", lo = 0, hi = 10 } } }
c:to(function(v) out[#out + 1] = v end)
c:push(2); c:push(100); c:push(-9); assert(out[1] == 5 and out[2] == 10 and out[3] == 0)
-- determinism of noise and dropout
local function run(seed) local r = {}; local k = A.chain{ seed = seed, nodes = { { type = "noise", amp = 1 }, { type = "dropout", p = 0.3 } } }; k:to(function(v) r[#r + 1] = string.format("%.6f", v) end); for i = 1, 50 do k:push(i) end; return table.concat(r, ","), k.dropped end
local a1, d1 = run(5); local a2, d2 = run(5); local a3 = run(6)
assert(a1 == a2 and d1 == d2 and a1 ~= a3 and d1 > 3 and d1 < 30, d1)
-- other steps
local q = A.chain{ nodes = { { type = "quantize", step = 0.5 }, { type = "invert" } } }; assert(q:push(1.3) == -1.5)
local dl = A.chain{ nodes = { { type = "delay", n = 2 } } }; assert(dl:push(1) == nil and dl:push(2) == nil and dl:push(3) == 1)
local sm = A.chain{ nodes = { { type = "smooth", alpha = 0.5 } } }; sm:push(0); assert(sm:push(10) == 5)
local db = A.chain{ nodes = { { type = "deadband", w = 1 } } }; assert(db:push(0.5) == 0 and db:push(2) == 2)
assert(not pcall(A.chain, { nodes = { { type = "bogus" } } }))
-- chain to chain, ending in a device; held until armed
local wire = {}
local dev = A.device{ link = { write = function(b) wire[#wire + 1] = b end }, channel = 3 }
local first = A.chain{ name = "knob", nodes = { { type = "gain", k = 2 } } }
local second = A.chain{ name = "esp", nodes = { { type = "clip", lo = 0, hi = 5 } } }
second:from(first); second:to(dev)
first:push(1.5); assert(#wire == 0 and second.held == 1)            -- not armed: nothing leaves the phone
second.armed = true; first:push(1.5); first:push(9)
assert(#wire == 2 and second.sent == 2)
local p = L.parser(); local f1 = p:feed(wire[1])[1]; local ch, milli = L.readData(f1.payload); assert(ch == 3 and milli == 3000)
local f2 = p:feed(wire[2])[1]; local _, m2 = L.readData(f2.payload); assert(m2 == 5000 and f2.seq == f1.seq + 1)
-- device to chain
local got = {}; local inc = A.chain{ nodes = { { type = "gain", k = 10 } } }; inc:to(function(v) got[#got + 1] = v end)
assert(dev:receive(L.encode(L.DATA, 1, L.dataPayload(3, 2500)) .. L.encode(L.DATA, 2, L.dataPayload(4, 1)), inc) == 1 and got[1] == 25)
assert(A.names()[1] and A.get("knob") == first)
-- policy
local function d(a) return (P.decide(a)) end
assert(d{ kind = "file.write", path = "/sdcard/koreader/sandbox/x.txt" } == "allow")
assert(d{ kind = "file.write", path = "/sdcard/koreader/sandbox/../x" } == "deny")
assert(d{ kind = "file.write", path = "/etc/passwd" } == "deny")
assert(d{ kind = "file.delete", path = "/sdcard/koreader/sandbox/x" } == "confirm")
assert(d{ kind = "setting.write", key = "kos_x" } == "allow" and d{ kind = "setting.write", key = "home_dir" } == "deny")
assert(d{ kind = "adapter.arm" } == "confirm" and d{ kind = "flash.device" } == "confirm" and d{ kind = "voice.hardware" } == "confirm")
assert(d{ kind = "policy.change" } == "deny" and d{ kind = "route.approve" } == "deny" and d{ kind = "token.change" } == "deny")
assert(d{ kind = "shell", cmd = "ls" } == "confirm" and d{ kind = "shell", cmd = "ls; rm -rf /" } == "deny")
assert(d{ kind = "invented" } == "deny")
local _, _, journal = P.decide{ kind = "app.open" }; assert(journal == true)
local ch1 = P.challenge(11); assert(P.confirm(ch1, ch1:upper() .. ".") and not P.confirm(ch1, "yes") and not P.confirm(ch1, nil))
print("adapters+policy ok")

local K = dofile("frontend/apps/kos/keyboardmodel.lua")
local L = K.qwerty()
assert(math.abs(L.keys.q.x - 0.5) < 1e-9 and math.abs(L.keys.a.x - 1.0) < 1e-9 and L.keys.m.y == 2.5)
assert(math.abs(K.travel(L, "qw") - 1) < 1e-9 and K.travel(L, "q") == 0 and K.travel(L, "q w!") > 0)
local f = K.bigrams(K.sample); assert(f.t and f.t.h and f.t.h >= 4)
assert(K.predict(f, "t", 1)[1] == "h" and #K.predict(f, "t", 3) == 3 and #K.predict(f, "zz", 3) == 0)
local x, y = K.restPoint(L, f, "t"); assert(x and y and x > 0 and y > 0)
local ex = K.expected(L, f); assert(ex > 0.5 and ex < 6)
local L2, before, after = K.optimize(L, f, 42, 3000)
assert(before == ex and after < before, before .. " -> " .. after)
local L3, _, after2 = K.optimize(L, f, 42, 3000); assert(after2 == after)                 -- same seed, same result
assert(math.abs(K.expected(L2, f) - after) < 1e-9)
local seen = {} for c, p in pairs(L2.keys) do local k = p.x .. "," .. p.y; assert(not seen[k]); seen[k] = true end   -- every position used once
assert(L.keys.q.x == 0.5)                                                                  -- original untouched
print(string.format("keyboard ok: expected travel %.3f -> %.3f key widths (%.0f%% less)", before, after, 100 * (1 - after / before)))

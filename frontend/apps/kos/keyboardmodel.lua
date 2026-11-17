--[[--
How far a finger travels over a keyboard, and where it should wait.

    local L = Keyboard.qwerty()                         -- { keys = { a = {x=, y=} ... }, rows }
    Keyboard.travel(L, "the quick fox")                 -- total finger travel in key widths
    local f = Keyboard.bigrams(text)                    -- counts of "next key given this key"
    Keyboard.expected(L, f)                             -- E = sum p(a,b) d(a,b), average travel per key press
    local L2, before, after = Keyboard.optimize(L, f, seed, iterations)   -- layout with less travel (swaps keys)
    Keyboard.restPoint(L, f, "t")                       -- x, y where the finger should wait after "t": the centre of the
                                                        -- likely next keys, weighted by how likely each is
    Keyboard.predict(f, "t", 3)                         -- the 3 most likely next keys

d(a,b) is the straight distance between key centres in key widths. Nothing here draws a keyboard: a real Samsung or
Google style keyboard is an Android input method, a separate app; this is the part that decides where keys and rest
points should be, so that app (or the toolbar above KOReader's keyboard) can use it.
]]

local K = {}

local ROWS = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }
local OFFSET = { 0, 0.5, 1.5 }

function K.qwerty()
    local keys, order = {}, {}
    for r, row in ipairs(ROWS) do
        for i = 1, #row do
            local c = row:sub(i, i)
            keys[c] = { x = OFFSET[r] + (i - 1) + 0.5, y = (r - 1) + 0.5 }
            order[#order + 1] = c
        end
    end
    return { keys = keys, order = order }
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

function K.travel(L, text)
    local prev, total = nil, 0
    for c in text:lower():gmatch("%a") do
        local p = L.keys[c]
        if prev and p then total = total + dist(prev, p) end
        prev = p
    end
    return total
end

function K.bigrams(text)
    local f, prev = {}, nil
    for c in text:lower():gmatch("%a") do
        if prev then
            f[prev] = f[prev] or {}
            f[prev][c] = (f[prev][c] or 0) + 1
        end
        prev = c
    end
    return f
end

function K.expected(L, f)
    local sum, n = 0, 0
    for a, row in pairs(f) do
        for b, c in pairs(row) do
            if L.keys[a] and L.keys[b] then sum = sum + c * dist(L.keys[a], L.keys[b]); n = n + c end
        end
    end
    return n > 0 and sum / n or 0
end

local function rng(seed)
    local s = (seed or 1) & 0x7FFFFFFF; if s == 0 then s = 1 end
    return function(n) s = (s * 1103515245 + 12345) & 0x7FFFFFFF; return (s % n) + 1 end
end

--- Swap keys while it lowers the expected travel. Same seed, same result. Returns the new layout and the numbers.
function K.optimize(L, f, seed, iterations)
    local r = rng(seed)
    local cur = { keys = {}, order = {} }
    for c, p in pairs(L.keys) do cur.keys[c] = { x = p.x, y = p.y } end
    for i, c in ipairs(L.order) do cur.order[i] = c end
    local before = K.expected(cur, f)
    local best = before
    for _ = 1, iterations or 2000 do
        local a, b = cur.order[r(#cur.order)], cur.order[r(#cur.order)]
        if a ~= b then
            cur.keys[a], cur.keys[b] = cur.keys[b], cur.keys[a]
            local e = K.expected(cur, f)
            if e < best then best = e else cur.keys[a], cur.keys[b] = cur.keys[b], cur.keys[a] end
        end
    end
    return cur, before, best
end

function K.restPoint(L, f, key)
    local row = f[key:lower()]
    if not row then return L.keys[key:lower()] and L.keys[key:lower()].x, L.keys[key:lower()] and L.keys[key:lower()].y end
    local sx, sy, w = 0, 0, 0
    for b, c in pairs(row) do
        local p = L.keys[b]
        if p then sx = sx + c * p.x; sy = sy + c * p.y; w = w + c end
    end
    if w == 0 then return nil end
    return sx / w, sy / w
end

function K.predict(f, key, n)
    local row = f[key:lower()] or {}
    local list = {}
    for b, c in pairs(row) do list[#list + 1] = { key = b, count = c } end
    table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.key < b.key end)
    local out = {}
    for i = 1, math.min(n or 3, #list) do out[i] = list[i].key end
    return out
end

--- A small English sample so predictions work before the user has typed anything; user text is added on top.
K.sample = "the quick brown fox jumps over the lazy dog and then there was another thing that they thought about when the weather was nice and everything was good in this world of ours with people and their other things"

return K

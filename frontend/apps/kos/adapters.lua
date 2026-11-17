--[[--
Virtual adapters. An adapter chain takes values (a number from a sensor, a key, a voice level) through steps that can
disturb them on purpose, and ends in a place: another chain, a function, or a real device over the kosLink protocol.

    local a = Adapters.chain{ name = "knobToEsp", seed = 7, nodes = { {type="gain", k=2}, {type="noise", amp=0.1}, {type="clip", lo=0, hi=10} } }
    a:to(Adapters.device{ link = transport, channel = 3 })     -- transport = { write = function(bytes) end }
    a:push(4.2)                                               -- 8.4 plus noise, clipped, sent as a DATA frame
    b:from(a)                                                 -- chains can feed chains

Steps (perturbations): gain k, offset b, noise amp, clip lo hi, quantize step, invert, delay n, dropout p,
deadband w, smooth alpha, map table.
Same seed gives the same noise and drops, so a simulation can be repeated exactly.
Real devices: only a chain that ends in Adapters.device touches hardware; the sandbox policy asks for confirmation
before that chain is armed (chain.armed = true), until then device output is held, not sent.
]]

local Link = require("apps/kos/linkproto")
local A = {}
local registry = {}

local function rng(seed)
    local s = (seed or 1) & 0x7FFFFFFF; if s == 0 then s = 1 end
    return function() s = (s * 1103515245 + 12345) & 0x7FFFFFFF; return s / 0x7FFFFFFF end
end

local steps = {
    gain = function(n) return function(v) return v * n.k end end,
    offset = function(n) return function(v) return v + n.b end end,
    invert = function() return function(v) return -v end end,
    clip = function(n) return function(v) return math.max(n.lo, math.min(n.hi, v)) end end,
    quantize = function(n) return function(v) return math.floor(v / n.step + 0.5) * n.step end end,
    deadband = function(n) return function(v) if math.abs(v) < n.w then return 0 end return v end end,
    smooth = function(n) local prev; return function(v) prev = prev and (prev + n.alpha * (v - prev)) or v; return prev end end,
    map = function(n) return function(v) local r = n.table[v]; if r == nil then return v end return r end end,
    delay = function(n) local q = {}; return function(v) q[#q + 1] = v; if #q > n.n then return table.remove(q, 1) end return nil end end,
    noise = function(n, r) return function(v) return v + (r() * 2 - 1) * n.amp end end,
    dropout = function(n, r) return function(v) if r() < n.p then return nil end return v end end,
}

local Chain = {}
Chain.__index = Chain

function A.chain(spec)
    local c = setmetatable({ name = spec.name, fns = {}, sent = 0, dropped = 0, held = 0, armed = false, log = {} }, Chain)
    local r = rng(spec.seed)
    for _, n in ipairs(spec.nodes or {}) do
        local make = steps[n.type]
        if not make then error("unknown step " .. tostring(n.type)) end
        c.fns[#c.fns + 1] = make(n, r)
    end
    if spec.name then registry[spec.name] = c end
    return c
end

function Chain:to(target) self.target = target; return target end
function Chain:from(other) other.target = self; return self end

function Chain:push(v)
    for _, f in ipairs(self.fns) do
        v = f(v)
        if v == nil then self.dropped = self.dropped + 1; return nil end
    end
    local t = self.target
    if t == nil then return v end
    if type(t) == "function" then t(v)
    elseif t.push then t:push(v)
    elseif t.send then t:send(v, self) end
    return v
end

--- End of a chain that talks to hardware over kosLink.
function A.device(o)
    local d = { link = o.link, channel = o.channel or 0, seq = 0, frames = {} }
    function d:send(v, chain)
        if chain and not chain.armed then chain.held = chain.held + 1; return false end
        self.seq = (self.seq + 1) & 0xFF
        local bytes = Link.encode(Link.DATA, self.seq, Link.dataPayload(self.channel, math.floor(v * 1000 + 0.5)))
        self.frames[#self.frames + 1] = bytes
        if self.link and self.link.write then self.link.write(bytes) end
        if chain then chain.sent = chain.sent + 1 end
        return true
    end
    -- bytes from the device: DATA frames for our channel go into `chain`
    function d:receive(bytes, chain)
        self.parser = self.parser or Link.parser()
        local n = 0
        for _, f in ipairs(self.parser:feed(bytes)) do
            if f.type == Link.DATA then
                local ch, milli = Link.readData(f.payload)
                if ch == self.channel then chain:push(milli / 1000); n = n + 1 end
            end
        end
        return n
    end
    return d
end

function A.get(name) return registry[name] end
function A.names() local t = {}; for k in pairs(registry) do t[#t + 1] = k end table.sort(t); return t end
function A.reset() registry = {} end

return A

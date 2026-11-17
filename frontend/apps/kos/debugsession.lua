--[[--
Debug session: breakpoints, stepping, inspection, post-mortem snapshots, call profile, session log.
Built on Lua's debug library (LuaJIT has it), so it needs nothing outside the app.

    local S = require("apps/kos/debugsession")
    S.start{ logfile = "/sdcard/koreader/kosDebug.log" }
    S.addBreakpoint("wintitlebar.lua", 120)                  -- file name ending, line
    S.addBreakpoint("usearch.lua", 98, "#words > 1")         -- with a condition (Lua expression over locals)
    S.run(function() ... end)                                -- code under the session
    S.protect(fn, ...)                                       -- on error: stack and locals at the failing line are kept
    S.snapshots()                                            -- list of { kind, file, line, locals, stack, time }
    S.profile(10)                                            -- 10 most called functions
    S.report()                                               -- plain text for people and for LLMs

A breakpoint in the app's UI thread cannot wait for a person, so by default it records a snapshot and carries on.
Give S.onBreak = function(snap) return "continue" | "step" | "over" | "out" end to pause synchronously
(used from tests, or from the laptop through the bridge).
]]

local S = {}

local state
local MAX_SNAP = 200

local function now() return os.time() end

function S.start(opts)
    opts = opts or {}
    state = {
        id = tostring(now()) .. "-" .. tostring(math.random(1000, 9999)),
        started = now(), logfile = opts.logfile,
        breakpoints = {}, snaps = {}, calls = {}, counts = { debug = 0, info = 0, warn = 0, error = 0 },
        spans = {}, mode = "run", depth = 0, target = 0,
    }
    S.log("info", "session started " .. state.id)
    return state.id
end

function S.active() return state ~= nil end

local function need() if not state then S.start() end return state end

function S.log(level, msg)
    local st = need()
    st.counts[level] = (st.counts[level] or 0) + 1
    local line = string.format("%s %-5s %s", os.date("%H:%M:%S"), level, tostring(msg))
    st.ring = st.ring or {}
    st.ring[#st.ring + 1] = line
    if #st.ring > 500 then table.remove(st.ring, 1) end
    if st.logfile then
        local f = io.open(st.logfile, "a")
        if f then f:write(line, "\n"); f:close() end
    end
end

--- Timing spans: S.span("scan") ... S.spanEnd("scan") -> seconds.
function S.span(name) need().spans[name] = { t0 = os.clock(), total = (state.spans[name] or {}).total or 0, n = (state.spans[name] or {}).n or 0 } end
function S.spanEnd(name)
    local sp = need().spans[name]; if not sp or not sp.t0 then return nil end
    local d = os.clock() - sp.t0
    sp.total, sp.n, sp.t0 = sp.total + d, sp.n + 1, nil
    return d
end

---------------------------------------------------------------------------
-- Inspection
---------------------------------------------------------------------------
function S.inspect(v, depth, seen)
    depth = depth or 2; seen = seen or {}
    local t = type(v)
    if t == "string" then
        return #v > 80 and string.format("%q…(%d chars)", v:sub(1, 80), #v) or string.format("%q", v)
    elseif t ~= "table" then return tostring(v) end
    if seen[v] then return "<cycle>" end
    if depth <= 0 then return "{…}" end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for i, k in ipairs(keys) do
        if i > 12 then out[#out + 1] = "…" .. (#keys - 12) .. " more"; break end
        out[#out + 1] = tostring(k) .. "=" .. S.inspect(v[k], depth - 1, seen)
    end
    seen[v] = nil
    return "{" .. table.concat(out, ", ") .. "}"
end

local function locals(level)
    local out = {}
    for i = 1, 60 do
        local name, val = debug.getlocal(level + 1, i)
        if not name then break end
        if name:sub(1, 1) ~= "(" then out[#out + 1] = { name = name, value = S.inspect(val) } end
    end
    return out
end

local function localTable(level)
    local env = {}
    for i = 1, 60 do
        local name, val = debug.getlocal(level + 1, i)
        if not name then break end
        if name:sub(1, 1) ~= "(" then env[name] = val end
    end
    return env
end

local function snapshot(kind, level, extra)
    local info = debug.getinfo(level + 1, "Sl") or {}
    local snap = {
        kind = kind, time = now(), file = info.short_src or "?", line = info.currentline or 0,
        locals = locals(level + 1), stack = debug.traceback("", level + 1), extra = extra,
    }
    local st = need()
    st.snaps[#st.snaps + 1] = snap
    if #st.snaps > MAX_SNAP then table.remove(st.snaps, 1) end
    S.log("debug", string.format("%s at %s:%d (%d locals)", kind, snap.file, snap.line, #snap.locals))
    return snap
end

---------------------------------------------------------------------------
-- Breakpoints and stepping
---------------------------------------------------------------------------
function S.addBreakpoint(file, line, condition)
    local st = need()
    st.breakpoints[#st.breakpoints + 1] = { file = file, line = line, condition = condition, hits = 0 }
    return #st.breakpoints
end

function S.removeBreakpoint(i) if state then table.remove(state.breakpoints, i) end end
function S.breakpoints() return need().breakpoints end

local function matches(bp, src, line)
    return bp.line == line and src:sub(-#bp.file) == bp.file
end

local function conditionHolds(bp, level)
    if not bp.condition then return true end
    local fn = load("return " .. bp.condition, "condition", "t", setmetatable(localTable(level + 1), { __index = _G }))
    if not fn then return false end
    local ok, res = pcall(fn)
    return ok and res and true or false
end

local function hook(event, line)
    local st = state
    if not st then return end
    if event == "call" or event == "tail call" then
        st.depth = st.depth + 1
        local info = debug.getinfo(2, "S")
        local key = (info.short_src or "?") .. ":" .. (info.linedefined or 0)
        st.calls[key] = (st.calls[key] or 0) + 1
    elseif event == "return" then
        st.depth = st.depth - 1
    elseif event == "line" then
        local info = debug.getinfo(2, "S")
        local src = info.short_src or ""
        local hit
        for _, bp in ipairs(st.breakpoints) do
            if matches(bp, src, line) and conditionHolds(bp, 2) then bp.hits = bp.hits + 1; hit = bp; break end
        end
        local stepping = st.mode == "step" or (st.mode == "over" and st.depth <= st.target) or (st.mode == "out" and st.depth < st.target)
        if hit or stepping then
            local snap = snapshot(hit and "breakpoint" or "step", 2)
            if S.onBreak then
                local act = S.onBreak(snap) or "continue"
                st.mode, st.target = act, st.depth
            else
                st.mode = "run"
            end
        end
    end
end

--- Run fn under the session (hooks on while it runs, off after, even on error).
function S.run(fn, ...)
    local st = need()
    st.depth = 0; st.mode = "run"
    debug.sethook(hook, "crl")
    local res = table.pack(xpcall(fn, S._onError, ...))
    debug.sethook()
    if not res[1] then return nil, res[2] end
    return table.unpack(res, 2, res.n)
end

---------------------------------------------------------------------------
-- Post-mortem: keep the stack and locals where an error happened
---------------------------------------------------------------------------
function S._onError(err)
    local st = need()
    st.counts.error = (st.counts.error or 0) + 1
    -- level 3: the function that raised the error (1 = handler, 2 = error/assert, 3 = caller)
    local info = debug.getinfo(3, "Sl")
    local snap = {
        kind = "error", time = now(), file = info and info.short_src or "?", line = info and info.currentline or 0,
        locals = locals(3), stack = debug.traceback(tostring(err), 3), extra = tostring(err),
    }
    st.snaps[#st.snaps + 1] = snap
    S.log("error", tostring(err))
    return err
end

function S.protect(fn, ...)
    need()
    local res = table.pack(xpcall(fn, S._onError, ...))
    if not res[1] then return nil, res[2] end
    return table.unpack(res, 2, res.n)
end

function S.snapshots() return need().snaps end

function S.profile(n)
    local rows = {}
    for k, c in pairs(need().calls) do rows[#rows + 1] = { where = k, calls = c } end
    table.sort(rows, function(a, b) if a.calls ~= b.calls then return a.calls > b.calls end return a.where < b.where end)
    local out = {}
    for i = 1, math.min(n or 10, #rows) do out[i] = rows[i] end
    return out
end

function S.report()
    local st = need()
    local L = { "DEBUG SESSION " .. st.id, string.format("started %s, %d s ago", os.date("%Y-%m-%d %H:%M:%S", st.started), now() - st.started) }
    L[#L + 1] = string.format("log lines: debug %d, info %d, warn %d, error %d", st.counts.debug, st.counts.info, st.counts.warn, st.counts.error)
    L[#L + 1] = "BREAKPOINTS"
    for i, bp in ipairs(st.breakpoints) do
        L[#L + 1] = string.format("  %d. %s:%d%s hits=%d", i, bp.file, bp.line, bp.condition and (" if " .. bp.condition) or "", bp.hits)
    end
    L[#L + 1] = "SNAPSHOTS (newest last)"
    for _, s in ipairs(st.snaps) do
        L[#L + 1] = string.format("  [%s] %s:%d %s", s.kind, s.file, s.line, s.extra or "")
        for _, l in ipairs(s.locals) do L[#L + 1] = "      " .. l.name .. " = " .. l.value end
    end
    L[#L + 1] = "MOST CALLED"
    for _, r in ipairs(S.profile(10)) do L[#L + 1] = string.format("  %6d  %s", r.calls, r.where) end
    L[#L + 1] = "SPANS"
    local names = {}
    for k in pairs(st.spans) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do L[#L + 1] = string.format("  %s: %d runs, %.4f s total", k, st.spans[k].n, st.spans[k].total) end
    return table.concat(L, "\n")
end

function S.stop() debug.sethook(); local s = state; state = nil; S.onBreak = nil; return s end

return S

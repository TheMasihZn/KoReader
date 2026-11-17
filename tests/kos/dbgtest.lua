local S = dofile("frontend/apps/kos/debugsession.lua")
S.start{}
local function work(n)
  local total = 0
  for i = 1, n do
    local sq = i * i
    total = total + sq        -- line 6
  end
  return total
end
-- breakpoint with condition, non-blocking
local f = debug.getinfo(work, "S").short_src
S.addBreakpoint("dbgtest.lua", 6, "i == 3")
-- (source is a file name; patch the match to this chunk)
S.stop(); S.start{}
local src = debug.getinfo(1, "S").short_src
S.addBreakpoint(src:match("[^/]+$"), 7, "i == 3")
assert(S.run(work, 5) == 55)
local snaps = S.snapshots()
assert(#snaps == 1 and snaps[1].kind == "breakpoint", #snaps)
local vals = {} for _, l in ipairs(snaps[1].locals) do vals[l.name] = l.value end
assert(vals.i == "3" and vals.sq == "9" and vals.total == "5", vals.i .. vals.sq .. vals.total)
assert(S.breakpoints()[1].hits == 1)
-- stepping with a synchronous handler
S.stop(); S.start{}
S.addBreakpoint(src:match("[^/]+$"), 7, "i == 1")
local seen = {}
S.onBreak = function(s) seen[#seen + 1] = s.line; return #seen < 3 and "step" or "continue" end
S.run(work, 3)
assert(#seen == 3 and seen[1] == 7, table.concat(seen, ","))
-- post-mortem on error keeps locals
S.stop(); S.start{}
local function bad() local secret, k = "hidden", 42; error("boom") end
local ok, err = S.protect(bad)
assert(not ok and tostring(err):find("boom"))
local e = S.snapshots()[1]
assert(e.kind == "error" and e.stack:find("boom"), e.stack)
local ev = {} for _, l in ipairs(e.locals) do ev[l.name] = l.value end
assert(ev.secret == '"hidden"' and ev.k == "42", ev.secret)
-- hook is off after run, even when run errors
local r, e2 = S.run(function() error("x") end); assert(r == nil and debug.gethook() == nil)
-- inspect: cycles and depth
local t = { a = 1, b = { c = { d = { e = 1 } } } }; t.self = t
local s = S.inspect(t, 2); assert(s:find("<cycle>") and s:find("{…}"), s)
-- profile and spans and report
S.run(function() for i = 1, 5 do work(1) end end)
assert(S.profile(1)[1].calls >= 5)
S.span("x"); S.spanEnd("x")
local rep = S.report(); assert(rep:find("MOST CALLED") and rep:find("SPANS") and rep:find("x: 1 runs"))
-- log file
local path = os.tmpname(); S.stop(); S.start{ logfile = path }; S.log("warn", "careful")
local f2 = io.open(path); local txt = f2:read("a"); f2:close(); os.remove(path); assert(txt:find("careful"))
print("debugsession ok")

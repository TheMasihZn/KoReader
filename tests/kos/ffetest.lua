local real = {}
_G.require = function(n) if real[n] then return real[n] end local f = assert(loadfile("frontend/" .. n .. ".lua")); real[n] = f(); return real[n] end
local E = require("apps/kos/entropycalc"); local F = require("apps/kos/folderfile")
local function near(a, b) return math.abs(a - b) < 1e-9 end
assert(near(E.shannon({ 1, 1 }), 1) and near(E.shannon({ 5 }), 0) and near(E.shannon({ 1, 1, 1, 1 }), 2) and near(E.shannon({ 2, 2 }), 1) and E.shannon({}) == 0)
local lo, hi = E.bounds(8); assert(lo == 0 and near(hi, 3))
assert(not pcall(E.shannon, { 1, -1 }))
local h, max, parts = E.frame{ events = { 1, 1 }, positions = { 1, 1, 1, 1 }, frames = { 3 } }
assert(near(h, 3) and near(max, 3) and near(parts.positions, 2))
local tex = E.latex(h, max, parts); assert(tex:find("\\log_2") and tex:find("3.0000") and tex:find("not yet defined"))
assert(near(E.bytes(string.rep("a", 100)), 0) and E.bytes(string.char(0, 1)) == 1)
-- folder per file in a real temp dir
local function sh(c) local h = io.popen(c .. " 2>&1; echo rc=$?"); local o = h:read("a"); h:close(); return o:match("rc=(%d+)") == "0" end
local base = os.tmpname(); os.remove(base); assert(sh("mkdir -p " .. base))
local function w(p, s) local f = io.open(p, "wb"); f:write(s); f:close() end
local function r(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("a"); f:close(); return s end
local fs = { exists = function(p) local f = io.open(p, "rb"); if f then f:close() return true end return sh("test -d '" .. p .. "'") end,
  mkdir = function(p) return sh("mkdir '" .. p .. "'") end, rename = os.rename, read = function(p, n) local f = io.open(p, "rb"); if not f then return nil end local s = f:read(n or "a"); f:close(); return s end,
  write = function(p, s) w(p, s); return true end, remove = os.remove, size = function(p) return #r(p) end }
local p = F.plan("/a/b/something.jpg"); assert(p.folder == "/a/b/something" and p.file == "/a/b/something/something.jpg" and p.meta:match("something.jpg.md$"))
w(base .. "/something.jpg", "\0\1\2\3\0\1\2\3")
local ok, plan = F.wrap(base .. "/something.jpg", fs); assert(ok, plan)
assert(r(base .. "/something/something.jpg") == "\0\1\2\3\0\1\2\3" and not r(base .. "/something.jpg"))
local note = r(base .. "/something/something.jpg.md"); assert(note:find("name: something.jpg") and note:find("2.0000 \\ \\text{bits}", 1, true), note)
-- second file with the same base shares the folder; existing target is refused
w(base .. "/something.png", "x"); assert(F.wrap(base .. "/something.png", fs) and r(base .. "/something/something.png") == "x")
w(base .. "/something.jpg", "new"); local ok2, e2 = F.wrap(base .. "/something.jpg", fs); assert(not ok2 and e2:find("already exists") and r(base .. "/something.jpg") == "new")
assert(not F.wrap(base .. "/missing.txt", fs))
-- unwrap puts the file back and keeps the note
os.remove(base .. "/something.jpg")
assert(F.unwrap(base .. "/something/something.jpg", fs) and r(base .. "/something.jpg") == "\0\1\2\3\0\1\2\3" and r(base .. "/something/something.jpg.md"))
sh("rm -rf " .. base)
print("entropy+folderfile ok")

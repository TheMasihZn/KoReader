local V = dofile("frontend/apps/kos/versions.lua")
os.execute("rm -rf /tmp/vt; mkdir -p /tmp/vt")
math.randomseed(7)
local function rnd(n) local t = {} for i = 1, n do t[i] = string.char(math.random(0, 255)) end return table.concat(t) end
local v0 = rnd(5000)
local vdir = assert(V.track("/tmp/vt", "photo.jpg", v0, "gallery", "sig-a", "imported"))
assert(vdir == "/tmp/vt/photo" and V.isTracked(vdir))
assert(not V.track("/tmp/vt", "x.jpg", "a", "", "s"), "must name the process")
local versions = { v0 }
-- edit middle, append, shrink, insert at start, replace everything
versions[2] = v0:sub(1, 2000) .. rnd(50) .. v0:sub(2051)
versions[3] = versions[2] .. rnd(300)
versions[4] = versions[3]:sub(1, 4000)
versions[5] = rnd(10) .. versions[4]
versions[6] = rnd(700)
for i = 2, 6 do assert(V.change(vdir, "photo.jpg", versions[i], "editor", "sig-b", "edit " .. i) == i) end
assert(V.change(vdir, "photo.jpg", versions[6], "editor", "sig-b") == 6, "same content: no new version")
assert(not V.change(vdir, "photo.jpg", "z", "editor", ""), "needs a signature")
for k = 0, 5 do assert(V.get(vdir, "photo.jpg", k) == versions[6 - k], "step back " .. k) end
assert(not V.get(vdir, "photo.jpg", 6))
assert(V.dottedName("photo.jpg", 0) == "photo.jpg" and V.dottedName("photo.jpg", 1) == "photo..jpg" and V.dottedName("photo.jpg", 2) == "photo...jpg")
local p = assert(V.materialize(vdir, "photo.jpg", 2)); assert(p == "/tmp/vt/photo/photo...jpg")
assert(io.open(p, "rb"):read("*a") == versions[4])
-- the log is small: bytes stored vs six full copies
local tl = V.timeline(vdir); assert(#tl == 6 and tl[3].process == "editor" and tl[3].note == "edit 3")
local stored = 0 for _, e in ipairs(tl) do stored = stored + e.changed_bytes end
assert(stored < 3 * #v0, "stored " .. stored)
-- restore keeps history going forward
assert(V.restore(vdir, "photo.jpg", 3, "user", "sig-c") == 7)
assert(V.get(vdir, "photo.jpg", 0) == versions[3] and V.get(vdir, "photo.jpg", 1) == versions[6])
-- the standalone rebuild script gives the same bytes without the library
local out = io.popen('texlua /tmp/vt/photo/rebuild.lua photo.jpg 4', "r"):read("*a")
assert(out == versions[3], "rebuild.lua 4 back from version 7 is version 3")
print("versions ok; stored", stored, "bytes for 6 versions of", #v0)

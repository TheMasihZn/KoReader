local A = dofile("frontend/apps/kos/adb.lua")
local seen
local function fake(out, code) return function(cmd) seen = cmd; return out, code or 0 end end
local sample = "List of devices attached\nR5CW123ABC  device usb:1-1 product:q5q model:SM_F946B transport_id:3\n192.168.1.20:5555  unauthorized\n* daemon started\n"
local d = A.devices(fake(sample))
assert(seen == "'adb' 'devices' '-l'", seen)
assert(#d == 2 and d[1].serial == "R5CW123ABC" and d[1].state == "device" and d[1].info:find("model:SM_F946B") and d[2].state == "unauthorized")
assert(A.command({ "shell", "echo 'hi'" }, "S1") == "'adb' -s 'S1' 'shell' 'echo '\\''hi'\\'''")
local ok, msg = A.connect("192.168.1.20:5555", fake("connected to 192.168.1.20:5555\n")); assert(ok)
assert(not A.connect("x y", fake("")) and not A.connect("h:5555", fake("failed to connect to h:5555")))
local lines = A.logcat("S1", "*:W", 50, fake("a\nb\n")); assert(#lines == 2 and seen:find("'-t' '50' '%*:W'"), seen)
A.install("/x.apk", "S1", fake("Success")); assert(seen == "'adb' -s 'S1' 'install' '-r' '/x.apk'")
local out = A.run("echo hello"); assert(out:find("hello"))
print("adb ok")

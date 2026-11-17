--[[--
ADB from inside the shell. Needs an `adb` program on the device (path in setting kos_adb_path, default "adb"),
or runs on the laptop. This module builds the commands, runs them, and reads the answers; it is not an ADB
server. An ADB daemon inside the OS image (adbd in the kernel's userspace) is an OS-layer item, see osEmbedding.md.

    ADB.devices()                      -> { { serial=, state=, info= } ... }
    ADB.connect("192.168.1.20:5555")   -> ok, message           (wireless debugging)
    ADB.shell("getprop ro.build.version.release", serial)
    ADB.logcat(serial, "*:W", 200)     -> lines, newest last
    ADB.install(apk, serial) / ADB.push(a, b, serial) / ADB.pull(a, b, serial)
Every call takes an optional runner (command -> output, exit code) so it can be tested without a device.
]]

local ADB = {}

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function adbPath()
    local p = G_reader_settings and G_reader_settings.readSetting and G_reader_settings:readSetting("kos_adb_path")
    return (p and p ~= "") and p or "adb"
end

function ADB.run(cmd, runner)
    if runner then return runner(cmd) end
    local h = io.popen(cmd .. " 2>&1")
    if not h then return "", 1 end
    local out = h:read("*a") or ""
    local ok, _, code = h:close()
    return out, (ok and 0) or code or 1
end

function ADB.command(args, serial)
    local parts = { quote(adbPath()) }
    if serial and serial ~= "" then parts[#parts + 1] = "-s " .. quote(serial) end
    for _, a in ipairs(args) do parts[#parts + 1] = quote(a) end
    return table.concat(parts, " ")
end

function ADB.parseDevices(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local serial, state, rest = line:match("^(%S+)%s+(device|offline|unauthorized|recovery|sideload)%s*(.*)$")
        if not serial then serial, state, rest = line:match("^(%S+)%s+(%a+)%s*(.*)$") end
        if serial and serial ~= "List" and not line:find("^%*") then
            out[#out + 1] = { serial = serial, state = state, info = rest }
        end
    end
    return out
end

function ADB.devices(runner)
    local out = ADB.run(ADB.command({ "devices", "-l" }), runner)
    return ADB.parseDevices(out)
end

function ADB.connect(hostport, runner)
    if not tostring(hostport):match("^[%w%.%-]+:%d+$") then return false, "use host:port, for example 192.168.1.20:5555" end
    local out = ADB.run(ADB.command({ "connect", hostport }), runner)
    return out:find("connected to") ~= nil and not out:find("cannot") and not out:find("failed"), (out:gsub("%s+$", ""))
end

function ADB.shell(cmd, serial, runner)
    return ADB.run(ADB.command({ "shell", cmd }, serial), runner)
end

function ADB.logcat(serial, filter, count, runner)
    local args = { "logcat", "-d", "-v", "threadtime", "-t", tostring(count or 200) }
    if filter and filter ~= "" then args[#args + 1] = filter end
    local out = ADB.run(ADB.command(args, serial), runner)
    local lines = {}
    for l in out:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
    return lines
end

function ADB.install(apk, serial, runner) return ADB.run(ADB.command({ "install", "-r", apk }, serial), runner) end
function ADB.push(a, b, serial, runner) return ADB.run(ADB.command({ "push", a, b }, serial), runner) end
function ADB.pull(a, b, serial, runner) return ADB.run(ADB.command({ "pull", a, b }, serial), runner) end

return ADB

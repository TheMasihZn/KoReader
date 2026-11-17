--[[--
Dotted file versions. Every tracked file lives in a folder named after it, together with a change log:

    something/                    the folder
        something.jpg             the file as it is now
        changes.log               one line per change: who, when, why, and the difference that undoes it
        rebuild.lua               plain Lua that rebuilds any older version from the log (no KOReader needed)
        something..jpg            one change back   (made on request, see materialize)
        something...jpg           two changes back  (each extra dot is one more step, like a derivative)

No duplicated data: the log keeps only the difference between a version and the one after it (the part that
changed, found by trimming what both share at the start and at the end), so older versions cost what they changed.
The dotted files are views made on demand; deleting them loses nothing.

A change must say who made it (process name) and sign it; a change without both is refused.

    Versions.track(dir, filename, content, who, signature, note)  -> folder path   (makes the folder, first entry)
    Versions.change(vdir, filename, new_content, who, signature, note) -> version number
    Versions.get(vdir, filename, steps_back) -> content
    Versions.materialize(vdir, filename, steps_back) -> path of something..jpg
    Versions.restore(vdir, filename, steps_back, who, signature) -> new version number (history keeps going forward)
    Versions.timeline(vdir) -> list of { n, time, process, signature, note, changed_bytes }
    Versions.isTracked(vdir)

Log line format (| separated, fields cleaned of | and newlines):
    n | time | process | signature | note | prefix | suffix | old_length | hex of the old middle
]]

local Versions = {}

local LOG = "changes.log"

local function clean(s) return ((s or ""):gsub("[|\r\n]", " ")) end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeAll(path, data)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(data)
    f:close()
    return true
end

local function toHex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function fromHex(h) return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end)) end

local function split(name)
    local base, ext = name:match("^(.*)%.([^.]+)$")
    if not base then return name, "" end
    return base, ext
end

--- The difference that turns `new` back into `old`: how many bytes both share at the start and at the end,
-- and the bytes of `old` between them.
local function reverseDelta(old, new)
    local limit = math.min(#old, #new)
    local pre = 0
    while pre < limit and old:byte(pre + 1) == new:byte(pre + 1) do pre = pre + 1 end
    local suf = 0
    while suf < limit - pre and old:byte(#old - suf) == new:byte(#new - suf) do suf = suf + 1 end
    return pre, suf, old:sub(pre + 1, #old - suf)
end

local function applyDelta(new, pre, suf, middle)
    return new:sub(1, pre) .. middle .. new:sub(#new - suf + 1)
end

local function readLog(vdir)
    local text = readAll(vdir .. "/" .. LOG)
    local entries = {}
    if not text then return entries end
    for line in text:gmatch("[^\n]+") do
        local f = {}
        for part in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
        entries[#entries + 1] = {
            n = tonumber(f[1]), time = f[2], process = f[3], signature = f[4], note = f[5],
            pre = tonumber(f[6]) or 0, suf = tonumber(f[7]) or 0, old_len = tonumber(f[8]) or 0,
            middle = fromHex(f[9] or ""),
        }
    end
    return entries
end

local function appendLog(vdir, e)
    local f = assert(io.open(vdir .. "/" .. LOG, "ab"))
    f:write(string.format("%d|%s|%s|%s|%s|%d|%d|%d|%s\n", e.n, e.time, clean(e.process), clean(e.signature),
        clean(e.note), e.pre, e.suf, e.old_len, toHex(e.middle)))
    f:close()
end

local REBUILD = [=[
-- Rebuilds an older version of a tracked file from changes.log. Plain Lua 5.1+, no KOReader needed.
--   lua rebuild.lua <file name> [steps back] > output
local name, back = arg[1], tonumber(arg[2] or "0")
if not name then io.stderr:write("usage: lua rebuild.lua <file name> [steps back] > output\n") os.exit(1) end
local here = (arg[0]:match("^(.*)[/\\]") or ".")
local function read(p) local f = io.open(p, "rb") if not f then return nil end local s = f:read("*a") f:close() return s end
local data = assert(read(here .. "/" .. name), "file not found")
local entries = {}
for line in (read(here .. "/changes.log") or ""):gmatch("[^\n]+") do
  local f = {}
  for part in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
  entries[#entries + 1] = { pre = tonumber(f[6]), suf = tonumber(f[7]), mid = (f[9] or ""):gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end) }
end
assert(back <= #entries - 1, "only " .. (#entries - 1) .. " earlier versions exist")
for i = #entries, #entries - back + 1, -1 do
  local e = entries[i]
  data = data:sub(1, e.pre) .. e.mid .. data:sub(#data - e.suf + 1)
end
io.write(data)
]=]

function Versions.isTracked(vdir)
    local f = io.open(vdir .. "/" .. LOG, "rb")
    if f then f:close() return true end
    return false
end

function Versions.track(dir, filename, content, who, signature, note)
    if not who or who == "" or not signature or signature == "" then
        return nil, "a change must say which process made it and sign it"
    end
    local base = split(filename)
    local vdir = dir .. "/" .. base
    os.execute('mkdir -p "' .. vdir .. '"')
    local ok, err = writeAll(vdir .. "/" .. filename, content)
    if not ok then return nil, err end
    os.remove(vdir .. "/" .. LOG)
    appendLog(vdir, { n = 1, time = os.date("%Y-%m-%d %H:%M:%S"), process = who, signature = signature,
        note = note or "first version", pre = 0, suf = 0, old_len = 0, middle = "" })
    writeAll(vdir .. "/rebuild.lua", REBUILD)
    return vdir
end

function Versions.change(vdir, filename, new_content, who, signature, note)
    if not who or who == "" or not signature or signature == "" then
        return nil, "a change must say which process made it and sign it"
    end
    local current = readAll(vdir .. "/" .. filename)
    if not current then return nil, "file not found in " .. vdir end
    local entries = readLog(vdir)
    if current == new_content then return #entries end -- nothing changed, no new version
    local pre, suf, middle = reverseDelta(current, new_content)
    local n = #entries + 1
    appendLog(vdir, { n = n, time = os.date("%Y-%m-%d %H:%M:%S"), process = who, signature = signature,
        note = note or "", pre = pre, suf = suf, old_len = #current, middle = middle })
    local ok, err = writeAll(vdir .. "/" .. filename, new_content)
    if not ok then return nil, err end
    return n
end

function Versions.get(vdir, filename, steps_back)
    steps_back = steps_back or 0
    local data = readAll(vdir .. "/" .. filename)
    if not data then return nil, "file not found" end
    local entries = readLog(vdir)
    if steps_back > #entries - 1 then return nil, "only " .. (#entries - 1) .. " earlier versions exist" end
    for i = #entries, #entries - steps_back + 1, -1 do
        local e = entries[i]
        data = applyDelta(data, e.pre, e.suf, e.middle)
    end
    return data
end

--- something..jpg for one step back, something...jpg for two, and so on.
function Versions.dottedName(filename, steps_back)
    local base, ext = split(filename)
    return base .. string.rep(".", steps_back + 1) .. ext
end

function Versions.materialize(vdir, filename, steps_back)
    local data, err = Versions.get(vdir, filename, steps_back)
    if not data then return nil, err end
    local path = vdir .. "/" .. Versions.dottedName(filename, steps_back)
    local ok, werr = writeAll(path, data)
    if not ok then return nil, werr end
    return path
end

function Versions.restore(vdir, filename, steps_back, who, signature)
    local old, err = Versions.get(vdir, filename, steps_back)
    if not old then return nil, err end
    return Versions.change(vdir, filename, old, who, signature,
        string.format("restored the version from %d change(s) back", steps_back))
end

function Versions.timeline(vdir)
    local out = {}
    for _, e in ipairs(readLog(vdir)) do
        out[#out + 1] = { n = e.n, time = e.time, process = e.process, signature = e.signature, note = e.note,
            changed_bytes = #e.middle }
    end
    return out
end

return Versions

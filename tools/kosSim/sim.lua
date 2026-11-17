--[[--
Fake KOReader for headless checks. Real Lua code of the apps runs; the screen, touch and Android are fakes.

    texlua tools/kosSim/sim.lua [pluginName ...]       checks every plugin (or the named ones)

For each plugin: its _meta.lua and main.lua must load, every name used must exist (a missing `require`
shows up as "undefined global X", the bug that is invisible until a device runs it), and if it has an app
(launchApp, or `app` in _meta) the app is opened and its build function is run at 600x800 and 1200x800.
Modules under frontend/ are loaded for real when they exist; anything else (ui widgets, device) is a stub
that accepts every call, so layout is NOT checked, only that the code runs and the names are right.
Exit code is the number of failed plugins.
]]

local ROOT = arg[0]:match("^(.*)/tools/kosSim/sim.lua$") or "."

-- stub objects: any field is a function returning the stub; calling it returns the stub
local Stub = {}
local function isStub(v) return type(v) == "table" and getmetatable(v) == Stub end
local function num(v) if isStub(v) then return 8 end return v end
local function newStub(name) return setmetatable({ _stub = name, _kids = {} }, Stub) end
Stub.__index = function(t, k)
    if k == "extend" then return function(self, o) o = o or {}; return setmetatable(o, getmetatable(self)) end end
    if k == "new" then return function(self, o) o = o or {}; return setmetatable(o, getmetatable(self)) end end
    local kids = rawget(t, "_kids")
    if not kids then kids = {}; rawset(t, "_kids", kids) end
    local kid = kids[k]
    if not kid then kid = newStub(tostring(k)); kids[k] = kid end
    return kid
end
Stub.__call = function(t) return t end
Stub.__concat = function(a, b) return (isStub(a) and "stub" or tostring(a)) .. (isStub(b) and "stub" or tostring(b)) end
Stub.__len = function() return 0 end
Stub.__tostring = function() return "stub" end
for _, op in ipairs({ "add", "sub", "mul", "div", "mod", "pow", "idiv" }) do Stub["__" .. op] = function() return 8 end end
Stub.__unm = function() return -8 end
Stub.__lt = function() return false end
Stub.__le = function() return true end
local settings = {}
local G = {
    readSetting = function(_, k) return settings[k] end,
    saveSetting = function(_, k, v) settings[k] = v end,
    delSetting = function(_, k) settings[k] = nil end,
    isTrue = function(_, k) return settings[k] == true end,
    nilOrTrue = function(_, k) return settings[k] == nil or settings[k] == true end,
    flipNilOrTrue = function(_, k) settings[k] = not (settings[k] == nil or settings[k]) end,
    has = function(_, k) return settings[k] ~= nil end,
}

local shown, opened = {}, {}
local real = {}  -- name -> module (loaded real code)

local STD = { "assert","collectgarbage","error","getmetatable","ipairs","load","next","pairs","pcall","print","rawequal","rawget","rawset","select","setmetatable","tonumber","tostring","type","xpcall","_VERSION","string","table","math","io","os","debug","coroutine","package","utf8","require","unpack","jit","bit","arg","dofile","loadfile","rawlen","_G","module" }
local allowed = { G_reader_settings = G, DEBUG = newStub("DEBUG"), android = newStub("android"), lfs = nil }

local function strictEnv(modname)
    local env = {}
    for _, k in ipairs(STD) do env[k] = _G[k] end
    env.unpack = table.unpack
    env.table = setmetatable({ unpack = table.unpack }, { __index = table })
    local function wrapNum(lib)
        local w = {}
        for k, v in pairs(lib) do
            if type(v) == "function" then w[k] = function(...) local a = table.pack(...); for i = 1, a.n do a[i] = num(a[i]) end return v(table.unpack(a, 1, a.n)) end else w[k] = v end
        end
        return w
    end
    env.math = wrapNum(math)
    env.tonumber = function(v, ...) if isStub(v) then return 8 end return tonumber(v, ...) end
    env.ipairs = function(t) if isStub(t) then return function() end, t, 0 end return ipairs(t) end
    env.pairs = function(t) if isStub(t) then return function() end, t, nil end return pairs(t) end
    env.type = function(v) if isStub(v) then return "table" end return type(v) end
    local str = {}
    for k, v in pairs(string) do str[k] = v end
    str.format = function(f, ...) local a = table.pack(...); for i = 1, a.n do if isStub(a[i]) then a[i] = 8 end end return string.format(f, table.unpack(a, 1, a.n)) end
    env.string = str
    env.jit = { os = "Linux", arch = "x64" }
    env.bit = { band = function(a, b) return a & b end, bor = function(a, b) return a | b end, bxor = function(a, b) return a ~ b end }
    env.G_reader_settings = G
    env.DEBUG = allowed.DEBUG
    env.require = function(name) return real.require(name, modname) end
    return setmetatable(env, { __index = function(_, k)
        error(("undefined global %q in %s"):format(tostring(k), modname), 2)
    end })
end

local function exists(path) local f = io.open(path); if f then f:close() return true end end

local special = {}
special["gettext"] = function() return setmetatable({}, { __call = function(_, s) return s end, __index = function() return function(s) return s end end }) end
special["ffi/util"] = function() return { template = function(fmt, ...) local a = { ... }; return (fmt:gsub("%%(%d+)", function(i) return tostring(a[tonumber(i)]) end)) end, joinPath = function(a, b) return a .. "/" .. b end, realpath = function(p) return p end, basename = function(p) return p:match("[^/]*$") end, dirname = function(p) return p:match("^(.*)/[^/]*$") or "." end } end
special["logger"] = function() return { dbg = function() end, info = function() end, warn = function() end, err = function() end } end
special["json"] = function() return { encode = function() return "{}" end, decode = function() return {} end } end
special["device"] = function()
    local d = newStub("device")
    d.screen = { scaleBySize = function(_, n) return n end, getWidth = function() return 600 end, getHeight = function() return 800 end, getSize = function() return { w = 600, h = 800 } end, getDPI = function() return 300 end, scaleByDPI = function(_, n) return n end }
    d.isAndroid = function() return false end; d.isKindle = function() return false end; d.hasKeyboard = function() return false end
    d.input = { group = { Alphabet = {}, Back = {}, PgFwd = {}, PgBack = {} } }
    d.home_dir = "/tmp"
    return d
end
special["ui/uimanager"] = function()
    local u = newStub("uimanager")
    u.show = function(_, w) shown[#shown + 1] = w end
    u.close = function() end
    u.scheduleIn = function() end
    u.unschedule = function() end
    u.setDirty = function() end
    u.broadcastEvent = function() end
    u.nextTick = function() end
    return u
end
local function lfsStub() return { dir = function() return function() return nil end end, attributes = function() return nil end, mkdir = function() return true end, currentdir = function() return "/tmp" end } end
special["libs/libkoreader-lfs"] = lfsStub
special["lfs"] = lfsStub
special["datastorage"] = function() return { getDataDir = function() return "/tmp/kosSimData" end, getSettingsDir = function() return "/tmp/kosSimData/settings" end } end

local pathsTried = {}
function real.require(name, from)
    if real[name] ~= nil then return real[name] end
    if special[name] then real[name] = special[name](); return real[name] end
    local candidates = { ROOT .. "/frontend/" .. name .. ".lua" }
    if real._plugin then
        local local_path = ROOT .. "/plugins/" .. real._plugin .. "/" .. name:gsub("^.*/", "") .. ".lua"
        if exists(local_path) then
            real[name] = true
            local f = assert(loadfile(local_path, "t", strictEnv(real._plugin .. "/" .. name)))
            real[name] = f()
            if real[name] == nil then real[name] = true end
            return real[name]
        end
    end
    for _, p in ipairs(candidates) do
        if exists(p) and (name:match("^apps/kos/") or name:match("^datetime") or name == "ffi/blitbuffer_stub") then
            local f = assert(loadfile(p, "t", strictEnv(name)))
            real[name] = true -- guard against cycles while loading
            real[name] = f()
            if real[name] == nil then real[name] = true end
            return real[name]
        end
    end
    -- the app window stub records what the app asks for
    if name == "apps/kos/appwindow" then return real[name] end
    real[name] = newStub(name)
    return real[name]
end

-- AppWindow is replaced by a recorder so apps can be "opened" and their build function run
real["apps/kos/appwindow"] = {
    open = function(_, o) opened[#opened + 1] = o; return newStub("window") end,
    extend = function(self, o) return setmetatable(o or {}, { __index = newStub("appwindow") }) end,
    new = function(_, o) return setmetatable(o or {}, getmetatable(newStub("appwindow"))) end,
}
-- the registry returns an empty list of apps when read here
real["apps/kos/appregistry"] = { getApps = function() return {
    { id = "a", title = "Alpha", description = "First app. More text.", icon_args = { icon = "x" } },
    { id = "b", title = "Beta", description = "Second", icon_args = { icon = "y" } } } end,
    register = function() end, extend = function() return {} end }

local function loadPlugin(dir, file)
    local path = ROOT .. "/plugins/" .. dir .. "/" .. file
    if not exists(path) then return nil, "missing " .. file end
    local f, err = loadfile(path, "t", strictEnv(dir .. "/" .. file))
    if not f then return nil, err end
    local ok, res = pcall(f)
    if not ok then return nil, res end
    return res
end

local function check(dir)
    real._plugin = dir
    local problems = {}
    local meta, err = loadPlugin(dir, "_meta.lua")
    if not meta then problems[#problems + 1] = "_meta: " .. tostring(err) end
    local main, err2 = loadPlugin(dir, "main.lua")
    if main == nil and err2 then problems[#problems + 1] = "main: " .. tostring(err2) end
    local hasApp = (type(meta) == "table" and meta.app) or (type(main) == "table" and main.launchApp)
    if type(main) == "table" and main.launchApp then
        for _, size in ipairs({ { 600, 800 }, { 1200, 800 } }) do
            opened = {}
            local inst = setmetatable({ ui = newStub("ui") }, { __index = main })
            local ok, e = pcall(main.launchApp, inst)
            if not ok then problems[#problems + 1] = "launchApp: " .. tostring(e); break end
            for _, o in ipairs(opened) do
                if type(o.build) == "function" then
                    local okb, eb = pcall(o.build, newStub("window"), size[1], size[2])
                    if not okb then problems[#problems + 1] = ("build %dx%d: %s"):format(size[1], size[2], tostring(eb)); break end
                end
            end
        end
    end
    return problems, hasApp and true or false
end

local function plugins()
    local out = {}
    local p = io.popen("ls " .. ROOT .. "/plugins")
    for d in p:lines() do if d:match("%.koplugin$") then out[#out + 1] = d end end
    p:close()
    return out
end

local wanted = {}
for i = 1, #arg do wanted[arg[i] .. ".koplugin"] = true end
local list = {}
if next(wanted) then for d in pairs(wanted) do list[#list + 1] = d end table.sort(list) else
    -- by default only the plugins that ship in the OS bundle
    local b = io.open(ROOT .. "/tools/kosBundle/build_bundle.py"):read("*a")
    local names = b:match("PLUGINS = %[(.-)%]")
    for n in names:gmatch('"([%w]+)"') do list[#list + 1] = n .. ".koplugin" end
end

local failed = 0
for _, d in ipairs(list) do
    local problems, hasApp = check(d)
    if #problems == 0 then
        print(("ok    %-22s%s"):format(d, hasApp and " (app opened)" or ""))
    else
        failed = failed + 1
        print(("FAIL  %s"):format(d))
        for _, p in ipairs(problems) do print("      " .. p) end
    end
end
print(("%d plugins, %d failed"):format(#list, failed))
os.exit(failed)

--[[--
Themes. One default theme for everything, and any app may override parts of it.

    Theme.default()                       -> the default theme table
    Theme.forApp("name")                  -> default merged with that app's overrides (a table with .face ready to use)
    Theme.set(name, key, value)           -> override one value for one app ("default" changes the default)
    Theme.clear(name, key)                -> remove an override (back to the default)
    Theme.saveAs("night") / Theme.use("night") / Theme.names()     named themes, switch or share
    Theme.export() -> text, Theme.import(text)                     themes as plain text lines "key = value"

Keys: fontSize (pt), lineWidth, cornerRadius, spacing, iconSize (small|medium|large), invert (true|false), accent (black|gray).
Everything is kept in the setting kos_themes = { default = {...}, apps = { name = {...} }, saved = { name = {...} } }.
]]

local T = {}

local BASE = { fontSize = 17, lineWidth = 2, cornerRadius = 6, spacing = 8, iconSize = "medium", invert = false, accent = "black" }
local KEYS = { fontSize = "number", lineWidth = "number", cornerRadius = "number", spacing = "number", iconSize = "string", invert = "boolean", accent = "string" }

local function store()
    local s = G_reader_settings:readSetting("kos_themes")
    if type(s) ~= "table" then s = {}; G_reader_settings:saveSetting("kos_themes", s) end
    s.default = s.default or {}; s.apps = s.apps or {}; s.saved = s.saved or {}
    return s
end

local function merge(...)
    local out = {}
    for _, t in ipairs({ ... }) do for k, v in pairs(t) do out[k] = v end end
    return out
end

function T.default() return merge(BASE, store().default) end

function T.forApp(name)
    local t = merge(BASE, store().default, store().apps[name] or {})
    local ok, Font = pcall(require, "ui/font")
    if ok and Font and Font.getFace then t.face = Font:getFace("cfont", t.fontSize) end
    return t
end

local function check(key, value)
    local want = KEYS[key]
    if not want then return false, "unknown key " .. tostring(key) end
    if type(value) ~= want then return false, key .. " must be a " .. want end
    if want == "number" and (value < 0 or value > 200) then return false, key .. " out of range" end
    if key == "iconSize" and not ({ small = 1, medium = 1, large = 1 })[value] then return false, "iconSize is small, medium or large" end
    if key == "accent" and not ({ black = 1, gray = 1 })[value] then return false, "accent is black or gray" end
    return true
end

function T.set(name, key, value)
    local ok, err = check(key, value); if not ok then return false, err end
    local s = store()
    if name == "default" then s.default[key] = value
    else s.apps[name] = s.apps[name] or {}; s.apps[name][key] = value end
    G_reader_settings:saveSetting("kos_themes", s)
    return true
end

function T.clear(name, key)
    local s = store()
    local t = (name == "default") and s.default or s.apps[name]
    if t then t[key] = nil end
    G_reader_settings:saveSetting("kos_themes", s)
end

function T.saveAs(name) local s = store(); s.saved[name] = merge(s.default); G_reader_settings:saveSetting("kos_themes", s) end
function T.use(name)
    local s = store()
    if not s.saved[name] then return false, "no theme called " .. name end
    s.default = merge(s.saved[name]); G_reader_settings:saveSetting("kos_themes", s); return true
end
function T.names() local t = {}; for k in pairs(store().saved) do t[#t + 1] = k end table.sort(t); return t end

function T.export()
    local lines, keys = {}, {}
    for k in pairs(KEYS) do keys[#keys + 1] = k end
    table.sort(keys)
    local d = T.default()
    for _, k in ipairs(keys) do lines[#lines + 1] = k .. " = " .. tostring(d[k]) end
    return table.concat(lines, "\n")
end

function T.import(text)
    local n = 0
    for k, v in text:gmatch("(%w+)%s*=%s*([^\n]+)") do
        local want = KEYS[k]
        local val = v
        if want == "number" then val = tonumber(v) elseif want == "boolean" then val = (v == "true") end
        if want and T.set("default", k, val) then n = n + 1 end
    end
    return n
end

return T

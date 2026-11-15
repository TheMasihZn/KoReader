--[[--
Replacement files for KOReader's own apps (not add-ons).

A replacement is a Lua file that is used *instead of* a built-in one of the
same module name, for example

    koreader/overrides/files/apps/kos/appwindow.lua   replaces   frontend/apps/kos/appwindow.lua

The built-in files are never touched: switch a replacement off (or delete it)
and the built-in one is back after a restart.

* Loaded at the very start (reader.lua calls `install()`), so everything that
  is required afterwards uses the replacement. Add-ons (plugins) are not
  affected: they live in koreader/plugins.
* Each replacement can be switched on/off (koreader/overrides/state.lua).
* Safety: if KOReader fails to start twice in a row while replacements are on,
  all of them are switched off by themselves and the Updates app tells you.
* A replacement that has a syntax error is ignored (the built-in one is used).

Zips may only replace apps (modules under apps/).

Not replaceable: files already loaded before this runs (setupkoenv, ffi
loaders) and anything that isn't a Lua module (icons, fonts).
]]

local lfs = require("libs/libkoreader-lfs")

local Overrides = {
    loaded = {},       -- module name -> path, replacements in use this run
    started = false,   -- set once KOReader is up
    safe_off = false,  -- true when the safety net switched everything off
}

local data_dir
local function baseDir()
    if not data_dir then
        data_dir = require("datastorage"):getDataDir() .. "/overrides"
    end
    return data_dir
end

function Overrides.dir() return baseDir() end
function Overrides.filesDir() return baseDir() .. "/files" end

local function readState()
    local f = loadfile(baseDir() .. "/state.lua")
    if f then
        local ok, t = pcall(f)
        if ok and type(t) == "table" then return t end
    end
    return {}
end

local function serialize(t)
    local parts = { "return {\n" }
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "table" then
            parts[#parts + 1] = string.format("  [%q] = {", k)
            local ik = {}
            for kk in pairs(v) do ik[#ik + 1] = kk end
            table.sort(ik)
            for _, kk in ipairs(ik) do
                local vv = v[kk]
                parts[#parts + 1] = string.format(" %s = %s,", kk, type(vv) == "string" and string.format("%q", vv) or tostring(vv))
            end
            parts[#parts + 1] = " },\n"
        else
            parts[#parts + 1] = string.format("  [%q] = %s,\n", k, type(v) == "string" and string.format("%q", v) or tostring(v))
        end
    end
    parts[#parts + 1] = "}\n"
    return table.concat(parts)
end

local function writeFile(path, content)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then return false, err end
    f:write(content)
    f:close()
    local ok, rename_err = os.rename(tmp, path)
    if not ok then return false, rename_err end
    return true
end

--- Per-module state: { enabled = bool, bundle = "name", time = n }
function Overrides.state()
    return readState()
end

local function saveState(state)
    lfs.mkdir(baseDir())
    return writeFile(baseDir() .. "/state.lua", serialize(state))
end

-- "apps/kos/appwindow" <-> "<files>/apps/kos/appwindow.lua"
local function validModule(name)
    if type(name) ~= "string" or name == "" then return false end
    if name:find("..", 1, true) or name:sub(1, 1) == "/" then return false end
    return name:match("^[%w_%-%./]+$") ~= nil
end

function Overrides.pathOf(module)
    return Overrides.filesDir() .. "/" .. module .. ".lua"
end

--- Every replacement file on disk: { { module =, path =, enabled =, bundle = } } sorted by name.
function Overrides.list()
    local state = readState()
    local out = {}
    local root = Overrides.filesDir()
    local function walk(dir, prefix)
        if lfs.attributes(dir, "mode") ~= "directory" then return end
        for entry in lfs.dir(dir) do
            if entry ~= "." and entry ~= ".." then
                local full = dir .. "/" .. entry
                local mode = lfs.attributes(full, "mode")
                if mode == "directory" then
                    walk(full, prefix .. entry .. "/")
                elseif mode == "file" and entry:match("%.lua$") then
                    local module = prefix .. entry:sub(1, -5)
                    local st = state[module] or {}
                    table.insert(out, {
                        module = module, path = full,
                        enabled = st.enabled ~= false, -- on unless switched off
                        bundle = st.bundle, time = st.time,
                        active = Overrides.loaded[module] ~= nil,
                    })
                end
            end
        end
    end
    walk(root, "")
    table.sort(out, function(a, b) return a.module < b.module end)
    return out
end

function Overrides.setEnabled(module, enabled)
    local state = readState()
    state[module] = state[module] or {}
    state[module].enabled = enabled and true or false
    return saveState(state)
end

function Overrides.remove(module)
    if not validModule(module) then return false end
    os.remove(Overrides.pathOf(module))
    local state = readState()
    state[module] = nil
    saveState(state)
    return true
end

--- Where the built-in source of a module is (ignores replacements).
function Overrides.builtinPath(module)
    for template in package.path:gmatch("[^;]+") do
        local path = template:gsub("%?", (module:gsub("%%", "%%%%")))
        if not path:find("/overrides/", 1, true) and lfs.attributes(path, "mode") == "file" then
            return path
        end
    end
end

--- Makes an editable copy of a built-in module. Returns the new file's path.
function Overrides.copyBuiltin(module)
    if not validModule(module) then return nil, "bad name" end
    local src = Overrides.builtinPath(module)
    if not src then return nil, "built-in file not found" end
    local f = io.open(src, "rb")
    if not f then return nil, "cannot read the built-in file" end
    local content = f:read("*a")
    f:close()
    local dest = Overrides.pathOf(module)
    -- create the folders
    local acc = Overrides.filesDir()
    lfs.mkdir(baseDir())
    lfs.mkdir(acc)
    local folder = module:match("^(.*)/[^/]+$")
    if folder then
        for part in folder:gmatch("[^/]+") do
            acc = acc .. "/" .. part
            lfs.mkdir(acc)
        end
    end
    if lfs.attributes(dest, "mode") == "file" then return dest end -- keep the user's edits
    local ok, err = writeFile(dest, content)
    if not ok then return nil, err end
    local state = readState()
    state[module] = { enabled = true, bundle = "my edits", time = os.time() }
    saveState(state)
    return dest
end

--- Built-in app modules that can be replaced: everything under frontend/apps and frontend/ui.
function Overrides.builtinModules()
    local seen, out = {}, {}
    local function walk(dir, prefix)
        if lfs.attributes(dir, "mode") ~= "directory" then return end
        for entry in lfs.dir(dir) do
            if entry ~= "." and entry ~= ".." then
                local full = dir .. "/" .. entry
                local mode = lfs.attributes(full, "mode")
                if mode == "directory" then
                    walk(full, prefix .. entry .. "/")
                elseif mode == "file" and entry:match("%.lua$") then
                    local module = prefix .. entry:sub(1, -5)
                    if not seen[module] then
                        seen[module] = true
                        table.insert(out, module)
                    end
                end
            end
        end
    end
    for root in package.path:gmatch("[^;]+") do
        local dir = root:match("^(.*)/%?%.lua$")
        if dir and not dir:find("koreader/overrides", 1, true) and not dir:find("plugins", 1, true) then
            walk(dir .. "/apps", "apps/")
        end
    end
    table.sort(out)
    return out
end

-- Zip layouts accepted (apps/ modules only): frontend/<module>.lua, files/<module>.lua, overrides/files/<module>.lua
local function moduleFromZipPath(path)
    local rest = path:match("^[^/]+/frontend/(.+)$") or path:match("^frontend/(.+)$")
        or path:match("^overrides/files/(.+)$") or path:match("^files/(.+)$")
        or path:match("^[^/]+/files/(.+)$")
    if not rest or not rest:match("%.lua$") then return nil end
    local module = rest:sub(1, -5)
    if not validModule(module) then return nil end
    -- Plugins are add-ons: the App installer handles those.
    if module:match("%.koplugin") then return nil end
    -- Apps only (frontend/apps/…): the base libraries stay as built.
    if module:sub(1, 5) ~= "apps/" then return nil end
    return module
end

--- Looks inside a zip. Returns { modules = {…}, name = "…" } or nil if it isn't an update zip.
function Overrides.inspectZip(zip_file)
    local Archiver = require("ffi/archiver")
    local arc = Archiver.Reader:new()
    if not arc:open(zip_file) then return nil end
    local modules = {}
    for entry in arc:iterate() do
        if entry.mode == "file" then
            local m = moduleFromZipPath(entry.path)
            if m then table.insert(modules, { module = m, zip_path = entry.path }) end
        end
    end
    arc:close()
    if #modules == 0 then return nil end
    table.sort(modules, function(a, b) return a.module < b.module end)
    local filename = zip_file:match("([^/]+)$") or zip_file
    local name = filename:gsub("%.[Zz][Ii][Pp]$", "")
    return { modules = modules, name = name }
end

--- Installs the replacement files from a zip. Existing ones are kept as "<name>.lua.old".
-- Returns the number of files installed, or nil + error.
function Overrides.installZip(zip_file, info)
    info = info or Overrides.inspectZip(zip_file)
    if not info then return nil, "not an update zip" end
    local Archiver = require("ffi/archiver")
    local arc = Archiver.Reader:new()
    if not arc:open(zip_file) then return nil, "cannot open the zip" end
    lfs.mkdir(baseDir())
    lfs.mkdir(Overrides.filesDir())
    local state = readState()
    local count = 0
    for _, m in ipairs(info.modules) do
        local dest = Overrides.pathOf(m.module)
        local acc = Overrides.filesDir()
        local folder = m.module:match("^(.*)/[^/]+$")
        if folder then
            for part in folder:gmatch("[^/]+") do
                acc = acc .. "/" .. part
                lfs.mkdir(acc)
            end
        end
        local tmp = dest .. ".new"
        if arc:extractToPath(m.zip_path, tmp) then
            -- A file with a syntax error would only be ignored later; refuse it now.
            local chunk, err = loadfile(tmp)
            if chunk then
                if lfs.attributes(dest, "mode") == "file" then
                    os.remove(dest .. ".old")
                    os.rename(dest, dest .. ".old")
                end
                os.rename(tmp, dest)
                state[m.module] = { enabled = true, bundle = info.name, time = os.time() }
                count = count + 1
            else
                os.remove(tmp)
                require("logger").warn("Overrides: skipped", m.module, err)
            end
        end
    end
    arc:close()
    saveState(state)
    return count
end

--- Restores the `.old` copy of a replacement (what it was before the last update).
function Overrides.restoreOld(module)
    local path = Overrides.pathOf(module)
    if lfs.attributes(path .. ".old", "mode") ~= "file" then return false end
    os.remove(path)
    return os.rename(path .. ".old", path) and true or false
end

function Overrides.hasOld(module)
    return lfs.attributes(Overrides.pathOf(module) .. ".old", "mode") == "file"
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------

--- Called from reader.lua right after setupkoenv: puts the replacements in front of the built-in files.
function Overrides.install()
    local ok, err = pcall(function()
        local dir = baseDir()
        if lfs.attributes(Overrides.filesDir(), "mode") ~= "directory" then return end

        -- Safety net: the last two starts never got going while replacements were on.
        local marker = dir .. "/starting"
        local tries = 0
        local f = io.open(marker, "r")
        if f then
            tries = tonumber(f:read("*a")) or 1
            f:close()
        end
        if tries >= 2 then
            Overrides.safe_off = true
            writeFile(dir .. "/switched-off.txt",
                os.date("%Y-%m-%d %H:%M") .. ": KOReader didn't finish starting twice with replacement files on, so they were all switched off.\n")
            local state = readState()
            for _, item in ipairs(Overrides.list()) do
                state[item.module] = state[item.module] or {}
                state[item.module].enabled = false
            end
            saveState(state)
            os.remove(marker)
            tries = 0
        end

        local state = readState()
        local replacements = {}
        local any = false
        for _, item in ipairs(Overrides.list()) do
            if item.enabled then
                replacements[item.module] = item.path
                any = true
            end
        end
        if not any then
            os.remove(marker)
            return
        end
        writeFile(marker, tostring(tries + 1))

        local loaders = package.loaders or package.searchers
        table.insert(loaders, 2, function(name)
            local path = replacements[name:gsub("%.", "/")] or replacements[name]
            if not path then return nil end
            local chunk, load_err = loadfile(path)
            if not chunk then
                io.stderr:write("[overrides] ignoring ", path, ": ", tostring(load_err), "\n")
                return nil -- the built-in file is used
            end
            Overrides.loaded[name:gsub("%.", "/")] = path
            return chunk
        end)
        io.write(" [*] Replacement files in use: ")
        local n = 0
        for _ in pairs(replacements) do n = n + 1 end
        io.write(tostring(n), "\n")
    end)
    if not ok then
        io.stderr:write("[overrides] could not start: ", tostring(err), "\n")
    end
end

--- Call once KOReader is up and running (a few seconds after start): clears the safety counter.
function Overrides.markStarted()
    if Overrides.started then return end
    Overrides.started = true
    os.remove(baseDir() .. "/starting")
end

return Overrides

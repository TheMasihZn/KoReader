-- KOReader OS bundle: ONE file that installs everything.
-- Put it in koreader/patches/ (named 2-0-kos-bundle.lua) and restart KOReader.
-- On start it unpacks its files into the koreader folder (once per version), then
-- switches them on. It never changes KOReader's own files: delete this file and
-- the koreader/overrides folder to go back.
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local data = DataStorage:getDataDir()
local VERSION = "@@VERSION@@"

local FILES = {
@@FILES@@
}

local function mkdirs(path)
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        lfs.mkdir(acc)
    end
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local function unpack_files()
    local written = 0
    for rel, content in pairs(FILES) do
        local dest = data .. "/" .. rel
        local folder = dest:match("^(.*)/[^/]+$")
        mkdirs(folder)
        local old = readAll(dest)
        if old ~= content then
            if old then -- keep what was there, e.g. your own edits
                os.remove(dest .. ".old")
                os.rename(dest, dest .. ".old")
            end
            local f = io.open(dest .. ".new", "wb")
            if f then
                f:write(content)
                f:close()
                os.rename(dest .. ".new", dest)
                written = written + 1
            end
        end
    end
    return written
end

local ok_unpack, written = pcall(function()
    if G_reader_settings:readSetting("kos_bundle_version") == VERSION then return 0 end
    local n = unpack_files()
    G_reader_settings:saveSetting("kos_bundle_version", VERSION)
    G_reader_settings:flush()
    return n
end)
if not ok_unpack then io.stderr:write("[kos-bundle] unpack failed: ", tostring(written), "\n") end

-- 1. Replacement app files and add-ons ------------------------------------
local boot = data .. "/overrides/boot/overrides.lua"
if not package.loaded["apps/kos/overrides"] and lfs.attributes(boot, "mode") == "file" then
    local chunk, err = loadfile(boot)
    if chunk then package.preload["apps/kos/overrides"] = chunk
    else io.stderr:write("[kos-bundle] ", tostring(err), "\n") end
end
local ok, Overrides = pcall(require, "apps/kos/overrides")
if ok and type(Overrides) == "table" then
    local ok2, err = pcall(function()
        Overrides.install()
        Overrides.hookPlugins()
    end)
    if not ok2 then io.stderr:write("[kos-bundle] ", tostring(err), "\n") end
else
    io.stderr:write("[kos-bundle] ", tostring(Overrides), "\n")
end

-- 2. The Paste + audio row on top of every keyboard ----------------------------
pcall(function()
    local InputDialog = require("ui/widget/inputdialog")
    if InputDialog.kos_toolbar_builtin or InputDialog._kos_toolbar_hooked then return end
    InputDialog._kos_toolbar_hooked = true
    local orig_init = InputDialog.init
    InputDialog.init = function(self, ...)
        if not self._kos_toolbar_done then
            self._kos_toolbar_done = true
            if not self.readonly and self.kos_toolbar ~= false and G_reader_settings:nilOrTrue("kos_keyboard_toolbar") then
                local okt, KT = pcall(require, "apps/kos/keyboardtoolbar")
                if okt then
                    self.buttons = self.buttons or {}
                    table.insert(self.buttons, KT.row{ input = self, audio = self.kos_toolbar_audio })
                end
            end
        end
        return orig_init(self, ...)
    end
end)

-- 3. Icons used by the new apps -----------------------------------------------
-- (copied to koreader/icons/ above)

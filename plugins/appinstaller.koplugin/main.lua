--[[--
App installer for KOReader OS.

* Tap a .zip in the file browser: if it contains a KOReader plugin/app
  (a `something.koplugin/` folder with a `main.lua`, at any depth, or
  `main.lua` + `_meta.lua` at the top of the zip), you're offered to install it
  into koreader/plugins/. Any other zip opens as before.
* Long-press a .zip: "Install app" is in the file menu too.
* Open "App installer" from the home screen to see installed apps and remove them.

Installing never runs code from the zip: it only extracts files. The new app
runs after KOReader restarts.
]]

local Archiver = require("ffi/archiver")
local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local AppInstaller = WidgetContainer:extend{
    name = "appinstaller",
}

local function pluginsDir()
    return DataStorage:getDataDir() .. "/plugins"
end

local function isZip(file)
    return type(file) == "string" and file:lower():match("%.zip$") ~= nil
end

-- A plugin folder name may only contain safe characters.
local function cleanName(name)
    name = name:gsub("%.koplugin$", ""):gsub("[^%w_%-%.]", "")
    if name == "" or name:sub(1, 1) == "." then return nil end
    return name
end

--- Looks inside a zip for plugins, without extracting or running anything.
-- @treturn table|nil list of { name = "foo", prefix = "path/in/zip/foo.koplugin/", files = n }
function AppInstaller.inspect(zip_file)
    local arc = Archiver.Reader:new()
    if not arc:open(zip_file) then
        return nil
    end
    local roots, order = {}, {}
    local has_top_main, has_top_meta, top_files = false, false, 0
    for entry in arc:iterate() do
        local path = entry.path
        if entry.mode == "file" then
            -- "anything/foo.koplugin/…" (also catches GitHub's "Repo-main/foo.koplugin/…")
            local prefix, folder = path:match("^(.-([^/]+%.koplugin)/)")
            if prefix then
                local root = roots[prefix]
                if not root then
                    root = { name = cleanName(folder), prefix = prefix, files = 0, has_main = false }
                    roots[prefix] = root
                    table.insert(order, root)
                end
                root.files = root.files + 1
                if path == prefix .. "main.lua" then
                    root.has_main = true
                end
            else
                top_files = top_files + 1
                if path == "main.lua" then has_top_main = true end
                if path == "_meta.lua" then has_top_meta = true end
            end
        end
    end
    arc:close()

    local found = {}
    for _, root in ipairs(order) do
        if root.has_main and root.name then
            table.insert(found, root)
        end
    end
    -- A zip of a plugin's contents, without the .koplugin folder: name it after the zip.
    if #found == 0 and has_top_main and has_top_meta then
        local _, filename = util.splitFilePathName(zip_file)
        local name = cleanName(filename:gsub("%.[Zz][Ii][Pp]$", ""):gsub("%-main$", ""):gsub("%-master$", ""))
        if name then
            table.insert(found, { name = name, prefix = "", files = top_files, has_main = true })
        end
    end
    return #found > 0 and found or nil
end

local function extractPlugin(zip_file, plugin, dest_dir)
    local arc = Archiver.Reader:new()
    if not arc:open(zip_file) then
        return false, _("Could not open the zip file.")
    end
    local ok_all, count = true, 0
    for entry in arc:iterate() do
        local path = entry.path
        if entry.mode == "file" and path:sub(1, #plugin.prefix) == plugin.prefix then
            local rel = path:sub(#plugin.prefix + 1)
            -- Refuse anything that would escape the plugin folder.
            if rel ~= "" and not rel:find("..", 1, true) and rel:sub(1, 1) ~= "/" then
                if arc:extractToPath(path, dest_dir .. "/" .. rel) then
                    count = count + 1
                else
                    ok_all = false
                    logger.warn("AppInstaller: failed to extract", path, arc.err)
                end
            end
        end
    end
    arc:close()
    if not ok_all or count == 0 then
        return false, _("Some files could not be extracted.")
    end
    if lfs.attributes(dest_dir .. "/main.lua", "mode") ~= "file" then
        return false, _("The app has no main.lua.")
    end
    return true
end

--- Installs one plugin from a zip into koreader/plugins/<name>.koplugin.
-- An existing copy is only replaced once the new one extracted fine.
function AppInstaller.install(zip_file, plugin)
    local dir = pluginsDir()
    util.makePath(dir)
    local dest = dir .. "/" .. plugin.name .. ".koplugin"
    local staging = dest .. ".installing"
    local backup = dest .. ".old"
    if lfs.attributes(staging, "mode") then ffiUtil.purgeDir(staging) end
    if lfs.attributes(backup, "mode") then ffiUtil.purgeDir(backup) end

    local ok, err = extractPlugin(zip_file, plugin, staging)
    if not ok then
        if lfs.attributes(staging, "mode") then ffiUtil.purgeDir(staging) end
        return false, err
    end
    if lfs.attributes(dest, "mode") then
        local renamed, rerr = os.rename(dest, backup)
        if not renamed then
            ffiUtil.purgeDir(staging)
            return false, T(_("Could not replace the old version: %1"), tostring(rerr))
        end
    end
    local moved, merr = os.rename(staging, dest)
    if not moved then
        if lfs.attributes(backup, "mode") then os.rename(backup, dest) end
        ffiUtil.purgeDir(staging)
        return false, T(_("Could not install: %1"), tostring(merr))
    end
    if lfs.attributes(backup, "mode") then ffiUtil.purgeDir(backup) end
    return true
end

local function afterInstall(names)
    UIManager:askForRestart(T(_("Installed: %1\n\nRestart KOReader to start using it."), table.concat(names, ", ")))
end

--- Asks before installing what a zip contains. Returns false if it's not an app zip.
function AppInstaller.offer(zip_file, open_normally)
    local found = AppInstaller.inspect(zip_file)
    if not found then
        return false
    end
    local lines, names = {}, {}
    for _, p in ipairs(found) do
        local exists = lfs.attributes(pluginsDir() .. "/" .. p.name .. ".koplugin", "mode") ~= nil
        table.insert(lines, T(exists and _("• %1 (%2 files, replaces the installed one)") or _("• %1 (%2 files)"),
            p.name, p.files))
        table.insert(names, p.name)
    end
    local text = T(_("This zip contains:\n%1\n\nInstall into %2?\n\nApps can do anything KOReader can. Only install apps you trust."),
        table.concat(lines, "\n"), BD.dirpath(pluginsDir()))
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Install"),
        ok_callback = function()
            local installed, errors = {}, {}
            for _, p in ipairs(found) do
                local ok, err = AppInstaller.install(zip_file, p)
                if ok then
                    table.insert(installed, p.name)
                else
                    table.insert(errors, p.name .. ": " .. tostring(err))
                end
            end
            if #errors > 0 then
                UIManager:show(InfoMessage:new{
                    text = T(_("Install failed:\n%1"), table.concat(errors, "\n")),
                    icon = "notice-warning",
                })
            end
            if #installed > 0 then
                afterInstall(installed)
            end
        end,
        other_buttons = open_normally and {{
            { text = _("Open as file"), callback = open_normally },
        }} or nil,
        other_buttons_first = true,
    })
    return true
end

-- Tapping a zip anywhere (file browser, history, collections) goes through here.
if not filemanagerutil._appinstaller_wrapped then
    filemanagerutil._appinstaller_wrapped = true
    local orig_openFile = filemanagerutil.openFile
    filemanagerutil.openFile = function(ui, file, ...)
        if isZip(file) and G_reader_settings:nilOrTrue("appinstaller_on_tap") then
            local args = { n = select("#", ...), ... }
            local ok, offered = pcall(AppInstaller.offer, file, function()
                orig_openFile(ui, file, unpack(args, 1, args.n))
            end)
            if ok and offered then
                return
            end
            if not ok then
                logger.warn("AppInstaller: could not inspect", file, offered)
            end
        end
        return orig_openFile(ui, file, ...)
    end
end

function AppInstaller:init()
    if self.ui.addFileDialogButtons then
        self.ui:addFileDialogButtons("appinstaller", function(file, is_file)
            if is_file and isZip(file) then
                return {
                    {
                        text = _("Install app"),
                        callback = function()
                            local fc = self.ui.file_chooser
                            if fc and fc.file_dialog then
                                UIManager:close(fc.file_dialog)
                            end
                            if not AppInstaller.offer(file) then
                                UIManager:show(InfoMessage:new{
                                    text = _("No app found in this zip.\n\nAn app zip contains a folder ending in .koplugin with a main.lua inside."),
                                })
                            end
                        end,
                    },
                }
            end
        end)
    end
end

-- The "App installer" app: installed apps, tap one to remove it.
function AppInstaller:launchApp()
    local dir = pluginsDir()
    local items = {}
    if lfs.attributes(dir, "mode") == "directory" then
        for entry in lfs.dir(dir) do
            if entry:match("%.koplugin$") and lfs.attributes(dir .. "/" .. entry, "mode") == "directory" then
                table.insert(items, entry:sub(1, -10))
            end
        end
    end
    table.sort(items)
    local menu
    local item_table = {
        {
            text = _("How to install: tap a .zip in Files"),
            dim = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = T(_("Put an app's .zip anywhere on your device and tap it in Files.\n\nApps are installed into:\n%1"), BD.dirpath(dir)),
                })
            end,
        },
        {
            text = G_reader_settings:nilOrTrue("appinstaller_on_tap")
                and _("Tapping a zip offers to install: on") or _("Tapping a zip offers to install: off"),
            callback = function()
                G_reader_settings:flipNilOrTrue("appinstaller_on_tap")
                UIManager:close(menu)
                self:launchApp()
            end,
        },
    }
    for _, name in ipairs(items) do
        table.insert(item_table, {
            text = name,
            mandatory = _("Remove"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Remove %1?\n\nIts files in %2 will be deleted. Its settings are kept."), name, BD.dirpath(dir)),
                    ok_text = _("Remove"),
                    ok_callback = function()
                        local ok = ffiUtil.purgeDir(dir .. "/" .. name .. ".koplugin")
                        UIManager:close(menu)
                        if ok then
                            UIManager:askForRestart(T(_("%1 was removed.\n\nRestart KOReader to finish."), name))
                        else
                            UIManager:show(InfoMessage:new{ text = T(_("Could not remove %1."), name), icon = "notice-warning" })
                        end
                    end,
                })
            end,
        })
    end
    menu = Menu:new{
        title = _("App installer"),
        subtitle = T(_("%1 installed in %2"), #items, BD.dirpath(dir)),
        item_table = item_table,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

return AppInstaller

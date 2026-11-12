--[[--
Studio: a small IDE for KOReader OS apps, running on the device.

* Projects: every app/plugin in koreader/plugins/, plus "New app" from a template.
* A project: its files (tap to edit in the Text editor), Check code (compiles
  every .lua file without running it and lists errors with line numbers),
  Package as .zip (shareable, installable with App installer), View log,
  Restart KOReader.

It is an AppWindow app, so it also runs in a split view: Studio on one side,
the app you're writing on the other.
]]

local AppWindow -- required lazily, see doc/Apps.md
local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local Studio = WidgetContainer:extend{
    name = "studio",
    project = nil, -- name of the open project, nil = project list
}

local function pluginsDir()
    return DataStorage:getDataDir() .. "/plugins"
end

local function projectDir(name)
    return pluginsDir() .. "/" .. name .. ".koplugin"
end

-- Files of a project, relative paths, sorted; folders are walked (not too deep).
local function listFiles(root)
    local files = {}
    local function walk(dir, rel, depth)
        if depth > 4 then return end
        for entry in lfs.dir(dir) do
            if entry ~= "." and entry ~= ".." and entry:sub(1, 1) ~= "." then
                local full = dir .. "/" .. entry
                local mode = lfs.attributes(full, "mode")
                local r = rel == "" and entry or (rel .. "/" .. entry)
                if mode == "directory" then
                    walk(full, r, depth + 1)
                elseif mode == "file" then
                    table.insert(files, r)
                end
            end
        end
    end
    if lfs.attributes(root, "mode") == "directory" then
        walk(root, "", 0)
    end
    table.sort(files)
    return files
end

--- Compiles (does not run) every .lua file of a project.
-- @treturn table list of error strings, empty when everything compiles
function Studio.checkProject(root)
    local errors = {}
    for _, rel in ipairs(listFiles(root)) do
        if rel:match("%.lua$") then
            local fn, err = loadfile(root .. "/" .. rel)
            if not fn then
                -- "path/file.lua:12: message" -> "file.lua:12: message"
                table.insert(errors, (tostring(err):gsub("^.-([^/]+%.lua:)", "%1")))
            end
        end
    end
    return errors
end

local function templateMeta(title)
    return string.format([==[
local _ = require("gettext")
return {
    fullname = _(%q),
    description = _([[A KOReader OS app.]]),
    app = {
        icon = "appbar.typeset", -- a KOReader icon name, or a file in this folder, e.g. "icon.svg"
    },
}
]==], title)
end

local function templateMain(name, title)
    return string.format([==[
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextBoxWidget = require("ui/widget/textboxwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local App = WidgetContainer:extend{
    name = %q, -- must match the folder name without .koplugin
}

-- Called when the app is opened from the home screen.
function App:launchApp()
    local AppWindow = require("apps/kos/appwindow")
    AppWindow:open{
        title = _(%q),
        -- Called again whenever the window size changes: lay out for width x height.
        build = function(window, width, height)
            return CenterContainer:new{
                dimen = Geom:new{ w = width, h = height },
                TextBoxWidget:new{
                    text = _("Hello from your new app.\n\nEdit main.lua in Studio to change this."),
                    face = Font:getFace("cfont", 22),
                    width = math.floor(width * 0.8),
                    alignment = "center",
                },
            }
        end,
    }
end

return App
]==], name, title)
end

local function writeFile(path, content)
    local f, err = io.open(path, "w")
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

function Studio:launchApp()
    AppWindow = AppWindow or require("apps/kos/appwindow")
    self.project = nil
    self.window = AppWindow:open{
        title = _("Studio"),
        build = function(window, width, height) return self:buildList(window, width, height) end,
        on_close = function() self.window = nil end,
    }
end

function Studio:refresh()
    if not self.window then return end
    if self.project then
        self.window:setTitle(T(_("Studio · %1"), self.project))
    else
        self.window:setTitle(_("Studio"))
    end
    self.window:refresh()
end

function Studio:buildList(window, width, height)
    local items = self.project and self:projectItems() or self:projectListItems()
    return Menu:new{
        width = width,
        height = height,
        no_title = true,
        is_borderless = true,
        is_popout = false,
        item_table = items,
        show_parent = window,
    }
end

function Studio:projectListItems()
    local items = {
        {
            text = _("+ New app"),
            bold = true,
            callback = function() self:newAppDialog() end,
        },
        {
            text = Device:isAndroid() and _("Logs (Android & crash.log)") or _("View log"),
            callback = function() self:showLogMenu() end,
            separator = true,
        },
    }
    local dir = pluginsDir()
    if lfs.attributes(dir, "mode") == "directory" then
        local names = {}
        for entry in lfs.dir(dir) do
            if entry:match("%.koplugin$") and lfs.attributes(dir .. "/" .. entry, "mode") == "directory" then
                table.insert(names, entry:sub(1, -10))
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            table.insert(items, {
                text = name,
                mandatory = "›",
                callback = function()
                    self.project = name
                    self:refresh()
                end,
            })
        end
    end
    return items
end

function Studio:projectItems()
    local root = projectDir(self.project)
    local items = {
        { text = _("‹ All projects"), callback = function()
            self.project = nil
            self:refresh()
        end },
        { text = _("Check code"), bold = true, callback = function() self:showCheck(root) end },
        { text = _("New file"), callback = function() self:newFileDialog(root) end },
        { text = _("Package as .zip"), callback = function() self:package(self.project) end },
        { text = Device:isAndroid() and _("Logs (Android & crash.log)") or _("View log"), callback = function() self:showLogMenu() end },
        { text = _("Restart KOReader to run changes"), callback = function()
            UIManager:askForRestart(_("Restart KOReader to load your changes?"))
        end, separator = true },
    }
    for _, rel in ipairs(listFiles(root)) do
        local size = lfs.attributes(root .. "/" .. rel, "size") or 0
        table.insert(items, {
            text = rel,
            mandatory = util.getFriendlySize(size),
            callback = function() self:editFile(root .. "/" .. rel) end,
        })
    end
    return items
end

------------------------------------------------------------------------
-- Actions
------------------------------------------------------------------------

function Studio:editFile(path)
    local editor = self.ui and self.ui.texteditor
    if not editor then
        UIManager:show(InfoMessage:new{
            text = _("The Text editor plugin is needed to edit files. Turn it on in Plugin management."),
        })
        return
    end
    editor:openFile(path, function()
        -- After editing a Lua file, tell right away if it no longer compiles.
        if path:match("%.lua$") then
            local fn, err = loadfile(path)
            if not fn then
                UIManager:show(InfoMessage:new{
                    text = T(_("This file has an error:\n%1"), (tostring(err):gsub("^.-([^/]+%.lua:)", "%1"))),
                    icon = "notice-warning",
                })
            end
        end
        self:refresh()
    end)
end

function Studio:showCheck(root)
    local errors = Studio.checkProject(root)
    if #errors == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No errors: every .lua file compiles.\n\nRestart KOReader to run your changes."),
            timeout = 3,
        })
    else
        UIManager:show(TextViewer:new{
            title = T(_("%1 errors"), #errors),
            text = table.concat(errors, "\n\n"),
        })
    end
end

-- Logs are read from the end: open the viewer scrolled to the bottom.
local function showTextAtEnd(title, text)
    local viewer = TextViewer:new{ title = title, text = text }
    UIManager:show(viewer)
    if viewer.scroll_widget and viewer.scroll_widget.scrollToBottom then
        pcall(viewer.scroll_widget.scrollToBottom, viewer.scroll_widget)
    end
end

--- Android system log (logcat). An app may read its own process' log
-- without any permission, which covers everything KOReader and its
-- plugins print through logger, plus Android's own messages about it.
local LOG_FILTERS = {
    { id = "koreader", text = _("KOReader & plugins") },
    { id = "problems", text = _("Errors & warnings") },
    { id = "all", text = _("Everything") },
}

function Studio:readAndroidLog(filter)
    local p = io.popen("logcat -d -v time -t 2000 2>&1")
    if not p then return nil end
    local tag = "KOReader"
    local ok_android, android = pcall(require, "android")
    if ok_android and type(android) == "table" and android.log_name then
        tag = android.log_name
    end
    local lines = {}
    for line in p:lines() do
        local keep
        if filter == "koreader" then
            keep = line:find("/" .. tag, 1, true) or line:find("luajit", 1, true)
        elseif filter == "problems" then
            keep = line:find(" [EWF]/") ~= nil
        else
            keep = true
        end
        if keep then table.insert(lines, line) end
    end
    p:close()
    return lines
end

function Studio:showAndroidLog(filter)
    filter = filter or "koreader"
    local lines = self:readAndroidLog(filter)
    if not lines then
        UIManager:show(InfoMessage:new{ text = _("Could not read the Android log."), icon = "notice-warning" })
        return
    end
    local name = filter
    for _, f in ipairs(LOG_FILTERS) do
        if f.id == filter then name = f.text end
    end
    if #lines == 0 then
        UIManager:show(InfoMessage:new{ text = T(_("No log lines for: %1"), name) })
        return
    end
    -- Keep it light on e-ink: the last 600 lines are enough to debug.
    local first = math.max(1, #lines - 599)
    showTextAtEnd(T(_("Android log · %1"), name), table.concat(lines, "\n", first))
end

function Studio:showLogMenu()
    local dialog
    local rows = {}
    if Device:isAndroid() then
        local row = {}
        for _, f in ipairs(LOG_FILTERS) do
            table.insert(row, { text = f.text, callback = function()
                UIManager:close(dialog)
                self:showAndroidLog(f.id)
            end })
        end
        table.insert(rows, row)
        table.insert(rows, {
            { text = _("Clear Android log"), callback = function()
                UIManager:close(dialog)
                os.execute("logcat -c")
                UIManager:show(InfoMessage:new{ text = _("Android log cleared. Reproduce the problem, then open the log again."), timeout = 3 })
            end },
        })
    end
    table.insert(rows, {
        { text = "crash.log", callback = function()
            UIManager:close(dialog)
            self:showLog()
        end },
    })
    dialog = ButtonDialog:new{ title = _("Logs"), buttons = rows }
    UIManager:show(dialog)
end

function Studio:showLog()
    local log = DataStorage:getDataDir() .. "/crash.log"
    local f = io.open(log, "r")
    if not f then
        UIManager:show(InfoMessage:new{
            text = _("No crash.log here.\n\nOn Android, KOReader logs to the system log instead: use Logs → KOReader & plugins."),
        })
        return
    end
    local content = f:read("*all") or ""
    f:close()
    -- The end of the log is what matters.
    local max = 20000
    if #content > max then
        content = "…\n" .. content:sub(-max)
    end
    showTextAtEnd("crash.log", content)
end

function Studio:package(name)
    local Archiver = require("ffi/archiver")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local errors = Studio.checkProject(projectDir(name))
    local function doPackage()
        local out_dir = filemanagerutil.getHomeFolder() or DataStorage:getDataDir()
        local zip = out_dir .. "/" .. name .. ".zip"
        local writer = Archiver.Writer:new{}
        local ok = writer:open(zip, "zip")
        if ok then
            ok = writer:addPath(name .. ".koplugin", projectDir(name), true)
            writer:close()
        end
        if ok then
            UIManager:show(InfoMessage:new{
                text = T(_("Packaged:\n%1\n\nAnyone with KOReader OS can tap it in Files to install it."), BD.filepath(zip)),
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Could not create the zip: %1"), tostring(writer.err)),
                icon = "notice-warning",
            })
        end
    end
    if #errors > 0 then
        UIManager:show(ConfirmBox:new{
            text = T(_("%1 files have errors. Package anyway?"), #errors),
            ok_text = _("Package"),
            ok_callback = doPackage,
        })
    else
        doPackage()
    end
end

function Studio:newAppDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("New app"),
        input_hint = "notes",
        description = _("Folder name: lowercase letters, digits and _ only."),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Create"), is_enter_default = true, callback = function()
                local name = util.trim(dialog:getInputText()):lower()
                if not name:match("^[a-z][a-z0-9_]*$") then
                    UIManager:show(InfoMessage:new{ text = _("Use lowercase letters, digits and _, starting with a letter.") })
                    return
                end
                local dir = projectDir(name)
                if lfs.attributes(dir, "mode") then
                    UIManager:show(InfoMessage:new{ text = T(_("%1 already exists."), name) })
                    return
                end
                UIManager:close(dialog)
                util.makePath(dir)
                local title = name:sub(1, 1):upper() .. name:sub(2):gsub("_", " ")
                local ok1 = writeFile(dir .. "/_meta.lua", templateMeta(title))
                local ok2 = writeFile(dir .. "/main.lua", templateMain(name, title))
                if not (ok1 and ok2) then
                    UIManager:show(InfoMessage:new{ text = _("Could not write the app files."), icon = "notice-warning" })
                    return
                end
                self.project = name
                self:refresh()
                UIManager:askForRestart(T(_("%1 created.\n\nRestart KOReader to see it on the home screen."), title))
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Studio:newFileDialog(root)
    local dialog
    dialog = InputDialog:new{
        title = _("New file"),
        input_hint = "helpers.lua",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Create"), is_enter_default = true, callback = function()
                local rel = util.trim(dialog:getInputText())
                if rel == "" or rel:find("..", 1, true) or rel:sub(1, 1) == "/" then return end
                UIManager:close(dialog)
                local path = root .. "/" .. rel
                local dir = path:match("(.*)/")
                if dir then util.makePath(dir) end
                if not lfs.attributes(path, "mode") then
                    writeFile(path, rel:match("%.lua$") and "-- " .. rel .. "\n" or "")
                end
                self:refresh()
                self:editFile(path)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return Studio

--[[--
Finds the apps shown on the KOReader OS home screen.

An app is either built in (a Dispatcher action) or an ordinary plugin that
declares an `app` table, in its `main.lua` or its `_meta.lua`:

    app = {
        title = _("Hello"),          -- default: the plugin's fullname from _meta.lua
        icon = "appbar.typeset",     -- a KOReader icon name, or a file in your plugin folder ("icon.svg")
        description = _("…"),        -- default: the plugin's description from _meta.lua
        order = 50,                  -- optional: lower comes first (built-ins use 1-20)
    }

and how to start it, the first that exists wins:

    function MyPlugin:launchApp() … end   -- usually opens an AppWindow
    app.event = "ShowMyThing"              -- or: send this event (for plugins that already have one)
    app.action = "my_dispatcher_action"    -- or: run this Dispatcher action

Only plugins loaded in the current view are listed: a plugin marked
`is_doc_only` only shows up while a book is open.
]]

local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local PluginLoader = require("pluginloader")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AppRegistry = {}

-- Built-in apps. `where`: nil = everywhere, "filemanager" or "reader" = only there.
AppRegistry.builtins = {
    { id = "continue", title = _("Continue"), icon = "book.opened", action = "open_previous_document", where = "filemanager", order = 1,
      description = _("Open the last book you were reading.") },
    { id = "files", title = _("Files"), icon = "appbar.filebrowser", action = "filemanager", order = 2,
      description = _("Browse folders and books.") },
    { id = "history", title = _("History"), icon = "appbar.pageview", action = "history", order = 3,
      description = _("Books you opened recently.") },
    { id = "favorites", title = _("Favorites"), icon = "star.empty", action = "favorites", order = 4,
      description = _("Your favorite books.") },
    { id = "collections", title = _("Collections"), icon = "bookmark", action = "collections", order = 5,
      description = _("Your book collections.") },
    { id = "search", title = _("Search"), icon = "appbar.search", action = "file_search", where = "filemanager", order = 6,
      description = _("Find files by name.") },
    { id = "dictionary", title = _("Dictionary"), icon = "appbar.textsize", action = "dictionary_lookup", order = 7,
      description = _("Look up a word.") },
    { id = "wikipedia", title = _("Wikipedia"), icon = "appbar.navigation", action = "wikipedia_lookup", order = 8,
      description = _("Look up an article.") },
    { id = "audio", title = _("Audio"), icon = "kos.audio", order = 9,
      description = _("Play again what any app read aloud (Gemma, messengers…). Plays through Bluetooth when connected."),
      launch = function() require("apps/kos/audiopipeline").showRecent() end },
    { id = "windows", title = _("Windows"), icon = "column.two", order = 10,
      description = _("All open app windows: switch between them, open another window of an app, or put them side by side."),
      launch = function() require("apps/kos/windows").showSwitcher() end },
    { id = "settings", title = _("Settings"), icon = "appbar.settings", action = "show_menu", order = 20,
      description = _("The KOReader menu.") },
}

-- Plugins that ship with KOReader but don't declare an `app` table themselves.
-- Wrapped here so their code stays untouched (easier to merge upstream).
AppRegistry.plugin_wrappers = {
    texteditor = { title = _("Text editor"), icon = "edit", order = 40,
        launch = function(p) p:chooseFile() end },
    terminal = { title = _("Terminal"), icon = "appbar.tools", order = 41, event = "TerminalStart" },
    SSH = { title = _("SSH server"), icon = "wifi", order = 42, event = "ToggleSSHServer",
        description = _("Start or stop the SSH server: copy files and get a shell from your computer.") },
    httpinspector = { title = _("HTTP inspector"), icon = "appbar.search", order = 43,
        description = _("Browse KOReader's internal objects from a web browser. Only on networks you trust."),
        launch = function(p)
            local InfoMsg = require("ui/widget/infomessage")
            if p:isRunning() then
                p:stop()
                UIManager:show(InfoMsg:new{ text = _("HTTP inspector stopped."), timeout = 2 })
            else
                p:start()
            end
        end },
    qrclipboard = { title = _("QR from clipboard"), icon = "appbar.pokeball", order = 44, event = "QRFromClipboard" },
}

local function currentView()
    local ReaderUI = package.loaded["apps/reader/readerui"]
    if ReaderUI and ReaderUI.instance then
        return "reader"
    end
    return "filemanager"
end

--- Turns an icon name or a plugin-relative file into IconWidget arguments.
local function resolveIcon(icon, plugin_path)
    if type(icon) ~= "string" or icon == "" then
        return { icon = "appbar.tools" }
    end
    if icon:match("%.svg$") or icon:match("%.png$") or icon:find("/", 1, true) then
        if icon:sub(1, 1) ~= "/" and plugin_path then
            icon = plugin_path .. "/" .. icon
        end
        return { file = icon }
    end
    return { icon = icon }
end

--- Returns the list of apps for the current view, sorted.
-- Each entry: { id, title, description, icon_args, launch = function() }
function AppRegistry:getApps()
    local view = currentView()
    local apps = {}
    for _, b in ipairs(self.builtins) do
        if b.where == nil or b.where == view then
            table.insert(apps, {
                id = b.id,
                title = b.title,
                description = b.description,
                icon_args = resolveIcon(b.icon),
                order = b.order,
                action = b.action,
                wrapper_launch = b.launch,
                needs = b.needs,
                status = b.status,
            })
        end
    end
    for name, instance in pairs(PluginLoader.loaded_plugins or {}) do
        local app = type(instance) == "table" and instance.app
        local wrapper = AppRegistry.plugin_wrappers[name]
        if type(app) ~= "table" and wrapper and type(instance) == "table" then
            app = wrapper
        end
        if type(app) == "table" then
            table.insert(apps, {
                id = name,
                title = app.title or instance.fullname or name,
                description = app.description or instance.description,
                icon_args = resolveIcon(app.icon, instance.path),
                order = app.order or 50,
                plugin = instance,
                wrapper_launch = app.launch,
                event = app.event,
                action = app.action,
                needs = app.needs,
                status = app.status,
            })
        end
    end
    table.sort(apps, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.title) < tostring(b.title)
    end)
    return AppRegistry.arrange(apps, AppRegistry.userOrder(), AppRegistry.sortMode())
end

--- Home order chosen by the user: list of app ids. Setting kos_home_order.
function AppRegistry.userOrder()
    return G_reader_settings and G_reader_settings:readSetting("kos_home_order") or {}
end

--- "custom" (default; the saved order, new apps at the end), "az", or "default" (built-in order).
function AppRegistry.sortMode()
    return G_reader_settings and G_reader_settings:readSetting("kos_home_sort") or "custom"
end

--- Pure: returns `apps` arranged by mode. Apps missing from `order` keep their default place after the listed ones.
function AppRegistry.arrange(apps, order, mode)
    if mode == "default" then return apps end
    if mode == "az" then
        local copy = {}
        for i, app in ipairs(apps) do copy[i] = app end
        table.sort(copy, function(a, b) return tostring(a.title):lower() < tostring(b.title):lower() end)
        return copy
    end
    if not order or #order == 0 then return apps end
    local rank = {}
    for i, id in ipairs(order) do rank[id] = i end
    local listed, rest = {}, {}
    for _i, app in ipairs(apps) do
        if rank[app.id] then listed[#listed + 1] = app else rest[#rest + 1] = app end
    end
    table.sort(listed, function(a, b) return rank[a.id] < rank[b.id] end)
    for _i, app in ipairs(rest) do listed[#listed + 1] = app end
    return listed
end

--- Pure: new id list with `id` moved before `before_id` (nil = to the end). `ids` = ids as shown now.
function AppRegistry.move(ids, id, before_id)
    local out = {}
    for _i, v in ipairs(ids) do
        if v ~= id then out[#out + 1] = v end
    end
    local pos = #out + 1
    if before_id then
        for i, v in ipairs(out) do
            if v == before_id then pos = i break end
        end
    end
    table.insert(out, pos, id)
    return out
end

--- Moves an app on Home and saves the whole shown order (so it survives new plugins).
function AppRegistry:moveApp(id, before_id)
    local ids = {}
    for _i, app in ipairs(self:getApps()) do ids[#ids + 1] = app.id end
    G_reader_settings:saveSetting("kos_home_order", AppRegistry.move(ids, id, before_id))
    G_reader_settings:saveSetting("kos_home_sort", "custom")
    G_reader_settings:flush()
end

--- Can this app run in a split-view window? (Only apps that open an AppWindow.)
function AppRegistry:canSplit(app)
    return app.plugin ~= nil and not app.wrapper_launch and not app.event and not app.action
        and type(app.plugin.launchApp) == "function"
end

--- Starts an app. Never lets an app's error take the whole UI down.
-- @param opts optional { split = { next_to = Pane|nil, dir = "row"|"column"|nil } } to open it in the Workspace
function AppRegistry:launch(app, opts)
    local AppWindow = require("apps/kos/appwindow")
    local split = opts and opts.split
    if split and not self:canSplit(app) then
        UIManager:show(InfoMessage:new{
            text = T(_("%1 can't open in a split view yet: it uses its own full-screen window."), app.title),
        })
        return
    end
    if not (opts and opts.force) and (app.needs or app.status == "development") then
        local Common = require("apps/kos/common")
        local missing = Common.unmet(app.needs)
        if #missing > 0 or app.status == "development" then
            Common.notice(app.title, missing, app.status == "development", function()
                AppRegistry:launch(app, { split = split, force = true })
            end)
            return
        end
    end
    local Debugger = require("apps/kos/debugger")
    if Debugger.isDisabled(app.id) then
        UIManager:show(InfoMessage:new{
            text = T(_("%1 is switched off because KOReader closed while it was starting.\n\nSwitch it on again in Home screen menu > Debug."), app.title),
        })
        return
    end
    Debugger.launching(app.id)
    AppWindow.pending_target = split
    local Windows = require("apps/kos/windows")
    Windows.launching_app = app.plugin and app or nil
    local ok, err = pcall(function()
        if app.wrapper_launch then
            app.wrapper_launch(app.plugin)
        elseif app.plugin and type(app.plugin.launchApp) == "function" then
            app.plugin:launchApp()
        elseif app.event then
            UIManager:sendEvent(Event:new(app.event))
        elseif app.action then
            Dispatcher:execute({ [app.action] = true })
        else
            error("this app has no launchApp(), app.event or app.action")
        end
    end)
    -- An app that didn't open an AppWindow must not leave the target armed.
    AppWindow.pending_target = nil
    Windows.launching_app = nil
    if ok then Debugger.started(app.id) else Debugger.failed(app.id, err) end
    if not ok then
        logger.err("AppRegistry: failed to launch", app.id, err)
        UIManager:show(InfoMessage:new{
            text = T(_("Could not open %1:\n%2"), app.title, tostring(err)),
            icon = "notice-warning",
        })
    end
end

return AppRegistry

--[[--
Overview: turns KOReader's file manager screen into a home screen.

Nothing in KOReader is removed or changed: Overview is a layer shown on top of the
file manager. "KOReader files" in the search (or Back from a KOReader app) shows the
untouched file manager underneath; the next Home press brings Overview back.

@module koplugin.Overview
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local Bridge = require("overviewBridge")
local Store = require("overviewStore")

local Overview = WidgetContainer:extend{
    name = "overview",
    is_doc_only = false,
    screen = nil,
}

function Overview:init()
    self.layout = require("overviewHomeLayout")
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if self:isHomeContext() and self:isEnabledAsHome() then
        UIManager:nextTick(function() self:show() end)
    end
end

--- Only over the file manager, never inside an open book.
function Overview:isHomeContext()
    return self.ui and not self.ui.document
end

function Overview:isEnabledAsHome()
    return G_reader_settings:nilOrTrue("overview_as_home")
end

function Overview:onDispatcherRegisterActions()
    Dispatcher:registerAction("overview_show", {
        category = "none", event = "ShowOverview", title = _("Overview home screen"), general = true,
    })
end

function Overview:onShowOverview()
    self:show()
    return true
end

-- Android sends Resume when the activity comes back, e.g. after Home is pressed in another app
function Overview:onResume()
    if self:isHomeContext() and self:isEnabledAsHome() and not Overview.shared_screen then
        self:show()
    end
end

function Overview:show()
    -- one Overview on screen at a time, even if the file manager re-creates this plugin
    if Overview.shared_screen then return end
    if not self.store and Bridge.isAndroid() then
        self.store = Store.open(Bridge.dbPath())
    end
    Bridge.sync()
    self.apps = Bridge.apps()
    self.status = Bridge.status()
    local OverviewScreen = require("overviewScreen")
    self.screen = OverviewScreen:new{ plugin = self }
    Overview.shared_screen = self.screen
    UIManager:show(self.screen)
end

function Overview:hide()
    if self.screen then
        UIManager:close(self.screen)
    end
end

function Overview:onScreenClosed()
    self.screen = nil
    Overview.shared_screen = nil
end

function Overview:findKoreaderApp(action)
    for _, app in ipairs(self.layout.koreaderApps) do
        if app.action == action then return app end
    end
end

function Overview:runKoreaderApp(app)
    self:hide()
    UIManager:nextTick(function()
        Dispatcher:execute({ [app.action] = true })
    end)
end

local function contains(haystack, needle)
    return haystack and haystack:lower():find(needle, 1, true) ~= nil
end

local function when(ms)
    return os.date("%d %b %Y  %H:%M", math.floor((ms or 0) / 1000))
end

--- Builds the result rows for a query. Order: commands, contacts, apps, then every
--- matching message from every app, oldest first.
function Overview:search(text)
    local q = util.trim(text or "")
    if q == "" then return nil end
    local lq = q:lower()
    local rows = {}

    for _, cmd in ipairs(self:commands()) do
        if contains(cmd.label, lq) then
            table.insert(rows, { title = _("Overview"), body = cmd.label, callback = cmd.run })
        end
    end

    local contacts = self.store and self.store:contacts(q) or {}
    for _, c in ipairs(contacts) do
        table.insert(rows, {
            title = c.phones ~= "" and c.phones or _("Contact"),
            body = c.name,
            bold = true,
            callback = function()
                -- narrow the search to exactly this person
                self.screen.input:setText(c.name)
                self.screen:scheduleSearch()
            end,
        })
    end

    for _, app in ipairs(self.apps or {}) do
        if contains(app.label, lq) then
            table.insert(rows, {
                title = _("App"), body = app.label,
                callback = function() Bridge.launchApp(app.package) end,
            })
        end
    end

    for _, app in ipairs(self.layout.koreaderApps) do
        if contains(app.label, lq) then
            table.insert(rows, {
                title = _("KOReader app"), body = app.label,
                callback = function() self:runKoreaderApp(app) end,
            })
        end
    end

    local messages = self.store and self.store:messages(q) or {}
    for _, m in ipairs(messages) do
        table.insert(rows, {
            title = string.format("%s  ·  %s  ·  %s", m.app, m.conversation, when(m.time)),
            body = string.format("%s: %s", m.outgoing and _("me") or m.sender, m.body),
            callback = function()
                if not self.status.navigator then
                    UIManager:show(InfoMessage:new{
                        text = _("Opening the chat. To land on this exact message, turn on \"Overview go to message\" in Accessibility settings."),
                        timeout = 4,
                    })
                end
                Bridge.openOriginal(m.id)
            end,
        })
    end

    if Bridge.isAndroid() and not (self.status.listener and self.status.contacts and self.status.sms) then
        table.insert(rows, {
            title = _("Overview"),
            body = _("Some message sources are off. Tap to turn them on."),
            callback = function() self:showSetup() end,
        })
    end
    return rows
end

function Overview:commands()
    return {
        { label = _("KOReader files"), run = function() self:hide() end },
        { label = _("Wallpaper"), run = function() self:chooseWallpaper() end },
        { label = _("Overview setup"), run = function() self:showSetup() end },
    }
end

function Overview:showSetup()
    self.status = Bridge.status()
    local function mark(on) return on and "✓  " or "✗  " end
    local dialog
    dialog = ButtonDialog:new{
        title = _("Overview message sources"),
        buttons = {
            {{ text = mark(self.status.listener) .. _("Messages from apps (notification access)"),
               callback = function() UIManager:close(dialog); Bridge.openSetup("listener") end }},
            {{ text = mark(self.status.contacts and self.status.sms) .. _("Contacts and SMS history"),
               callback = function() UIManager:close(dialog); Bridge.openSetup("permissions") end }},
            {{ text = mark(self.status.navigator) .. _("Go to the original message (accessibility)"),
               callback = function() UIManager:close(dialog); Bridge.openSetup("navigator") end }},
        },
    }
    UIManager:show(dialog)
end

function Overview:chooseWallpaper()
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new{
        select_directory = false,
        path = G_reader_settings:readSetting("home_dir") or require("datastorage"):getDataDir(),
        file_filter = function(file)
            local ext = util.getFileNameSuffix(file):lower()
            return ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" or ext == "gif"
        end,
        onConfirm = function(path)
            G_reader_settings:saveSetting("overview_wallpaper", path)
            if self.screen then self.screen:layout() end
        end,
    })
end

function Overview:addToMainMenu(menu_items)
    menu_items.overview = {
        text = _("Overview home screen"),
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Show Overview"), callback = function() self:show() end },
            {
                text = _("Show Overview when KOReader opens"),
                checked_func = function() return self:isEnabledAsHome() end,
                callback = function() G_reader_settings:flipNilOrTrue("overview_as_home") end,
            },
            { text = _("Wallpaper"), callback = function() self:chooseWallpaper() end },
            { text = _("Message sources"), callback = function() self:showSetup() end },
        },
    }
end

function Overview:onCloseWidget()
    if self.store then
        self.store:close()
        self.store = nil
    end
end

return Overview

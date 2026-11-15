--[[--
Updates: replacement files for KOReader's own apps (not add-ons).

* "Install update…": pick a .zip. Also: tap such a zip in Files.
  A zip is an update if it has files like `frontend/apps/kos/appwindow.lua`
  (the same folders as the fork's source). They are put in koreader/overrides/files/.
* "Edit a built-in file": makes an editable copy of a built-in app file
  (e.g. apps/kos/appwindow); edit it in the Text editor or Studio.
* Tap an entry to switch it on or off. Hold for more (edit, previous version, delete).
* Changes apply after a restart. Built-in files are never modified.

The mechanism is apps/kos/overrides.lua.
]]

local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local Overrides = require("apps/kos/overrides")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local Updates = WidgetContainer:extend{
    name = "updates",
}

function Updates:init()
    -- Up and running for a while: the replacement files work, clear the safety counter.
    UIManager:scheduleIn(5, function() Overrides.markStarted() end)
    -- Closing KOReader yourself is never a failed start.
    if not UIManager._kos_quit_hooked then
        UIManager._kos_quit_hooked = true
        local orig_quit = UIManager.quit
        UIManager.quit = function(...)
            pcall(Overrides.markStarted)
            return orig_quit(...)
        end
    end
    -- A zip with replacement files, tapped in Files, is offered by the App installer (it calls offerZip).
    self.ui.menu:registerToMainMenu(self)
end

function Updates:addToMainMenu(menu_items)
    menu_items.kos_updates = {
        text = _("Updates"),
        sorting_hint = "tools",
        callback = function() self:launchApp() end,
    }
end

local function restartNote()
    UIManager:askForRestart(_("Restart KOReader for the change to take effect."))
end

--- Asks, then installs an update zip. Returns false if the zip isn't an update.
function Updates.offerZip(zip_file, open_normally)
    local info = Overrides.inspectZip(zip_file)
    if not info then return false end
    local lines = {}
    for i, m in ipairs(info.modules) do
        if i > 12 then
            table.insert(lines, T(_("… and %1 more"), #info.modules - 12))
            break
        end
        table.insert(lines, "• " .. m.module)
    end
    UIManager:show(ConfirmBox:new{
        text = T(_("Update “%1” replaces these built-in files:\n%2\n\nThe built-in files stay as they are. You can switch each one off later.\n\nInstall?"),
            info.name, table.concat(lines, "\n")),
        ok_text = _("Install"),
        ok_callback = function()
            local n, err = Overrides.installZip(zip_file, info)
            if n then
                UIManager:askForRestart(T(_("%1 files installed.\n\nRestart KOReader to use them."), n))
            else
                UIManager:show(InfoMessage:new{ text = T(_("Install failed: %1"), tostring(err)), icon = "notice-warning" })
            end
        end,
        other_buttons = open_normally and {{
            { text = _("Open as file"), callback = open_normally },
        }} or nil,
        other_buttons_first = true,
    })
    return true
end

function Updates:editFile(path)
    local PluginLoader = require("pluginloader")
    local editor = PluginLoader:getPluginInstance("texteditor")
    if editor and editor.checkEditFile then
        editor:checkEditFile(path)
    else
        UIManager:show(InfoMessage:new{ text = T(_("Open this file in a text editor:\n%1"), BD.filepath(path)) })
    end
end

function Updates:itemMenu(item, reopen)
    local dialog
    local function act(fn) return function() UIManager:close(dialog); fn() end end
    dialog = ButtonDialog:new{
        title = item.module,
        buttons = {
            {
                { text = item.enabled and _("Switch off") or _("Switch on"), callback = act(function()
                    Overrides.setEnabled(item.module, not item.enabled)
                    restartNote()
                    reopen()
                end) },
                { text = _("Edit"), callback = act(function() self:editFile(item.path) end) },
            },
            {
                { text = _("Previous version"), enabled = Overrides.hasOld(item.module), callback = act(function()
                    if Overrides.restoreOld(item.module) then restartNote() end
                    reopen()
                end) },
                { text = _("Delete"), callback = act(function()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete the replacement for %1?\nThe built-in file is used again after a restart."), item.module),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            Overrides.remove(item.module)
                            restartNote()
                            reopen()
                        end,
                    })
                end) },
            },
        },
    }
    UIManager:show(dialog)
end

function Updates:chooseBuiltin(reopen)
    local modules = Overrides.builtinModules()
    local have = {}
    for _, it in ipairs(Overrides.list()) do have[it.module] = true end
    local items = {}
    for _, m in ipairs(modules) do
        table.insert(items, {
            text = m,
            mandatory = have[m] and _("already edited") or nil,
            module = m,
        })
    end
    local menu
    menu = Menu:new{
        title = _("Edit a built-in file"),
        subtitle = _("Makes your own copy. The built-in one stays."),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            local path, err = Overrides.copyBuiltin(item.module)
            if not path then
                UIManager:show(InfoMessage:new{ text = T(_("Could not make a copy: %1"), tostring(err)), icon = "notice-warning" })
                return
            end
            reopen()
            self:editFile(path)
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

function Updates:chooseZip()
    local PathChooser = require("ui/widget/pathchooser")
    local start = require("datastorage"):getDataDir()
    UIManager:show(PathChooser:new{
        select_directory = false,
        file_filter = function(f) return f:lower():match("%.zip$") ~= nil end,
        path = start,
        onConfirm = function(file)
            if not Updates.offerZip(file) then
                UIManager:show(InfoMessage:new{
                    text = _("This zip has no replacement files.\n\nExpected files like frontend/apps/kos/appwindow.lua inside it. For add-ons (plugins), tap the zip in Files instead."),
                })
            end
        end,
    })
end

function Updates:launchApp()
    if self.menu then UIManager:close(self.menu); self.menu = nil end
    local reopen = function() UIManager:nextTick(function() self:launchApp() end) end
    local list = Overrides.list()
    local items = {}
    if Overrides.safe_off then
        table.insert(items, {
            text = _("⚠ Switched off: KOReader didn't start three times"),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = _("KOReader didn't finish starting three times in a row while replacement files were on, so all of them were switched off.\n\nSwitch them on one at a time (tap) to find the one that breaks."),
                })
            end,
        })
    end
    table.insert(items, { text = _("Install update from a .zip…"), callback = function() self:chooseZip() end })
    table.insert(items, { text = _("Edit a built-in file…"), callback = function() self:chooseBuiltin(reopen) end, separator = true })
    if #list == 0 then
        table.insert(items, { text = _("No replacement files yet."), dim = true })
    end
    for _, item in ipairs(list) do
        local state = item.enabled and (item.active and _("on") or _("on after restart")) or _("off")
        if item.enabled == false and item.active then state = _("off after restart") end
        table.insert(items, {
            text = item.module,
            mandatory = (item.bundle and (item.bundle .. " · ") or "") .. state,
            callback = function()
                Overrides.setEnabled(item.module, not item.enabled)
                restartNote()
                reopen()
            end,
            hold_callback = function() self:itemMenu(item, reopen) end,
        })
    end
    self.menu = Menu:new{
        title = _("Updates"),
        subtitle = T(_("Replacement files for built-in apps · %1"), #list),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function() UIManager:close(self.menu); self.menu = nil end,
    }
    UIManager:show(self.menu)
end

return Updates

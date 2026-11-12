--[[--
KOReader OS "Open with": apps claim file types.

    local FileHandlers = require("apps/kos/filehandlers")
    FileHandlers:register{
        id = "sheets",                       -- unique
        title = _("Sheets"),                 -- shown in "Open with"
        extensions = { "csv", "tsv", "xlsx" },
        open = function(file) … end,        -- usually opens an AppWindow
    }

Registering a type:
* makes those files visible in the file browser (even if no reader supports them),
* opens them with the app when tapped (if several apps claim a type, you choose),
* adds "Open with…" to the long-press menu of those files.

Register from your plugin's init() (not at the top of main.lua), so it works
whatever order plugins load in. Registering the same id again replaces it.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local DocumentRegistry = require("document/documentregistry")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local FileHandlers = {
    handlers = {}, -- id -> handler
}

local function suffix(file)
    return type(file) == "string" and util.getFileNameSuffix(file):lower() or ""
end

function FileHandlers:register(handler)
    assert(handler.id and handler.open and handler.extensions, "FileHandlers: id, extensions and open are required")
    local exts = {}
    for _, e in ipairs(handler.extensions) do exts[e:lower()] = true end
    handler._exts = exts
    self.handlers[handler.id] = handler
end

function FileHandlers:unregister(id)
    self.handlers[id] = nil
end

--- Handlers for a file, sorted by title.
function FileHandlers:forFile(file)
    local ext = suffix(file)
    local list = {}
    for _, h in pairs(self.handlers) do
        if h._exts[ext] then table.insert(list, h) end
    end
    table.sort(list, function(a, b) return tostring(a.title) < tostring(b.title) end)
    return list
end

function FileHandlers:openWith(handler, file)
    local ok, err = pcall(handler.open, file)
    if not ok then
        logger.err("FileHandlers:", handler.id, "failed to open", file, err)
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("Could not open the file:") .. "\n" .. tostring(err),
            icon = "notice-warning",
        })
    end
end

--- Shows a chooser when several apps can open the file; returns false if none can.
function FileHandlers:open(file, fallback)
    local list = self:forFile(file)
    if #list == 0 then return false end
    if #list == 1 and not fallback then
        self:openWith(list[1], file)
        return true
    end
    local dialog
    local buttons = {}
    for _, h in ipairs(list) do
        table.insert(buttons, {{ text = h.title, callback = function()
            UIManager:close(dialog)
            self:openWith(h, file)
        end }})
    end
    if fallback then
        table.insert(buttons, {{ text = _("Open as a document"), callback = function()
            UIManager:close(dialog)
            fallback()
        end }})
    end
    dialog = ButtonDialog:new{
        title = _("Open with…") .. "\n" .. (file:match("([^/]+)$") or file),
        buttons = buttons,
    }
    UIManager:show(dialog)
    return true
end

-- Hook into KOReader once.
if not FileHandlers._installed then
    FileHandlers._installed = true

    -- Show claimed file types in the file browser.
    local orig_hasProvider = DocumentRegistry.hasProvider
    DocumentRegistry.hasProvider = function(registry, file, mimetype, include_aux)
        if orig_hasProvider(registry, file, mimetype, include_aux) then return true end
        return file ~= nil and #FileHandlers:forFile(file) > 0
    end

    -- Tapping a claimed file opens its app. A type that KOReader can also read
    -- as a document (e.g. .txt) asks which one to use.
    local orig_openFile = filemanagerutil.openFile
    filemanagerutil.openFile = function(ui, file, ...)
        if #FileHandlers:forFile(file) > 0 then
            local args = { n = select("#", ...), ... }
            local doc_fallback
            if orig_hasProvider(DocumentRegistry, file) then
                doc_fallback = function() orig_openFile(ui, file, unpack(args, 1, args.n)) end
            end
            if FileHandlers:open(file, doc_fallback) then return end
        end
        return orig_openFile(ui, file, ...)
    end
end

--- Adds "Open with…" to the long-press menu of a FileManager.
function FileHandlers:addFileDialogButton(fm)
    if not (fm and fm.addFileDialogButtons) then return end
    fm:addFileDialogButtons("kos_open_with", function(file, is_file)
        if is_file and #FileHandlers:forFile(file) > 0 then
            return {{
                text = _("Open with…"),
                callback = function()
                    local fc = fm.file_chooser
                    if fc and fc.file_dialog then UIManager:close(fc.file_dialog) end
                    FileHandlers:open(file, nil)
                end,
            }}
        end
    end)
end

return FileHandlers

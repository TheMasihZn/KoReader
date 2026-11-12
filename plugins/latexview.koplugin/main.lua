--[[--
LaTeX view: read .tex files as formatted pages, in a KOReader OS window.

Tap a .tex file in Files, or open the app from the home screen.
Reload re-reads the file, so you can keep the source open in the Text editor
in a window beside it and see your changes.
]]

local ButtonTable = require("ui/widget/buttontable")
local InfoMessage = require("ui/widget/infomessage")
local Latex = require("latex2html")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = require("device").screen

local LatexView = WidgetContainer:extend{
    name = "latexview",
}

function LatexView:init()
    local ok, FileHandlers = pcall(require, "apps/kos/filehandlers")
    if ok then
        FileHandlers:register{
            id = "latexview",
            title = _("LaTeX view"),
            extensions = { "tex", "latex", "ltx" },
            open = function(file) self:openFile(file) end,
        }
    else
        logger.warn("LatexView: KOReader OS file handlers not available", FileHandlers)
    end
end

local function readFile(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local s = f:read("*all")
    f:close()
    return s
end

function LatexView:openFile(path, split_target)
    local view = { path = path, font_size = G_reader_settings:readSetting("latexview_font_size") or 20 }

    local function load()
        local src, err = readFile(path)
        if not src then return nil, err end
        local ok, html, title = pcall(Latex.convert, src)
        if not ok then return nil, html end
        view.html, view.title = html, title
        return true
    end
    local ok, err = load()
    if not ok then
        UIManager:show(InfoMessage:new{ text = T(_("Could not open %1:\n%2"), path:match("([^/]+)$"), tostring(err)), icon = "notice-warning" })
        return
    end

    local AppWindow = require("apps/kos/appwindow")
    if split_target then AppWindow.pending_target = split_target end
    view.window = AppWindow:open{
        title = view.title or path:match("([^/]+)$"),
        subtitle = view.title and path:match("([^/]+)$") or nil,
        build = function(window, width, height)
            local toolbar = ButtonTable:new{
                width = width,
                show_parent = window,
                buttons = {{
                    { text = "A−", callback = function()
                        view.font_size = math.max(12, view.font_size - 2)
                        G_reader_settings:saveSetting("latexview_font_size", view.font_size)
                        window:refresh()
                    end },
                    { text = "A+", callback = function()
                        view.font_size = math.min(40, view.font_size + 2)
                        G_reader_settings:saveSetting("latexview_font_size", view.font_size)
                        window:refresh()
                    end },
                    { text = _("Reload"), callback = function()
                        local reloaded, rerr = load()
                        if not reloaded then
                            UIManager:show(InfoMessage:new{ text = tostring(rerr), icon = "notice-warning" })
                        end
                        window:refresh()
                    end },
                    { text = _("Source"), callback = function() self:showSource(path) end },
                }},
            }
            local page = ScrollHtmlWidget:new{
                html_body = view.html,
                css = Latex.CSS,
                default_font_size = Screen:scaleBySize(view.font_size),
                width = width,
                height = height - toolbar:getSize().h,
                dialog = window,
                html_link_tapped_callback = function() end, -- footnote links: nothing to follow
            }
            return VerticalGroup:new{ align = "left", page, toolbar }
        end,
    }
end

function LatexView:showSource(path)
    local editor = self.ui and self.ui.texteditor
    if editor then
        editor:openFile(path)
    else
        UIManager:show(InfoMessage:new{ text = _("Turn on the Text editor plugin to edit the source.") })
    end
end

function LatexView:launchApp()
    local AppWindow = require("apps/kos/appwindow")
    local split_target = AppWindow.pending_target
    AppWindow.pending_target = nil
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new{
        title = _("Long-press a .tex file to open it"),
        select_directory = false,
        select_file = true,
        path = filemanagerutil.getHomeFolder() or require("datastorage"):getDataDir(),
        file_filter = function(f) return f:lower():match("%.tex$") or f:lower():match("%.ltx$") or f:lower():match("%.latex$") end,
        onConfirm = function(file) self:openFile(file, split_target) end,
    })
end

return LatexView

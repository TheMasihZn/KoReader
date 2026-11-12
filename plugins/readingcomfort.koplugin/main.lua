--[[--
Reading comfort: fonts and spacing that many people with dyslexia or ADHD
find easier to read.

* Book font: installs the font into koreader/fonts/ (so the book renderer
  sees it) and makes it the default for books.
* Menu font: KOReader's own interface (menus, apps, dialogs) in that font.
* Comfortable spacing: more line and word space, slight letter spacing,
  left-aligned text (no uneven gaps from justification).

Everything can be undone from the same screen ("Default").
]]

local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Event = require("ui/event")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

-- The plugin's own folder (where the bundled fonts are).
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
-- Font paths must be absolute or start with "./" to be used as-is.
if PLUGIN_DIR:sub(1, 1) ~= "/" and PLUGIN_DIR:sub(1, 2) ~= "./" then
    PLUGIN_DIR = "./" .. PLUGIN_DIR
end

local FONTS = {
    { id = "opendyslexic", family = "OpenDyslexic",
      regular = "OpenDyslexic-Regular.otf", bold = "OpenDyslexic-Bold.otf",
      files = { "OpenDyslexic-Regular.otf", "OpenDyslexic-Bold.otf", "OpenDyslexic-Italic.otf", "OpenDyslexic-BoldItalic.otf", "OpenDyslexic-OFL.txt" },
      about = _("Heavier bottoms on letters, so they're harder to flip or mirror. Designed for dyslexia.") },
    { id = "atkinson", family = "Atkinson Hyperlegible",
      regular = "AtkinsonHyperlegible-Regular.ttf", bold = "AtkinsonHyperlegible-Bold.ttf",
      files = { "AtkinsonHyperlegible-Regular.ttf", "AtkinsonHyperlegible-Bold.ttf", "AtkinsonHyperlegible-Italic.ttf", "AtkinsonHyperlegible-BoldItalic.ttf", "AtkinsonHyperlegible-OFL.txt" },
      about = _("Letters that are hard to confuse (I l 1, O 0, b d). Designed for low vision; calm and clear.") },
    { id = "lexend", family = "Lexend",
      regular = "Lexend.ttf", bold = "Lexend.ttf",
      files = { "Lexend.ttf", "Lexend-OFL.txt" },
      about = _("Wide letters and spacing, designed to reduce visual stress and help reading fluency.") },
    { id = "andika", family = "Andika",
      regular = "Andika-Regular.ttf", bold = "Andika-Bold.ttf",
      files = { "Andika-Regular.ttf", "Andika-Bold.ttf", "Andika-Italic.ttf", "Andika-BoldItalic.ttf", "Andika-OFL.txt" },
      about = _("Simple, clear letter shapes, designed for people learning to read (single-storey a and g).") },
}
local BY_ID = {}
for _, f in ipairs(FONTS) do BY_ID[f.id] = f end

------------------------------------------------------------------------
-- Menu font: applied as early as possible (when this file is loaded),
-- before the file browser builds its widgets.
------------------------------------------------------------------------

local UI_REGULAR = { "cfont", "ffont", "smallffont", "largeffont", "rifont", "pgfont", "hfont",
    "infofont", "smallinfofont", "x_smallinfofont", "xx_smallinfofont" }
local UI_BOLD = { "tfont", "smalltfont", "x_smalltfont", "smallinfofontbold" }

local function applyUiFont(id)
    local f = BY_ID[id]
    if not f then return end
    local regular = PLUGIN_DIR .. "/fonts/" .. f.regular
    local bold = PLUGIN_DIR .. "/fonts/" .. f.bold
    if lfs.attributes(regular, "mode") ~= "file" then
        logger.warn("ReadingComfort: missing font", regular)
        return
    end
    for _, k in ipairs(UI_REGULAR) do Font.fontmap[k] = regular end
    for _, k in ipairs(UI_BOLD) do Font.fontmap[k] = bold end
end

if G_reader_settings and G_reader_settings:readSetting("readingcomfort_ui_font") then
    applyUiFont(G_reader_settings:readSetting("readingcomfort_ui_font"))
end

------------------------------------------------------------------------

local ReadingComfort = WidgetContainer:extend{
    name = "readingcomfort",
}

local function userFontsDir()
    return DataStorage:getDataDir() .. "/fonts"
end

local function copyFile(src, dst)
    local i = io.open(src, "rb")
    if not i then return false end
    local o = io.open(dst, "wb")
    if not o then i:close(); return false end
    o:write(i:read("*all"))
    i:close(); o:close()
    return true
end

--- Copies a font family into koreader/fonts/. Returns true if anything was new.
function ReadingComfort:installFont(f)
    local dir = userFontsDir()
    util.makePath(dir)
    local copied = false
    for _, file in ipairs(f.files) do
        local dst = dir .. "/" .. file
        if lfs.attributes(dst, "mode") ~= "file" then
            if copyFile(PLUGIN_DIR .. "/fonts/" .. file, dst) then
                copied = true
            else
                logger.warn("ReadingComfort: could not copy", file)
            end
        end
    end
    return copied
end

function ReadingComfort:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReadingComfort:addToMainMenu(menu_items)
    menu_items.reading_comfort = {
        text = _("Reading comfort (fonts, spacing)"),
        sorting_hint = "typeset",
        callback = function() self:launchApp() end,
    }
end

function ReadingComfort:setBookFont(id)
    local restart_needed = false
    if id then
        local f = BY_ID[id]
        restart_needed = self:installFont(f)
        G_reader_settings:saveSetting("readingcomfort_book_font", id)
        G_reader_settings:saveSetting("cre_font", f.family)
        if not restart_needed and self.ui.document and self.ui.font then
            -- Font already known to the renderer: switch the open book now.
            UIManager:sendEvent(Event:new("SetFont", f.family))
        end
    else
        G_reader_settings:delSetting("readingcomfort_book_font")
        G_reader_settings:delSetting("cre_font")
    end
    if restart_needed then
        UIManager:askForRestart(_("The font is installed. Restart KOReader so books can use it."))
    else
        UIManager:show(InfoMessage:new{
            text = id and T(_("Books now open in %1.\n\nA book you've already set a font for keeps it: change it in that book's font menu."), BY_ID[id].family)
                or _("Books use KOReader's default font again."),
            timeout = 4,
        })
    end
end

function ReadingComfort:setUiFont(id)
    if id then
        G_reader_settings:saveSetting("readingcomfort_ui_font", id)
    else
        G_reader_settings:delSetting("readingcomfort_ui_font")
    end
    UIManager:askForRestart(_("Restart KOReader to change the font of menus and apps."))
end

-- Comfortable spacing: remembered previous values, so "off" restores them.
local LETTER_SPACING_TWEAK = "Reading comfort - letter spacing.css"
local LEFT_ALIGN_TWEAK = "text_align_most_left"
local LINE_SPACING = 125
local WORD_SPACING = { 100, 90 }

local function writeLetterSpacingTweak()
    local dir = DataStorage:getDataDir() .. "/styletweaks"
    util.makePath(dir)
    local f = io.open(dir .. "/" .. LETTER_SPACING_TWEAK, "w")
    if f then
        f:write("/* Added by Reading comfort: a little more space between letters. */\n")
        f:write("body, p, li, td, blockquote { letter-spacing: 0.04em; }\n")
        f:close()
    end
end

function ReadingComfort:isSpacingOn()
    return G_reader_settings:readSetting("readingcomfort_spacing_backup") ~= nil
end

function ReadingComfort:setSpacing(on)
    local tweaks = G_reader_settings:readSetting("style_tweaks")
    if not tweaks then
        tweaks = {}
        local ok, CssTweaks = pcall(require, "ui/data/css_tweaks")
        if ok then
            for k, v in pairs(CssTweaks.DEFAULT_GLOBAL_STYLE_TWEAKS) do tweaks[k] = v end
        end
    end
    if on then
        if not self:isSpacingOn() then
            G_reader_settings:saveSetting("readingcomfort_spacing_backup", {
                line = G_reader_settings:readSetting("copt_line_spacing") or false,
                word = G_reader_settings:readSetting("copt_word_spacing") or false,
                left = tweaks[LEFT_ALIGN_TWEAK] or false,
            })
        end
        writeLetterSpacingTweak()
        G_reader_settings:saveSetting("copt_line_spacing", LINE_SPACING)
        G_reader_settings:saveSetting("copt_word_spacing", WORD_SPACING)
        tweaks[LEFT_ALIGN_TWEAK] = true
        tweaks[LETTER_SPACING_TWEAK] = true
    else
        local b = G_reader_settings:readSetting("readingcomfort_spacing_backup") or {}
        if b.line then G_reader_settings:saveSetting("copt_line_spacing", b.line) else G_reader_settings:delSetting("copt_line_spacing") end
        if b.word then G_reader_settings:saveSetting("copt_word_spacing", b.word) else G_reader_settings:delSetting("copt_word_spacing") end
        tweaks[LEFT_ALIGN_TWEAK] = b.left or nil
        tweaks[LETTER_SPACING_TWEAK] = nil
        G_reader_settings:delSetting("readingcomfort_spacing_backup")
    end
    G_reader_settings:saveSetting("style_tweaks", tweaks)

    -- The open book follows right away.
    if self.ui.document then
        pcall(function()
            UIManager:sendEvent(Event:new("SetLineSpace", on and LINE_SPACING or (G_reader_settings:readSetting("copt_line_spacing") or 100)))
            UIManager:sendEvent(Event:new("SetWordSpacing", on and WORD_SPACING or (G_reader_settings:readSetting("copt_word_spacing") or { 95, 75 })))
            local st = self.ui.styletweak
            if st and st.global_tweaks then
                st.global_tweaks[LEFT_ALIGN_TWEAK] = tweaks[LEFT_ALIGN_TWEAK]
                st.global_tweaks[LETTER_SPACING_TWEAK] = tweaks[LETTER_SPACING_TWEAK]
                st:updateCssText(true)
            end
        end)
    end
    UIManager:show(InfoMessage:new{
        text = on and _("Comfortable spacing on, for this book and new ones.\n\nLetter spacing appears in Style tweaks › User style tweaks.")
            or _("Spacing back to how it was."),
        timeout = 4,
    })
end

function ReadingComfort:launchApp()
    local dialog
    local book = G_reader_settings:readSetting("readingcomfort_book_font")
    local ui = G_reader_settings:readSetting("readingcomfort_ui_font")
    local function fontRow(current, setter)
        local rows, row = {}, {}
        for _, f in ipairs(FONTS) do
            table.insert(row, { text = (current == f.id and "✓ " or "") .. f.family, callback = function()
                UIManager:close(dialog)
                setter(f.id)
            end })
            if #row == 2 then table.insert(rows, row); row = {} end
        end
        table.insert(row, { text = (current == nil and "✓ " or "") .. _("Default"), callback = function()
            UIManager:close(dialog)
            setter(nil)
        end })
        table.insert(rows, row)
        return rows
    end
    local buttons = {}
    table.insert(buttons, {{ text = _("— Font for books —"), enabled = false }})
    for _, r in ipairs(fontRow(book, function(id) self:setBookFont(id) end)) do table.insert(buttons, r) end
    table.insert(buttons, {{ text = _("— Font for menus and apps —"), enabled = false }})
    for _, r in ipairs(fontRow(ui, function(id) self:setUiFont(id) end)) do table.insert(buttons, r) end
    table.insert(buttons, {{
        text = self:isSpacingOn() and _("✓ Comfortable spacing (tap to turn off)") or _("Comfortable spacing"),
        callback = function()
            UIManager:close(dialog)
            self:setSpacing(not self:isSpacingOn())
        end,
    }})
    table.insert(buttons, {{ text = _("About these fonts"), callback = function()
        UIManager:close(dialog)
        local lines = {}
        for _, f in ipairs(FONTS) do table.insert(lines, f.family .. ": " .. f.about) end
        table.insert(lines, "")
        table.insert(lines, _("Research on special fonts for dyslexia is mixed: what helps most is what feels easiest to you. Bigger text and more space between lines and words help many readers. Try each one for a few pages."))
        table.insert(lines, "")
        table.insert(lines, _("All four fonts are free (SIL Open Font License)."))
        local TextViewer = require("ui/widget/textviewer")
        UIManager:show(TextViewer:new{ title = _("Reading comfort fonts"), text = table.concat(lines, "\n\n") })
    end }})
    dialog = ButtonDialog:new{
        title = _("Reading comfort"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

return ReadingComfort

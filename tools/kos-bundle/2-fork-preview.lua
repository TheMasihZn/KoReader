--[[
KOReader user patch: preview of two TheMasihZn/KoReader fork features
on a stock KOReader install (not the F-Droid build, which ignores patches).

  1. Windows-style path bar in the file manager:
     tap a folder to jump to it, tap "…" for all parent folders,
     long-press to type/paste a path.
  2. Android split-screen / freeform windows: redraw at the window's real
     size instead of the whole display's.
  3. Foldables: each screen remembers its own DPI (set it in Screen DPI while
     using that screen); folding / unfolding switches automatically and live.
  4. dp/sp scaling like Android: sizes follow the screen's density instead of
     its size, so nothing stretches when you unfold. Settings › Screen ›
     "Screen size: dp, sp and DPI" has Interface size (dp) and Text size (sp).
  6. Android: background helper processes exit cleanly (no more SIGSEGV
     crash dumps in libGLESv2_adreno.so on Samsung devices).
  5. Long-press on text in PDFs never runs OCR: the text layer is used
     (OCR only with the document's "Force OCR" option).

Install: copy this file to  koreader/patches/2-fork-preview.lua
then restart KOReader. Remove the file to undo.
--]]

local BD = require("ui/bidi")
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local function kosHomeFolder()
    if type(filemanagerutil.getHomeFolder) == "function" then
        local ok, dir = pcall(filemanagerutil.getHomeFolder)
        if ok and type(dir) == "string" and dir ~= "" then return dir end
    end
    local dir = G_reader_settings:readSetting("home_dir") or Device.home_dir
    if type(dir) ~= "string" or dir == "" then dir = require("datastorage"):getDataDir() end
    return dir
end
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

------------------------------------------------------------------------
-- 0. Diagnostics and safe mode
------------------------------------------------------------------------
local PATCH_VERSION = "9"
local DataStorage = require("datastorage")
local LOG_FILE = DataStorage:getDataDir() .. "/fork-preview.log"
local function plog(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S "), table.concat(parts, " "), "\n")
        f:close()
    end
end
do -- keep the log small
    local size = lfs.attributes(LOG_FILE, "size")
    if size and size > 200000 then os.remove(LOG_FILE) end
end

-- KOReader's and plugins' errors and warnings also go to the log
-- (on Android they otherwise only go to the system log you can't see).
for _, level in ipairs({ "err", "warn" }) do
    local orig = logger[level]
    logger[level] = function(...)
        pcall(plog, level:upper(), ...)
        return orig(...)
    end
end

-- Safe mode: if two starts in a row never got going, the newer features stay
-- off (path bar only). One quick exit is not enough (closing the app within a
-- few seconds is normal while testing). The message shows what went wrong, so
-- nobody has to dig for the log file.
local function lastLogLines(n)
    local f = io.open(LOG_FILE, "r")
    if not f then return "(no log yet)" end
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    local out = {}
    for i = math.max(1, #lines - n + 1), #lines do out[#out + 1] = lines[i]:sub(1, 160) end
    return table.concat(out, "\n")
end

local VERSION_KEY = "fork_preview_fails_v" .. PATCH_VERSION
local SAFE_KEY = "fork_preview_safe_v" .. PATCH_VERSION
local fails = G_reader_settings:readSetting(VERSION_KEY) or 0
if G_reader_settings:readSetting("fork_preview_boot") == PATCH_VERSION then
    fails = fails + 1 -- the previous start with this version didn't finish
    G_reader_settings:saveSetting(VERSION_KEY, fails)
end
-- Three unfinished starts in a row (not one or two: closing the app quickly
-- while testing is normal) put the newer features on hold.
local SAFE = fails >= 3 or G_reader_settings:isTrue(SAFE_KEY)
if SAFE then G_reader_settings:makeTrue(SAFE_KEY) end
G_reader_settings:saveSetting("fork_preview_boot", PATCH_VERSION)
G_reader_settings:flush()
plog("START patch v" .. PATCH_VERSION, SAFE and "(SAFE MODE: newer features off)" or "", "unfinished starts:", fails, "Device:", Device.model or "?")

local function startedFine(reason)
    if G_reader_settings:readSetting("fork_preview_boot") == nil then return end
    G_reader_settings:delSetting("fork_preview_boot")
    if SAFE then
        -- Heals itself: the next start tries the newer features again, and
        -- goes back to safe mode right away if that one fails once.
        G_reader_settings:delSetting(SAFE_KEY)
        G_reader_settings:saveSetting(VERSION_KEY, 2)
    else
        G_reader_settings:delSetting(VERSION_KEY)
    end
    G_reader_settings:flush()
    plog("started fine", reason or "")
end
UIManager:scheduleIn(5, function() startedFine("after 5 s") end)
-- Closing KOReader yourself is never a failed start, however quickly it happens.
do
    local orig_quit = UIManager.quit
    UIManager.quit = function(...)
        pcall(startedFine, "clean exit")
        return orig_quit(...)
    end
end
if SAFE then
    -- No error screen: a short note, and the details are in koreader/fork-preview.log.
    UIManager:scheduleIn(3, function()
        UIManager:show(InfoMessage:new{
            text = "Some newer features are paused after a failed start. They try again on the next start.",
            timeout = 4,
        })
    end)
end

-- Fatal errors: write the traceback to the log before KOReader goes down.
local function guard(tbl, name, label)
    local orig = tbl and tbl[name]
    if type(orig) ~= "function" then return end
    tbl[name] = function(...)
        local res = table.pack(xpcall(orig, debug.traceback, ...))
        if not res[1] then
            pcall(plog, "FATAL in " .. label .. ":", res[2])
            error(res[2], 0)
        end
        return unpack(res, 2, res.n)
    end
end
guard(UIManager, "run", "UIManager:run")
guard(FileManager, "showFiles", "FileManager:showFiles")
guard(FileManager, "init", "FileManager:init")
if package.loaded["apps/reader/readerui"] then
    guard(package.loaded["apps/reader/readerui"], "init", "ReaderUI:init")
end

-- Android: background helper processes (book re-rendering, covers…) must end
-- with _exit(): exit() runs the GPU driver's exit-time cleanup, which crashes
-- on Samsung/Adreno (SIGSEGV in libGLESv2_adreno.so under __cxa_finalize).
pcall(function()
    require("ffi/util").addRunInSubProcessAfterForkFunc("android_child_safe_exit", function()
        local ffi = require("ffi")
        os.exit = function(code)
            pcall(io.stdout.flush, io.stdout)
            pcall(io.stderr.flush, io.stderr)
            if code == nil or code == true then code = 0 elseif code == false then code = 1 end
            ffi.C._exit(tonumber(code) or 0)
        end
    end)
end)

------------------------------------------------------------------------
-- 1. Path bar
------------------------------------------------------------------------

local BreadcrumbWidget
do
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")

BreadcrumbWidget = InputContainer:extend{
    segments = nil, -- list of { text = string, path = string|nil }
    face = Font:getFace("xx_smallinfofont"),
    max_width = nil,
    separator = " \u{203A} ", -- " › "
    ellipsis = "\u{2026}", -- "…"
    bold_last = true, -- current folder in bold
    lang = nil,
    callback = nil, -- function(path) on segment tap
    overflow_callback = nil, -- function() on "…" tap
    hold_callback = nil, -- function() on long-press anywhere on the bar
    -- extra vertical touch margin, as the text itself is quite thin
    touch_v_padding = Size.padding.large,
}

function BreadcrumbWidget:init()
    self.segments = self.segments or {}
    self.dimen = Geom:new{ x = 0, y = 0, w = 0, h = 0 }
    local range = function()
        return Geom:new{
            x = self.dimen.x,
            y = self.dimen.y - self.touch_v_padding,
            w = self.dimen.w,
            h = self.dimen.h + 2 * self.touch_v_padding,
        }
    end
    self.ges_events = {
        TapBreadcrumb = { GestureRange:new{ ges = "tap", range = range } },
        HoldBreadcrumb = { GestureRange:new{ ges = "hold", range = range } },
    }
    self:_build()
end

function BreadcrumbWidget:_newText(text, bold, max_width)
    return TextWidget:new{
        text = text,
        face = self.face,
        bold = bold,
        max_width = max_width,
        truncate_left = true, -- paths: keep the end visible
        padding = 0,
        lang = self.lang,
    }
end

function BreadcrumbWidget:_build()
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    local nb = #self.segments
    local max_width = self.max_width or math.huge

    -- Build every segment and separator once, so we can measure them.
    local seg_widgets = {}
    for i, seg in ipairs(self.segments) do
        seg_widgets[i] = self:_newText(seg.text, self.bold_last and i == nb)
    end
    local function measure(text)
        local tw = self:_newText(text)
        local w = tw:getSize().w
        tw:free()
        return w
    end
    local sep_w = measure(self.separator)
    local ell_w = measure(self.ellipsis)

    -- Find the first segment to display so that everything fits.
    local first = 1
    local function widthFrom(start)
        local w = start > 1 and (ell_w + sep_w) or 0
        for i = start, nb do
            w = w + seg_widgets[i]:getSize().w
            if i < nb then w = w + sep_w end
        end
        return w
    end
    while first < nb and widthFrom(first) > max_width do
        first = first + 1
    end
    -- If even the last segment alone is too wide, truncate it.
    if nb > 0 and widthFrom(first) > max_width then
        local avail = max_width - (first > 1 and (ell_w + sep_w) or 0)
        seg_widgets[nb]:free()
        seg_widgets[nb] = self:_newText(self.segments[nb].text, self.bold_last, math.max(avail, ell_w))
    end

    -- Assemble, remembering each item's horizontal extent for hit-testing.
    -- Paths read left-to-right even in RTL UIs, so no mirroring.
    local group = HorizontalGroup:new{ allow_mirroring = false }
    self._hits = {}
    local x = 0
    local function add(widget, hit)
        table.insert(group, widget)
        local w = widget:getSize().w
        if hit then
            hit.x0, hit.x1 = x, x + w
            table.insert(self._hits, hit)
        end
        x = x + w
    end
    if first > 1 then
        add(self:_newText(self.ellipsis), { overflow = true })
        add(self:_newText(self.separator))
    end
    for i = first, nb do
        add(seg_widgets[i], { path = self.segments[i].path })
        if i < nb then
            add(self:_newText(self.separator))
        end
    end
    for i = 1, first - 1 do
        seg_widgets[i]:free()
    end
    -- Extend each hit zone halfway into the neighbouring separators,
    -- so taps between two names still land somewhere sensible.
    for i, hit in ipairs(self._hits) do
        if i > 1 then hit.x0 = hit.x0 - sep_w / 2 end
        if i < #self._hits then hit.x1 = hit.x1 + sep_w / 2 end
    end
    self[1] = group
    local size = group:getSize()
    self.dimen.w, self.dimen.h = size.w, size.h
end

function BreadcrumbWidget:getSize()
    return self[1]:getSize()
end

function BreadcrumbWidget:setSegments(segments)
    self.segments = segments or {}
    self:_build()
end

-- Compatibility with TextWidget-like callers: plain text, not tappable.
function BreadcrumbWidget:setText(text)
    self:setSegments({ { text = text or "" } })
end

function BreadcrumbWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self[1]:paintTo(bb, x, y)
end

function BreadcrumbWidget:onTapBreadcrumb(_, ges)
    local rx = ges.pos.x - self.dimen.x
    for _, hit in ipairs(self._hits) do
        if rx >= hit.x0 and rx < hit.x1 then
            if hit.overflow then
                if self.overflow_callback then
                    self.overflow_callback()
                    return true
                end
            elseif hit.path and self.callback then
                self.callback(hit.path)
                return true
            end
            break
        end
    end
    -- Tap on a non-actionable spot: let it propagate.
    return false
end

function BreadcrumbWidget:onHoldBreadcrumb()
    if self.hold_callback then
        self.hold_callback()
        return true
    end
end

end

function TitleBar:setSubTitleSegments(segments, no_refresh)
    if self.subtitle_widget and self.subtitle_widget.setSegments then
        self.subtitle_widget:setSegments(segments)
        if self.inner_subtitle_group then
            self.inner_subtitle_group:resetLayout()
        end
        self.title_group:resetLayout()
        if not no_refresh then
            UIManager:setDirty(self.show_parent, "ui", self.dimen)
        end
    end
end

local installBreadcrumbs
local orig_setupLayout = FileManager.setupLayout
FileManager.setupLayout = function(self, ...)
    local ret = orig_setupLayout(self, ...)
    local ok, err = pcall(installBreadcrumbs, self)
    if not ok then logger.warn("fork-preview: path bar disabled:", err) end
    return ret
end

installBreadcrumbs = function(self)
    local tb = self.title_bar
    local old = tb and tb.subtitle_widget
    if not old or old.setSegments then return end
    local fm = self
    local crumbs = BreadcrumbWidget:new{
        face = tb.subtitle_face,
        max_width = old.max_width,
        callback = function(path) fm:onBreadcrumbTap(path) end,
        overflow_callback = function()
            if fm.onShowFolderMenu then fm:onShowFolderMenu() end
        end,
        hold_callback = function() fm:showGoToPathDialog() end,
    }
    local container = tb.inner_subtitle_group or tb.title_group
    for i, w in ipairs(container) do
        if w == old then
            container[i] = crumbs
            break
        end
    end
    old:free()
    tb.subtitle_widget = crumbs
    container:resetLayout()
    tb.title_group:resetLayout()
end

function FileManager:getPathSegments(path)
    local home_dir = kosHomeFolder()
    if home_dir ~= "/" then
        home_dir = home_dir:gsub("/+$", "")
    end
    local segments = { { text = "/", path = "/" } }
    local home_idx = home_dir == "/" and 1 or nil
    local cur = ""
    for part in path:gmatch("[^/]+") do
        cur = cur .. "/" .. part
        table.insert(segments, { text = part, path = cur })
        if cur == home_dir then
            home_idx = #segments
        end
    end
    if home_idx then
        if G_reader_settings:nilOrTrue("shorten_home_dir") then
            local home_path = segments[home_idx].path
            for _ = 1, home_idx do
                table.remove(segments, 1)
            end
            table.insert(segments, 1, { text = _("Home"), path = home_path })
        elseif G_reader_settings:isTrue("lock_home_folder") then
            for i = 1, home_idx - 1 do
                segments[i].path = nil
            end
        end
    end
    return segments
end

function FileManager:updateTitleBarPath(path)
    path = path or self.file_chooser.path
    local ok, err = pcall(function()
        if self.title_bar.subtitle_widget and self.title_bar.subtitle_widget.setSegments then
            self.title_bar:setSubTitleSegments(self:getPathSegments(path))
        else
            self.title_bar:setSubTitle(BD.directory(filemanagerutil.abbreviate(path)))
        end
    end)
    if not ok then logger.warn("fork-preview: path bar update failed:", err) end
end
FileManager.onPathChanged = FileManager.updateTitleBarPath

function FileManager:onBreadcrumbTap(path)
    if path ~= self.file_chooser.path then
        self.file_chooser:changeToPath(path)
    end
end

function FileManager:showGoToPathDialog()
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Go to folder"),
        input = self.file_chooser.path,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(input_dialog) end,
            },
            {
                text = _("Copy"),
                callback = function()
                    Device.input.setClipboardText(self.file_chooser.path)
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Go"),
                is_enter_default = true,
                callback = function()
                    local target = util.trim(input_dialog:getInputText())
                    if target == "" then return end
                    if target == "~" or target:sub(1, 2) == "~/" then
                        target = kosHomeFolder() .. target:sub(2)
                    elseif target:sub(1, 1) ~= "/" then
                        target = self.file_chooser.path .. "/" .. target
                    end
                    if #target > 1 then
                        target = target:gsub("/+$", "")
                    end
                    local mode = lfs.attributes(target, "mode")
                    if mode == "directory" then
                        UIManager:close(input_dialog)
                        self.file_chooser:changeToPath(target)
                    elseif mode == "file" then
                        UIManager:close(input_dialog)
                        local dir = target:match("(.*)/") or ""
                        self.file_chooser:changeToPath(dir ~= "" and dir or "/", target)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("Folder not found:\n%1"), BD.dirpath(target)),
                            icon = "notice-warning",
                        })
                    end
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

if SAFE then
    plog("safe mode: path bar only")
    return
end
plog("path bar ready")

------------------------------------------------------------------------
-- 5. Long-press on text: no OCR (the text layer is used instead)
------------------------------------------------------------------------
do
    -- A page whose text layer is a single line/block is still a text page
    -- (KOReader required more than one line, and sent the rest to OCR).
    local ok, KoptInterface = pcall(require, "document/koptinterface")
    if ok and KoptInterface.getTextBoxes then
        local orig_getTextBoxes = KoptInterface.getTextBoxes
        KoptInterface.getTextBoxes = function(self, doc, pageno)
            local text = doc:getPageTextBoxes(pageno)
            if text and #text == 1 and doc.configurable.forced_ocr ~= 1 then
                return text
            end
            return orig_getTextBoxes(self, doc, pageno)
        end
    end
    local ok2, ReaderHighlight = pcall(require, "apps/reader/modules/readerhighlight")
    if ok2 then
        local function useOCR(self)
            return self.ui.document.configurable and self.ui.document.configurable.forced_ocr == 1
        end
        local function textFromTextLayer(self, page, pboxes)
            local doc = self.ui.document
            if not (page and pboxes and doc.getPageTextBoxes) then return "" end
            local okl, lines = pcall(doc.getPageTextBoxes, doc, page)
            if not okl or type(lines) ~= "table" then return "" end
            local words = {}
            for _, line in ipairs(lines) do
                for _, w in ipairs(line) do
                    if w.word and w.word ~= "" and w.x0 then
                        for _, b in ipairs(pboxes) do
                            if w.x1 > b.x and w.x0 < b.x + b.w and w.y1 > b.y and w.y0 < b.y + b.h then
                                table.insert(words, w.word)
                                break
                            end
                        end
                    end
                end
            end
            return table.concat(words, " ")
        end
        local function noTextHere(self)
            UIManager:show(InfoMessage:new{
                text = _("No text under your finger here. Try a long-press right on a word, or drag to select a few words."),
                timeout = 3,
            })
            UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function() self:clear() end)
        end
        -- Fill in empty selections from the text layer before KOReader would run OCR.
        local function fillOrStop(self)
            local st = self.selected_text
            if st and (st.text == nil or #st.text == 0) and self.hold_pos and not useOCR(self) then
                local t = textFromTextLayer(self, self.hold_pos.page, st.pboxes)
                if t == "" then
                    noTextHere(self)
                    return false
                end
                st.text = t
            end
            return true
        end
        local orig_lookup = ReaderHighlight.lookupDictWord
        ReaderHighlight.lookupDictWord = function(self, ...)
            if not fillOrStop(self) then return end
            return orig_lookup(self, ...)
        end
        local orig_translate = ReaderHighlight.translate
        ReaderHighlight.translate = function(self, ...)
            if not fillOrStop(self) then return end
            return orig_translate(self, ...)
        end
    end
end

------------------------------------------------------------------------
-- 2. Android split-screen / freeform windows
------------------------------------------------------------------------

if not Device:isAndroid() then return end
local ok, android = pcall(require, "android")
if not ok or type(android) ~= "table" or android.getScreenWidth == nil then return end
local C = require("ffi").C

local display_width = android.getScreenWidth
local display_height = android.getScreenHeight

local function getMultiWindowSize()
    local ok, w, h = pcall(function()
        local window = android.app.window
        if window == nil then return end
        local ww = android.lib.ANativeWindow_getWidth(window)
        local wh = android.lib.ANativeWindow_getHeight(window)
        if ww <= 0 or wh <= 0 then return end
        if ww < display_width() or wh < display_height() then
            return ww, wh
        end
    end)
    if ok then return w, h end
end

android.getScreenWidth = function()
    local w = getMultiWindowSize()
    return w or display_width()
end
android.getScreenHeight = function()
    local _, h = getMultiWindowSize()
    return h or display_height()
end


------------------------------------------------------------------------
-- 3. A DPI for each screen (foldables), automatic
-- 4. dp / sp scaling: no stretching when unfolding; Interface size and Text size
------------------------------------------------------------------------
local DisplayProfiles, Scaling
do
local T = require("ffi/util").template
DisplayProfiles = { applying = false }


--- Key for a physical display size, e.g. "w900" (cover) or "w1810" (unfolded).
function DisplayProfiles.key(display_w, display_h)
    local short = math.min(display_w, display_h)
    return "w" .. math.floor(short / 10 + 0.5) * 10
end

--- A friendly name for a key, for menus.
function DisplayProfiles.label(display_w, display_h)
    local long, short = math.max(display_w, display_h), math.min(display_w, display_h)
    local kind = (long / short >= 1.8) and _("narrow screen") or _("wide screen")
    return T(_("%1 (%2 px)"), kind, short)
end

local function profiles()
    return G_reader_settings:readSetting("dpi_profiles") or {}
end

--- DPI stored for a key: a number, "auto", or nil if never set.
function DisplayProfiles.get(key)
    return profiles()[key]
end

function DisplayProfiles.set(key, dpi)
    local p = profiles()
    p[key] = dpi or "auto"
    G_reader_settings:saveSetting("dpi_profiles", p)
end

--- Recomputes ui/size (paddings, borders…) in place for the current DPI.
-- Widgets keep a reference to the same table, so they pick up the new values.
function DisplayProfiles.refreshSizes()
    local Size = package.loaded["ui/size"]
    if not Size then return end
    local path = package.searchpath("ui/size", package.path)
    local chunk = path and loadfile(path)
    if not chunk then return end
    local ok, fresh = pcall(chunk)
    if not ok or type(fresh) ~= "table" then return end
    for group, values in pairs(fresh) do
        local target = rawget(Size, group)
        if type(values) == "table" and type(target) == "table" then
            for k, v in pairs(values) do rawset(target, k, v) end
        end
    end
end

--- Sets DPI now. dpi = number, or nil for auto. Returns true if it changed.
function DisplayProfiles.applyDPI(Device, dpi)
    local Screen = Device.screen
    -- dpi_override is only a flag; the overriding value is Screen.dpi.
    local current = Screen.dpi_override and Screen.dpi or nil
    if current == dpi then return false end
    G_reader_settings:saveSetting("screen_dpi", dpi) -- also used at the next start
    DisplayProfiles.applying = true
    Device:setScreenDPI(dpi)
    DisplayProfiles.applying = false
    DisplayProfiles.refreshSizes()
    logger.info("DisplayProfiles: DPI now", dpi or "auto")
    return true
end

--- Called when the screen changes: applies the stored DPI for the new screen.
-- Returns true if the DPI changed (the caller then relayouts everything).
function DisplayProfiles.onDisplayChanged(Device, display_w, display_h)
    local want = DisplayProfiles.get(DisplayProfiles.key(display_w, display_h)) or "auto"
    return DisplayProfiles.applyDPI(Device, want ~= "auto" and want or nil)
end

--- At startup: the DPI for the screen in use. A screen seen for the first time
-- keeps the DPI already chosen (so updating doesn't change anything).
-- Returns the DPI to use (number or nil for auto).
function DisplayProfiles.startupDPI(display_w, display_h)
    local key = DisplayProfiles.key(display_w, display_h)
    local want = DisplayProfiles.get(key)
    if want == nil then
        local current = G_reader_settings:readSetting("screen_dpi")
        DisplayProfiles.set(key, current)
        return current
    end
    return want ~= "auto" and want or nil
end

--- The Screen DPI menu: set the DPI for the screen in use, live.
function DisplayProfiles.setForCurrentScreen(Device, display_w, display_h, dpi)
    DisplayProfiles.set(DisplayProfiles.key(display_w, display_h), dpi)
    if DisplayProfiles.applyDPI(Device, dpi) then
        DisplayProfiles.relayout(Device)
    end
end

--- After a DPI change: rebuild the UI, and resize book text (it's in pixels).
function DisplayProfiles.relayout(Device)
    local UIManager = require("ui/uimanager")
    local new_size = Device.screen:getSize()
    UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
    UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
    local ReaderUI = package.loaded["apps/reader/readerui"]
    local reader = ReaderUI and ReaderUI.instance
    if reader and reader.font and reader.document and reader.font.configurable then
        pcall(function()
            reader.document:setFontSize(Device.screen:scaleBySize(reader.font.configurable.font_size))
            reader:handleEvent(Event:new("UpdatePos"))
        end)
    end
    UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    if FileManager and FileManager.instance then
        FileManager.instance:reinit(FileManager.instance.path, FileManager.instance.focused_file)
    end
    UIManager:setDirty("all", "full")
end

Scaling = {
    installed = false,
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function Scaling.uiPercent() return G_reader_settings:readSetting("kos_ui_scale") or 100 end
function Scaling.textPercent() return G_reader_settings:readSetting("kos_text_scale") or 100 end

--- KOReader's own formula, for calibration (see ffi/framebuffer.lua fb:scaleBySize).
local function legacyScale(fb)
    local size_scale = math.min(fb:getWidth(), fb:getHeight()) / 600
    local dpi_scale = fb.dpi_override and (fb:getDPI() / 160) or size_scale
    return (size_scale + dpi_scale) / 2
end

--- Pixels per "KOReader unit" per dp at 100 %: chosen once so nothing changes
-- on the screen in use the first time; after that, density alone decides.
function Scaling.calibration(fb)
    local c = G_reader_settings:readSetting("kos_dp_calibration")
    if not c then
        c = clamp(legacyScale(fb) / (fb:getDPI() / 160), 0.35, 2.0)
        G_reader_settings:saveSetting("kos_dp_calibration", c)
        logger.info("Scaling: calibrated dp scale", c)
    end
    return c
end

--- Pixels for one KOReader size unit (dp), all factors included.
function Scaling.factor(fb)
    return (fb:getDPI() / 160) * Scaling.calibration(fb) * Scaling.uiPercent() / 100
end

--- Android-like window size class from a width in pixels.
-- compact < 600dp ≤ medium < 840dp ≤ expanded
function Scaling.windowClass(width_px)
    local Screen = require("device").screen
    width_px = width_px or Screen:getWidth()
    -- Real Android dp (density only), like WindowSizeClass, not KOReader's units.
    local dp = width_px / (Screen:getDPI() / 160)
    if dp >= 840 then return "expanded", dp end
    if dp >= 600 then return "medium", dp end
    return "compact", dp
end

--- Replaces scaleBySize on the screen, and makes interface fonts follow sp.
function Scaling.install(Device)
    if Scaling.installed then return end
    local fb = Device.screen
    Scaling.calibration(fb) -- before replacing the formula it calibrates against
    Scaling.orig_scaleBySize = fb.scaleBySize
    fb.scaleBySize = function(self, px)
        return math.ceil(px * Scaling.factor(self))
    end

    -- sp: interface text gets the text size on top of dp.
    local Font = require("ui/font")
    local orig_getFace = Font.getFace
    Font.getFace = function(self, font, size, faceindex)
        if not size then size = self.sizemap[font] end
        local pct = Scaling.textPercent()
        if not size or pct == 100 then
            return orig_getFace(self, font, size, faceindex)
        end
        local face = orig_getFace(self, font, size * pct / 100, faceindex)
        -- Keep the unscaled size here: code that derives other faces from it
        -- (fallback fonts, "a bit smaller") calls getFace again, which scales once.
        if face then face.orig_size = size end
        return face
    end

    Scaling.installed = true
    -- ui/size may already have been computed with the old formula.
    DisplayProfiles.refreshSizes()
end

--- Android only: the display's density can change when the device folds or
-- unfolds. Returns true if it changed.
function Scaling.refreshDensity(Device)
    local ok, android = pcall(require, "android")
    if not ok or type(android) ~= "table" or not android.lib or not android.app then return false end
    local ok2, density = pcall(function() return android.lib.AConfiguration_getDensity(android.app.config) end)
    if not ok2 or not density or density <= 0 or density == Device.display_dpi then return false end
    logger.info("Scaling: display density", Device.display_dpi, "->", density)
    Device.display_dpi = density
    if not Device.screen.dpi_override then
        Device.screen:clearDPI() -- re-reads display_dpi
    end
    return true
end

--- Apply a change of interface or text size now.
function Scaling.apply(Device)
    DisplayProfiles.refreshSizes()
    DisplayProfiles.relayout(Device)
end

--- Menu items: Interface size (dp) and Text size (sp).
function Scaling.menuItems(Device)
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local function spin(title, info, key, current, touchmenu_instance)
        local SpinWidget = require("ui/widget/spinwidget")
        UIManager:show(SpinWidget:new{
            title_text = title,
            info_text = info,
            value = current,
            value_min = 50,
            value_max = 250,
            value_step = 5,
            value_hold_step = 25,
            unit = "%",
            default_value = 100,
            ok_text = _("Apply"),
            callback = function(s)
                G_reader_settings:saveSetting(key, s.value ~= 100 and s.value or nil)
                Scaling.apply(Device)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end
    return {
        {
            text_func = function() return T(_("Interface size (dp): %1%"), Scaling.uiPercent()) end,
            help_text = _("Buttons, icons, spacing and text, all together. Sizes follow the screen's real density, so they stay the same physical size when you unfold: you get more room instead of bigger things."),
            keep_menu_open = true,
            callback = function(tmi)
                spin(_("Interface size"), _("Like Android's display size. Applies right away."), "kos_ui_scale", Scaling.uiPercent(), tmi)
            end,
        },
        {
            text_func = function() return T(_("Text size (sp): %1%"), Scaling.textPercent()) end,
            help_text = _("Only the text of menus, dialogs and apps, on top of the interface size. Book text has its own font size."),
            keep_menu_open = true,
            callback = function(tmi)
                spin(_("Text size"), _("Like Android's font size. Applies right away."), "kos_text_scale", Scaling.textPercent(), tmi)
            end,
            separator = true,
        },
    }
end

end

-- At start: the DPI stored for the screen in use (first time: keep the current one).
local display_key
pcall(function()
    display_key = DisplayProfiles.key(display_width(), display_height())
    local want = DisplayProfiles.startupDPI(display_width(), display_height())
    DisplayProfiles.applyDPI(Device, want) -- nothing is drawn yet: no relayout needed
end)

-- dp/sp instead of "scale by screen size".
do
    local ok, err = pcall(Scaling.install, Device)
    if not ok then logger.warn("fork-preview: dp/sp scaling not installed:", err) end
    plog("scaling", ok and "installed" or "FAILED", Device.screen:getDPI(), "dpi, calibration", G_reader_settings:readSetting("kos_dp_calibration"))
end

-- Screen DPI menu: Interface size (dp) and Text size (sp) first.
pcall(function()
    local menu = require("ui/elements/screen_dpi_menu_table")
    if Scaling.installed and not menu._kos_items then
        menu._kos_items = true
        menu.text = _("Screen size: dp, sp and DPI")
        local items = Scaling.menuItems(Device)
        for i = #items, 1, -1 do table.insert(menu.sub_item_table, 1, items[i]) end
    end
end)

-- KOReader's own Screen DPI choices: remembered for this screen, applied now.
local orig_setScreenDPI = Device.setScreenDPI
Device.setScreenDPI = function(self, dpi)
    orig_setScreenDPI(self, dpi)
    if DisplayProfiles.applying then return end
    pcall(function()
        DisplayProfiles.set(DisplayProfiles.key(display_width(), display_height()), dpi)
        UIManager:nextTick(function()
            DisplayProfiles.refreshSizes()
            DisplayProfiles.relayout(Device)
        end)
    end)
end

local function checkWindowSize()
    -- Folding / unfolding: apply that screen's DPI.
    local dpi_changed = Scaling.refreshDensity(Device) -- folding can change the density
    local key = DisplayProfiles.key(display_width(), display_height())
    if key ~= display_key then
        display_key = key
        dpi_changed = DisplayProfiles.onDisplayChanged(Device, display_width(), display_height()) or dpi_changed
    end
    local size_changed = android.screen.width ~= android.getScreenWidth()
        or android.screen.height ~= android.getScreenHeight()
    if not size_changed and not dpi_changed then
        return false
    end
    if dpi_changed then
        if size_changed then Device.screen:resize() end
        DisplayProfiles.refreshSizes()
        DisplayProfiles.relayout(Device)
        return true
    end
    Device.screen:resize()
    local new_size = Device.screen:getSize()
    logger.info("fork-preview: resizing screen to", new_size)
    UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
    UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
    UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))
    if FileManager.instance then
        FileManager.instance:reinit(FileManager.instance.path, FileManager.instance.focused_file)
    end
    return true
end

local function safeCheckWindowSize()
    local ok, err = pcall(checkWindowSize)
    if not ok then logger.warn("fork-preview: resize failed:", err) end
end

-- Only react to real layout changes (split-screen, divider moved, window resized, rotation),
-- which Android always announces with a configuration change. The window surface
-- may be resized a moment later, so keep listening for a few seconds after one.
local CONFIG_CHANGED = C.APP_CMD_CONFIG_CHANGED
local followups = {
    [C.APP_CMD_WINDOW_RESIZED] = true,
    [C.APP_CMD_CONTENT_RECT_CHANGED] = true,
    [C.APP_CMD_WINDOW_REDRAW_NEEDED] = true,
}
local listen_until = 0
-- Pulling the notification panel (or a keyboard / system bar change) also sends these
-- events. Never resize inside the native event itself: wait until the size has stopped
-- changing (two identical reads 0.35 s apart), ignore impossible sizes, and write
-- every step to the log so a crash leaves a trail.
local pending, last_probe = false, nil
local function probe()
    local w, h = android.getScreenWidth(), android.getScreenHeight()
    return (w or 0) .. "x" .. (h or 0), w, h
end
local function scheduleCheck(reason)
    if pending then return end
    pending = true
    last_probe = nil
    local function step()
        local key, w, h = probe()
        if not w or not h or w < 100 or h < 100 then
            plog("resize skipped: odd size", key, reason)
            pending = false
            return
        end
        if key ~= last_probe then
            last_probe = key
            UIManager:scheduleIn(0.35, step)
            return
        end
        pending = false
        plog("resize check", key, reason)
        safeCheckWindowSize()
        plog("resize done")
    end
    UIManager:scheduleIn(0.35, step)
end
local orig_handleMiscEv = Device.input.handleMiscEv
Device.input.handleMiscEv = function(this, ev)
    if ev.code == CONFIG_CHANGED then
        listen_until = os.time() + 3
        scheduleCheck("config")
    elseif followups[ev.code] and os.time() <= listen_until then
        scheduleCheck("followup")
    end
    return orig_handleMiscEv(this, ev)
end

-- In case we were started directly in a split-screen window.
UIManager:scheduleIn(0.5, function() scheduleCheck("start") end)
plog("all sections loaded")

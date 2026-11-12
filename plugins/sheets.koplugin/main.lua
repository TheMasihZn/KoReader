--[[--
Sheets: spreadsheets for KOReader OS.

* Opens .csv, .tsv (read/write) and .xlsx (read; "Save as CSV" to edit).
* Page-based grid for e-ink: buttons or swipes move a whole screen at a time.
* Tap a cell to see its full content/formula; tap it again (or long-press) to edit.
* Formulas in CSV cells: =SUM(A1:A9), =A1*B2, AVERAGE, MIN, MAX, COUNT, ABS, ROUND.
* Each file opens in its own window, so two sheets can sit side by side.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CSV = require("sheets_csv")
local ConfirmBox = require("ui/widget/confirmbox")
local Font = require("ui/font")
local Formula = require("sheets_formula")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local XLSX = require("sheets_xlsx")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = ffiUtil.template
local Screen = require("device").screen

------------------------------------------------------------------------
-- Grid widget: draws the visible part of a sheet, reports taps.
------------------------------------------------------------------------

local SheetGrid = InputContainer:extend{
    doc = nil,
    width = nil,
    height = nil,
}

function SheetGrid:init()
    local doc = self.doc
    self.face = Font:getFace("smallinfofont")
    self.bold_face = Font:getFace("smallinfofontbold")
    self.pad = Size.padding.default
    local probe = TextWidget:new{ text = "Ag", face = self.face }
    self.row_h = probe:getSize().h + 2 * self.pad
    probe:free()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    local rows = doc:rows()
    local nrows = #rows
    local ncols = 0
    for _, r in ipairs(rows) do if #r > ncols then ncols = #r end end
    ncols = math.max(ncols, 1)
    self.nrows, self.ncols = nrows, ncols

    -- Which rows are visible: the header row stays put when "freeze" is on.
    local fits = math.max(1, math.floor(self.height / self.row_h) - 1) -- minus the column letters
    local row_list = {}
    if doc.freeze and doc.row0 > 1 and nrows >= 1 then
        table.insert(row_list, 1)
        fits = fits - 1
    end
    for r = doc.row0, math.min(nrows, doc.row0 + math.max(fits, 1) - 1) do
        table.insert(row_list, r)
    end
    self.row_list = row_list
    self.page_rows = math.max(1, fits)

    -- Row-number column width.
    local num_w = TextWidget:new{ text = tostring(math.max(nrows, 99)), face = self.face }
    self.num_w = num_w:getSize().w + 2 * self.pad
    num_w:free()

    -- Columns: measure what's visible, add columns while they fit.
    local avail = self.width - self.num_w
    local max_col_w = math.max(Screen:scaleBySize(80), math.floor(avail * 0.5))
    local min_col_w = Screen:scaleBySize(48)
    self.cols = {} -- { c, x, w }
    self.cells = {} -- [r][c] = widget
    local x = self.num_w
    local c = doc.col0
    while c <= ncols do
        local widest = min_col_w
        local col_cells = {}
        for _, r in ipairs(row_list) do
            local text = doc:display(r, c)
            if text ~= "" then
                local tw = TextWidget:new{ text = text, face = (r == 1 and doc.freeze) and self.bold_face or self.face }
                local w = tw:getSize().w + 2 * self.pad
                if w > max_col_w then
                    tw:free()
                    tw = TextWidget:new{
                        text = text,
                        face = (r == 1 and doc.freeze) and self.bold_face or self.face,
                        max_width = max_col_w - 2 * self.pad,
                    }
                    w = max_col_w
                end
                col_cells[r] = tw
                if w > widest then widest = w end
            end
        end
        if x + widest > self.width and #self.cols > 0 then
            for _, tw in pairs(col_cells) do tw:free() end
            break
        end
        widest = math.min(widest, self.width - x)
        table.insert(self.cols, { c = c, x = x, w = widest })
        for r, tw in pairs(col_cells) do
            self.cells[r] = self.cells[r] or {}
            self.cells[r][c] = tw
        end
        x = x + widest
        c = c + 1
    end
    self.page_cols = math.max(1, #self.cols)

    self.ges_events = {
        TapCell = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        HoldCell = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
        SwipeGrid = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
end

function SheetGrid:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function SheetGrid:free()
    for _, row in pairs(self.cells or {}) do
        for _, tw in pairs(row) do tw:free() end
    end
    self.cells = {}
end

function SheetGrid:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local doc = self.doc
    local row_h, pad = self.row_h, self.pad
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    -- Column letters and row numbers on a light background.
    bb:paintRect(x, y, self.width, row_h, Blitbuffer.COLOR_GRAY_E)
    bb:paintRect(x, y, self.num_w, self.height, Blitbuffer.COLOR_GRAY_E)
    for _, col in ipairs(self.cols) do
        local tw = TextWidget:new{ text = Formula.colName(col.c), face = self.face, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
        tw:paintTo(bb, x + col.x + math.floor((col.w - tw:getSize().w) / 2), y + pad)
        tw:free()
    end
    local cy = y + row_h
    for i, r in ipairs(self.row_list) do
        local num = TextWidget:new{ text = tostring(r), face = self.face, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
        num:paintTo(bb, x + self.num_w - pad - num:getSize().w, cy + pad)
        num:free()
        for _, col in ipairs(self.cols) do
            local tw = self.cells[r] and self.cells[r][col.c]
            if tw then
                local tx = x + col.x + pad
                if tonumber(doc:display(r, col.c)) then
                    tx = x + col.x + col.w - pad - tw:getSize().w -- numbers align right
                end
                tw:paintTo(bb, tx, cy + pad)
            end
            if doc.sel_r == r and doc.sel_c == col.c then
                bb:paintBorder(x + col.x, cy, col.w, row_h, Size.border.thick * 2, Blitbuffer.COLOR_BLACK)
            end
        end
        -- Frozen header: a thicker line under it.
        local line = (doc.freeze and r == 1 and i == 1) and Size.border.thick or Size.border.thin
        cy = cy + row_h
        bb:paintRect(x, cy - line, self.width, line, Blitbuffer.COLOR_GRAY)
    end
    for _, col in ipairs(self.cols) do
        bb:paintRect(x + col.x, y, Size.border.thin, cy - y, Blitbuffer.COLOR_LIGHT_GRAY)
    end
    bb:paintRect(x, y + row_h - Size.border.thin, self.width, Size.border.thin, Blitbuffer.COLOR_GRAY)
end

function SheetGrid:_cellAt(pos)
    local rx, ry = pos.x - self.dimen.x, pos.y - self.dimen.y
    local idx = math.floor(ry / self.row_h) -- 0 = column letters
    local r = self.row_list[idx]
    if not r then return end
    for _, col in ipairs(self.cols) do
        if rx >= col.x and rx < col.x + col.w then return r, col.c end
    end
end

function SheetGrid:onTapCell(_, ges)
    local r, c = self:_cellAt(ges.pos)
    if r then self.doc:onCellTap(r, c) end
    return true
end

function SheetGrid:onHoldCell(_, ges)
    local r, c = self:_cellAt(ges.pos)
    if r then self.doc:editCell(r, c) end
    return true
end

function SheetGrid:onSwipeGrid(_, ges)
    local d = ges.direction
    if d == "north" then self.doc:page(1, 0)
    elseif d == "south" then self.doc:page(-1, 0)
    elseif d == "west" then self.doc:page(0, 1)
    elseif d == "east" then self.doc:page(0, -1)
    else return false end
    return true
end

------------------------------------------------------------------------
-- A document: one open file, in its own window.
------------------------------------------------------------------------

local Doc = {}
Doc.__index = Doc

function Doc.open(path)
    local self = setmetatable({ path = path, row0 = 1, col0 = 1, sheet_idx = 1, freeze = true, dirty = false }, Doc)
    if path:lower():match("%.xlsx$") then
        local book, err = XLSX.read(path)
        if not book then return nil, err end
        self.kind = "xlsx"
        self.sheets = book.sheets
    else
        local f, err = io.open(path, "rb")
        if not f then return nil, err end
        local text = f:read("*all") or ""
        f:close()
        self.kind = "csv"
        self.sep = CSV.sniff(text, path)
        self.sheets = { { name = path:match("([^/]+)$"), rows = CSV.parse(text, self.sep) } }
    end
    if #self:rows() == 0 then self.sheets[self.sheet_idx].rows = { { "" } } end
    self:recalc()
    return self
end

function Doc:rows() return self.sheets[self.sheet_idx].rows end
function Doc:raw(r, c) local row = self:rows()[r]; return row and row[c] or "" end
function Doc:display(r, c) return tostring(self.resolve(r, c) or "") end
function Doc:recalc() self.resolve = Formula.makeResolver(self:rows()) end

function Doc:title()
    local name = self.path:match("([^/]+)$")
    if #self.sheets > 1 then name = name .. " · " .. self.sheets[self.sheet_idx].name end
    return (self.dirty and "• " or "") .. name
end

function Doc:refresh()
    if self.window then
        self.window:setTitle(self:title())
        self.window:refresh()
    end
end

function Doc:page(dr, dc)
    local grid = self.grid
    if not grid then return end
    if dr ~= 0 then
        local step = grid.page_rows
        self.row0 = math.max(1, math.min(math.max(1, grid.nrows - step + 1), self.row0 + dr * step))
    end
    if dc ~= 0 then
        local step = grid.page_cols
        self.col0 = math.max(1, math.min(grid.ncols, self.col0 + dc * step))
    end
    self:refresh()
end

function Doc:onCellTap(r, c)
    if self.sel_r == r and self.sel_c == c then
        self:editCell(r, c)
        return
    end
    self.sel_r, self.sel_c = r, c
    self:refresh()
end

function Doc:setCell(r, c, value)
    local rows = self:rows()
    while #rows < r do table.insert(rows, {}) end
    local row = rows[r]
    for k = #row + 1, c - 1 do row[k] = "" end
    row[c] = value
    self.dirty = true
    self:recalc()
end

function Doc:editCell(r, c)
    self.sel_r, self.sel_c = r, c
    local dialog
    dialog = InputDialog:new{
        title = T(_("Cell %1%2"), Formula.colName(c), r),
        input = self:raw(r, c),
        description = _("Start with = for a formula, e.g. =SUM(A1:A9)"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Set"), is_enter_default = true, callback = function()
                local value = dialog:getInputText()
                UIManager:close(dialog)
                self:setCell(r, c, value)
                if value:sub(1, 1) == "=" and self:display(r, c) == "#ERR" then
                    UIManager:show(InfoMessage:new{ text = _("That formula has an error."), timeout = 2 })
                end
                self:refresh()
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Doc:save(path, callback)
    path = path or self.path
    local sep = self.sep or (path:lower():match("%.tsv$") and "\t" or ",")
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then
        UIManager:show(InfoMessage:new{ text = T(_("Could not save: %1"), tostring(err)), icon = "notice-warning" })
        return false
    end
    f:write(CSV.serialize(self:rows(), sep))
    f:close()
    local ok, rerr = os.rename(tmp, path)
    if not ok then
        os.remove(tmp)
        UIManager:show(InfoMessage:new{ text = T(_("Could not save: %1"), tostring(rerr)), icon = "notice-warning" })
        return false
    end
    if path == self.path then self.dirty = false end
    UIManager:show(InfoMessage:new{ text = T(_("Saved %1"), path:match("([^/]+)$")), timeout = 1 })
    self:refresh()
    if callback then callback() end
    return true
end

function Doc:saveAsCSV()
    local base = self.path:gsub("%.[^./]+$", "")
    local name = self.kind == "xlsx" and (base .. " - " .. self.sheets[self.sheet_idx].name:gsub("[/\\]", "_") .. ".csv") or (base .. ".csv")
    local doSave = function()
        if self:save(name) then
            -- Keep working on the CSV, which can be saved normally.
            local new = Doc.open(name)
            if new and self.window then
                self.kind, self.sep, self.path, self.sheets, self.sheet_idx, self.dirty = "csv", new.sep, name, new.sheets, 1, false
                self:recalc()
                self:refresh()
            end
        end
    end
    if require("libs/libkoreader-lfs").attributes(name, "mode") then
        UIManager:show(ConfirmBox:new{
            text = T(_("%1 exists. Replace it?"), name:match("([^/]+)$")),
            ok_text = _("Replace"),
            ok_callback = doSave,
        })
    else
        doSave()
    end
end

function Doc:showMenu()
    local dialog
    local function act(fn) return function() UIManager:close(dialog); fn() end end
    local r, c = self.sel_r or 1, self.sel_c or 1
    local buttons = {
        {
            { text = _("Insert row above"), callback = act(function()
                table.insert(self:rows(), r, {}); self.dirty = true; self:recalc(); self:refresh() end) },
            { text = _("Delete row"), callback = act(function()
                if #self:rows() > 1 then table.remove(self:rows(), r); self.dirty = true; self:recalc(); self:refresh() end end) },
        },
        {
            { text = _("Insert column left"), callback = act(function()
                for _, row in ipairs(self:rows()) do if #row >= c then table.insert(row, c, "") end end
                self.dirty = true; self:recalc(); self:refresh() end) },
            { text = _("Delete column"), callback = act(function()
                for _, row in ipairs(self:rows()) do if #row >= c then table.remove(row, c) end end
                self.dirty = true; self:recalc(); self:refresh() end) },
        },
        {
            { text = self.freeze and _("Unfreeze header row") or _("Freeze header row"), callback = act(function()
                self.freeze = not self.freeze; self:refresh() end) },
            { text = _("Go to top"), callback = act(function() self.row0, self.col0 = 1, 1; self:refresh() end) },
        },
        {
            { text = self.kind == "xlsx" and _("Save sheet as CSV (to edit)") or _("Save a copy as CSV"),
              callback = act(function() self:saveAsCSV() end) },
        },
    }
    dialog = ButtonDialog:new{ title = self:title(), buttons = buttons }
    UIManager:show(dialog)
end

function Doc:chooseSheet()
    local dialog
    local buttons = {}
    for i, sh in ipairs(self.sheets) do
        table.insert(buttons, {{ text = (i == self.sheet_idx and "• " or "") .. sh.name, callback = function()
            UIManager:close(dialog)
            self.sheet_idx, self.row0, self.col0, self.sel_r, self.sel_c = i, 1, 1, nil, nil
            self:recalc()
            self:refresh()
        end }})
    end
    dialog = ButtonDialog:new{ title = _("Sheets"), buttons = buttons }
    UIManager:show(dialog)
end

function Doc:build(window, width, height)
    if self.grid then self.grid:free() end
    -- Top: the selected cell's reference and full content (formula shown as written).
    local info_text
    if self.sel_r then
        local raw = self:raw(self.sel_r, self.sel_c)
        local shown = self:display(self.sel_r, self.sel_c)
        info_text = Formula.colName(self.sel_c) .. self.sel_r .. ":  " .. raw
        if raw ~= shown then info_text = info_text .. "  →  " .. shown end
    else
        info_text = self.kind == "xlsx" and _("Tap a cell. Read-only: save as CSV to edit.") or _("Tap a cell, tap again to edit.")
    end
    local info = TextWidget:new{
        text = info_text,
        face = Font:getFace("smallinfofont"),
        max_width = width - 2 * Size.padding.large,
        padding = Size.padding.default,
    }
    local is_csv = self.kind == "csv"
    local row = {
        { text = "◀", callback = function() self:page(0, -1) end },
        { text = "▲", callback = function() self:page(-1, 0) end },
        { text = "▼", callback = function() self:page(1, 0) end },
        { text = "▶", callback = function() self:page(0, 1) end },
    }
    if #self.sheets > 1 then
        table.insert(row, { text = T(_("Sheet %1/%2"), self.sheet_idx, #self.sheets), callback = function() self:chooseSheet() end })
    end
    table.insert(row, { text = _("Save"), enabled = is_csv and self.dirty, callback = function() self:save() end })
    table.insert(row, { text = "⋯", callback = function() self:showMenu() end })
    local toolbar = ButtonTable:new{
        width = width,
        show_parent = window,
        buttons = { row },
    }
    local grid_h = height - info:getSize().h - toolbar:getSize().h
    self.grid = SheetGrid:new{ doc = self, width = width, height = math.max(grid_h, Screen:scaleBySize(60)) }
    return VerticalGroup:new{
        align = "left",
        info,
        self.grid,
        toolbar,
    }
end

------------------------------------------------------------------------
-- Plugin
------------------------------------------------------------------------

local Sheets = WidgetContainer:extend{
    name = "sheets",
}

function Sheets:init()
    -- Lazy: works whatever order plugins load in (see doc/Apps.md).
    local ok, FileHandlers = pcall(require, "apps/kos/filehandlers")
    if ok then
        FileHandlers:register{
            id = "sheets",
            title = _("Sheets"),
            extensions = { "csv", "tsv", "xlsx" },
            open = function(file) self:openFile(file) end,
        }
    else
        logger.warn("Sheets: KOReader OS file handlers not available", FileHandlers)
    end
end

function Sheets:openFile(path, split_target)
    local doc, err = Doc.open(path)
    if not doc then
        UIManager:show(InfoMessage:new{ text = T(_("Could not open %1:\n%2"), path:match("([^/]+)$"), tostring(err)), icon = "notice-warning" })
        return
    end
    local AppWindow = require("apps/kos/appwindow")
    if split_target then AppWindow.pending_target = split_target end
    doc.window = AppWindow:open{
        title = doc:title(),
        build = function(window, width, height) return doc:build(window, width, height) end,
        confirm_close = function(window, do_close)
            if not doc.dirty then return do_close() end
            UIManager:show(ConfirmBox:new{
                text = T(_("Save changes to %1?"), doc.path:match("([^/]+)$")),
                ok_text = _("Save"),
                ok_callback = function() doc:save(nil, do_close) end,
                cancel_text = _("Discard"),
                cancel_callback = do_close,
            })
        end,
        on_close = function()
            if doc.grid then doc.grid:free() end
        end,
    }
end

-- From the home screen: pick a file, or start a new sheet.
function Sheets:launchApp()
    -- "Open beside" from the home screen: keep where the window should go,
    -- since the actual window only opens after a file is picked.
    local AppWindow = require("apps/kos/appwindow")
    local split_target = AppWindow.pending_target
    AppWindow.pending_target = nil
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local home = filemanagerutil.getHomeFolder() or require("datastorage"):getDataDir()
    local dialog
    dialog = ButtonDialog:new{
        title = _("Sheets"),
        buttons = {
            {{ text = _("Open a spreadsheet…"), callback = function()
                UIManager:close(dialog)
                local PathChooser = require("ui/widget/pathchooser")
                UIManager:show(PathChooser:new{
                    select_directory = false,
                    select_file = true,
                    path = home,
                    file_filter = function(f) return f:lower():match("%.[ct]sv$") or f:lower():match("%.xlsx$") end,
                    onConfirm = function(path) self:openFile(path, split_target) end,
                })
            end }},
            {{ text = _("New spreadsheet"), callback = function()
                UIManager:close(dialog)
                local path = home .. "/" .. os.date("sheet-%Y%m%d-%H%M") .. ".csv"
                local f = io.open(path, "w")
                if f then
                    f:write(",,,\n,,,\n")
                    f:close()
                    self:openFile(path, split_target)
                end
            end }},
        },
    }
    UIManager:show(dialog)
end

return Sheets

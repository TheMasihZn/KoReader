--[[--
KOReader OS workspace: several app windows on screen at once.

Windows (panes) are kept in a layout tree, so any number of them can be
arranged side by side and stacked, nested as deep as you like:

    split(row)               ┌─────────┬─────────┐
    ├── pane: Notes          │         │ Files   │
    └── split(column)        │ Notes   ├─────────┤
        ├── pane: Files      │         │ Hello   │
        └── pane: Hello      └─────────┴─────────┘

* New windows fill the screen automatically: each one splits the largest
  window along its longer side, so 2D space is used evenly.
* Drag a window by its title bar onto another window to rearrange:
  drop on an edge to put it on that side, in the middle to swap the two.
* "Tidy" lays every window out as an even grid.
* Drag a divider to resize the windows on each side of it.
  Tap it to cycle 1/3 · 1/2 · 2/3, long-press it for more options.
* Each window has a menu (top left) to maximise, split, swap, rotate or close it.
* Any app written with AppWindow runs in a pane unchanged: its `build(window,
  width, height)` is simply called with the pane's size.

Apps open here through AppRegistry:launch(app, { split = ... }), or
directly with Workspace:addPane(params, opts).
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local PRESETS = { 1/3, 1/2, 2/3 }

-- On wide screens, keep content at a readable width instead of stretching it
-- (Android's "expanded" layouts): max_content_dp, centred.
local function contentWidth(width, max_dp)
    if not max_dp then return width end
    return math.min(width, Screen:scaleBySize(max_dp))
end

local function centred(content, width, content_w, height)
    if not content or content_w >= width then return content end
    local CenterContainer = require("ui/widget/container/centercontainer")
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, ignore_if_over = "height", content }
end


------------------------------------------------------------------------
-- Pane: one window. Same API as AppWindow (refresh, setTitle, close),
-- so app code can't tell the difference.
------------------------------------------------------------------------

local Pane = InputContainer:extend{
    title = "",
    subtitle = nil,
    build = nil,
    on_close = nil,
    confirm_close = nil,
    max_content_dp = nil,
    workspace = nil,
    rect = nil, -- Geom, absolute position on screen
}

function Pane:setRect(rect)
    self.rect = rect
    self:_layout()
end

function Pane:_layout()
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    local rect = self.rect
    -- Same border width for every pane, so focusing one never changes its size:
    -- only the border colour shows which pane has focus (see paintTo).
    local border = Size.border.thick * 2
    local inner_w = rect.w - 2 * border
    local inner_h = rect.h - 2 * border
    self.title_bar = TitleBar:new{
        width = inner_w,
        title = self.title,
        subtitle = self.subtitle,
        with_bottom_line = true,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self.workspace:showPaneMenu(self) end,
        close_callback = function() self:close() end,
        show_parent = self.workspace,
    }
    local content_h = inner_h - self.title_bar:getHeight()
    local content
    local content_w = contentWidth(inner_w, self.max_content_dp)
    if self.build then
        local ok, result = pcall(self.build, self, content_w, content_h)
        if ok then
            content = centred(result, inner_w, content_w, content_h)
        else
            logger.err("Workspace: build failed for", self.title, result)
        end
    end
    self.content_width, self.content_height = content_w, content_h
    self[1] = FrameContainer:new{
        width = rect.w,
        height = rect.h,
        padding = 0,
        margin = 0,
        bordersize = border,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", self.title_bar, content },
    }
    self.dimen = Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

function Pane:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local focused = self.workspace and self.workspace.focused == self
    self[1].color = focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY
    self[1]:paintTo(bb, x, y)
end

function Pane:refresh()
    self:_layout()
    UIManager:setDirty(self.workspace, "ui", self.dimen)
end

function Pane:setTitle(title, subtitle)
    self.title = title
    if subtitle ~= nil then self.subtitle = subtitle end
    self:refresh()
end

function Pane:close(force)
    if self.confirm_close and not force then
        self.confirm_close(self, function() self:close(true) end)
        return
    end
    self.workspace:closePane(self)
end

-- So apps can call window:goHome() as with AppWindow.
function Pane:goHome()
    UIManager:broadcastEvent(Event:new("ShowAppLauncher"))
end

------------------------------------------------------------------------
-- Workspace
------------------------------------------------------------------------

local Workspace = InputContainer:extend{
    covers_fullscreen = true,
    root = nil,      -- layout tree; leaf = { pane = Pane }, split = { dir = "row"|"column", children = {}, sizes = {} }
    focused = nil,   -- Pane
    maximized = nil, -- Pane shown alone, or nil
}

--- The current workspace, or nil.
Workspace.instance = nil

function Workspace:getInstance()
    if not Workspace.instance then
        Workspace.instance = Workspace:new{}
    end
    return Workspace.instance
end

function Workspace:init()
    self.divider_w = Screen:scaleBySize(10)  -- visible gap between windows
    self.touch_w = Screen:scaleBySize(24)    -- touch zone around a divider (narrow: taps near a window edge stay in the window)
    self.min_size = Screen:scaleBySize(140)  -- no window gets smaller than this
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.dividers = {}
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

-- Default direction for a new split: side by side when wide, stacked when tall.
function Workspace:defaultDir(rect)
    rect = rect or self.dimen
    return rect.w >= rect.h and "row" or "column"
end

local function leafOf(node, pane, parent, index)
    if node.pane then
        if node.pane == pane then return node, parent, index end
        return nil
    end
    for i, child in ipairs(node.children) do
        local found, p, idx = leafOf(child, pane, node, i)
        if found then return found, p, idx end
    end
end

local function eachPane(node, fn)
    if not node then return end
    if node.pane then
        fn(node.pane)
    else
        for _, child in ipairs(node.children) do eachPane(child, fn) end
    end
end

function Workspace:getPanes()
    local panes = {}
    eachPane(self.root, function(p) table.insert(panes, p) end)
    return panes
end

--- Opens an app in a new pane.
-- @param params same as AppWindow:open (title, subtitle, build, on_close)
-- @param opts { dir = "row"|"column"|nil, next_to = Pane|nil }
-- @return the Pane
function Workspace:addPane(params, opts)
    opts = opts or {}
    local pane = Pane:new{
        title = params.title,
        subtitle = params.subtitle,
        build = params.build,
        on_close = params.on_close,
        confirm_close = params.confirm_close,
        max_content_dp = params.max_content_dp,
        workspace = self,
    }
    local leaf = { pane = pane }
    -- "Beside/below this one" uses the focused window; otherwise split the
    -- largest window, so the screen fills up evenly in both directions.
    local anchor = opts.next_to or (opts.dir and self.focused) or self:largestPane() or self.focused
    local anchor_leaf, parent, index
    if anchor and self.root then
        anchor_leaf, parent, index = leafOf(self.root, anchor)
    end
    if not self.root then
        self.root = leaf
    elseif not anchor_leaf then
        -- No anchor: add at the end of the top level.
        local dir = opts.dir or self:defaultDir()
        if self.root.pane or self.root.dir ~= dir then
            self.root = { dir = dir, children = { self.root }, sizes = { 1 } }
        end
        self:_insertChild(self.root, #self.root.children, leaf)
    else
        local dir = opts.dir or self:defaultDir(anchor.rect)
        if parent and parent.dir == dir then
            -- Same direction as the parent: become a sibling, sharing the anchor's space.
            self:_insertChild(parent, index, leaf)
        else
            -- Split the anchor in two.
            local split = { dir = dir, children = { anchor_leaf, leaf }, sizes = { 0.5, 0.5 } }
            if parent then
                parent.children[index] = split
            else
                self.root = split
            end
        end
    end
    self.maximized = nil
    self.focused = pane
    self:show()
    return pane
end

function Workspace:largestPane()
    local best, best_area
    for _, p in ipairs(self:getPanes()) do
        local area = p.rect and p.rect.w * p.rect.h or 0
        if not best_area or area > best_area then
            best, best_area = p, area
        end
    end
    return best
end

-- Inserts `leaf` after position `after` in a split, halving that child's share.
function Workspace:_insertChild(split, after, leaf)
    local share = split.sizes[after] or 0
    if after >= 1 and share > 0 then
        split.sizes[after] = share / 2
        table.insert(split.children, after + 1, leaf)
        table.insert(split.sizes, after + 1, share / 2)
    else
        -- Give the newcomer an equal share.
        local n = #split.children + 1
        for i = 1, #split.sizes do split.sizes[i] = split.sizes[i] * (n - 1) / n end
        table.insert(split.children, leaf)
        table.insert(split.sizes, 1 / n)
    end
end

--- Removes a pane's leaf from the tree without closing the pane. Returns the leaf.
function Workspace:_detach(pane)
    local leaf, parent, index = leafOf(self.root, pane)
    if not leaf then return end
    if not parent then
        self.root = nil
    else
        table.remove(parent.children, index)
        local freed = table.remove(parent.sizes, index)
        -- Give the freed space to the neighbour that touched it.
        local heir = math.min(index, #parent.sizes)
        if heir >= 1 then parent.sizes[heir] = parent.sizes[heir] + freed end
        if #parent.children == 1 then
            -- Collapse a split with a single child into that child.
            local only = parent.children[1]
            self:_replaceNode(parent, only)
        end
    end
    return leaf
end

function Workspace:closePane(pane)
    if not self.root then return end
    if self.maximized == pane then self.maximized = nil end
    if not self:_detach(pane) then return end
    if pane.on_close then
        pcall(pane.on_close, pane)
        pane.on_close = nil
    end
    pane:free()
    if self.focused == pane then
        self.focused = self:getPanes()[1]
    end
    if not self.root then
        UIManager:close(self)
        Workspace.instance = nil
        return
    end
    self:relayout()
end

function Workspace:_replaceNode(old, new)
    if self.root == old then
        self.root = new
        return
    end
    local function walk(node)
        if node.pane then return false end
        for i, child in ipairs(node.children) do
            if child == old then
                node.children[i] = new
                return true
            end
            if walk(child) then return true end
        end
    end
    walk(self.root)
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------

function Workspace:_layoutNode(node, rect)
    if node.pane then
        node.pane:setRect(rect)
        table.insert(self, node.pane)
        return
    end
    local n = #node.children
    local horizontal = node.dir == "row"
    local total = (horizontal and rect.w or rect.h) - (n - 1) * self.divider_w
    local pos = horizontal and rect.x or rect.y
    for i, child in ipairs(node.children) do
        local len = (i == n) and ((horizontal and rect.x + rect.w or rect.y + rect.h) - pos)
            or math.floor(total * node.sizes[i] + 0.5)
        local child_rect = horizontal
            and Geom:new{ x = pos, y = rect.y, w = len, h = rect.h }
            or Geom:new{ x = rect.x, y = pos, w = rect.w, h = len }
        self:_layoutNode(child, child_rect)
        pos = pos + len
        if i < n then
            -- Divider i sits between child i and child i+1.
            table.insert(self.dividers, {
                node = node,
                index = i,
                horizontal = horizontal,
                parent_rect = rect,
                total = total,
                rect = horizontal
                    and Geom:new{ x = pos, y = rect.y, w = self.divider_w, h = rect.h }
                    or Geom:new{ x = rect.x, y = pos, w = rect.w, h = self.divider_w },
            })
            pos = pos + self.divider_w
        end
    end
end

function Workspace:relayout()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    -- Children are rebuilt from the tree on every layout.
    for i = #self, 1, -1 do self[i] = nil end
    self.dividers = {}
    if self.maximized then
        self.maximized:setRect(Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h })
        table.insert(self, self.maximized)
    elseif self.root then
        self:_layoutNode(self.root, Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h })
    end
    UIManager:setDirty(self, "ui")
end

function Workspace:show()
    if not self.shown then
        self.shown = true
        UIManager:show(self)
    end
    self:relayout()
end

function Workspace:onCloseWidget()
    self.shown = false
    if Workspace.instance == self then Workspace.instance = nil end
end

function Workspace:onScreenResize()
    self:relayout()
end

function Workspace:onClose()
    -- Back key: close the focused window.
    if self.focused then
        self:closePane(self.focused)
    else
        UIManager:close(self)
    end
    return true
end

function Workspace:paintTo(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_GRAY_E)
    for _, pane in ipairs(self) do
        pane:paintTo(bb, x + pane.rect.x, y + pane.rect.y)
    end
    for _, d in ipairs(self.dividers) do
        self:_paintDivider(bb, x, y, d)
    end
    if self.move then
        local t = Size.border.thick * 3
        -- Outline the window being moved, and shade where it would land.
        local src = self.move.pane
        if src and src.dimen then
            bb:paintBorder(x + src.dimen.x, y + src.dimen.y, src.dimen.w, src.dimen.h, t, Blitbuffer.COLOR_DARK_GRAY)
        end
        local target = self.move.target
        if target and target.dimen then
            local rx, ry, rw, rh = dropRect(target.dimen, self.move.zone)
            bb:lightenRect(x + rx, y + ry, rw, rh, 0.5)
            bb:paintBorder(x + rx, y + ry, rw, rh, t, Blitbuffer.COLOR_BLACK)
        end
    end
    if self.drag then
        -- Where the divider will land when the finger lifts.
        local d, p = self.drag.divider, self.drag.pos
        local t = Size.border.thick * 2
        if d.horizontal then
            bb:paintRect(x + p - t, y + d.rect.y, 2 * t, d.rect.h, Blitbuffer.COLOR_BLACK)
        else
            bb:paintRect(x + d.rect.x, y + p - t, d.rect.w, 2 * t, Blitbuffer.COLOR_BLACK)
        end
    end
end

function Workspace:_paintDivider(bb, x, y, d)
    -- A small grip in the middle of the gap, so it's clear it can be dragged.
    local r = d.rect
    local grip_long, grip_short = Screen:scaleBySize(36), Screen:scaleBySize(4)
    if d.horizontal then
        bb:paintRect(x + r.x + math.floor((r.w - grip_short) / 2), y + r.y + math.floor((r.h - grip_long) / 2),
            grip_short, grip_long, Blitbuffer.COLOR_DARK_GRAY)
    else
        bb:paintRect(x + r.x + math.floor((r.w - grip_long) / 2), y + r.y + math.floor((r.h - grip_short) / 2),
            grip_long, grip_short, Blitbuffer.COLOR_DARK_GRAY)
    end
end

------------------------------------------------------------------------
-- Rearranging windows
------------------------------------------------------------------------

--- Moves `pane` next to `target`. side: "left" | "right" | "top" | "bottom" | "swap".
function Workspace:movePane(pane, target, side)
    if pane == target or not self.root then return end
    if side == "swap" then
        local a = leafOf(self.root, pane)
        local b = leafOf(self.root, target)
        if a and b then a.pane, b.pane = b.pane, a.pane end
        self:relayout()
        return
    end
    local leaf = self:_detach(pane)
    if not leaf then return end
    local dir = (side == "left" or side == "right") and "row" or "column"
    local before = side == "left" or side == "top"
    if not self.root then
        self.root = leaf
    else
        local t_leaf, parent, index = leafOf(self.root, target)
        if not t_leaf then
            -- Shouldn't happen; put it back at the top level.
            self.root = { dir = dir, children = { self.root, leaf }, sizes = { 0.5, 0.5 } }
        elseif parent and parent.dir == dir then
            -- Sibling in the same row/column: take an equal share from everyone,
            -- so no single window gets squeezed.
            local n = #parent.children + 1
            for k = 1, #parent.sizes do parent.sizes[k] = parent.sizes[k] * (n - 1) / n end
            local at = before and index or index + 1
            table.insert(parent.children, at, leaf)
            table.insert(parent.sizes, at, 1 / n)
        else
            local children = before and { leaf, t_leaf } or { t_leaf, leaf }
            local split = { dir = dir, children = children, sizes = { 0.5, 0.5 } }
            if parent then
                parent.children[index] = split
            else
                self.root = split
            end
        end
    end
    self.focused = pane
    self:relayout()
end

--- Lays every window out as an even grid, using the screen's shape.
function Workspace:tidy()
    local panes = self:getPanes()
    local n = #panes
    if n == 0 then return end
    local w, h = self.dimen.w, self.dimen.h
    -- Pick the grid whose cells are closest to square.
    local best_cols, best_score = 1, math.huge
    for cols = 1, n do
        local rows = math.ceil(n / cols)
        local cell_ratio = (w / cols) / (h / rows)
        local score = math.abs(math.log(cell_ratio)) + (cols * rows - n) * 0.3
        if score < best_score then best_cols, best_score = cols, score end
    end
    local cols = best_cols
    local rows = math.ceil(n / cols)
    local root = { dir = "row", children = {}, sizes = {} }
    local i = 1
    for c = 1, cols do
        -- Spread the remainder over the first columns.
        local in_col = math.floor(n / cols) + ((c <= n % cols) and 1 or 0)
        if n % cols == 0 then in_col = rows end
        local col = { dir = "column", children = {}, sizes = {} }
        for _ = 1, in_col do
            if panes[i] then
                table.insert(col.children, { pane = panes[i] })
                i = i + 1
            end
        end
        for k = 1, #col.children do col.sizes[k] = 1 / #col.children end
        if #col.children == 1 then
            table.insert(root.children, col.children[1])
        elseif #col.children > 1 then
            table.insert(root.children, col)
        end
    end
    for k = 1, #root.children do root.sizes[k] = 1 / #root.children end
    self.root = #root.children == 1 and root.children[1] or root
    self.maximized = nil
    self:relayout()
end

function Workspace:_paneAt(pos)
    for _, pane in ipairs(self) do
        if pane.dimen and pane.dimen:contains(pos) then return pane end
    end
end

-- Which part of `target` a point is over: an edge, or the middle (swap).
function Workspace:_dropZone(target, pos)
    local r = target.dimen
    local fx = (pos.x - r.x) / r.w
    local fy = (pos.y - r.y) / r.h
    if fx > 0.3 and fx < 0.7 and fy > 0.3 and fy < 0.7 then return "swap" end
    -- Nearest edge.
    local d = { left = fx, right = 1 - fx, top = fy, bottom = 1 - fy }
    local side, best = "left", 2
    for k, v in pairs(d) do
        if v < best then side, best = k, v end
    end
    return side
end

-- The rectangle a drop would fill, for the preview.
local function dropRect(r, zone)
    if zone == "left" then return r.x, r.y, math.floor(r.w / 2), r.h end
    if zone == "right" then return r.x + math.floor(r.w / 2), r.y, r.w - math.floor(r.w / 2), r.h end
    if zone == "top" then return r.x, r.y, r.w, math.floor(r.h / 2) end
    if zone == "bottom" then return r.x, r.y + math.floor(r.h / 2), r.w, r.h - math.floor(r.h / 2) end
    return r.x, r.y, r.w, r.h
end

function Workspace:_titleBarAt(pos)
    if not pos or self.maximized then return end
    for _, pane in ipairs(self) do
        local d = pane.dimen
        local tb_h = pane.title_bar and pane.title_bar:getHeight() or 0
        if d and pos.x >= d.x and pos.x <= d.x + d.w and pos.y >= d.y and pos.y <= d.y + tb_h + Size.border.thick * 2 then
            return pane
        end
    end
end

function Workspace:_handleMoveGesture(ges)
    local kind = ges.ges
    if kind == "pan" then
        local src = self.move and self.move.pane or self:_titleBarAt(ges.start_pos)
        if not src or #self:getPanes() < 2 then return false end
        local target = self:_paneAt(ges.pos)
        if target == src then target = nil end
        self.move = { pane = src, target = target, zone = target and self:_dropZone(target, ges.pos) }
        UIManager:setDirty(self, "fast")
        return true
    elseif kind == "pan_release" then
        if not self.move then return false end
        local m = self.move
        self.move = nil
        local target = self:_paneAt(ges.pos)
        if target and target ~= m.pane then
            self:movePane(m.pane, target, self:_dropZone(target, ges.pos))
        else
            UIManager:setDirty(self, "ui")
        end
        return true
    elseif kind == "swipe" then
        -- A quick drag of a title bar.
        local src = self:_titleBarAt(ges.pos)
        if not src or not ges.end_pos or #self:getPanes() < 2 then return false end
        local target = self:_paneAt(ges.end_pos)
        if not target or target == src then return false end
        self:movePane(src, target, self:_dropZone(target, ges.end_pos))
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Dividers: drag, tap, long-press
------------------------------------------------------------------------

function Workspace:_dividerAt(pos)
    if not pos then return end
    local half = math.floor(self.touch_w / 2)
    for _, d in ipairs(self.dividers) do
        local r = d.rect
        local zone = d.horizontal
            and Geom:new{ x = r.x + math.floor(r.w / 2) - half, y = r.y, w = self.touch_w, h = r.h }
            or Geom:new{ x = r.x, y = r.y + math.floor(r.h / 2) - half, w = r.w, h = self.touch_w }
        if zone:contains(pos) then return d end
    end
end

-- Moves divider `d` so that its centre is at screen coordinate `p`.
function Workspace:_moveDivider(d, p)
    local node, i = d.node, d.index
    local start = d.horizontal and d.parent_rect.x or d.parent_rect.y
    -- Space before child i (children 1..i-1 plus their dividers).
    local before = 0
    for k = 1, i - 1 do before = before + node.sizes[k] end
    local first_px = start + math.floor(before * d.total + 0.5) + (i - 1) * self.divider_w
    local pair = node.sizes[i] + node.sizes[i + 1]
    local pair_px = pair * d.total
    local len_i = p - math.floor(self.divider_w / 2) - first_px
    len_i = math.max(self.min_size, math.min(pair_px - self.min_size, len_i))
    if pair_px < 2 * self.min_size then return end -- too small to resize
    node.sizes[i] = pair * len_i / pair_px
    node.sizes[i + 1] = pair - node.sizes[i]
end

function Workspace:_cyclePreset(d)
    local node, i = d.node, d.index
    local pair = node.sizes[i] + node.sizes[i + 1]
    local current = node.sizes[i] / pair
    local next_ratio = PRESETS[1]
    for _, r in ipairs(PRESETS) do
        if r > current + 0.02 then
            next_ratio = r
            break
        end
    end
    node.sizes[i] = pair * next_ratio
    node.sizes[i + 1] = pair - node.sizes[i]
    self:relayout()
end

function Workspace:showDividerMenu(d)
    local node = d.node
    local dialog
    local function act(fn)
        return function()
            UIManager:close(dialog)
            fn()
            self:relayout()
        end
    end
    dialog = ButtonDialog:new{
        title = _("Windows"),
        buttons = {
            {
                { text = "1/3 · 2/3", callback = act(function() node.sizes[d.index], node.sizes[d.index + 1] = (node.sizes[d.index] + node.sizes[d.index + 1]) / 3, (node.sizes[d.index] + node.sizes[d.index + 1]) * 2 / 3 end) },
                { text = "1/2 · 1/2", callback = act(function() local s = (node.sizes[d.index] + node.sizes[d.index + 1]) / 2; node.sizes[d.index], node.sizes[d.index + 1] = s, s end) },
                { text = "2/3 · 1/3", callback = act(function() node.sizes[d.index], node.sizes[d.index + 1] = (node.sizes[d.index] + node.sizes[d.index + 1]) * 2 / 3, (node.sizes[d.index] + node.sizes[d.index + 1]) / 3 end) },
            },
            {
                { text = _("Tidy all"), callback = function()
                    UIManager:close(dialog)
                    self:tidy()
                end },
                { text = _("All equal"), callback = act(function()
                    for k = 1, #node.sizes do node.sizes[k] = 1 / #node.sizes end
                end) },
                { text = _("Swap"), callback = act(function()
                    local i = d.index
                    node.children[i], node.children[i + 1] = node.children[i + 1], node.children[i]
                    node.sizes[i], node.sizes[i + 1] = node.sizes[i + 1], node.sizes[i]
                end) },
                { text = node.dir == "row" and _("Stack") or _("Side by side"), callback = act(function()
                    node.dir = node.dir == "row" and "column" or "row"
                end) },
            },
        },
    }
    UIManager:show(dialog)
end

-- Your Gestures keep working in split view too (apps/kos/gestureforward.lua).
function Workspace:handleEvent(event)
    return require("apps/kos/gestureforward").handle(self, event, Workspace._handleEvent)
end

function Workspace:_handleEvent(event)
    if event.handler == "onGesture" then
        local ges = event.args and event.args[1]
        if ges and (self:_handleDividerGesture(ges) or self:_handleMoveGesture(ges)) then
            return true
        end
        -- Touching a window focuses it (the touch still reaches the window).
        if ges and ges.ges == "tap" and not self.maximized then
            for _, pane in ipairs(self) do
                if pane.dimen and pane.dimen:contains(ges.pos) and self.focused ~= pane then
                    local previous = self.focused
                    self.focused = pane
                    UIManager:setDirty(self, "ui", pane.dimen)
                    if previous and previous.dimen then
                        UIManager:setDirty(self, "ui", previous.dimen)
                    end
                    break
                end
            end
        end
    end
    return InputContainer.handleEvent(self, event)
end

function Workspace:_handleDividerGesture(ges)
    local kind = ges.ges
    if kind == "pan" then
        local d = self.drag and self.drag.divider or self:_dividerAt(ges.start_pos)
        if not d then return false end
        local p = d.horizontal and ges.pos.x or ges.pos.y
        self.drag = { divider = d, pos = p }
        UIManager:setDirty(self, "fast", d.parent_rect)
        return true
    elseif kind == "pan_release" then
        if not self.drag then return false end
        local d = self.drag.divider
        self.drag = nil
        self:_moveDivider(d, d.horizontal and ges.pos.x or ges.pos.y)
        self:relayout()
        return true
    elseif kind == "swipe" then
        -- A quick drag is reported as a swipe: start and end points are all we need.
        local d = self:_dividerAt(ges.pos)
        if not d or not ges.end_pos then return false end
        self:_moveDivider(d, d.horizontal and ges.end_pos.x or ges.end_pos.y)
        self:relayout()
        return true
    elseif kind == "tap" then
        local d = self:_dividerAt(ges.pos)
        if not d then return false end
        self:_cyclePreset(d)
        return true
    elseif kind == "hold" then
        local d = self:_dividerAt(ges.pos)
        if not d then return false end
        self:showDividerMenu(d)
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Pane menu
------------------------------------------------------------------------

function Workspace:showPaneMenu(pane)
    local dialog
    local function act(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    local function openNext(dir)
        -- Pick an app on the home screen; it opens next to this pane.
        UIManager:broadcastEvent(Event:new("ShowAppLauncher", { split = { next_to = pane, dir = dir } }))
    end
    dialog = ButtonDialog:new{
        title = pane.title,
        buttons = {
            {
                { text = _("Add window beside"), callback = act(function() openNext("row") end) },
                { text = _("Add window below"), callback = act(function() openNext("column") end) },
            },
            {
                { text = self.maximized == pane and _("Restore") or _("Maximize"), callback = act(function()
                    self.maximized = self.maximized ~= pane and pane or nil
                    self.focused = pane
                    self:relayout()
                end) },
                { text = _("Close"), callback = act(function() self:closePane(pane) end) },
            },
            {
                { text = _("Tidy all windows"), callback = act(function() self:tidy() end) },
                { text = _("Close all windows"), callback = act(function()
                    for _, p in ipairs(self:getPanes()) do self:closePane(p) end
                end) },
            },
        },
    }
    UIManager:show(dialog)
end

return Workspace

--[[--
A single-line, Windows Explorer style "address bar" showing a path as
tappable segments, e.g.:

    Home › Books › Manga › Cells at Work

Each segment can be tapped to jump to it. When the full path does not
fit in max_width, the leading segments are collapsed into a "…" segment
(the deepest folders always stay visible).

Segments are given as a list of tables:

    { text = "Books", path = "/mnt/onboard/Books" }

A segment without a path is displayed but not tappable.

@usage
    local BreadcrumbWidget = require("ui/widget/breadcrumbwidget")
    local crumbs = BreadcrumbWidget:new{
        max_width = 400,
        segments = { {text = "/", path = "/"}, {text = "mnt", path = "/mnt"} },
        callback = function(path) print("go to", path) end,
        overflow_callback = function() print("tapped …") end,
        hold_callback = function() print("long-pressed the bar") end,
    }
]]

local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")

local BreadcrumbWidget = InputContainer:extend{
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

return BreadcrumbWidget

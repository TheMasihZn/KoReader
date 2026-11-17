local AppRegistry = require("apps/kos/appregistry")
local AppWindow = require("apps/kos/appwindow")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CanvasModel = require("apps/kos/canvasmodel")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

-- The drawing surface: draws what the model says is visible, forwards drags and holds.
local Surface = InputContainer:extend{ model = nil, width = nil, height = nil, on_hold = nil, on_change = nil }

function Surface:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        Pan = { GestureRange:new{ ges = "pan", range = self.dimen } },
        PanRelease = { GestureRange:new{ ges = "pan_release", range = self.dimen } },
        Hold = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function Surface:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    for _i, e in ipairs(self.model:visible()) do
        local box = FrameContainer:new{
            bordersize = 1, padding = Screen:scaleBySize(6), margin = 0,
            width = e.item.w, height = e.item.h,
            TextBoxWidget:new{
                text = e.item.app and ("▣ " .. e.item.app) or (e.item.text or ""),
                face = Font:getFace("cfont", 18), width = e.item.w - Screen:scaleBySize(16),
            },
        }
        box:paintTo(bb, x + e.x, y + e.y)
        box:free()
    end
end

function Surface:onPan(_args, ges)
    -- pan events carry the distance since the start; apply the step since the last event
    local px, py = self._px or 0, self._py or 0
    local dx, dy = (ges.relative.x or 0) - px, (ges.relative.y or 0) - py
    self._px, self._py = ges.relative.x or 0, ges.relative.y or 0
    self.model:pan(dx, dy)
    UIManager:setDirty(self, "ui")
    return true
end

function Surface:onPanRelease()
    self._px, self._py = 0, 0
    if self.on_change then self.on_change() end
    return true
end

function Surface:onHold(_args, ges)
    local sx, sy = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    if self.on_hold then self.on_hold(sx, sy, self.model:hit(sx, sy)) end
    return true
end

local Plugin = WidgetContainer:extend{ name = "kosCanvas", is_doc_only = false }

local function save(model) G_reader_settings:saveSetting("kos_canvas", model:toData()) end

function Plugin:launchApp()
    local function build(win, width, height)
        local model = CanvasModel.fromData(G_reader_settings:readSetting("kos_canvas"), { w = width, h = height })
        local surface
        surface = Surface:new{
            model = model, width = width, height = height,
            on_change = function() save(model) end,
            on_hold = function(sx, sy, item)
                local dlg
                local function close() UIManager:close(dlg) end
                local buttons = {}
                if item then
                    buttons[#buttons + 1] = {{ text = _("Move here next time"), callback = function() close() end }}
                    buttons[#buttons + 1] = {{ text = _("Remove"), callback = function()
                        close(); model:remove(item.id); save(model); UIManager:setDirty(surface, "ui")
                    end }}
                else
                    local wx, wy = sx + model.ox, sy + model.oy
                    buttons[#buttons + 1] = {{ text = _("Note here"), callback = function()
                        close()
                        local d
                        d = InputDialog:new{ title = _("Note"), buttons = {{
                            { text = _("Cancel"), callback = function() UIManager:close(d) end },
                            { text = _("Put it here"), is_enter_default = true, callback = function()
                                local t = d:getInputText(); UIManager:close(d)
                                if t ~= "" then model:add{ x = wx, y = wy, text = t }; save(model); UIManager:setDirty(surface, "ui") end
                            end },
                        }} }
                        UIManager:show(d); d:onShowKeyboard()
                    end }}
                    buttons[#buttons + 1] = {{ text = _("App here"), callback = function()
                        close()
                        local rows = {}
                        for _i, a in ipairs(AppRegistry:getApps()) do
                            rows[#rows + 1] = {{ text = a.title, callback = function()
                                UIManager:close(dlg)
                                model:add{ x = wx, y = wy, app = a.title }; save(model); UIManager:setDirty(surface, "ui")
                            end }}
                        end
                        dlg = ButtonDialog:new{ title = _("Which app?"), buttons = rows }
                        UIManager:show(dlg)
                    end }}
                end
                dlg = ButtonDialog:new{ buttons = buttons }
                UIManager:show(dlg)
            end,
        }
        return surface
    end
    AppWindow:open{ title = _("Canvas"), build = build }
end

return Plugin

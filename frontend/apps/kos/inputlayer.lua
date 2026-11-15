--[[--
Input layer: the one door the OS's local model (or any script) uses to act like a user.

It sends taps, swipes and typed text through KOReader's normal event path,
the same one your finger uses, so nothing happens that you could not do by hand.
Every action is drawn on a small overlay (a ring where it lands) and appended to
`koreader/kos-trace.log` as one line: time, who, action, details, result.

    local IL = require("apps/kos/inputlayer")
    IL.tap(300, 500, "gemma")
    IL.swipe(100, 800, 100, 300, "gemma")
    IL.type("hello", "gemma")

`who` is just a label for the log. Set IL.enabled = false to stop all actions.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local IL = { enabled = true, overlay = true }

local TRACE = DataStorage:getDataDir() .. "/kos-trace.log"

--- One trace line. Kept small: the file is cut when it passes 300 KB.
function IL.format(who, action, detail, result)
    return string.format("%s %s %s %s -> %s", os.date("%Y-%m-%d %H:%M:%S"), who or "?", action, detail or "", result or "ok")
end

local function trace(who, action, detail, result)
    local f = io.open(TRACE, "a")
    if f then
        f:write(IL.format(who, action, detail, result), "\n")
        f:close()
    end
end
IL.trace = trace

-- A ring drawn where an action lands, for about 0.7 s. It never takes input.
local function ring(x, y)
    if not IL.overlay then return end
    pcall(function()
        local Blitbuffer = require("ffi/blitbuffer")
        local Widget = require("ui/widget/widget")
        local r = Device.screen:scaleBySize(18)
        local Ring = Widget:extend{ dimen = Geom:new{ x = x - r, y = y - r, w = 2 * r, h = 2 * r } }
        function Ring:paintTo(bb, px, py)
            bb:paintRoundedRect(self.dimen.x, self.dimen.y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_DARK_GRAY, r)
            bb:paintRoundedRect(self.dimen.x + 3, self.dimen.y + 3, self.dimen.w - 6, self.dimen.h - 6, Blitbuffer.COLOR_WHITE, r - 3)
        end
        local w = Ring:new{}
        UIManager:show(w, "ui")
        UIManager:scheduleIn(0.7, function() UIManager:close(w, "ui") end)
    end)
end

local function gesture(ges, pos, extra)
    local g = { ges = ges, pos = Geom:new{ x = pos.x, y = pos.y, w = 0, h = 0 }, time = require("ui/time").realtime() }
    for k, v in pairs(extra or {}) do g[k] = v end
    UIManager:sendEvent(Event:new("Gesture", g))
end

function IL.tap(x, y, who)
    if not IL.enabled then trace(who, "tap", x .. "," .. y, "blocked") return false end
    ring(x, y)
    local ok, err = pcall(gesture, "tap", { x = x, y = y })
    trace(who, "tap", x .. "," .. y, ok and "ok" or tostring(err))
    return ok
end

function IL.hold(x, y, who)
    if not IL.enabled then trace(who, "hold", x .. "," .. y, "blocked") return false end
    ring(x, y)
    local ok, err = pcall(gesture, "hold", { x = x, y = y })
    trace(who, "hold", x .. "," .. y, ok and "ok" or tostring(err))
    return ok
end

--- direction is worked out from the two points: "north", "south", "east", "west".
function IL.swipe(x1, y1, x2, y2, who)
    if not IL.enabled then trace(who, "swipe", x1 .. "," .. y1 .. ">" .. x2 .. "," .. y2, "blocked") return false end
    local dx, dy = x2 - x1, y2 - y1
    local dir
    if math.abs(dx) > math.abs(dy) then dir = dx > 0 and "east" or "west" else dir = dy > 0 and "south" or "north" end
    ring(x1, y1)
    ring(x2, y2)
    local ok, err = pcall(gesture, "swipe", { x = x1, y = y1 }, {
        direction = dir, distance = math.sqrt(dx * dx + dy * dy),
        pos_to = Geom:new{ x = x2, y = y2, w = 0, h = 0 },
    })
    trace(who, "swipe", x1 .. "," .. y1 .. ">" .. x2 .. "," .. y2 .. " " .. dir, ok and "ok" or tostring(err))
    return ok
end

--- Types text into the input box that is open and focused (like a keyboard would).
function IL.type(text, who)
    if not IL.enabled then trace(who, "type", #text .. " chars", "blocked") return false end
    local top = UIManager:getTopmostVisibleWidget()
    local input = top and (top._input_widget or top.input_widget)
    if not (input and input.addChars) then
        trace(who, "type", #text .. " chars", "no input box is open")
        return false
    end
    local ok, err = pcall(function() input:addChars(text) end)
    trace(who, "type", #text .. " chars", ok and "ok" or tostring(err))
    return ok
end

---------------------------------------------------------------------------
-- Buttons: press any key by name, and hear every key and gesture.
---------------------------------------------------------------------------

--- Names usable with IL.key: the Android hardware keys plus letters, arrows, etc.
function IL.keyNames()
    local names, seen = {}, {}
    local ok, map = pcall(require, "device/android/event_map")
    if ok and type(map) == "table" then
        for _k, v in pairs(map) do
            if type(v) == "string" and not seen[v] then seen[v] = true names[#names + 1] = v end
        end
    end
    for _i, v in ipairs({ "Back", "Home", "Menu", "Press", "Up", "Down", "Left", "Right", "LPgBack", "LPgFwd",
                          "RPgBack", "RPgFwd", "Enter", "Backspace", "Del", "Tab", "Space", "Escape" }) do
        if not seen[v] then seen[v] = true names[#names + 1] = v end
    end
    table.sort(names)
    return names
end

--- Presses and releases a key inside KOReader, like a hardware button would.
-- `modifiers` is optional: { Shift = true, Ctrl = true }.
-- (Android's own system buttons, such as the volume rocker, cannot be pressed by an app.)
function IL.key(name, who, modifiers)
    if not IL.enabled then trace(who, "key", tostring(name), "blocked") return false end
    local ok, err = pcall(function()
        local Key = require("device/key")
        local key = Key:new(name, modifiers or {})
        key.__kos_synthetic = true
        UIManager:sendEvent(Event:new("KeyPress", key))
        UIManager:sendEvent(Event:new("KeyRelease", key))
    end)
    trace(who, "key", tostring(name), ok and "ok" or tostring(err))
    return ok
end

local listeners, installed = {}, false

local function emit(info)
    for fn in pairs(listeners) do
        local ok, err = pcall(fn, info)
        if not ok then listeners[fn] = nil end -- a broken listener is dropped, not retried
    end
end

local function install()
    if installed then return end
    installed = true
    local orig = UIManager.sendEvent
    UIManager.sendEvent = function(self, event, ...)
        local h = event and event.handler
        if h == "onGesture" and event.args and event.args[1] then
            local g = event.args[1]
            emit{ kind = "gesture", name = g.ges, x = g.pos and g.pos.x, y = g.pos and g.pos.y, direction = g.direction }
        elseif h == "onKeyPress" or h == "onKeyRelease" then
            local k = event.args and event.args[1]
            emit{ kind = "key", name = k and k.key, down = h == "onKeyPress", synthetic = k and k.__kos_synthetic or false }
        end
        return orig(self, event, ...)
    end
end

--- Calls fn(info) for every key and gesture KOReader receives, real or synthetic.
-- info = { kind = "key", name = "LPgBack", down = true/false, synthetic = bool }
--      | { kind = "gesture", name = "tap"/"swipe"/..., x, y, direction }
-- Returns a function that stops listening. fn errors drop the listener.
function IL.listen(fn)
    install()
    listeners[fn] = true
    return function() listeners[fn] = nil end
end

return IL

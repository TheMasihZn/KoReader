--[[--
Lets your Gestures (Settings › Taps and gestures) work while a KOReader OS
app window is open.

App windows cover the screen, so touches used to stop at them and never
reached the gesture zones of the file browser or reader underneath: a
corner long-press set to open a plugin did nothing while Studio was open.

* Long-press, multi-swipe and two-finger gestures that you assigned an
  action to are handled first, like system gestures.
* Taps and swipes go to the app first; if the app doesn't use them,
  they're passed on.
* Only gestures with an assigned action are forwarded, so a tap in an app
  never turns the page of the book behind it.
]]

local GestureForward = {
    -- True while a forwarded gesture's action runs: its events (sent to the
    -- topmost window, i.e. the app) are passed on to the file browser/reader.
    dispatching = false,
}

-- Gesture types that are "yours" before the app's.
local PRIORITY = {
    hold = true, multiswipe = true,
    two_finger_tap = true, two_finger_swipe = true, two_finger_hold = true,
    spread = true, pinch = true, rotate = true,
}

local function currentUI()
    local ReaderUI = package.loaded["apps/reader/readerui"]
    if ReaderUI and ReaderUI.instance then return ReaderUI.instance end
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    if FileManager and FileManager.instance then return FileManager.instance end
end

--- Runs the user's gesture action matching `ges`, if any. Returns true if one ran.
function GestureForward.forward(ges)
    local ui = currentUI()
    local gestures = ui and ui.gestures
    if not (gestures and gestures.gestures and ui._ordered_touch_zones) then return false end
    for _, tzone in ipairs(ui._ordered_touch_zones) do
        local id = tzone.def and tzone.def.id
        -- Only the Gestures plugin's zones that have something assigned.
        local assigned = id and (gestures.gestures[id] ~= nil
            or (id == "multiswipe" and ges.ges == "multiswipe"))
        if assigned and tzone.gs_range:match(ges) then
            GestureForward.dispatching = true
            local ok, handled = pcall(tzone.handler, ges)
            GestureForward.dispatching = false
            if ok and handled then return true end
        end
    end
    return false
end

function GestureForward.isPriority(ges)
    return ges and PRIORITY[ges.ges] or false
end

--- Wraps a widget's handleEvent: priority gestures first, others after the app.
-- `inner` is the widget's own handleEvent.
function GestureForward.handle(widget, event, inner)
    if event.handler == "onGesture" then
        local ges = event.args and event.args[1]
        if ges and GestureForward.isPriority(ges) and GestureForward.forward(ges) then
            return true
        end
        if inner(widget, event) then return true end
        if ges and not GestureForward.isPriority(ges) then
            return GestureForward.forward(ges)
        end
        return false
    end
    if inner(widget, event) then return true end
    -- An action started by a forwarded gesture: let the file browser / reader
    -- (and its plugins) handle what the app didn't.
    if GestureForward.dispatching then
        local ui = currentUI()
        if ui and ui ~= widget then return ui:handleEvent(event) end
    end
    return false
end

return GestureForward

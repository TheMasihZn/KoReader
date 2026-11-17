local store = {}
G_reader_settings = { readSetting = function(_, k) return store[k] end }
local GF = dofile("frontend/apps/kos/gestureforward.lua")
-- fake file browser with a hold zone that has an action assigned
local ran = {}
package.loaded["apps/filemanager/filemanager"] = { instance = {
  gestures = { gestures = { hold_top_left_corner = "open_x" } },
  _ordered_touch_zones = { { def = { id = "hold_top_left_corner" }, gs_range = { match = function(_, g) return g.pos.x < 10 end },
                             handler = function(g) ran[#ran + 1] = g.ges; return true end } } } }
local Menu = {}; Menu.handleEvent = function(self, ev) self.seen = (self.seen or 0) + 1; return ev.handler == "onTap" end
assert(GF.installMenus(Menu) == true and GF.installMenus(Menu) == false)       -- installed once only
local coll = { covers_fullscreen = true }
local hold = { handler = "onGesture", args = { { ges = "hold", pos = { x = 5, y = 5 } } } }
assert(Menu.handleEvent(coll, hold) == true and ran[1] == "hold" and coll.seen == nil)   -- the assigned hold reaches the file browser, the menu is not asked
local away = { handler = "onGesture", args = { { ges = "hold", pos = { x = 500, y = 5 } } } }
Menu.handleEvent(coll, away); assert(coll.seen == 1 and #ran == 1)                          -- a hold elsewhere stays with the menu
local small = { covers_fullscreen = false }; Menu.handleEvent(small, hold); assert(small.seen == 1 and #ran == 1)  -- popup menus untouched
store.kos_menu_gestures = false; Menu.handleEvent(coll, hold); assert(#ran == 1)            -- switch off
print("menu gestures ok")

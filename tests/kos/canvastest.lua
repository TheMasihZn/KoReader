local C = dofile("frontend/apps/kos/canvasmodel.lua")
local c = C.new({ w = 100, h = 100 })
local a = c:add{ x = 10, y = 10, w = 20, h = 20, text = "a" }
local b = c:add{ x = 500, y = 500, w = 20, h = 20, app = "p" }
assert(#c:visible() == 1)
c:pan(-490, -490)            -- finger moves left/up -> page moves; view now at (490,490)
local v = c:visible(); assert(#v == 1 and v[1].item == b and v[1].x == 10 and v[1].y == 10)
c:pan(490, 490); assert(c.ox == 0 and c.oy == 0)
c:pan(-50, 0); assert(c.ox == 50)  -- dragging left shows what is on the right
c:moveTo(0, 0)
assert(c:hit(15, 15) == a and c:hit(60, 60) == nil)
c:drag(a, 5, 5); assert(a.x == 15)
local x0, y0, x1, y1 = c:bounds(); assert(x0 == 15 and y1 == 520)
c:fitAll(); assert(c.ox == 15)
local d = c:toData(); local r = C.fromData(d, { w = 100, h = 100 }); assert(#r.items == 2 and r.ox == 15 and r.items[2].app == "p")
assert(c:remove(a.id) and #c.items == 1 and not c:remove(999))
c:add{ x = 0, y = 0, w = 5, h = 5, z = 3 }; c:moveTo(490, 490); assert(#c:visible() == 1)
assert(#C.fromData(nil, { w = 1, h = 1 }).items == 0)
print("canvas ok")

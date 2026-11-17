package.path = "plugins/icons.koplugin/?.lua;" .. package.path
local Model = dofile("plugins/icons.koplugin/iconmodel.lua")
local suits = dofile("plugins/icons.koplugin/holycart.lua")
assert(#suits == 302, "count")
local bad = 0
for _, su in ipairs(suits) do
  local m = Model.fromSuit(su)
  assert(#m.shapes == 1 and #m.shapes[1].points >= 3, su.id)
  local svg = m:toSVG()
  assert(svg:find("<path"), su.id)
  -- round trip through the saved-drawing format
  local m2, err = Model.fromLua(m:toLua())
  assert(m2, su.id .. " " .. tostring(err))
  local a, b = #(m.shapes[1].rings or {}), #(m2.shapes[1].rings or {})
  if a ~= b then bad = bad + 1 end
  -- undo copy keeps rings
  m:checkpoint(); m:clear(); m:undo()
  assert(#(m.shapes[1].rings or {}) == a, "undo " .. su.id)
end
print("ok 302 suits, ring mismatches:", bad)
local m = Model.fromSuit(suits[1]); print(#m:toSVG(), "bytes svg", #m:toLua(), "bytes lua")
print(suits[150].name, "|", suits[150].formula)

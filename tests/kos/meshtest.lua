local Mesh = dofile("frontend/apps/kos/mesh.lua")
local function near(a, b, tol) assert(math.abs(a - b) <= (tol or 1e-6), a .. " vs " .. b) end
-- box: 10 x 20 x 30
local b = Mesh.box(10, 20, 30)
near(Mesh.volume(b), 6000); near(Mesh.area(b), 2 * (200 + 300 + 600))
local r = Mesh.report(b, 1.24); assert(r.closed and not r.inside_out and r.triangles == 12)
near(r.mass_g, 6000 / 1000 * 1.24)
-- cylinder r=5 h=10, 96 sides approaches pi r^2 h
local c = Mesh.cylinder(5, 10, 96)
assert(math.abs(Mesh.volume(c) - math.pi * 25 * 10) / (math.pi * 250) < 0.002, Mesh.volume(c))
assert(Mesh.report(c).closed)
-- ascii round trip
local back = assert(Mesh.parseSTL(Mesh.toSTL(b))); near(Mesh.volume(back), 6000, 1e-3); assert(#back == 12)
-- binary STL written by hand: one triangle
local function f32(x)
  if x == 0 then return "\0\0\0\0" end
  local sign = x < 0 and 1 or 0; x = math.abs(x)
  local e = math.floor(math.log(x, 2)); local m = x / 2 ^ e - 1
  local mi = math.floor(m * 8388608 + 0.5); local ex = e + 127
  local bits = sign * 2 ^ 31 + ex * 2 ^ 23 + mi
  local t = {}; for i = 1, 4 do t[i] = string.char(bits % 256); bits = math.floor(bits / 256) end
  return table.concat(t)
end
local bin = string.rep("\0", 80) .. "\1\0\0\0" .. f32(0)..f32(0)..f32(1) .. f32(0)..f32(0)..f32(0) .. f32(2.5)..f32(0)..f32(0) .. f32(0)..f32(-4)..f32(0) .. "\0\0"
local tri = assert(Mesh.parseSTL(bin)); near(tri[1][2][1], 2.5); near(tri[1][3][2], -4)
-- open mesh (one triangle) is not closed
assert(not Mesh.report(tri).closed)
-- overhang: a box on the bed has none; a box floating above has its bottom face
near(Mesh.overhang(b, 45), 0)
near(Mesh.overhang(Mesh.join(Mesh.box(10,10,2), Mesh.box(10,10,2,0,0,10)), 45), 100)
-- script
local m = assert(Mesh.runScript("return join(box(10,10,2), cylinder(3,8,32,5,5,2))"))
assert(#m == 12 + 128)
assert(not Mesh.runScript("os.execute('x')"), "no os in the script")
assert(select(2, Mesh.runScript("return 5")) == "the script must return a mesh")
-- projection fits inside the square
local P = Mesh.projector(b, 30, 25, 400, 1)
for _, t in ipairs(b) do for k = 1, 3 do local x, y = P(t[k]); assert(x >= 0 and x <= 400 and y >= 0 and y <= 400) end end
-- inside out
local flipped = {} for i, t in ipairs(b) do flipped[i] = { t[1], t[3], t[2] } end
assert(Mesh.report(flipped).inside_out)
print("mesh ok")

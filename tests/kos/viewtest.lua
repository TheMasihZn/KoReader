local function class()
  local c = {}
  c.__index = c
  function c:extend(t) t = t or {}; t.__index = t; return setmetatable(t, self) end
  function c:new(t) t = t or {}; return setmetatable(t, self) end
  function c:getSize() return self.dimen end
  return c
end
local calls = 0
local stubs = {
  ["apps/kos/appwindow"] = { open = function(_, p) _G.APP = p; return { refresh = function() end } end },
  ["ffi/blitbuffer"] = { COLOR_WHITE = 1, COLOR_BLACK = 0, Color8 = function(x) return x end },
  ["ui/widget/buttontable"] = class(), ["ui/font"] = { getFace = function() return {} end },
  ["ui/geometry"] = class(), ["apps/kos/home"] = { get = function() return "/tmp/vh" end },
  ["ui/widget/infomessage"] = class(), ["ui/widget/menu"] = class(),
  ["ui/widget/textwidget"] = class(), ["ui/uimanager"] = { show = function() end, close = function() end },
  ["ui/widget/verticalgroup"] = class(), ["ui/widget/widget"] = class(),
  ["ui/widget/container/widgetcontainer"] = class(), ["gettext"] = function(s) return s end,
}
stubs["ui/geometry"].new = function(_, t) return t end
stubs["ui/widget/verticalgroup"].new = function(_, t) return t end
for k, v in pairs(stubs) do package.preload[k] = function() return v end end
package.preload["apps/kos/mesh"] = function() return dofile("frontend/apps/kos/mesh.lua") end
package.preload["libs/libkoreader-lfs"] = function()
  return { attributes = function(p) local ok = os.execute('[ -d "'..p..'" ]'); if ok == true or ok == 0 then return "directory" end end,
           mkdir = function(p) os.execute('mkdir -p "'..p..'"') end,
           dir = function(p) local h = io.popen('ls -A "'..p..'"'); local t = {} for l in h:lines() do t[#t+1] = l end h:close(); local i = 0; return function() i = i + 1; return t[i] end end }
end
os.execute("rm -rf /tmp/vh; mkdir -p /tmp/vh")
local V = dofile("plugins/viewer3d.koplugin/main.lua")
V:launchApp()
local win = { refresh = function() end }
local group = APP.build(win, 600, 1000)
assert(group[1].state, "view first")
-- open the example through the same path the menu uses
local Mesh = dofile("frontend/apps/kos/mesh.lua")
local st = group[1].state
local f = io.open("/tmp/vh/kosModels/example.lua", "w")
if not f then os.execute("mkdir -p /tmp/vh/kosModels"); f = io.open("/tmp/vh/kosModels/example.lua", "w") end
f:write("return join(box(40,20,4), cylinder(6,12,48,20,10,4))"); f:close()
-- chooseModel creates the example when the folder is empty; here call export path through the module
local mesh = assert(Mesh.runScript(io.open("/tmp/vh/kosModels/example.lua"):read("*a")))
st.mesh = mesh; local _n, _b, feat = Mesh.edges(mesh, 30); st.edges = feat; st.name = "example.lua"
-- paint with a recording buffer
local painted = 0
local bb = { paintRect = function() painted = painted + 1 end, paintBorder = function() end }
local view = group[1]; view.dimen = { w = 300, h = 300 }
view:paintTo(bb, 0, 0)
assert(painted > 200, painted)
local g2 = APP.build(win, 600, 1000)
print("viewer ok; painted pixels:", painted, "feature edges:", #feat)
V:exportSTL(st)
local out = io.open("/tmp/vh/kosModels/example.stl"):read("*a")
assert(out:find("facet normal")); print("export ok", #out)

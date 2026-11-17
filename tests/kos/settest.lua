local M = dofile("frontend/apps/kos/settingsmap.lua")
local function near(a,b) assert(math.abs(a-b)<1e-9, a.." vs "..b) end
near(M.entropy({choices={1,2,3,4}}), 2); near(M.entropy({kind="toggle"}), 1)
near(M.entropy({choices={1,2}}, {a=5}), 0)           -- everyone picks the same: no uncertainty
near(M.entropy({choices={1,2}}, {a=5,b=5}), 1)
local t = M.tree()
assert(#t == 3 and t[1].group.id=="time" and t[3].group.id=="energy")
for _, g in ipairs(t) do for i = 2, #g.items do assert(g.items[i-1].bits >= g.items[i].bits) end end
assert(t[3].items[1].entry.id == "light" and t[3].items[1].bits > 6)   -- 100 options: top of energy
-- simulation: if everyone picks the same sleep time, it drops below the wifi toggle
local cases = {} for i=1,20 do cases[i] = { sleep = 1800, wifi = (i%2==0) and "on" or "off" } end
local tree = M.simulate(cases)
local order = {} for _, it in ipairs(tree[3].items) do order[#order+1] = it.entry.id end
local pos = {} for i,id in ipairs(order) do pos[id]=i end
assert(pos.wifi < pos.sleep, table.concat(order, ","))
assert(#M.search("brightness")==1 and M.search("brightness")[1].id=="light")
assert(#M.search("menu look")==2 and #M.search("zzz")==0)
local seen = {} for _, e in ipairs(M.entries) do assert(not seen[e.id]); seen[e.id]=true; assert(e.group=="time" or e.group=="space" or e.group=="energy") end
print("settingsmap ok")

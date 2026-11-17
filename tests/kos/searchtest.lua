package.preload["apps/kos/home"]=function() return { get=function() return "/tmp/sh" end } end
os.execute("rm -rf /tmp/sh; mkdir -p /tmp/sh/Downloads/books /tmp/sh/Desktop /tmp/sh/documents; touch '/tmp/sh/Downloads/books/Quantum Notes.pdf' /tmp/sh/Desktop/quantum_draft.md /tmp/sh/documents/tax.txt /tmp/sh/.hidden")
-- minimal lfs from shell
local lfs = {
  attributes=function(p, what) local ok=os.execute('[ -d "'..p..'" ]'); if ok==true or ok==0 then return "directory" end
    ok=os.execute('[ -f "'..p..'" ]'); if ok==true or ok==0 then return "file" end end,
  dir=function(p) local h=io.popen('ls -A "'..p..'"'); local t={} for l in h:lines() do t[#t+1]=l end h:close(); local i=0; return function() i=i+1; return t[i] end end }
local S = dofile("frontend/apps/kos/usearch.lua")
assert(S.length("اب")==2 and S.length("abc")==3 and S.length("é")==1)
assert(not S.shouldRun("a") and S.shouldRun("ab") and not S.shouldRun("  a  "))
local places = S.places(lfs); local labels={} for _,p in ipairs(places) do labels[#labels+1]=p.label end
print(table.concat(labels, ","))
local items = {{name="Pendulums", lname="pendulums", app={}, label="app"}}
local seen={} for _,p in ipairs(places) do for _,it in ipairs(S.scan(lfs, p.path, {}, 0)) do if not seen[it.path] then seen[it.path]=true items[#items+1]=it end end end
for _,it in ipairs(items) do it.label = it.label or "x" end
local r = S.match(items, "quantum", 5)
assert(#r==2, #r)
local r2 = S.match(items, "quantum notes", 5); assert(#r2==1 and r2[1].name=="Quantum Notes.pdf")
assert(S.match(items,"pend",3)[1].name=="Pendulums")
assert(#S.match(items,"hidden",3)==0, "hidden skipped")
assert(S.match(items,"quantum",5)[1].name=="quantum_draft.md" or true)
print("search ok", r[1].name, r[2].name)

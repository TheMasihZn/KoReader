-- stubs
local shown, closed, bc = {}, {}, {}
local stubs = {
 ["ui/widget/buttondialog"]={}, ["ui/widget/infomessage"]={}, ["ui/event"]={ new=function(_,n) return {name=n} end },
 ["ui/uimanager"]={ close=function(_,w) closed[#closed+1]=w end, show=function(_,w) shown[#shown+1]=w end,
   setDirty=function() end, nextTick=function(_,f) f() end, broadcastEvent=function(_,e) bc[#bc+1]=e.name end, _window_stack={} },
 ["logger"]={ dbg=function() end, err=print }, ["gettext"]=function(s) return s end,
 ["ffi/util"]={ template=function(s) return s end },
}
for k,v in pairs(stubs) do package.preload[k]=function() return v end end
package.preload["gettext"]=function() return function(s) return s end end
local W = dofile("frontend/apps/kos/windows.lua")
local win = {title="Gemma"}
W.add(win, {id="gemma"})
assert(W.count()==1)
W.minimize(win)
assert(win._minimized and win._keep_in_list and #closed==1 and bc[1]=="ShowAppLauncher")
assert(W.count()==1, "stays in list")
W.raise(win)
assert(not win._minimized and shown[1]==win)
print("windows minimize/raise ok")

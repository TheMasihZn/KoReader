local L = dofile("frontend/apps/kos/linkproto.lua")
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function unhex(h) return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end)) end
local function sh(cmd) local p = io.popen(cmd); local o = p:read("*l"); p:close(); return o end
-- crc check vector: CRC-16/CCITT-FALSE of "123456789" = 0x29B1
assert(L.crc16("123456789") == 0x29B1)
-- Lua encode == C encode, including bytes that need escaping
local cases = { {1, 0, "6573703332"}, {2, 7, hex(L.dataPayload(3, 1234))}, {2, 255, hex(L.dataPayload(0x7E, -1))}, {3, 1, hex("\x7e\x7d\x7e")}, {4, 9, ""} }
for _, c in ipairs(cases) do
  local lua = hex(L.encode(c[1], c[2], unhex(c[3])))
  local cc = sh(("/tmp/kosLinkTest enc %d %d '%s'"):format(c[1], c[2], c[3]))
  assert(lua == cc, lua .. " vs " .. tostring(cc))
  -- and C reads what Lua wrote
  local dec = sh("/tmp/kosLinkTest dec " .. lua)
  local want = ("%d %d %s"):format(c[1], c[2], c[3]); assert(dec:gsub(" $", "") == want:gsub(" $", ""), dec)
end
-- Lua reads what C wrote, split across feeds
local cframe = unhex(sh("/tmp/kosLinkTest enc 2 5 " .. hex(L.dataPayload(9, 42000))))
local p = L.parser(); local got = p:feed(cframe:sub(1, 3)); assert(#got == 0); got = p:feed(cframe:sub(4))
assert(#got == 1 and got[1].type == 2 and got[1].seq == 5); local ch, v = L.readData(got[1].payload); assert(ch == 9 and v == 42000)
-- corruption is rejected and counted; the parser recovers on the next frame
local bad = L.encode(2, 1, L.dataPayload(1, 5)); bad = bad:sub(1, 5) .. string.char(bad:byte(6) ~ 1) .. bad:sub(7)
local q = L.parser(); assert(#q:feed(bad) == 0 and q.errors == 1)
assert(#q:feed(L.encode(1, 2, "ok")) == 1)
assert(sh("/tmp/kosLinkTest dec " .. hex(bad)) == "BAD")
-- garbage before a frame, two frames in one feed
local two = q:feed("junk" .. L.encode(1, 3, "a") .. L.encode(1, 4, "b")); assert(#two == 2 and two[2].payload == "b")
print("linkproto ok (Lua and C agree)")

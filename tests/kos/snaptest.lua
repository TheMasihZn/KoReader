local S = dofile("frontend/apps/kos/snapshot.lua")
local s = S.new{ title = "Settings tree", saved = "2026-11-17 05:50",
  decisions = { "Groups are time, space, energy", "Classic settings hidden" },
  open = { "Where do volume and contrast go?" }, next_step = "Draw the first tree\nfrom usage cases",
  formulas = { { tex = "H = -\\sum_i p_i \\log_2 p_i", note = "Shannon entropy, stand-in" }, { tex = "E \\ge k_B T \\ln 2" } },
  notes = "free text\nsecond line" }
local md = S.toMarkdown(s)
local b = assert(S.parse(md))
assert(b.title == s.title and b.saved == s.saved)
assert(#b.decisions == 2 and b.decisions[2] == "Classic settings hidden")
assert(b.open[1] == s.open[1])
assert(b.next_step == "Draw the first tree\nfrom usage cases")
assert(#b.formulas == 2 and b.formulas[1].tex == s.formulas[1].tex and b.formulas[1].note == "Shannon entropy, stand-in")
assert(b.formulas[2].note == nil)
assert(b.notes == "free text\nsecond line")
assert(S.toMarkdown(b) == md, "round trip identical")
assert(not S.parse("# just a heading"))
assert(S.fileTopic("Settings tree!") == "settingsTree" and S.fileTopic("") == "snapshot" and S.fileTopic("my-OS plan") == "myOSPlan")
local p = assert(S.save(s, "/tmp")); assert(p == "/tmp/settingsTree.snapshot.md")
print("snapshot ok"); print(md)

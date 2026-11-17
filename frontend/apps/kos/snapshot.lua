--[[--
Snapshot file: where an unfinished discussion stands, as one plain Markdown file. Plain KOReader can open
it, nothing else is needed; hand it to an agent and it continues from there.

    local snap = Snapshot.new{
        title = "Settings tree",
        decisions = { "Groups are time, space, energy" },
        open = { "Where do volume and contrast go?" },
        next_step = "Draw the first tree from the usage cases",
        formulas = { { tex = "H = -\\sum_i p_i \\log_2 p_i", note = "Shannon entropy, stand-in for Framal Entropy" } },
        notes = "free text",
    }
    local text = Snapshot.toMarkdown(snap)
    local back = Snapshot.parse(text)          -- the same table
    Snapshot.save(snap, folder)                -- <folder>/<topic>.snapshot.md ; returns the path

File name: `<topic>.snapshot.md`, the topic in camelCase (no hyphens).
]]

local Snapshot = {}

local VERSION = 1

local function list(items)
    local out = {}
    for _, it in ipairs(items or {}) do
        if it ~= "" then out[#out + 1] = "- " .. it:gsub("\n", " ") end
    end
    return out
end

function Snapshot.new(t)
    t = t or {}
    return {
        title = t.title or "Untitled",
        saved = t.saved or os.date("%Y-%m-%d %H:%M"),
        decisions = t.decisions or {},
        open = t.open or {},
        next_step = t.next_step or "",
        formulas = t.formulas or {},
        notes = t.notes or "",
    }
end

function Snapshot.toMarkdown(s)
    local out = {
        "# " .. s.title,
        "",
        "snapshot: " .. VERSION,
        "saved: " .. (s.saved or ""),
        "",
        "## Decisions",
    }
    for _, l in ipairs(list(s.decisions)) do out[#out + 1] = l end
    out[#out + 1] = ""
    out[#out + 1] = "## Open questions"
    for _, l in ipairs(list(s.open)) do out[#out + 1] = l end
    out[#out + 1] = ""
    out[#out + 1] = "## Next step"
    out[#out + 1] = s.next_step or ""
    out[#out + 1] = ""
    out[#out + 1] = "## Formulas"
    for _, f in ipairs(s.formulas or {}) do
        out[#out + 1] = "- $" .. f.tex .. "$" .. (f.note and f.note ~= "" and (" — " .. f.note) or "")
    end
    out[#out + 1] = ""
    out[#out + 1] = "## Notes"
    out[#out + 1] = s.notes or ""
    out[#out + 1] = ""
    return table.concat(out, "\n")
end

--- Reads a snapshot back. Unknown headings are kept in `notes`. Returns nil + message if it is not a snapshot.
function Snapshot.parse(text)
    local title = text:match("^#%s+([^\n]+)")
    if not title or not text:find("\nsnapshot:%s*%d+") then return nil, "not a snapshot file" end
    local s = Snapshot.new{ title = title, saved = text:match("\nsaved:%s*([^\n]*)") or "" }
    local section
    local notes = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local h = line:match("^##%s+(.+)$")
        if h then
            section = h
        elseif section == "Decisions" and line:match("^%- ") then
            s.decisions[#s.decisions + 1] = line:sub(3)
        elseif section == "Open questions" and line:match("^%- ") then
            s.open[#s.open + 1] = line:sub(3)
        elseif section == "Next step" and line ~= "" then
            s.next_step = (s.next_step ~= "" and (s.next_step .. "\n") or "") .. line
        elseif section == "Formulas" and line:match("^%- %$") then
            local tex, rest = line:match("^%- %$(.-)%$(.*)$")
            if tex then
                local note = rest:match("^%s*—%s*(.*)$")
                s.formulas[#s.formulas + 1] = { tex = tex, note = note }
            end
        elseif section == "Notes" then
            notes[#notes + 1] = line
        end
    end
    s.notes = (table.concat(notes, "\n"):gsub("^%s+", ""):gsub("%s+$", ""))
    return s
end

--- A topic as a camelCase file name: "Settings tree!" -> "settingsTree".
function Snapshot.fileTopic(title)
    local words = {}
    for w in (title or ""):gmatch("[%w]+") do words[#words + 1] = w end
    if #words == 0 then return "snapshot" end
    local out = words[1]:sub(1, 1):lower() .. words[1]:sub(2)
    for i = 2, #words do out = out .. words[i]:sub(1, 1):upper() .. words[i]:sub(2) end
    return out
end

function Snapshot.save(s, folder)
    local path = folder .. "/" .. Snapshot.fileTopic(s.title) .. ".snapshot.md"
    local f, err = io.open(path, "w")
    if not f then return nil, err end
    f:write(Snapshot.toMarkdown(s))
    f:close()
    return path
end

return Snapshot

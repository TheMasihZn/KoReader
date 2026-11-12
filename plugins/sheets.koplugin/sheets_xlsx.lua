-- Minimal .xlsx reader: cell values (cached results for formulas), all sheets.
-- An .xlsx is a zip of XML files; we only need a few of them.
local M = {}

local function unescape(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'")
        :gsub("&#(%d+);", function(d) return require("util").unicodeCodepointToUtf8(tonumber(d)) end)
        :gsub("&#x(%x+);", function(h) return require("util").unicodeCodepointToUtf8(tonumber(h, 16)) end)
        :gsub("&amp;", "&"))
end

--- "B12" -> row 12, column 2 ; "AA3" -> 3, 27
function M.cellRef(ref)
    local letters, digits = ref:match("^(%a+)(%d+)$")
    if not letters then return end
    local col = 0
    for ch in letters:upper():gmatch(".") do col = col * 26 + (ch:byte() - 64) end
    return tonumber(digits), col
end

local function sharedStrings(xml)
    local list = {}
    if not xml then return list end
    for si in xml:gmatch("<si>(.-)</si>") do
        local parts = {}
        for t in si:gmatch("<t[^>]*>(.-)</t>") do table.insert(parts, unescape(t)) end
        table.insert(list, table.concat(parts))
    end
    -- empty <si/> entries keep their index
    return list
end

function M.parseSheet(xml, strings)
    local rows = {}
    for attrs, body in xml:gmatch("<c ([^>]-)/?>(.-)</c>") do
        local ref = attrs:match('r="([^"]+)"')
        local t = attrs:match('t="([^"]+)"')
        local r, c
        if ref then r, c = M.cellRef(ref) end
        if r and c then
            local value
            if t == "inlineStr" then
                local parts = {}
                for s in body:gmatch("<t[^>]*>(.-)</t>") do table.insert(parts, unescape(s)) end
                value = table.concat(parts)
            else
                local v = body:match("<v>(.-)</v>")
                if v == "" then v = nil end
                local f = body:match("<f[^>]*>(.-)</f>")
                if not v and f then
                    -- No saved result: let our formula evaluator compute it.
                    value = "=" .. unescape(f)
                elseif v then
                    if t == "s" then
                        value = strings[tonumber(v) + 1] or ""
                    elseif t == "b" then
                        value = v == "1" and "TRUE" or "FALSE"
                    else
                        value = unescape(v)
                        -- Tidy floating point noise like 0.30000000000000004
                        local num = tonumber(value)
                        if num and value:find("%.") then
                            value = string.format("%.10g", num)
                        end
                    end
                end
            end
            if value then
                rows[r] = rows[r] or {}
                rows[r][c] = value
            end
        end
    end
    -- Make it a dense table of rows (holes become "").
    local max_r, max_c = 0, 0
    for r, row in pairs(rows) do
        if r > max_r then max_r = r end
        for c in pairs(row) do if c > max_c then max_c = c end end
    end
    local dense = {}
    for r = 1, max_r do
        local row = {}
        for c = 1, max_c do row[c] = rows[r] and rows[r][c] or "" end
        dense[r] = row
    end
    return dense
end

--- @treturn table|nil { sheets = { { name = "Sheet1", rows = {...} }, … } }, err
function M.read(path)
    local Archiver = require("ffi/archiver")
    local arc = Archiver.Reader:new()
    if not arc:open(path) then return nil, "not a valid .xlsx file" end
    local function get(name)
        local ok, content = pcall(arc.extractToMemory, arc, name)
        return ok and content or nil
    end
    local strings = sharedStrings(get("xl/sharedStrings.xml"))
    local workbook = get("xl/workbook.xml") or ""
    local rels = get("xl/_rels/workbook.xml.rels") or ""
    local targets = {}
    for rel in rels:gmatch("<Relationship ([^>]+)/?>") do
        local id = rel:match('Id="([^"]+)"')
        local target = rel:match('Target="([^"]+)"')
        if id and target then
            target = target:gsub("^/", ""):gsub("^xl/", "")
            targets[id] = "xl/" .. target
        end
    end
    local result = { sheets = {} }
    for attrs in workbook:gmatch("<sheet ([^>]+)/?>") do
        local name = unescape(attrs:match('name="([^"]+)"') or "Sheet")
        local rid = attrs:match('r:id="([^"]+)"') or attrs:match('id="([^"]+)"')
        local file = rid and targets[rid]
        local xml = file and get(file)
        if xml then
            table.insert(result.sheets, { name = name, rows = M.parseSheet(xml, strings) })
        end
    end
    if #result.sheets == 0 then
        -- Some writers skip the relationships: try the usual file name.
        local xml = get("xl/worksheets/sheet1.xml")
        if xml then
            table.insert(result.sheets, { name = "Sheet1", rows = M.parseSheet(xml, strings) })
        end
    end
    arc:close()
    if #result.sheets == 0 then return nil, "no sheets found" end
    return result
end

return M

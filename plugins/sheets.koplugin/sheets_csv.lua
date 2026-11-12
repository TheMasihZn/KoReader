-- CSV / TSV reading and writing (RFC 4180 style quoting).
local M = {}

--- Guesses the separator from the first line: tab, semicolon or comma.
function M.sniff(text, path)
    if path and path:lower():match("%.tsv$") then return "\t" end
    local first = text:match("^[^\r\n]*") or ""
    local counts = { [","] = 0, [";"] = 0, ["\t"] = 0 }
    for c in first:gmatch("[,;\t]") do counts[c] = counts[c] + 1 end
    local best, n = ",", 0
    for c, k in pairs(counts) do
        if k > n then best, n = c, k end
    end
    return best
end

--- Parses text into rows of strings.
function M.parse(text, sep)
    text = text:gsub("^\239\187\191", "") -- UTF-8 BOM
    local rows, row, field = {}, {}, {}
    local i, n = 1, #text
    local in_quotes = false
    while i <= n do
        local c = text:sub(i, i)
        if in_quotes then
            if c == '"' then
                if text:sub(i + 1, i + 1) == '"' then
                    table.insert(field, '"')
                    i = i + 1
                else
                    in_quotes = false
                end
            else
                table.insert(field, c)
            end
        elseif c == '"' then
            in_quotes = true
        elseif c == sep then
            table.insert(row, table.concat(field))
            field = {}
        elseif c == "\n" or c == "\r" then
            table.insert(row, table.concat(field))
            field = {}
            table.insert(rows, row)
            row = {}
            if c == "\r" and text:sub(i + 1, i + 1) == "\n" then i = i + 1 end
        else
            table.insert(field, c)
        end
        i = i + 1
    end
    if #field > 0 or #row > 0 then
        table.insert(row, table.concat(field))
        table.insert(rows, row)
    end
    return rows
end

local function quote(v, sep)
    v = tostring(v or "")
    if v:find('[' .. (sep == "\t" and "\t" or sep) .. '"\r\n]') then
        return '"' .. v:gsub('"', '""') .. '"'
    end
    return v
end

function M.serialize(rows, sep)
    local out = {}
    for _, row in ipairs(rows) do
        local cells = {}
        for j = 1, #row do cells[j] = quote(row[j], sep) end
        table.insert(out, table.concat(cells, sep))
    end
    return table.concat(out, "\n") .. "\n"
end

return M

-- Parsing and filtering for the Logcat app (no UI here, so it can be tested alone).
local LogLines = {}

-- Level letters in order of severity.
LogLines.ORDER = { V = 1, D = 2, I = 3, W = 4, E = 5, F = 6 }

--- "11-15 06:20:19.928 I/Tag(123): text" (logcat -v time) -> level letter.
-- Our own logs: "2026-11-15 06:20:19 message" -> from keywords.
function LogLines.level(line)
    local lv = line:match("^%d%d%-%d%d %d%d:%d%d:%d%d%.?%d* (%a)/")
    if lv and LogLines.ORDER[lv] then return lv end
    lv = line:match("^%a/")
    if lv and LogLines.ORDER[lv:sub(1, 1)] then return lv:sub(1, 1) end
    local low = line:lower()
    if low:find("fatal", 1, true) or low:find("traceback", 1, true) or low:find("error", 1, true)
        or low:find("failed", 1, true) or low:find("attempt to", 1, true) then
        return "E"
    end
    if low:find("warn", 1, true) then return "W" end
    if low:find("debug", 1, true) then return "D" end
    return "I"
end

--- lines: array of strings. opts.min_level (letter), opts.text (plain substring, case-insensitive).
-- Returns array of { text = line, level = letter } in the same order.
function LogLines.filter(lines, opts)
    opts = opts or {}
    local min = LogLines.ORDER[opts.min_level or "V"] or 1
    local needle = opts.text and opts.text ~= "" and opts.text:lower() or nil
    local out = {}
    for _, line in ipairs(lines) do
        local lv = LogLines.level(line)
        if LogLines.ORDER[lv] >= min and (not needle or line:lower():find(needle, 1, true)) then
            out[#out + 1] = { text = line, level = lv }
        end
    end
    return out
end

--- The page of `per_page` entries ending `back` pages before the newest one.
function LogLines.page(entries, per_page, back)
    local last = #entries - (back or 0) * per_page
    if last < 0 then last = 0 end
    local first = math.max(1, last - per_page + 1)
    local out = {}
    for i = first, last do out[#out + 1] = entries[i] end
    local pages = math.max(1, math.ceil(#entries / per_page))
    return out, pages
end

return LogLines

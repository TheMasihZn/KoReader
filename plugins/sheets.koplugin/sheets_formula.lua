-- Tiny, safe formula evaluator for CSV sheets (never runs Lua code).
-- Supports numbers, cell refs (A1), ranges (A1:B3) in functions,
-- + - * / ^, parentheses, unary minus, and SUM AVERAGE AVG MIN MAX COUNT ABS ROUND.
local M = {}

local function colIndex(letters)
    local col = 0
    for ch in letters:upper():gmatch(".") do col = col * 26 + (ch:byte() - 64) end
    return col
end

function M.colName(c)
    local s = ""
    while c > 0 do
        local r = (c - 1) % 26
        s = string.char(65 + r) .. s
        c = math.floor((c - 1) / 26)
    end
    return s
end

local function tokenize(src)
    local tokens, i = {}, 1
    while i <= #src do
        local c = src:sub(i, i)
        if c:match("%s") then
            i = i + 1
        else
            local num = src:match("^%d+%.?%d*", i) or src:match("^%.%d+", i)
            local ref = src:match("^%$?%a+%$?%d+", i)
            local word = src:match("^%a+", i)
            if num then
                table.insert(tokens, { t = "num", v = tonumber(num) }); i = i + #num
            elseif ref then
                local clean = ref:gsub("%$", "")
                local letters, digits = clean:match("^(%a+)(%d+)$")
                table.insert(tokens, { t = "ref", r = tonumber(digits), c = colIndex(letters) }); i = i + #ref
            elseif word then
                table.insert(tokens, { t = "fn", v = word:upper() }); i = i + #word
            elseif c:match("[%+%-%*/%^%(%):,;]") then
                table.insert(tokens, { t = c }); i = i + 1
            else
                error("unexpected '" .. c .. "'")
            end
        end
    end
    return tokens
end

local FUNCS = {
    SUM = function(v) local s = 0; for _, x in ipairs(v) do s = s + x end; return s end,
    AVERAGE = function(v) if #v == 0 then error("AVERAGE of nothing") end; local s = 0; for _, x in ipairs(v) do s = s + x end; return s / #v end,
    MIN = function(v) return #v > 0 and math.min(unpack(v)) or 0 end,
    MAX = function(v) return #v > 0 and math.max(unpack(v)) or 0 end,
    COUNT = function(v) return #v end,
    ABS = function(v) return math.abs(v[1] or 0) end,
    ROUND = function(v) local d = v[2] or 0; local m = 10 ^ d; return math.floor((v[1] or 0) * m + 0.5) / m end,
}
FUNCS.AVG = FUNCS.AVERAGE

--- Evaluates `src` (without the leading "="). getValue(r, c) returns a number or nil.
function M.eval(src, getValue)
    local tokens = tokenize(src)
    local pos = 1
    local function peek() return tokens[pos] end
    local function take(t)
        local tok = tokens[pos]
        if t and (not tok or tok.t ~= t) then error("expected " .. t) end
        pos = pos + 1
        return tok
    end
    local expr
    local function args()
        local values = {}
        take("(")
        if peek() and peek().t == ")" then take(")"); return values end
        while true do
            local tok, nxt = peek(), tokens[pos + 1]
            if tok and tok.t == "ref" and nxt and nxt.t == ":" then
                local a = take(); take(":"); local b = take("ref")
                for r = math.min(a.r, b.r), math.max(a.r, b.r) do
                    for c = math.min(a.c, b.c), math.max(a.c, b.c) do
                        local v = getValue(r, c)
                        if v then table.insert(values, v) end
                    end
                end
            else
                table.insert(values, expr())
            end
            local sep = peek()
            if sep and (sep.t == "," or sep.t == ";") then take() else break end
        end
        take(")")
        return values
    end
    local function primary()
        local tok = take()
        if not tok then error("incomplete formula") end
        if tok.t == "num" then return tok.v end
        if tok.t == "ref" then return getValue(tok.r, tok.c) or 0 end
        if tok.t == "-" then return -primary() end
        if tok.t == "+" then return primary() end
        if tok.t == "(" then local v = expr(); take(")"); return v end
        if tok.t == "fn" then
            local f = FUNCS[tok.v]
            if not f then error("unknown function " .. tok.v) end
            return f(args())
        end
        error("unexpected " .. tok.t)
    end
    local function power()
        local v = primary()
        while peek() and peek().t == "^" do take(); v = v ^ primary() end
        return v
    end
    local function term()
        local v = power()
        while peek() and (peek().t == "*" or peek().t == "/") do
            local op = take().t
            local r = power()
            if op == "*" then v = v * r else
                if r == 0 then error("division by zero") end
                v = v / r
            end
        end
        return v
    end
    expr = function()
        local v = term()
        while peek() and (peek().t == "+" or peek().t == "-") do
            local op = take().t
            local r = term()
            v = op == "+" and v + r or v - r
        end
        return v
    end
    local result = expr()
    if pos <= #tokens then error("unexpected input after the formula") end
    return result
end

--- Builds a function that displays a cell: formulas evaluated, with cycle protection.
function M.makeResolver(rows)
    local cache, visiting = {}, {}
    local resolve
    local function number(r, c)
        local v = resolve(r, c)
        if v == "#CYCLE" or v == "#ERR" then error(v) end
        return tonumber(v)
    end
    resolve = function(r, c)
        local key = r * 100000 + c
        if cache[key] ~= nil then return cache[key] end
        local raw = rows[r] and rows[r][c] or ""
        local out = raw
        if type(raw) == "string" and raw:sub(1, 1) == "=" and #raw > 1 then
            if visiting[key] then return "#CYCLE" end
            visiting[key] = true
            local ok, v = pcall(M.eval, raw:sub(2), number)
            visiting[key] = nil
            if ok then
                out = (v == math.floor(v) and math.abs(v) < 1e15) and string.format("%d", v) or string.format("%.6g", v)
            else
                out = "#ERR"
            end
        end
        cache[key] = out
        return out
    end
    return resolve
end

return M

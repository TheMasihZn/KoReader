--[[--
Entropy calculator with LaTeX output. STAND-IN: this is Shannon entropy. Your Framal Entropy (events, positions,
frames) has no definition yet; until it has one, the "frame" function below is the independent-axes version
and every output says so.

    E.shannon(weights)            -> bits           H = -sum p_i log2 p_i, weights need not add up to 1
    E.bounds(n)                   -> 0, log2(n)     lowest and highest H for n outcomes
    E.frame{ events = {..}, positions = {..}, frames = {..} } -> H, max, parts
                                     H = H_events + H_positions + H_frames (axes independent), max = log2(E P F)
    E.latex(result)               -> LaTeX text for the formula with the numbers put in
    E.bytes(string)               -> bits per byte of a string, 0 to 8
]]

local E = {}
local log2 = function(x) return math.log(x) / math.log(2) end

function E.shannon(w)
    local total = 0
    for _, v in ipairs(w) do if v < 0 then error("weights cannot be negative") end total = total + v end
    if total == 0 then return 0 end
    local h = 0
    for _, v in ipairs(w) do
        if v > 0 then local p = v / total; h = h - p * log2(p) end
    end
    return h
end

function E.bounds(n) if n < 1 then return 0, 0 end return 0, log2(n) end

function E.frame(o)
    local parts, max = {}, 0
    for _, axis in ipairs({ "events", "positions", "frames" }) do
        local w = o[axis] or { 1 }
        parts[axis] = E.shannon(w)
        max = max + select(2, E.bounds(#w))
    end
    return parts.events + parts.positions + parts.frames, max, parts
end

function E.latex(h, max, parts)
    local f = "%.4f"
    local l = {}
    l[#l + 1] = "% Shannon entropy used in place of Framal Entropy (not yet defined)"
    l[#l + 1] = "\\[ H = -\\sum_{i} p_i \\log_2 p_i, \\qquad p_i = \\frac{w_i}{\\sum_j w_j} \\]"
    if parts then
        l[#l + 1] = ("\\[ H = H_{\\text{events}} + H_{\\text{positions}} + H_{\\text{frames}} = %s + %s + %s = %s \\ \\text{bits} \\]"):format(f:format(parts.events), f:format(parts.positions), f:format(parts.frames), f:format(h))
    else
        l[#l + 1] = ("\\[ H = %s \\ \\text{bits} \\]"):format(f:format(h))
    end
    l[#l + 1] = ("\\[ 0 \\le H \\le \\log_2 n = %s \\ \\text{bits} \\]"):format(f:format(max))
    return table.concat(l, "\n")
end

function E.bytes(s)
    if #s == 0 then return 0 end
    local c = {}
    for i = 1, #s do local b = s:byte(i); c[b] = (c[b] or 0) + 1 end
    local w = {}
    for _, v in pairs(c) do w[#w + 1] = v end
    return E.shannon(w)
end

return E

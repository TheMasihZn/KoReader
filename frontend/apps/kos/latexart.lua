--[[--
LaTeX art: pictures drawn from a scene, not from characters.

A scene is a list of shapes in world units (x to the right, y up). The same scene gives:

  * LatexArt.tikz(scene)          real LaTeX (TikZ) source you can paste into a .tex file
  * LatexArt.paint(scene, bb, ...) pixels on a blitbuffer (the "virtual display")
  * LatexArt.unicode(tex)         a LaTeX formula as readable text (alpha, ², √, ½ ...)

    local S = LatexArt.scene{ xmin = -1, xmax = 1, ymin = -1, ymax = 1 }
    S:line(0, 0, 1, 0.5, { width = 2 })
    S:circle(0, 0, 0.2, { fill = true })
    S:dot(0.5, 0.5)
    S:text(0, 0.9, "$E = mc^2$")          -- text is kept as LaTeX
    print(LatexArt.tikz(S))

Shape options: width (pixels, default 1), fill (bool), gray (0 black ... 1 white, default 0).
]]

local LatexArt = {}

local Scene = {}
Scene.__index = Scene

function LatexArt.scene(view)
    view = view or {}
    return setmetatable({
        xmin = view.xmin or 0, xmax = view.xmax or 1, ymin = view.ymin or 0, ymax = view.ymax or 1,
        shapes = {},
    }, Scene)
end

local function add(self, kind, t, o)
    o = o or {}
    t.kind, t.width, t.fill, t.gray = kind, o.width or 1, o.fill and true or false, o.gray or 0
    self.shapes[#self.shapes + 1] = t
    return self
end

function Scene:line(x1, y1, x2, y2, o) return add(self, "line", { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }, o) end
function Scene:circle(x, y, r, o) return add(self, "circle", { x = x, y = y, r = r }, o) end
function Scene:rect(x, y, w, h, o) return add(self, "rect", { x = x, y = y, w = w, h = h }, o) end
function Scene:dot(x, y, o) return add(self, "dot", { x = x, y = y }, o) end
function Scene:text(x, y, tex, o) return add(self, "text", { x = x, y = y, tex = tex }, o) end
--- A polyline through {{x,y},...}
function Scene:path(points, o) return add(self, "path", { points = points }, o) end

--- World -> pixel inside a w x h box.
function Scene:toPixel(x, y, w, h)
    local px = (x - self.xmin) / (self.xmax - self.xmin) * w
    local py = (1 - (y - self.ymin) / (self.ymax - self.ymin)) * h
    return px, py
end

---------------------------------------------------------------------------
-- TikZ (real LaTeX)
---------------------------------------------------------------------------

local function f(n) return string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", "") end

function LatexArt.tikz(scene)
    local out = { "\\begin{tikzpicture}[x=1cm,y=1cm]" }
    local function style(s)
        local parts = { string.format("line width=%.2fpt", (s.width or 1) * 0.4) }
        if s.gray and s.gray > 0 then parts[#parts + 1] = string.format("draw=black!%d", math.floor((1 - s.gray) * 100)) end
        if s.fill then parts[#parts + 1] = "fill" end
        return table.concat(parts, ",")
    end
    for _i, s in ipairs(scene.shapes) do
        if s.kind == "line" then
            out[#out + 1] = string.format("\\draw[%s] (%s,%s) -- (%s,%s);", style(s), f(s.x1), f(s.y1), f(s.x2), f(s.y2))
        elseif s.kind == "circle" then
            out[#out + 1] = string.format("\\%s[%s] (%s,%s) circle (%s);", s.fill and "fill" or "draw", style(s), f(s.x), f(s.y), f(s.r))
        elseif s.kind == "rect" then
            out[#out + 1] = string.format("\\draw[%s] (%s,%s) rectangle (%s,%s);", style(s), f(s.x), f(s.y), f(s.x + s.w), f(s.y + s.h))
        elseif s.kind == "dot" then
            out[#out + 1] = string.format("\\fill (%s,%s) circle (0.03);", f(s.x), f(s.y))
        elseif s.kind == "path" then
            local pts = {}
            for _j, p in ipairs(s.points) do pts[#pts + 1] = string.format("(%s,%s)", f(p[1]), f(p[2])) end
            out[#out + 1] = string.format("\\draw[%s] %s;", style(s), table.concat(pts, " -- "))
        elseif s.kind == "text" then
            out[#out + 1] = string.format("\\node at (%s,%s) {%s};", f(s.x), f(s.y), s.tex)
        end
    end
    out[#out + 1] = "\\end{tikzpicture}"
    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Formulas as text
---------------------------------------------------------------------------

local GREEK = {
    alpha = "α", beta = "β", gamma = "γ", delta = "δ", epsilon = "ε", varepsilon = "ε", zeta = "ζ", eta = "η",
    theta = "θ", vartheta = "ϑ", iota = "ι", kappa = "κ", lambda = "λ", mu = "μ", nu = "ν", xi = "ξ", pi = "π",
    rho = "ρ", sigma = "σ", tau = "τ", phi = "φ", varphi = "φ", chi = "χ", psi = "ψ", omega = "ω",
    Gamma = "Γ", Delta = "Δ", Theta = "Θ", Lambda = "Λ", Xi = "Ξ", Pi = "Π", Sigma = "Σ", Phi = "Φ", Psi = "Ψ", Omega = "Ω",
    hbar = "ħ", infty = "∞", partial = "∂", nabla = "∇", cdot = "·", times = "×", pm = "±", approx = "≈", neq = "≠",
    leq = "≤", geq = "≥", sum = "Σ", int = "∫", prod = "Π", to = "→", rightarrow = "→", sin = "sin", cos = "cos",
    tan = "tan", log = "log", ln = "ln", exp = "exp", sqrt = "√", ell = "ℓ", dots = "…", ldots = "…", cdots = "⋯",
    langle = "⟨", rangle = "⟩", sim = "∼", propto = "∝", ddot = "¨", dot = "˙",
}
local SUP = { ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴", ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷",
    ["8"] = "⁸", ["9"] = "⁹", ["+"] = "⁺", ["-"] = "⁻", ["n"] = "ⁿ", ["i"] = "ⁱ" }
local SUB = { ["0"] = "₀", ["1"] = "₁", ["2"] = "₂", ["3"] = "₃", ["4"] = "₄", ["5"] = "₅", ["6"] = "₆", ["7"] = "₇",
    ["8"] = "₈", ["9"] = "₉", ["+"] = "₊", ["-"] = "₋", ["i"] = "ᵢ", ["j"] = "ⱼ", ["n"] = "ₙ", ["x"] = "ₓ" }

local function script(s, map, mark)
    local out, ok = {}, true
    for ch in s:gmatch(".") do
        if map[ch] then out[#out + 1] = map[ch] else ok = false break end
    end
    if ok and #out > 0 then return table.concat(out) end
    return mark .. (#s > 1 and "(" .. s .. ")" or s)
end

--- "\frac{a}{b}" -> "(a)/(b)", "x^2" -> "x²", "\theta_1" -> "θ₁", "\sqrt{x}" -> "√(x)".
function LatexArt.unicode(tex)
    local s = tex:gsub("^%$+", ""):gsub("%$+$", "")
    local function group(str, i) -- returns content of {...} starting at i, and the index after it
        if str:sub(i, i) ~= "{" then return str:sub(i, i), i + 1 end
        local depth, j = 0, i
        while j <= #str do
            local c = str:sub(j, j)
            if c == "{" then depth = depth + 1 elseif c == "}" then depth = depth - 1 if depth == 0 then break end end
            j = j + 1
        end
        return str:sub(i + 1, j - 1), j + 1
    end
    local function conv(str)
        local out, i = {}, 1
        while i <= #str do
            local c = str:sub(i, i)
            if c == "\\" then
                local name = str:match("^\\([%a]+)", i)
                if name == "frac" then
                    local a, j = group(str, i + 5)
                    local b, k = group(str, j)
                    out[#out + 1] = "(" .. conv(a) .. ")/(" .. conv(b) .. ")"
                    i = k
                elseif name == "sqrt" then
                    local a, j = group(str, i + 5)
                    out[#out + 1] = "√(" .. conv(a) .. ")"
                    i = j
                elseif name == "left" or name == "right" then
                    i = i + #name + 1
                elseif name and (name == "dot" or name == "ddot") then
                    local a, j = group(str, i + #name + 1)
                    out[#out + 1] = conv(a) .. (name == "dot" and "˙" or "¨")
                    i = j
                elseif name then
                    out[#out + 1] = GREEK[name] or name
                    i = i + #name + 1
                    if str:sub(i, i) == " " then i = i + 1 end
                else
                    out[#out + 1] = str:sub(i + 1, i + 1)
                    i = i + 2
                end
            elseif c == "^" then
                local a, j = group(str, i + 1)
                out[#out + 1] = script(conv(a), SUP, "^")
                i = j
            elseif c == "_" then
                local a, j = group(str, i + 1)
                out[#out + 1] = script(conv(a), SUB, "_")
                i = j
            elseif c == "{" or c == "}" then
                i = i + 1
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end
    return conv(s)
end

---------------------------------------------------------------------------
-- Pixels
---------------------------------------------------------------------------

local function stroke(bb, x1, y1, x2, y2, w, color)
    local dx, dy = x2 - x1, y2 - y1
    local n = math.max(math.abs(dx), math.abs(dy))
    if n < 1 then bb:paintRect(math.floor(x1), math.floor(y1), w, w, color) return end
    local h = math.floor(w / 2)
    for i = 0, n do
        local t = i / n
        bb:paintRect(math.floor(x1 + dx * t) - h, math.floor(y1 + dy * t) - h, w, w, color)
    end
end

local function circle(bb, cx, cy, r, w, fill, color)
    r = math.max(1, math.floor(r))
    if fill then
        for dy = -r, r do
            local dx = math.floor(math.sqrt(r * r - dy * dy))
            bb:paintRect(math.floor(cx) - dx, math.floor(cy) + dy, 2 * dx + 1, 1, color)
        end
        return
    end
    local steps = math.max(16, r * 4)
    local px, py = cx + r, cy
    for i = 1, steps do
        local a = 2 * math.pi * i / steps
        local nx, ny = cx + r * math.cos(a), cy + r * math.sin(a)
        stroke(bb, px, py, nx, ny, w, color)
        px, py = nx, ny
    end
end

--- Draws the scene into the box (x, y, w, h) of a blitbuffer.
-- `Blitbuffer` is passed in so this file loads anywhere; `draw_text(bb, x, y, text)` is optional.
function LatexArt.paint(scene, bb, x, y, w, h, Blitbuffer, draw_text)
    for _i, s in ipairs(scene.shapes) do
        local color = Blitbuffer.Color8(math.floor((s.gray or 0) * 255))
        local W = math.max(1, math.floor(s.width or 1))
        local function P(wx, wy)
            local px, py = scene:toPixel(wx, wy, w, h)
            return x + px, y + py
        end
        if s.kind == "line" then
            local ax, ay = P(s.x1, s.y1)
            local bx, by = P(s.x2, s.y2)
            stroke(bb, ax, ay, bx, by, W, color)
        elseif s.kind == "path" then
            for j = 1, #s.points - 1 do
                local ax, ay = P(s.points[j][1], s.points[j][2])
                local bx, by = P(s.points[j + 1][1], s.points[j + 1][2])
                stroke(bb, ax, ay, bx, by, W, color)
            end
        elseif s.kind == "circle" then
            local cx, cy = P(s.x, s.y)
            circle(bb, cx, cy, s.r / (scene.xmax - scene.xmin) * w, W, s.fill, color)
        elseif s.kind == "dot" then
            local cx, cy = P(s.x, s.y)
            circle(bb, cx, cy, math.max(2, W), W, true, color)
        elseif s.kind == "rect" then
            local ax, ay = P(s.x, s.y + s.h)
            local pw = s.w / (scene.xmax - scene.xmin) * w
            local ph = s.h / (scene.ymax - scene.ymin) * h
            if s.fill then bb:paintRect(math.floor(ax), math.floor(ay), math.floor(pw), math.floor(ph), color)
            else bb:paintBorder(math.floor(ax), math.floor(ay), math.floor(pw), math.floor(ph), W, color) end
        elseif s.kind == "text" and draw_text then
            local ax, ay = P(s.x, s.y)
            draw_text(bb, ax, ay, LatexArt.unicode(s.tex))
        end
    end
end

return LatexArt

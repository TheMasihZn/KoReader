--[[--
LaTeX to HTML, good enough to *read* a .tex document on an e-reader.

No TeX engine: common structure (sections, lists, tables, emphasis, quotes,
verbatim, footnotes, links) is converted, math is rendered with Unicode,
<sup>/<sub> and simple fractions. Unknown commands keep their text argument.
]]

local M = {}

local SYMBOLS = {
    -- Greek
    alpha="α", beta="β", gamma="γ", delta="δ", epsilon="ϵ", varepsilon="ε", zeta="ζ", eta="η", theta="θ",
    vartheta="ϑ", iota="ι", kappa="κ", lambda="λ", mu="μ", nu="ν", xi="ξ", pi="π", varpi="ϖ", rho="ρ",
    varrho="ϱ", sigma="σ", varsigma="ς", tau="τ", upsilon="υ", phi="ϕ", varphi="φ", chi="χ", psi="ψ", omega="ω",
    Gamma="Γ", Delta="Δ", Theta="Θ", Lambda="Λ", Xi="Ξ", Pi="Π", Sigma="Σ", Upsilon="Υ", Phi="Φ", Psi="Ψ", Omega="Ω",
    -- Operators and relations
    times="×", cdot="⋅", div="÷", pm="±", mp="∓", ast="∗", star="⋆", circ="∘", bullet="∙",
    leq="≤", le="≤", geq="≥", ge="≥", neq="≠", ne="≠", approx="≈", equiv="≡", sim="∼", simeq="≃", cong="≅", propto="∝",
    ll="≪", gg="≫", prec="≺", succ="≻", mid="∣", parallel="∥", perp="⊥",
    ["in"]="∈", notin="∉", ni="∋", subset="⊂", supset="⊃", subseteq="⊆", supseteq="⊇", cup="∪", cap="∩",
    setminus="∖", emptyset="∅", varnothing="∅", forall="∀", exists="∃", nexists="∄", neg="¬", lnot="¬",
    land="∧", wedge="∧", lor="∨", vee="∨", oplus="⊕", otimes="⊗",
    to="→", rightarrow="→", leftarrow="←", gets="←", leftrightarrow="↔", Rightarrow="⇒", Leftarrow="⇐",
    Leftrightarrow="⇔", iff="⟺", implies="⟹", mapsto="↦", uparrow="↑", downarrow="↓", longrightarrow="⟶",
    infty="∞", partial="∂", nabla="∇", hbar="ℏ", ell="ℓ", Re="ℜ", Im="ℑ", aleph="ℵ", angle="∠", degree="°",
    sum="∑", prod="∏", coprod="∐", int="∫", iint="∬", iiint="∭", oint="∮", bigcup="⋃", bigcap="⋂",
    sqrt="√", cdots="⋯", ldots="…", dots="…", vdots="⋮", ddots="⋱", prime="′",
    langle="⟨", rangle="⟩", lvert="|", rvert="|", lVert="‖", rVert="‖", colon=":", lceil="⌈", rceil="⌉", lfloor="⌊", rfloor="⌋", vert="|", Vert="‖",
    -- Text symbols
    LaTeX="LaTeX", TeX="TeX", S="§", P="¶", dag="†", ddag="‡", copyright="©", pounds="£", euro="€",
    textbackslash="\\", ss="ß", ae="æ", AE="Æ", o="ø", O="Ø", aa="å", AA="Å", oe="œ", OE="Œ",
    quad=" ", qquad="  ", [","]=" ", [";"]=" ", [":"]=" ", ["!"]="", [" "]=" ",
    log="log", ln="ln", exp="exp", sin="sin", cos="cos", tan="tan", lim="lim", max="max", min="min",
    sup="sup", inf="inf", det="det", dim="dim", ker="ker", gcd="gcd", arg="arg", deg="deg", Pr="Pr",
}

local BLACKBOARD = { N="ℕ", Z="ℤ", Q="ℚ", R="ℝ", C="ℂ", P="ℙ", H="ℍ", E="𝔼" }

local function esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Placeholders protect already-converted HTML from later passes.
local Store = {}
Store.__index = Store
function Store.new() return setmetatable({ items = {} }, Store) end
function Store:put(html)
    table.insert(self.items, html)
    return "\1" .. #self.items .. "\2"
end
function Store:restore(s)
    for _ = 1, 5 do -- nested placeholders
        local changed
        s, changed = s:gsub("\1(%d+)\2", function(i) return self.items[tonumber(i)] end)
        if changed == 0 then break end
    end
    return s
end

local function strip(group) return group:sub(2, -2) end

---------------------------------------------------------------- math

local function mathToHtml(m, store)
    m = m:gsub("\\label%b{}", ""):gsub("\\nonumber", ""):gsub("\\notag", "")
    m = m:gsub("\\left", ""):gsub("\\right", ""):gsub("\\big[lr]?", ""):gsub("\\Big[lr]?", "")
    m = m:gsub("\\displaystyle", ""):gsub("\\limits", "")
    -- Escaped braces before anything else.
    m = m:gsub("\\{", "\3"):gsub("\\}", "\4")
    for _ = 1, 6 do -- nested commands, innermost first
        local before = m
        m = m:gsub("\\mathbb(%b{})", function(g) local k = strip(g); return BLACKBOARD[k] or k end)
        m = m:gsub("\\mathbb (%a)", function(k) return BLACKBOARD[k] or k end)
        m = m:gsub("\\math[a-z]+(%b{})", strip)
        m = m:gsub("\\text[a-z]*(%b{})", function(g) return store:put("<span class=\"mt\">" .. esc(strip(g)) .. "</span>") end)
        m = m:gsub("\\operatorname(%b{})", strip)
        m = m:gsub("\\d?frac(%b{})(%b{})", function(a, b)
            return store:put("<span class=\"fr\"><sup>") .. strip(a) .. store:put("</sup>⁄<sub>") .. strip(b) .. store:put("</sub></span>")
        end)
        m = m:gsub("\\binom(%b{})(%b{})", function(a, b) return "(" .. strip(a) .. " choose " .. strip(b) .. ")" end)
        m = m:gsub("\\sqrt%[(.-)%](%b{})", function(n, g) return store:put("<sup>" .. n .. "</sup>") .. "√(" .. strip(g) .. ")" end)
        m = m:gsub("\\sqrt(%b{})", function(g) return "√(" .. strip(g) .. ")" end)
        m = m:gsub("\\(%a+)(%b{})", function(cmd, g) -- hat, bar, vec, overline…
            local accents = { hat = "\204\130", bar = "\204\132", overline = "\204\133", vec = "\226\131\151", dot = "\204\135", ddot = "\204\136", tilde = "\204\131" }
            if accents[cmd] then return strip(g) .. accents[cmd] end
            return nil
        end)
        m = m:gsub("%^(%b{})", function(g) return store:put("<sup>") .. strip(g) .. store:put("</sup>") end)
        m = m:gsub("_(%b{})", function(g) return store:put("<sub>") .. strip(g) .. store:put("</sub>") end)
        if m == before then break end
    end
    m = m:gsub("%^(\\%a+)", function(c) return store:put("<sup>") .. c .. store:put("</sup>") end)
    m = m:gsub("_(\\%a+)", function(c) return store:put("<sub>") .. c .. store:put("</sub>") end)
    m = m:gsub("%^([%w%+%-%*'])", function(c) return store:put("<sup>") .. c .. store:put("</sup>") end)
    m = m:gsub("_([%w%+%-%*])", function(c) return store:put("<sub>") .. c .. store:put("</sub>") end)
    -- Unknown commands in math: keep their name (better "\foo" → "foo" than nothing).
    m = m:gsub("\\([%a]+)", function(cmd) return SYMBOLS[cmd] or cmd end)
    m = m:gsub("\\([,;:! ])", function(c) return SYMBOLS[c] end)
    m = m:gsub("\\\\", store:put("<br/>"))
    m = m:gsub("&", " ") -- alignment points
    m = m:gsub("[{}]", "")
    m = m:gsub("\3", "{"):gsub("\4", "}")
    m = m:gsub("~", " ")
    return esc(m)
end

---------------------------------------------------------------- text

local function textCommands(s, store, notes)
    for _ = 1, 6 do
        local before = s
        local simple = {
            textbf = "b", bf = "b", textit = "i", it = "i", emph = "em", textsl = "i", texttt = "code",
            underline = "u", textsc = "span class=\"sc\"", textup = "span", textrm = "span", textsf = "span",
        }
        s = s:gsub("\\(%a+)(%b{})", function(cmd, g)
            local tag = simple[cmd]
            if tag then
                local close = tag:match("^(%a+)")
                return store:put("<" .. tag .. ">") .. strip(g) .. store:put("</" .. close .. ">")
            end
            if cmd == "footnote" then
                table.insert(notes, strip(g))
                local n = #notes
                return store:put(string.format('<sup class="fn"><a href="#fn%d">%d</a></sup>', n, n))
            end
            if cmd == "url" then
                local u = strip(g)
                return store:put('<a href="' .. esc(u) .. '">' .. esc(u) .. '</a>')
            end
            if cmd == "label" or cmd == "index" or cmd == "vspace" or cmd == "hspace" or cmd == "setlength"
                or cmd == "usepackage" or cmd == "documentclass" or cmd == "newcommand" or cmd == "renewcommand"
                or cmd == "pagestyle" or cmd == "thispagestyle" or cmd == "bibliographystyle" or cmd == "bibliography"
                or cmd == "includegraphics" or cmd == "input" or cmd == "include" then
                return ""
            end
            if cmd == "ref" or cmd == "eqref" or cmd == "pageref" then return "[" .. strip(g) .. "]" end
            if cmd == "cite" or cmd == "citep" or cmd == "citet" then return "[" .. strip(g) .. "]" end
            return nil
        end)
        s = s:gsub("\\href(%b{})(%b{})", function(u, t)
            return store:put('<a href="' .. esc(strip(u)) .. '">') .. strip(t) .. store:put("</a>")
        end)
        s = s:gsub("{\\bf%s+([^{}]-)}", function(t) return store:put("<b>") .. t .. store:put("</b>") end)
        s = s:gsub("{\\it%s+([^{}]-)}", function(t) return store:put("<i>") .. t .. store:put("</i>") end)
        s = s:gsub("{\\em%s+([^{}]-)}", function(t) return store:put("<em>") .. t .. store:put("</em>") end)
        if s == before then break end
    end
    return s
end

local function tabularToHtml(body, store, inline)
    local rows = {}
    body = body:gsub("\\hline", ""):gsub("\\cline%b{}", ""):gsub("\\toprule", ""):gsub("\\midrule", ""):gsub("\\bottomrule", "")
    for line in (body .. "\\\\"):gmatch("(.-)\\\\") do
        if line:match("%S") then
            local cells = {}
            for cell in (line .. "&"):gmatch("(.-)&") do
                cell = cell:gsub("\\multicolumn%b{}%b{}(%b{})", strip)
                table.insert(cells, "<td>" .. inline(cell) .. "</td>")
            end
            table.insert(rows, "<tr>" .. table.concat(cells) .. "</tr>")
        end
    end
    return store:put("<table>" .. table.concat(rows) .. "</table>")
end

local function listToHtml(env, body, inline, store)
    local tag = env == "enumerate" and "ol" or (env == "description" and "dl" or "ul")
    local items = {}
    body = body .. "\\item"
    local pos = body:find("\\item", 1, true)
    while pos do
        local next_pos = body:find("\\item", pos + 5, true)
        if not next_pos then break end
        local chunk = body:sub(pos + 5, next_pos - 1)
        local label = chunk:match("^%s*(%b[])")
        if label then chunk = chunk:sub(chunk:find("]", 1, true) + 1) end
        if tag == "dl" then
            table.insert(items, "<dt>" .. (label and inline(strip(label)) or "") .. "</dt><dd>" .. inline(chunk) .. "</dd>")
        else
            table.insert(items, "<li>" .. (label and ("<b>" .. inline(strip(label)) .. "</b> ") or "") .. inline(chunk) .. "</li>")
        end
        pos = next_pos
    end
    return store:put("<" .. tag .. ">" .. table.concat(items) .. "</" .. tag .. ">")
end

--- @treturn string html body, string title
function M.convert(src)
    local store = Store.new()
    local notes = {}
    local s = src:gsub("\r\n", "\n")

    -- Verbatim first: nothing inside is LaTeX.
    for _, env in ipairs({ "verbatim", "lstlisting", "minted", "Verbatim" }) do
        s = s:gsub("\\begin{" .. env .. "}(.-)\\end{" .. env .. "}", function(body)
            body = body:gsub("^%b[]", ""):gsub("^%b{}", "")
            return store:put("<pre>" .. esc(body:gsub("^\n", "")) .. "</pre>")
        end)
    end
    s = s:gsub("\\verb(%p)(.-)%1", function(_, body) return store:put("<code>" .. esc(body) .. "</code>") end)

    -- Comments (an unescaped % to end of line).
    s = s:gsub("\\%%", "\5")
    s = s:gsub("%%[^\n]*", "")
    s = s:gsub("\5", "%%")

    -- Title block.
    local title = s:match("\\title(%b{})")
    local author = s:match("\\author(%b{})")
    local date = s:match("\\date(%b{})")
    local body = s:match("\\begin{document}(.-)\\end{document}") or s

    -- Math.
    local function display(m) return store:put('<div class="math">' .. mathToHtml(m, store) .. "</div>") end
    for _, env in ipairs({ "equation%*?", "align%*?", "gather%*?", "multline%*?", "eqnarray%*?", "displaymath" }) do
        body = body:gsub("\\begin{(" .. env .. ")}(.-)\\end{%1}", function(_, m) return display(m) end)
    end
    body = body:gsub("\\%[(.-)\\%]", display)
    body = body:gsub("%$%$(.-)%$%$", display)
    body = body:gsub("\\%((.-)\\%)", function(m) return store:put('<span class="m">' .. mathToHtml(m, store) .. "</span>") end)
    body = body:gsub("\\%$", "\6")
    body = body:gsub("%$(.-)%$", function(m) return store:put('<span class="m">' .. mathToHtml(m, store) .. "</span>") end)
    body = body:gsub("\6", "$")

    local function inline(t)
        t = textCommands(t, store, notes)
        t = t:gsub("\\\\%s*", store:put("<br/>"))
        t = t:gsub("\\([&#_{}%%])", "%1")
        t = t:gsub("\\(%a+)%*?", function(cmd) return SYMBOLS[cmd] or "" end)
        t = t:gsub("[{}]", "")
        t = t:gsub("~", "\194\160")
        t = t:gsub("%-%-%-", "—"):gsub("%-%-", "–"):gsub("``", "“"):gsub("''", "”"):gsub("`", "‘")
        return esc(t)
    end

    -- Environments with structure.
    for _ = 1, 4 do -- nested lists/tables
        local before = body
        body = body:gsub("\\begin{(itemize)}(.-)\\end{itemize}", function(env, b) return listToHtml(env, b, inline, store) end)
        body = body:gsub("\\begin{(enumerate)}(.-)\\end{enumerate}", function(env, b) return listToHtml(env, b, inline, store) end)
        body = body:gsub("\\begin{(description)}(.-)\\end{description}", function(env, b) return listToHtml(env, b, inline, store) end)
        body = body:gsub("\\begin{tabular%*?}%b{}(.-)\\end{tabular%*?}", function(b) return tabularToHtml(b, store, inline) end)
        if body == before then break end
    end
    body = body:gsub("\\begin{(quote)}(.-)\\end{quote}", function(_, b) return store:put("<blockquote>") .. b .. store:put("</blockquote>") end)
    body = body:gsub("\\begin{(quotation)}(.-)\\end{quotation}", function(_, b) return store:put("<blockquote>") .. b .. store:put("</blockquote>") end)
    body = body:gsub("\\begin{abstract}(.-)\\end{abstract}", function(b) return store:put('<div class="abstract"><b>Abstract.</b> ') .. b .. store:put("</div>") end)
    body = body:gsub("\\begin{center}(.-)\\end{center}", function(b) return store:put('<div class="center">') .. b .. store:put("</div>") end)
    body = body:gsub("\\caption(%b{})", function(g) return store:put('<p class="caption">') .. strip(g) .. store:put("</p>") end)
    -- Theorem-like environments: \begin{theorem}[name] … \end{theorem}
    body = body:gsub("\\begin{(%a+)}(.-)\\end{%1}", function(env, b)
        local opt = b:match("^%s*(%b[])") or ""
        if opt ~= "" then b = b:sub((b:find("]", 1, true)) + 1) end
        local named = { theorem = "Theorem", lemma = "Lemma", proof = "Proof", definition = "Definition",
            corollary = "Corollary", proposition = "Proposition", remark = "Remark", example = "Example" }
        if named[env] then
            local head = named[env] .. (opt ~= "" and (" (" .. strip(opt) .. ")") or "") .. "."
            return store:put('<div class="thm"><b>' .. esc(head) .. "</b> ") .. b .. store:put(env == "proof" and " ∎</div>" or "</div>")
        end
        return b -- figure, table, document parts…: keep the content
    end)
    body = body:gsub("\\begin%b{}", ""):gsub("\\end%b{}", "")

    -- Sectioning.
    local levels = { part = "h1", chapter = "h1", section = "h2", subsection = "h3", subsubsection = "h4" }
    body = body:gsub("\\(%a+)%*?(%b{})", function(cmd, g)
        if levels[cmd] then
            return "\n\n" .. store:put("<" .. levels[cmd] .. ">") .. strip(g) .. store:put("</" .. levels[cmd] .. ">") .. "\n\n"
        end
        if cmd == "paragraph" then return "\n\n" .. store:put("<b>") .. strip(g) .. store:put("</b> ") end
        return nil
    end)
    if body:find("\\maketitle", 1, true) or title then
        local head = {}
        if title then table.insert(head, "<h1 class=\"title\">" .. inline(strip(title)) .. "</h1>") end
        if author then table.insert(head, "<p class=\"author\">" .. inline((strip(author):gsub("%s*\\and%s*", ", "))) .. "</p>") end
        if date and strip(date) ~= "" then table.insert(head, "<p class=\"author\">" .. inline(strip(date)) .. "</p>") end
        local block = store:put(table.concat(head))
        if body:find("\\maketitle", 1, true) then
            body = body:gsub("\\maketitle", function() return block end, 1)
        else
            body = block .. body
        end
    end
    body = body:gsub("\\tableofcontents", ""):gsub("\\newpage", ""):gsub("\\clearpage", ""):gsub("\\noindent", "")

    -- Paragraphs: blank lines.
    local out = {}
    for para in (body .. "\n\n"):gmatch("(.-)\n%s*\n") do
        if para:match("%S") then
            local html = store:restore(inline(para))
            -- A paragraph starting with a block element (heading, list, table…) doesn't get <p>.
            local first = html:match("^%s*<(%a+%d?)")
            local blocks = { h1 = 1, h2 = 1, h3 = 1, h4 = 1, div = 1, table = 1, ul = 1, ol = 1, dl = 1, pre = 1, blockquote = 1 }
            if first and blocks[first] then
                table.insert(out, html)
            else
                table.insert(out, "<p>" .. html .. "</p>")
            end
        end
    end
    if #notes > 0 then
        table.insert(out, "<hr/><ol class=\"notes\">")
        for i, n in ipairs(notes) do
            table.insert(out, string.format('<li id="fn%d">%s</li>', i, inline(n)))
        end
        table.insert(out, "</ol>")
    end
    local html = store:restore(table.concat(out, "\n"))
    -- Plain-text title for the window.
    local plain = title and strip(title):gsub("\\%a+", ""):gsub("[{}]", ""):gsub("%s+", " ") or nil
    return html, plain
end

M.CSS = [[
body { line-height: 1.4; }
h1 { font-size: 1.5em; margin: 0.6em 0 0.3em 0; }
h1.title { text-align: center; font-size: 1.6em; }
p.author { text-align: center; margin: 0.2em 0; }
h2 { font-size: 1.3em; margin: 1em 0 0.3em 0; }
h3 { font-size: 1.15em; margin: 0.8em 0 0.2em 0; }
h4 { font-size: 1em; margin: 0.6em 0 0.2em 0; }
p { margin: 0.4em 0; text-align: justify; }
.math { text-align: center; margin: 0.6em 0; font-style: italic; }
span.m { font-style: italic; }
span.mt { font-style: normal; }
.fr sup, .fr sub { font-size: 0.75em; }
pre { font-family: monospace; font-size: 0.85em; white-space: pre-wrap; border-left: 2px solid black; padding-left: 0.5em; }
code { font-family: monospace; }
blockquote, .abstract { margin: 0.5em 1.5em; }
.center { text-align: center; }
.caption { text-align: center; font-size: 0.9em; font-style: italic; }
.thm { margin: 0.6em 0; }
table { border-collapse: collapse; margin: 0.6em auto; }
td { border: 1px solid black; padding: 0.15em 0.5em; }
.sc { font-variant: small-caps; }
ol.notes { font-size: 0.85em; }
]]

return M

--[[--
The settings, grouped by what they cost: TIME (waiting, repeating, response), SPACE (memory, storage, size on
screen) and ENERGY (power). The classic settings menu stays underneath; search finds a setting by any name it
has ever had (`aliases`), so "brightness" still leads somewhere.

An entry:  { id, group, title, aliases = {...}, kind = "choice" | "toggle" | "event",
             key = G_reader_settings key, default, choices = { {value, label}, ... }, event = "EventName", note }

Order inside a group comes from entropy (see docs/osEmbedding.md, section 17): a setting that can change more
futures sits nearer the top.
    H = - sum_i p_i log2 p_i   over the values people actually pick (from usage cases), or
    H = log2(n)                when nothing is known: n equally likely choices.
Shannon entropy is the stand-in until the user's own Framal Entropy is defined. Nothing here claims otherwise.

Pure functions (tested without a screen): SettingsMap.entropy, tree, simulate, search.
]]

local SettingsMap = {}

SettingsMap.GROUPS = {
    { id = "time",   title = "Time",   about = "waiting, repeating, how fast it answers" },
    { id = "space",  title = "Space",  about = "memory, storage, size and shape on the screen" },
    { id = "energy", title = "Energy", about = "power and light" },
}

local function mins(n) return { n * 60, n .. " min" } end

SettingsMap.entries = {
    { id = "light", group = "energy", title = "Light", kind = "event", event = "ShowFlDialog", options = 100,
      aliases = { "brightness", "frontlight", "backlight", "contrast", "screen light", "warmth" },
      note = "Opens the light dialog. The OS will replace brightness with contrast (ambient light against screen light)." },
    { id = "sleep", group = "energy", title = "Sleep after idle", kind = "choice", key = "auto_suspend_timeout_seconds",
      default = 1800, aliases = { "auto suspend", "timeout", "screen off", "standby" },
      choices = { mins(1), mins(5), mins(15), mins(30), mins(60), { 0, "never" } } },
    { id = "poweroff", group = "energy", title = "Power off after sleep", kind = "choice", key = "autoshutdown_timeout_seconds",
      default = 259200, aliases = { "auto shutdown", "shut down", "turn off" },
      choices = { { 3600, "1 hour" }, { 86400, "1 day" }, { 259200, "3 days" }, { 604800, "7 days" }, { -1, "never" } } },
    { id = "wifi", group = "energy", title = "Wi-Fi", kind = "event", event = "ToggleWifi", options = 2,
      aliases = { "wifi", "wireless", "network", "internet" } },
    { id = "autosave", group = "time", title = "Save settings every", kind = "choice",
      key = "auto_save_settings_interval_minutes", default = 15, aliases = { "autosave", "save interval" },
      choices = { { 1, "1 min" }, { 5, "5 min" }, { 15, "15 min" }, { 60, "1 hour" } } },
    { id = "searchchars", group = "time", title = "Search starts after", kind = "choice", key = "kos_search_min_chars",
      default = 2, aliases = { "search", "type ahead", "characters" },
      choices = { { 1, "1 character" }, { 2, "2 characters" }, { 3, "3 characters" }, { 4, "4 characters" } } },
    { id = "titlebar", group = "space", title = "Windows 11 title bar", kind = "toggle", key = "kos_win11_titlebar",
      default = true, aliases = { "title bar", "window buttons", "minimize", "maximize", "close button" } },
    { id = "thumbs", group = "space", title = "Thumbnail cache", kind = "choice", key = "kos_thumb_cache_mb", default = 100,
      aliases = { "cache", "thumbnails", "previews", "storage" },
      choices = { { 25, "25 MB" }, { 50, "50 MB" }, { 100, "100 MB" }, { 250, "250 MB" }, { 500, "500 MB" } } },
    { id = "lines", group = "space", title = "Outline strength", kind = "choice", key = "kos_flat_lines", default = 2,
      aliases = { "lines", "borders", "menu look", "theme" },
      choices = { { 1, "faint" }, { 2, "soft" }, { 3, "clear" } } },
    { id = "corners", group = "space", title = "Corner roundness", kind = "choice", key = "kos_flat_radius", default = 1,
      aliases = { "radius", "round corners", "menu look", "theme" },
      choices = { { 0, "square" }, { 1, "soft" }, { 2, "round" } } },
}

local log2 = function(x) return math.log(x) / math.log(2) end

--- Number of values a setting can take.
function SettingsMap.options(e)
    if e.choices then return #e.choices end
    if e.kind == "toggle" then return 2 end
    return e.options or 2
end

--- Entropy in bits. `counts` (value -> times picked) gives the observed spread; without it, log2 of the
-- number of options.
function SettingsMap.entropy(e, counts)
    local total = 0
    for _, c in pairs(counts or {}) do total = total + c end
    if total == 0 then return log2(math.max(1, SettingsMap.options(e))) end
    local h = 0
    for _, c in pairs(counts) do
        if c > 0 then
            local p = c / total
            h = h - p * log2(p)
        end
    end
    return h
end

--- The three groups, each a list of { entry, bits } with the highest entropy first (ties by title).
-- `usage`: setting id -> { value -> count }, optional.
function SettingsMap.tree(usage)
    local out = {}
    for _, g in ipairs(SettingsMap.GROUPS) do
        local items = {}
        for _, e in ipairs(SettingsMap.entries) do
            if e.group == g.id then
                items[#items + 1] = { entry = e, bits = SettingsMap.entropy(e, usage and usage[e.id]) }
            end
        end
        table.sort(items, function(a, b)
            if math.abs(a.bits - b.bits) > 1e-9 then return a.bits > b.bits end
            return a.entry.title < b.entry.title
        end)
        out[#out + 1] = { group = g, items = items }
    end
    return out
end

--- Cases (each: setting id -> value picked) to usage counts, then the tree they give.
function SettingsMap.simulate(cases)
    local usage = {}
    for _, case in ipairs(cases) do
        for id, value in pairs(case) do
            usage[id] = usage[id] or {}
            local k = tostring(value)
            usage[id][k] = (usage[id][k] or 0) + 1
        end
    end
    return SettingsMap.tree(usage), usage
end

--- Entries whose title or any alias contains every word of the query.
function SettingsMap.search(query)
    local words = {}
    for w in (query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return {} end
    local hits = {}
    for _, e in ipairs(SettingsMap.entries) do
        local hay = (e.title .. " " .. table.concat(e.aliases or {}, " ")):lower()
        local ok = true
        for _, w in ipairs(words) do
            if not hay:find(w, 1, true) then ok = false break end
        end
        if ok then hits[#hits + 1] = e end
    end
    return hits
end

function SettingsMap.byId(id)
    for _, e in ipairs(SettingsMap.entries) do if e.id == id then return e end end
end

return SettingsMap

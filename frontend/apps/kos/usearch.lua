--[[--
Universal search: type, and the results follow the text. Apps and files, in places that are either
fixed (the system ones) or added by the user.

Settings (G_reader_settings):
  kos_search_min_chars   how many characters before it searches (default 2)
  kos_search_places      list of folder paths the user added

Fixed places: the Home screen's apps, the home folder, and Desktop, Downloads and Documents inside it
when they exist. Nothing here is searched before the character count is reached.

Pure parts (tested without a screen): Search.match, Search.length, Search.shouldRun, Search.scan.
]]

local Search = {}

local cache = { at = 0, key = nil, items = nil }
local CACHE_SECONDS = 60
local MAX_ITEMS = 20000
local MAX_DEPTH = 4

local function setting(name, default)
    if G_reader_settings then
        local v = G_reader_settings:readSetting(name)
        if v ~= nil then return v end
    end
    return default
end

--- Characters in a UTF-8 string (not bytes), so one Persian or accented letter counts as one.
function Search.length(text)
    local n = 0
    for _ in (text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n
end

function Search.minChars()
    local n = tonumber(setting("kos_search_min_chars", 2)) or 2
    return math.max(1, math.min(8, math.floor(n)))
end

function Search.shouldRun(query)
    return Search.length((query or ""):gsub("^%s+", ""):gsub("%s+$", "")) >= Search.minChars()
end

--- Folders searched: { label, path } in order. System ones first, then the user's own.
function Search.places(lfs)
    local places = {}
    local ok, Home = pcall(require, "apps/kos/home")
    local home = ok and Home.get() or nil
    if home then
        places[#places + 1] = { label = "Home", path = home, system = true }
        for _, name in ipairs({ "Desktop", "Downloads", "Documents" }) do
            for _, candidate in ipairs({ name, name:lower() }) do
                local p = home .. "/" .. candidate
                if lfs.attributes(p, "mode") == "directory" then
                    places[#places + 1] = { label = name, path = p, system = true }
                    break
                end
            end
        end
    end
    for _, p in ipairs(setting("kos_search_places", {})) do
        if type(p) == "string" and lfs.attributes(p, "mode") == "directory" then
            places[#places + 1] = { label = p:match("([^/]+)/*$") or p, path = p }
        end
    end
    return places
end

--- Walks one folder (to MAX_DEPTH) and appends { name, lname, path, dir } entries.
function Search.scan(lfs, root, items, depth)
    depth = depth or 0
    if depth > MAX_DEPTH or #items >= MAX_ITEMS then return items end
    local ok, iter, state = pcall(lfs.dir, root)
    if not ok then return items end
    for name in iter, state do
        if name:sub(1, 1) ~= "." then
            local path = root .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" or mode == "file" then
                items[#items + 1] = { name = name, lname = name:lower(), path = path, dir = mode == "directory" }
                if mode == "directory" then Search.scan(lfs, path, items, depth + 1) end
            end
            if #items >= MAX_ITEMS then break end
        end
    end
    return items
end

--- Every word of the query must appear in the name. Better first: name starts with the query, then
-- word starts, then shorter names. Apps rank above files when equal. Returns at most `max`.
function Search.match(items, query, max)
    local words = {}
    for w in (query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return {} end
    local scored = {}
    for _, it in ipairs(items) do
        local hay = it.lname or (it.name or ""):lower()
        local score, ok = 0, true
        for _, w in ipairs(words) do
            local at = hay:find(w, 1, true)
            if not at then ok = false; break end
            if at == 1 then score = score + 3
            elseif hay:sub(at - 1, at - 1):match("[%s%._%-]") then score = score + 2
            else score = score + 1 end
        end
        if ok then
            score = score * 100 - math.min(#hay, 99) + (it.app and 5 or 0)
            scored[#scored + 1] = { item = it, score = score }
        end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.item.name or "") < (b.item.name or "")
    end)
    local out = {}
    for i = 1, math.min(max or 8, #scored) do out[i] = scored[i].item end
    return out
end

--- All searchable things: the apps on Home, then files and folders in the places.
function Search.index(force)
    local lfs = require("libs/libkoreader-lfs")
    local places = Search.places(lfs)
    local key = ""
    for _, p in ipairs(places) do key = key .. "|" .. p.path end
    if not force and cache.items and cache.key == key and os.time() - cache.at < CACHE_SECONDS then
        return cache.items
    end
    local items = {}
    local ok, AppRegistry = pcall(require, "apps/kos/appregistry")
    if ok then
        for _, app in ipairs(AppRegistry:getApps()) do
            items[#items + 1] = { name = app.title or app.id, lname = (app.title or app.id):lower(),
                app = app, label = "app" }
        end
    end
    local seen = {}
    for _, place in ipairs(places) do
        local found = Search.scan(lfs, place.path, {}, 0)
        for _, it in ipairs(found) do
            if not seen[it.path] then
                seen[it.path] = true
                it.label = place.label
                items[#items + 1] = it
            end
        end
    end
    cache = { at = os.time(), key = key, items = items }
    return items
end

local function openItem(it)
    if it.app then
        require("apps/kos/appregistry"):launch(it.app)
    elseif it.dir then
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance then FileManager.instance:reinit(it.path) else FileManager:showFiles(it.path) end
    else
        require("apps/reader/readerui"):showReader(it.path)
    end
end
Search.openItem = openItem

---------------------------------------------------------------------------
-- The dialog. KOReader gives an input box one callback per edit, so results are rebuilt after a short
-- pause in typing (0.4 s) and the box is reopened with the same text.
---------------------------------------------------------------------------

local dialog, pending_query

function Search.show(query)
    local UIManager = require("ui/uimanager")
    local InputDialog = require("ui/widget/inputdialog")
    local _ = require("gettext")
    query = query or ""
    if dialog then UIManager:close(dialog); dialog = nil end
    local rows = {}
    if Search.shouldRun(query) then
        for _i, it in ipairs(Search.match(Search.index(), query, 6)) do
            rows[#rows + 1] = {{
                text = it.name .. "   (" .. (it.label or "") .. ")",
                callback = function()
                    UIManager:close(dialog); dialog = nil
                    openItem(it)
                end,
            }}
        end
        if #rows == 0 then rows[1] = {{ text = _("Nothing found"), enabled = false }} end
    else
        rows[1] = {{ text = string.format(_("Type %d or more characters"), Search.minChars()), enabled = false }}
    end
    rows[#rows + 1] = {{ text = _("Close"), callback = function() UIManager:close(dialog); dialog = nil end }}
    local this
    this = InputDialog:new{
        title = _("Search"),
        input = query,
        input_hint = _("apps and files"),
        buttons = rows,
        edited_callback = function()
            local text = this and this:getInputText() or ""
            pending_query = text
            UIManager:unschedule(Search._rebuild)
            if Search.shouldRun(text) then UIManager:scheduleIn(0.4, Search._rebuild) end
        end,
    }
    dialog = this
    UIManager:show(this)
    this:onShowKeyboard()
end

function Search._rebuild()
    if dialog and pending_query and Search.shouldRun(pending_query) then
        Search.show(pending_query)
    end
end

--- Menu entries for the Home screen's settings.
function Search.settingsMenu()
    local _ = require("gettext")
    local UIManager = require("ui/uimanager")
    local lengths = {}
    for n = 1, 5 do
        lengths[#lengths + 1] = {
            text = string.format(_("%d characters"), n), radio = true,
            checked_func = function() return Search.minChars() == n end,
            callback = function() G_reader_settings:saveSetting("kos_search_min_chars", n) end,
        }
    end
    return {
        text = _("Search"),
        sub_item_table = {
            { text = _("Open search"), keep_menu_open = false, callback = function() Search.show() end },
            { text = _("Start searching after"), sub_item_table = lengths },
            { text = _("Add a folder to search…"), keep_menu_open = true, callback = function()
                local InputDialog = require("ui/widget/inputdialog")
                local box
                box = InputDialog:new{
                    title = _("Folder to search"),
                    input_hint = "/storage/emulated/0/Books",
                    buttons = {{
                        { text = _("Cancel"), callback = function() UIManager:close(box) end },
                        { text = _("Add"), is_enter_default = true, callback = function()
                            local path = box:getInputText():gsub("/+$", "")
                            UIManager:close(box)
                            local lfs = require("libs/libkoreader-lfs")
                            if path ~= "" and lfs.attributes(path, "mode") == "directory" then
                                local list = setting("kos_search_places", {})
                                list[#list + 1] = path
                                G_reader_settings:saveSetting("kos_search_places", list)
                            else
                                UIManager:show(require("ui/widget/infomessage"):new{ text = _("That folder does not exist."), timeout = 3 })
                            end
                        end },
                    }},
                }
                UIManager:show(box)
                box:onShowKeyboard()
            end },
            { text = _("Forget the folders I added"), keep_menu_open = true, callback = function()
                G_reader_settings:delSetting("kos_search_places")
            end },
        },
    }
end

return Search

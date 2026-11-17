--[[--
REST router. A request is { method, path, body, client, local_ui }, an answer is status, table.
Telegram messages, HTTP requests on this device and the laptop bridge all end up here.

Built-in routes (scope in brackets):
    GET    /routes                         list every route                      [read]
    GET    /settings/:key                  read a setting                        [read]
    PUT    /settings/:key                  write a setting (keys kos_* only)     [write]
    POST   /app/:name                      open an app by name                   [control]
    POST   /event/:name                    send an allowed event                 [control]
    POST   /pipeline                       run text through the input pipeline   [control]
    GET    /adapters                       list virtual adapters                 [read]
    POST   /routes                         add a route (waits for approval)      [admin]
    DELETE /routes/:id                     remove a custom route                 [admin]
    PUT    /routes/:id/approve             approve a custom route, local screen only [admin]

A custom route is made only from the closed set of actions below. There is no "run any Lua" action,
by design: a message from outside must not become code on the device.
    { type = "setting", key = "kos_x" }     GET reads, PUT writes
    { type = "event", name = "ShowSearch" } only events from the allowed list
    { type = "app", name = "Gemma" }
    { type = "reply", text = "pong" }
Methods: GET, PUT, POST, DELETE. The words SET and WRITE mean PUT, READ means GET.
Clients need a scope: a client's scopes are in the setting kos_rest_clients { [clientId] = { "read", ... } }.
]]

local R = {}

R.METHOD_ALIAS = { SET = "PUT", WRITE = "PUT", READ = "GET", GET = "GET", PUT = "PUT", POST = "POST", DELETE = "DELETE" }
R.ALLOWED_EVENTS = { ShowSearch = true, ShowAppLauncher = true, ShowFlDialog = true, ToggleWifi = true, ShowOpenWindows = true }

local custom = {}      -- route list added at run time
local hooks = {}       -- functions the device provides: openApp, sendEvent, runPipeline, adapters

function R.setHooks(h) hooks = h or {} end

local function settings() return G_reader_settings end

function R.load()
    local saved = settings() and settings():readSetting("kos_routes")
    custom = type(saved) == "table" and saved or {}
end
local function save() if settings() then settings():saveSetting("kos_routes", custom) end end

local function nextId()
    local n = 0
    for _, r in ipairs(custom) do n = math.max(n, tonumber(r.id:match("%d+")) or 0) end
    return "r" .. (n + 1)
end

-- "/settings/:key" -> match "/settings/abc" -> { key = "abc" }
local function match(pattern, path)
    local names = {}
    local lua = "^" .. pattern:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%0"):gsub(":(%w+)", function(n) names[#names + 1] = n; return "([^/]+)" end) .. "$"
    local caps = { path:match(lua) }
    if #caps == 0 then return nil end
    local params = {}
    for i, n in ipairs(names) do params[n] = caps[i] end
    return params
end

local builtin = {
    { id = "b1", method = "GET", path = "/routes", scope = "read", about = "list every route" },
    { id = "b2", method = "GET", path = "/settings/:key", scope = "read", about = "read a setting" },
    { id = "b3", method = "PUT", path = "/settings/:key", scope = "write", about = "write a setting, keys starting kos_ only" },
    { id = "b4", method = "POST", path = "/app/:name", scope = "control", about = "open an app by name" },
    { id = "b5", method = "POST", path = "/event/:name", scope = "control", about = "send an allowed event" },
    { id = "b6", method = "POST", path = "/pipeline", scope = "control", about = "run text through the input pipeline" },
    { id = "b7", method = "GET", path = "/adapters", scope = "read", about = "list virtual adapters" },
    { id = "b8", method = "POST", path = "/routes", scope = "admin", about = "add a route, it waits for approval" },
    { id = "b9", method = "DELETE", path = "/routes/:id", scope = "admin", about = "remove a custom route" },
    { id = "b10", method = "PUT", path = "/routes/:id/approve", scope = "admin", about = "approve a custom route (local screen only)" },
}

function R.list()
    local out = {}
    for _, r in ipairs(builtin) do out[#out + 1] = { id = r.id, method = r.method, path = r.path, scope = r.scope, about = r.about, kind = "builtin", approved = true } end
    for _, r in ipairs(custom) do out[#out + 1] = { id = r.id, method = r.method, path = r.path, scope = r.scope, about = r.about or r.action.type, kind = "custom", approved = r.approved == true } end
    return out
end

local function hasScope(client, scope)
    local all = settings() and settings():readSetting("kos_rest_clients") or {}
    local mine = all[client or ""]
    if not mine then return false end
    for _, s in ipairs(mine) do if s == scope or s == "admin" then return true end end
    return false
end

--- Parse a chat line: "GET /settings/kos_x", "SET /settings/kos_x 5", "POST /app/gemma", "/pipeline hello".
function R.parseText(text)
    local m, p, body = (text or ""):match("^%s*(%a+)%s+(/%S*)%s*(.*)$")
    if not m then p, body = (text or ""):match("^%s*(/%S*)%s*(.*)$"); m = "GET" end
    if not p then return nil, "write it as: GET /path   or   SET /settings/kos_key value" end
    local method = R.METHOD_ALIAS[m:upper()]
    if not method then return nil, "unknown method " .. m .. " (GET, SET, PUT, WRITE, POST, DELETE)" end
    if body == "" then body = nil end
    return { method = method, path = p, body = body }
end

local function runAction(route, params, req)
    local a = route.action
    if a.type == "reply" then return 200, { reply = a.text } end
    if a.type == "setting" then
        if req.method == "PUT" then
            if not a.key:match("^kos_") then return 403, { error = "only kos_ settings" } end
            settings():saveSetting(a.key, req.body); return 200, { key = a.key, value = req.body }
        end
        return 200, { key = a.key, value = settings():readSetting(a.key) }
    end
    if a.type == "event" then
        if not R.ALLOWED_EVENTS[a.name] then return 403, { error = "event not allowed: " .. a.name } end
        if hooks.sendEvent then hooks.sendEvent(a.name) end
        return 200, { sent = a.name }
    end
    if a.type == "app" then
        local ok = hooks.openApp and hooks.openApp(a.name)
        return ok and 200 or 404, { app = a.name, opened = ok and true or false }
    end
    return 400, { error = "unknown action " .. tostring(a.type) }
end

function R.dispatch(req)
    req.method = R.METHOD_ALIAS[(req.method or ""):upper()] or req.method
    local path = req.path or ""
    path = path:gsub("%?.*$", "")
    -- built-in
    for _, r in ipairs(builtin) do
        if r.method == req.method then
            local params = match(r.path, path)
            if params then
                if not hasScope(req.client, r.scope) then return 403, { error = "client has no scope " .. r.scope } end
                return R._builtin(r.id, params, req)
            end
        end
    end
    for _, r in ipairs(custom) do
        if r.method == req.method then
            local params = match(r.path, path)
            if params then
                if not r.approved then return 403, { error = "route " .. r.id .. " waits for approval on the device" } end
                if not hasScope(req.client, r.scope) then return 403, { error = "client has no scope " .. r.scope } end
                return runAction(r, params, req)
            end
        end
    end
    return 404, { error = "no route for " .. req.method .. " " .. path }
end

function R._builtin(id, params, req)
    if id == "b1" then return 200, { routes = R.list() } end
    if id == "b2" then return 200, { key = params.key, value = settings():readSetting(params.key) } end
    if id == "b3" then
        if not params.key:match("^kos_") then return 403, { error = "only kos_ settings can be written" } end
        settings():saveSetting(params.key, req.body); return 200, { key = params.key, value = req.body }
    end
    if id == "b4" then
        local ok = hooks.openApp and hooks.openApp(params.name)
        return ok and 200 or 404, { app = params.name, opened = ok and true or false }
    end
    if id == "b5" then
        if not R.ALLOWED_EVENTS[params.name] then return 403, { error = "event not allowed: " .. params.name } end
        if hooks.sendEvent then hooks.sendEvent(params.name) end
        return 200, { sent = params.name }
    end
    if id == "b6" then
        if not hooks.runPipeline then return 501, { error = "no pipeline on this device" } end
        return 200, { result = hooks.runPipeline(req.body or "") }
    end
    if id == "b7" then return 200, { adapters = hooks.adapters and hooks.adapters() or {} } end
    if id == "b8" then
        -- body is "METHOD /path actionType argument", for example: GET /ping reply pong
        local m, p, t, arg = (req.body or ""):match("^(%a+)%s+(/%S*)%s+(%a+)%s*(.*)$")
        local method = m and R.METHOD_ALIAS[m:upper()]
        if not method then return 400, { error = "body: METHOD /path actionType argument" } end
        local action = { type = t }
        if t == "reply" then action.text = arg
        elseif t == "setting" then action.key = arg
        elseif t == "event" then action.name = arg
        elseif t == "app" then action.name = arg
        else return 400, { error = "action types: reply, setting, event, app" } end
        local r = { id = nextId(), method = method, path = p, scope = (method == "GET") and "read" or "control", action = action, approved = false }
        custom[#custom + 1] = r; save()
        return 201, { id = r.id, approved = false, note = "approve it on the device screen" }
    end
    if id == "b9" then
        for i, r in ipairs(custom) do if r.id == params.id then table.remove(custom, i); save(); return 200, { removed = params.id } end end
        return 404, { error = "no custom route " .. params.id }
    end
    if id == "b10" then
        if not req.local_ui then return 403, { error = "approval is only possible on the device screen" } end
        for _, r in ipairs(custom) do if r.id == params.id then r.approved = true; save(); return 200, { approved = params.id } end end
        return 404, { error = "no custom route " .. params.id }
    end
    return 500, { error = "route not implemented" }
end

--- One-line text for a chat reply.
function R.render(status, tbl)
    local parts = {}
    local keys = {}
    for k in pairs(tbl or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = tbl[k]
        if type(v) == "table" then
            local rows = {}
            for _, item in ipairs(v) do
                if type(item) == "table" then rows[#rows + 1] = (item.method or "") .. " " .. (item.path or "") .. (item.approved == false and " (waiting)" or "") else rows[#rows + 1] = tostring(item) end
            end
            parts[#parts + 1] = k .. ":\n" .. table.concat(rows, "\n")
        else parts[#parts + 1] = k .. ": " .. tostring(v) end
    end
    return status .. "\n" .. table.concat(parts, "\n")
end

function R._reset() custom = {}; hooks = {} end

return R

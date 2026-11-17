--[[--
Pipelines for the one input box. Text goes in, passes through small steps one after another, and the last
step may send it somewhere (open an app, search, a Telegram bot).

    Pipeline.run("hello", { "trim", "upper" }, ctx)      -> "HELLO", trace
    Pipeline.dispatch(text, pipelines)                  -> pipeline, rest   (first word names a pipeline)
    Pipeline.register("shout", function(text, ctx) return text .. "!" end)

A step is  function(text, ctx) -> text  |  nil, "why it stopped". A pipeline is { name =, steps = { names... } }
and the user's own are kept in the setting kos_pipelines. With no pipeline named, the text goes to
the "search" pipeline (universal search).

Steps that exist: trim lower upper firstWord rest search app telegram echo
Telegram needs two settings: kos_telegram_token (from @BotFather) and kos_telegram_chat (your chat id).
Everything a run did is returned as a trace, line by line, for the action log.
]]

local Pipeline = {}

local steps = {}

function Pipeline.register(name, fn) steps[name] = fn end
function Pipeline.hasStep(name) return steps[name] ~= nil end

function Pipeline.run(text, names, ctx)
    ctx = ctx or {}
    local trace = {}
    for _, name in ipairs(names or {}) do
        local fn = steps[name]
        if not fn then
            trace[#trace + 1] = name .. ": no such step"
            return nil, trace, "no such step: " .. name
        end
        local out, err = fn(text, ctx)
        if out == nil then
            trace[#trace + 1] = name .. ": stopped, " .. tostring(err)
            return nil, trace, err or (name .. " stopped")
        end
        trace[#trace + 1] = string.format("%s: %q -> %q", name, text, out)
        text = out
    end
    return text, trace
end

--- "bot hello there" with a pipeline called bot -> that pipeline and "hello there". Also "bot: hello".
function Pipeline.dispatch(text, pipelines)
    local word, rest = text:match("^%s*([^%s:]+)[%s:]+(.*)$")
    if word then
        for _, p in ipairs(pipelines or {}) do
            if p.name:lower() == word:lower() then return p, rest end
        end
    end
    return nil, text
end

function Pipeline.defaults()
    return {
        { name = "search", steps = { "trim", "search" } },
        { name = "open", steps = { "trim", "app" } },
        { name = "bot", steps = { "trim", "telegram" } },
    }
end

function Pipeline.load()
    local saved = G_reader_settings and G_reader_settings:readSetting("kos_pipelines")
    if type(saved) == "table" and #saved > 0 then return saved end
    return Pipeline.defaults()
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------

Pipeline.register("trim", function(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end)
Pipeline.register("lower", function(t) return t:lower() end)
Pipeline.register("upper", function(t) return t:upper() end)
Pipeline.register("echo", function(t) return t end)
Pipeline.register("firstWord", function(t) return t:match("^%s*(%S+)") or "" end)
Pipeline.register("rest", function(t) return (t:match("^%s*%S+%s*(.*)$")) or "" end)

Pipeline.register("search", function(t, ctx)
    if t == "" then return nil, "nothing to search for" end
    if ctx.search then ctx.search(t) end
    return t
end)

Pipeline.register("app", function(t, ctx)
    local match = ctx.findApp and ctx.findApp(t)
    if not match then return nil, "no app called " .. t end
    if ctx.openApp then ctx.openApp(match) end
    return t
end)

--- Sends one message with the Telegram bot API. `transport(url, json_body)` -> http code, body text;
-- the default uses LuaSec on the device. Only the token and chat id from the settings are used.
function Pipeline.telegramSend(token, chat, text, transport)
    if not token or token == "" then return nil, "no bot token (setting kos_telegram_token, from @BotFather)" end
    if not chat or chat == "" then return nil, "no chat id (setting kos_telegram_chat)" end
    local JSON = require("json")
    local url = "https://api.telegram.org/bot" .. token .. "/sendMessage"
    local body = JSON.encode({ chat_id = chat, text = text })
    local code, reply = (transport or Pipeline.httpsPost)(url, body)
    if code ~= 200 then
        return nil, "Telegram answered " .. tostring(code) .. (reply and (": " .. tostring(reply):sub(1, 120)) or "")
    end
    return true
end

function Pipeline.httpsPost(url, body)
    local https = require("ssl.https")
    local ltn12 = require("ltn12")
    local sink = {}
    local ok, code = https.request{
        url = url, method = "POST", source = ltn12.source.string(body), sink = ltn12.sink.table(sink),
        headers = { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body) },
    }
    if not ok then return nil, tostring(code) end
    return code, table.concat(sink)
end

Pipeline.register("telegram", function(t, ctx)
    local token = ctx.telegram_token or (G_reader_settings and G_reader_settings:readSetting("kos_telegram_token"))
    local chat = ctx.telegram_chat or (G_reader_settings and G_reader_settings:readSetting("kos_telegram_chat"))
    local ok, err = Pipeline.telegramSend(token, chat, t, ctx.transport)
    if not ok then return nil, err end
    return t
end)

return Pipeline

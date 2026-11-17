--[[--
The name this phone gives itself to the laptop bridge. The bridge's registry lists clients by this id and
asks you to approve a new one. It is made once (device model plus 4 random characters) and kept.

    BridgeId.get()                  -> "SM-F946B-3fa1"
    BridgeId.headers(pin)           -> { ["X-Bridge-Pin"] = pin, ["X-Bridge-Client"] = id }
    BridgeId.explain(code, body)    -> text for a 401 or 403 answer, nil for other codes
]]
local BridgeId = {}

function BridgeId.get()
    local id = G_reader_settings and G_reader_settings:readSetting("kos_client_id")
    if id then return id end
    local model = "koreader"
    local ok, Device = pcall(require, "device")
    if ok and Device and Device.model then model = tostring(Device.model):gsub("[^%w]", "") end
    math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000000))
    id = string.format("%s-%04x", model, math.random(0, 0xffff))
    if G_reader_settings then G_reader_settings:saveSetting("kos_client_id", id) end
    return id
end

function BridgeId.headers(pin, extra)
    local h = { ["X-Bridge-Pin"] = pin or "", ["X-Bridge-Client"] = BridgeId.get() }
    for k, v in pairs(extra or {}) do h[k] = v end
    return h
end

function BridgeId.explain(code, body)
    local _ = require("gettext")
    if code == 401 then return _("Wrong PIN.") end
    if code == 403 then
        local id = BridgeId.get()
        local reason = type(body) == "string" and body:match('"error"%s*:%s*"([^"]*)"') or nil
        if reason and reason:find("waiting for approval", 1, true) then
            return _("Waiting for your approval on the laptop. Run:  python3 registry.py approve ") .. id
        end
        return _("The laptop refused: ") .. (reason or _("no grant"))
    end
end

return BridgeId

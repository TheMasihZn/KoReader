--[[--
What the top-level model may do inside the sandbox, decided in one place. The model proposes an action, this
module answers "allow", "confirm" (a person says yes on the screen, or by voice with a spoken phrase) or "deny".

    Policy.decide{ kind = "file.write", path = "/sdcard/koreader/sandbox/a.txt" } -> "allow", reason
    Policy.decide{ kind = "adapter.arm", chain = "knobToEsp" }                    -> "confirm", reason

Autonomy here means: it can read, write inside the sandbox folder, open apps, change kos_ settings and build apps
without asking. It cannot change this policy, approve routes, change tokens or leave the sandbox. Things with
effects outside the phone (hardware, network, packages, deleting) ask first. Every allowed action is returned with
journal = true so the caller writes it to the change journal. File writes are meant to be undone through dotted
versions (apps/kos/versions.lua) and git restore points.
Change the table below to change the rules; the model cannot.
]]

local Policy = {}

Policy.sandbox = "/sdcard/koreader/sandbox"

local rules = {
    ["read"] = "allow", ["setting.read"] = "allow", ["app.open"] = "allow", ["adapter.list"] = "allow", ["adapter.simulate"] = "allow",
    ["setting.write"] = "allow", ["file.write"] = "allow", ["app.build"] = "allow", ["adapter.define"] = "allow",
    ["file.delete"] = "confirm", ["adapter.arm"] = "confirm", ["adapter.send"] = "confirm", ["net.request"] = "confirm",
    ["package.install"] = "confirm", ["shell"] = "confirm", ["flash.device"] = "confirm", ["voice.hardware"] = "confirm",
    ["policy.change"] = "deny", ["route.approve"] = "deny", ["token.change"] = "deny", ["registry.approve"] = "deny",
}

local function inside(path)
    if type(path) ~= "string" or path:find("%.%.") then return false end
    return path:sub(1, #Policy.sandbox + 1) == Policy.sandbox .. "/" or path == Policy.sandbox
end

function Policy.decide(a)
    local rule = rules[a.kind]
    if not rule then return "deny", "unknown kind of action: " .. tostring(a.kind) end
    if (a.kind == "file.write" or a.kind == "file.delete") and not inside(a.path) then
        return "deny", "outside the sandbox folder " .. Policy.sandbox
    end
    if a.kind == "setting.write" and not tostring(a.key or ""):match("^kos_") then
        return "deny", "only kos_ settings"
    end
    if a.kind == "shell" and a.cmd and a.cmd:find("[;&|`$<>]") then
        return "deny", "shell commands with chaining or redirection are refused"
    end
    local reason = rule == "allow" and "allowed, written to the journal" or rule == "confirm" and "needs a yes from you" or "only you can do this, on the screen"
    return rule, reason, rule == "allow"
end

--- Voice confirmation: a one-time phrase the person must say back, so a stray word cannot approve hardware.
local words = { "amber", "birch", "cedar", "delta", "ember", "fjord", "glade", "harbor" }
function Policy.challenge(seed)
    local n = (seed or os.time())
    return words[(n % #words) + 1] .. " " .. (((n // #words) % 90) + 10)
end
function Policy.confirm(challenge, heard)
    return type(heard) == "string" and heard:lower():gsub("[%p]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "") == challenge:lower()
end

return Policy

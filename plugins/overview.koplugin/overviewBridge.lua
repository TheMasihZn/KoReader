--[[--
Calls from Lua into the Android side of Overview (MainActivity.overview* methods).
On any other platform (desktop emulator, Kindle) every call is a harmless no-op,
so the UI can still be developed and tested there.
--]]

local ok, android = pcall(require, "android")
local Bridge = {}

local function available()
    return ok and android and android.app and android.jni
end

local function call(kind, method, signature, ...)
    if not available() then return nil end
    local args = { ... }
    return android.jni:context(android.app.activity.vm, function(jni)
        local refs = {}
        for i, v in ipairs(args) do
            if type(v) == "string" then
                args[i] = jni.env[0].NewStringUTF(jni.env, v)
                table.insert(refs, args[i])
            end
        end
        local clazz = android.app.activity.clazz
        local result
        if kind == "string" then
            result = jni:to_string(jni:callObjectMethod(clazz, method, signature, unpack(args)))
        elseif kind == "boolean" then
            result = jni:callBooleanMethod(clazz, method, signature, unpack(args))
        else
            jni:callVoidMethod(clazz, method, signature, unpack(args))
        end
        for _, ref in ipairs(refs) do
            jni.env[0].DeleteLocalRef(jni.env, ref)
        end
        return result
    end)
end

function Bridge.isAndroid() return available() and true or false end

function Bridge.dbPath()
    return call("string", "overviewDbPath", "()Ljava/lang/String;")
end

--- Returns { listener = bool, navigator = bool, contacts = bool, sms = bool }
function Bridge.status()
    local s = call("string", "overviewStatus", "()Ljava/lang/String;") or ""
    local status = {}
    for key, value in s:gmatch("(%w+)=(%d)") do
        status[key] = value == "1"
    end
    return status
end

function Bridge.sync()
    call("void", "overviewSync", "()V")
end

--- Returns { { label = "Instagram", package = "com.instagram.android" }, ... }
function Bridge.apps()
    local list = {}
    local raw = call("string", "overviewApps", "()Ljava/lang/String;") or ""
    for line in raw:gmatch("[^\n]+") do
        local label, package = line:match("^(.-)\t(.+)$")
        if label then table.insert(list, { label = label, package = package }) end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return list
end

function Bridge.launchApp(package)
    return call("boolean", "overviewLaunchApp", "(Ljava/lang/String;)Z", package)
end

--- Opens the original chat and scrolls to the message (needs the accessibility service).
function Bridge.openOriginal(message_id)
    if not available() then return false end
    return android.jni:context(android.app.activity.vm, function(jni)
        return jni:callBooleanMethod(android.app.activity.clazz,
            "overviewOpenOriginal", "(J)Z", require("ffi").new("int64_t", message_id))
    end)
end

--- kind: "listener", "navigator" or "permissions"
function Bridge.openSetup(kind)
    call("void", "overviewOpenSetup", "(Ljava/lang/String;)V", kind)
end

return Bridge

--[[--
Open a file in an IDE (IntelliJ, Android Studio, or any app the user names) with an Android intent.

    IdeHandoff.command(path, package)   -> the shell command that asks Android to open the file in that app
    IdeHandoff.open(path, package)      -> runs it, returns ok, message
    IdeHandoff.supported(path)          -> true for source and text files an IDE can edit

The package is chosen by the user in the setting kos_ide_package (for example the package name of the IDE
as shown by `pm list packages`). Without one, Android's own chooser appears. The path is quoted for the shell.
Only the file named by the user is handed over, nothing else.
]]

local IdeHandoff = {}

local EXT = {}
for e in ([[lua py kt kts java xml gradle json md txt c h cpp hpp cs js ts html css sh yml yaml toml ini properties sql tex svg]]):gmatch("%S+") do EXT[e] = true end

function IdeHandoff.supported(path)
    local ext = (path or ""):match("%.([^%./]+)$")
    return ext ~= nil and EXT[ext:lower()] == true
end

local function shellQuote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function uriEncode(path)
    return (path:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", c:byte()) end))
end

function IdeHandoff.command(path, package)
    local parts = { "am start -a android.intent.action.VIEW",
        "-d " .. shellQuote("file://" .. uriEncode(path)),
        "-t " .. shellQuote(IdeHandoff.mime(path)) }
    if package and package ~= "" then parts[#parts + 1] = "-p " .. shellQuote(package) end
    return table.concat(parts, " ")
end

function IdeHandoff.mime(path)
    local ext = (path:match("%.([^%./]+)$") or ""):lower()
    local m = { json = "application/json", xml = "text/xml", html = "text/html", svg = "image/svg+xml" }
    return m[ext] or "text/plain"
end

function IdeHandoff.open(path, package, runner)
    if not IdeHandoff.supported(path) then return false, "not a file an IDE edits" end
    local cmd = IdeHandoff.command(path, package)
    local rc = (runner or os.execute)(cmd .. " >/dev/null 2>&1")
    if rc == 0 or rc == true then return true, cmd end
    return false, "Android refused (" .. tostring(rc) .. "). Is the app installed, and is its package name right?"
end

return IdeHandoff

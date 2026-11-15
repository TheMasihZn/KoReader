-- Pure helpers for the Share app (testable without the UI).
local U = {}

function U.humanSize(n)
    n = tonumber(n) or 0
    if n < 1024 then return string.format("%d B", n) end
    if n < 1048576 then return string.format("%.0f KB", n / 1024) end
    if n < 1073741824 then return string.format("%.1f MB", n / 1048576) end
    return string.format("%.2f GB", n / 1073741824)
end

--- "a/b" + "c" -> "a/b/c"; "" + "c" -> "c". Never produces a leading slash.
function U.join(dir, name)
    if dir == nil or dir == "" then return name end
    return (dir:gsub("/+$", "")) .. "/" .. name
end

--- "a/b/c" -> "a/b"; "a" -> "".
function U.parent(dir)
    return (dir or ""):match("^(.*)/[^/]*$") or ""
end

--- Percent-encodes a path for a query string.
function U.encode(s)
    return (tostring(s):gsub("[^%w%-_%.~/]", function(c) return string.format("%%%02X", c:byte()) end))
end

--- Keeps a file name from walking out of the target folder.
function U.safeName(name)
    name = tostring(name or ""):gsub("[/\\]", "_"):gsub("^%.+", "")
    if name == "" then name = "file" end
    return name
end

return U

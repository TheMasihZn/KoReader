--[[--
Plain HTTP in and out for the REST router: turns the text of one request into a router request, and the router's
answer into the text of a response. The socket loop lives in the plugin; this part has no I/O so it can be tested.

    local req, err_status = Http.parse(raw, tokens)    -- tokens = { [secret] = clientId }
    local text = Http.response(status, tbl, json)
A request needs the header X-Rest-Token. Unknown token: 401. A body is read up to Content-Length (max 8 KB).
]]

local Http = {}
local REASON = { [200] = "OK", [201] = "Created", [400] = "Bad Request", [401] = "Unauthorized", [403] = "Forbidden", [404] = "Not Found", [413] = "Payload Too Large", [500] = "Internal Server Error", [501] = "Not Implemented" }

function Http.parse(raw, tokens)
    local head, body = raw:match("^(.-)\r?\n\r?\n(.*)$")
    head = head or raw; body = body or ""
    local method, path = head:match("^(%u+)%s+(%S+)%s+HTTP/")
    if not method then return nil, 400 end
    local headers = {}
    for k, v in head:gmatch("\n([%w%-]+):%s*([^\r\n]*)") do headers[k:lower()] = v end
    local len = tonumber(headers["content-length"]) or 0
    if len > 8192 then return nil, 413 end
    body = body:sub(1, len)
    local client = tokens and headers["x-rest-token"] and tokens[headers["x-rest-token"]]
    if not client then return nil, 401 end
    return { method = method, path = path, body = (body ~= "" and body or nil), client = client }
end

function Http.response(status, tbl, json)
    local body = json and json.encode(tbl or {}) or "{}"
    return ("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"):format(status, REASON[status] or "Status", #body, body)
end

return Http

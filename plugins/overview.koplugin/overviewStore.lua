--[[--
Read-only queries on the database the Android side fills (overview.sqlite).
--]]

local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local Store = {}
Store.__index = Store

function Store.open(path)
    if not path then return nil end
    local ok, conn = pcall(SQ3.open, path)
    if not ok then
        logger.warn("Overview: cannot open", path, conn)
        return nil
    end
    return setmetatable({ conn = conn }, Store)
end

local function rows(conn, sql, ...)
    local result = {}
    local ok, err = pcall(function(...)
        local stmt = conn:prepare(sql)
        stmt:bind(...)
        local row = stmt:step()
        while row do
            table.insert(result, row)
            row = stmt:step()
        end
        stmt:close()
    end, ...)
    if not ok then logger.warn("Overview: query failed", err) end
    return result
end

local function like(q)
    return "%" .. q:gsub("[%%_\\]", "\\%0") .. "%"
end

--- Contacts whose name contains q.
function Store:contacts(q, limit)
    local list = {}
    for _, r in ipairs(rows(self.conn,
            "SELECT name, phones FROM contacts WHERE name LIKE ? ESCAPE '\\' ORDER BY name LIMIT " .. math.floor(limit or 5),
            like(q))) do
        table.insert(list, { name = r[1], phones = r[2] })
    end
    return list
end

--- Messages that mention q in the chat name, the sender or the text,
--- the newest `limit` of them, returned oldest first.
function Store:messages(q, limit)
    local list = {}
    local pattern = like(q)
    for _, r in ipairs(rows(self.conn, [[
            SELECT id, appName, conversation, sender, body, time, outgoing FROM messages
            WHERE conversation LIKE ?1 ESCAPE '\' OR sender LIKE ?1 ESCAPE '\' OR body LIKE ?1 ESCAPE '\'
            ORDER BY time DESC LIMIT ]] .. math.floor(limit or 300), pattern)) do
        table.insert(list, 1, {
            id = tonumber(r[1]),
            app = r[2],
            conversation = r[3],
            sender = r[4],
            body = r[5],
            time = tonumber(r[6]),
            outgoing = tonumber(r[7]) == 1,
        })
    end
    return list
end

function Store:close()
    pcall(function() self.conn:close() end)
end

return Store

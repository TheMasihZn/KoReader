local store = {}
G_reader_settings = { readSetting = function(_, k) return store[k] end, saveSetting = function(_, k, v) store[k] = v end }
local R = dofile("frontend/apps/kos/restrouter.lua")
local opened, sent = {}, {}
R.setHooks{ openApp = function(n) opened[#opened + 1] = n; return n:lower() == "gemma" end, sendEvent = function(n) sent[#sent + 1] = n end,
  runPipeline = function(t) return "ran:" .. t end, adapters = function() return { "esp32a" } end }
store.kos_rest_clients = { tg42 = { "read", "write", "control" }, boss = { "admin" }, nobody = {} }
local s, b
-- parse
local q = R.parseText("SET /settings/kos_search_min_chars 4"); assert(q.method == "PUT" and q.path == "/settings/kos_search_min_chars" and q.body == "4")
assert(R.parseText("/routes").method == "GET"); assert(R.parseText("WRITE /x y").method == "PUT"); assert(not R.parseText("hello"))
assert(select(2, R.parseText("FLY /x")):find("unknown method"))
-- scopes
s, b = R.dispatch{ method = "GET", path = "/routes", client = "nobody" }; assert(s == 403)
s, b = R.dispatch{ method = "GET", path = "/routes", client = "tg42" }; assert(s == 200 and #b.routes >= 10)
-- settings read/write, kos_ only
s = R.dispatch{ method = "PUT", path = "/settings/kos_search_min_chars", body = "4", client = "tg42" }; assert(s == 200 and store.kos_search_min_chars == "4")
s, b = R.dispatch{ method = "GET", path = "/settings/kos_search_min_chars", client = "tg42" }; assert(b.value == "4")
s = R.dispatch{ method = "PUT", path = "/settings/home_dir", body = "/", client = "tg42" }; assert(s == 403 and store.home_dir == nil)
-- app, event allowlist, pipeline, adapters
s = R.dispatch{ method = "POST", path = "/app/gemma", client = "tg42" }; assert(s == 200 and opened[1] == "gemma")
s = R.dispatch{ method = "POST", path = "/app/nothing", client = "tg42" }; assert(s == 404)
s = R.dispatch{ method = "POST", path = "/event/ShowSearch", client = "tg42" }; assert(s == 200 and sent[1] == "ShowSearch")
s = R.dispatch{ method = "POST", path = "/event/Exit", client = "tg42" }; assert(s == 403 and #sent == 1)
s, b = R.dispatch{ method = "POST", path = "/pipeline", body = "hi", client = "tg42" }; assert(b.result == "ran:hi")
s, b = R.dispatch{ method = "GET", path = "/adapters", client = "tg42" }; assert(b.adapters[1] == "esp32a")
-- custom routes: need approval, approval only on the local screen, closed action set
s, b = R.dispatch{ method = "POST", path = "/routes", body = "GET /ping reply pong", client = "boss" }; assert(s == 201 and b.id == "r1" and b.approved == false)
s = R.dispatch{ method = "GET", path = "/ping", client = "tg42" }; assert(s == 403)
s = R.dispatch{ method = "PUT", path = "/routes/r1/approve", client = "boss" }; assert(s == 403)          -- remote cannot approve
s = R.dispatch{ method = "PUT", path = "/routes/r1/approve", client = "boss", local_ui = true }; assert(s == 200)
s, b = R.dispatch{ method = "GET", path = "/ping", client = "tg42" }; assert(s == 200 and b.reply == "pong")
s = R.dispatch{ method = "POST", path = "/routes", body = "GET /x lua os.execute('rm')", client = "boss" }; assert(s == 400)
s = R.dispatch{ method = "POST", path = "/routes", body = "POST /e event Exit", client = "boss" }; assert(s == 201)
R.dispatch{ method = "PUT", path = "/routes/r2/approve", client = "boss", local_ui = true }
s = R.dispatch{ method = "POST", path = "/e", client = "tg42" }; assert(s == 403)   -- allowlist applies to custom routes too
-- persistence and delete
R.load(); assert(#R.list() == 12, #R.list())
s = R.dispatch{ method = "DELETE", path = "/routes/r1", client = "boss" }; assert(s == 200 and #R.list() == 11)
s = R.dispatch{ method = "GET", path = "/nope", client = "tg42" }; assert(s == 404)
assert(R.render(200, { routes = R.list() }):find("GET /routes"))
print("restrouter ok")

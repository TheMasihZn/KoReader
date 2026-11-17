import os, sys, json, tempfile, threading, urllib.request, urllib.error
home = tempfile.mkdtemp(); os.environ["HOME"] = home
os.environ["KOS_BRIDGE_TEST_REMOTE"] = "1"
sys.path.insert(0, "tools/gemmaBridge")
import importlib
import registry as R
R.APP_DIR = os.path.join(home, ".gemmaBridge")
import gemma_bridge as G
from http.server import ThreadingHTTPServer
reg = R.Registry(os.path.join(R.APP_DIR, "registry.json"), os.path.join(R.APP_DIR, "access.log"))
cfg = {"pin": "123456", "share_dir": os.path.join(home, "share")}
os.makedirs(cfg["share_dir"], exist_ok=True)
class Stub:
    sessions = {}
    def summary(self): return []
    def pick_model(self): return "m"
class Sp: engine = None
H = G.make_handler(Stub(), None, Stub(), cfg, Sp(), reg)
srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
def get(path, pin="123456", client="phoneA"):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}")
    if pin: req.add_header("X-Bridge-Pin", pin)
    if client: req.add_header("X-Bridge-Client", client)
    try:
        with urllib.request.urlopen(req) as r: return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read())
assert get("/api/info", pin="bad")[0] == 401                 # wrong PIN
c, body = get("/api/info");  assert c == 403 and "waiting for approval" in body["error"], (c, body)   # unknown client
assert "phoneA" in reg.pending()
reg.approve("phoneA", ["chat", "info"])
assert get("/api/info")[0] == 200                           # granted
assert get("/api/sessions")[0] == 200
c, body = get("/api/files"); assert c == 403 and "no grant for files.read" in body["error"]
reg.grant("phoneA", ["files.read"]); assert get("/api/files")[0] in (200, 404)
reg.revoke("phoneA", ["files.read"]); assert get("/api/files")[0] == 403
reg.revoke("phoneA"); assert get("/api/info")[0] == 403      # all access removed, entry kept
assert get("/api/registry")[0] == 403                        # registry is laptop only (test treats us as remote)
log = [json.loads(l) for l in open(reg.log_path)]
assert any(l["client"] == "phoneA" and not l["allowed"] for l in log) and any(l["allowed"] for l in log)
try: reg.approve("x", ["nonsense"]); assert False
except ValueError: pass
reg.forget("phoneA"); assert "phoneA" not in reg.listing()
# hand edit takes effect
open(reg.path, "w").write(json.dumps({"entries": {"phoneB": {"kind": "device", "approved": True, "grants": ["info"], "address": ""}}}))
assert get("/api/info", client="phoneB")[0] == 200
print("registry ok;", len(log), "log lines")

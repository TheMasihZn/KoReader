#!/usr/bin/env python3
"""
Gemma bridge: one Gemma conversation shared by your laptop and your phone.

Runs on the laptop, in front of Ollama. The laptop (browser page) and the
phone (KOReader OS "Gemma" app) see and continue the same conversation.

    python3 gemma_bridge.py                 # then open http://localhost:8765
    python3 gemma_bridge.py --model gemma3  # pick a model (default: first gemma* in Ollama)

Only Python's standard library is used (Ubuntu: nothing to install).

Reliability ("repeat / cache"):
* Every message is saved to disk (~/.gemmaBridge/sessions/*.json) as it changes.
* Each message a client sends carries its own id: sending it again (e.g. after
  Wi-Fi dropped) never creates a duplicate.
* Replies are generated on the laptop even if the phone disconnects; the phone
  picks up the finished answer when it reconnects.

Security: the phone needs the PIN printed at start-up (kept in
~/.gemmaBridge/config.json). The laptop itself (localhost) needs no PIN.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import os
import secrets
import socket
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

APP_DIR = os.path.expanduser("~/.gemmaBridge")
_OLD_DIR = os.path.expanduser("~/.gemma-bridge")  # renamed: keep existing conversations
if os.path.isdir(_OLD_DIR) and not os.path.exists(APP_DIR):
    os.rename(_OLD_DIR, APP_DIR)
SESSIONS_DIR = os.path.join(APP_DIR, "sessions")
CONFIG_FILE = os.path.join(APP_DIR, "config.json")
AUDIO_DIR = os.path.join(APP_DIR, "audio")
import fileshare
import registry as registry_mod  # noqa: E402  (same folder)

DISCOVERY_PORT = 47801
DISCOVERY_ASK = b"GEMMA-BRIDGE?"


# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------

def load_config():
    os.makedirs(SESSIONS_DIR, exist_ok=True)
    cfg = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, encoding="utf-8") as f:
            cfg = json.load(f)
    if not cfg.get("pin"):
        cfg["pin"] = f"{secrets.randbelow(1_000_000):06d}"
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    return cfg


# --------------------------------------------------------------------------
# Ollama
# --------------------------------------------------------------------------

class Ollama:
    def __init__(self, url, model=None):
        self.url = url.rstrip("/")
        self.model = model

    def models(self):
        with urllib.request.urlopen(self.url + "/api/tags", timeout=5) as r:
            return [m["name"] for m in json.load(r).get("models", [])]

    def pick_model(self):
        if self.model:
            return self.model
        try:
            names = self.models()
        except OSError:
            return None
        gemmas = [n for n in names if "gemma" in n.lower()]
        self.model = (gemmas or names or [None])[0]
        return self.model

    def chat_stream(self, messages):
        """Yields text chunks of the reply."""
        body = json.dumps({"model": self.pick_model(), "messages": messages, "stream": True}).encode()
        req = urllib.request.Request(self.url + "/api/chat", data=body,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            for line in r:
                if not line.strip():
                    continue
                data = json.loads(line)
                if data.get("error"):
                    raise RuntimeError(data["error"])
                chunk = data.get("message", {}).get("content", "")
                if chunk:
                    yield chunk
                if data.get("done"):
                    break


# --------------------------------------------------------------------------
# Sessions (the shared conversations)
# --------------------------------------------------------------------------

class Store:
    """All sessions, with a revision counter so clients can ask "what changed since N"."""

    def __init__(self):
        self.lock = threading.Condition()
        self.rev = 0
        self.sessions = {}
        for name in sorted(os.listdir(SESSIONS_DIR)):
            if name.endswith(".json"):
                with open(os.path.join(SESSIONS_DIR, name), encoding="utf-8") as f:
                    s = json.load(f)
                for m in s["messages"]:
                    if m.get("status") == "thinking":  # interrupted by a restart
                        m["status"] = "error"
                        m["text"] = (m.get("text") or "") + "\n[interrupted: the bridge was restarted]"
                self.sessions[s["id"]] = s
                self.rev = max(self.rev, s.get("rev", 0))
        if "main" not in self.sessions:
            self.create("Main", sid="main")

    def _save(self, s):
        tmp = os.path.join(SESSIONS_DIR, s["id"] + ".json.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(s, f, ensure_ascii=False, indent=1)
        os.replace(tmp, os.path.join(SESSIONS_DIR, s["id"] + ".json"))

    def _bump(self, s, msg=None):
        self.rev += 1
        s["rev"] = self.rev
        s["updated"] = time.time()
        if msg is not None:
            msg["rev"] = self.rev
        self.lock.notify_all()

    def create(self, title, sid=None):
        with self.lock:
            sid = sid or f"s{int(time.time())}{secrets.randbelow(1000):03d}"
            s = {"id": sid, "title": title or "Chat", "messages": [], "rev": 0, "updated": time.time()}
            self.sessions[sid] = s
            self._bump(s)
            self._save(s)
            return s

    def summary(self):
        with self.lock:
            return [{"id": s["id"], "title": s["title"], "updated": s["updated"], "count": len(s["messages"])}
                    for s in sorted(self.sessions.values(), key=lambda x: -x["updated"])]

    def changes(self, sid, since, wait=0.0):
        """Messages changed after revision `since`; waits up to `wait` s for news."""
        deadline = time.time() + min(wait, 25)
        with self.lock:
            s = self.sessions.get(sid)
            if s is None:
                return None
            while s["rev"] <= since and time.time() < deadline:
                self.lock.wait(deadline - time.time())
            msgs = [m for m in s["messages"] if m.get("rev", 0) > since]
            busy = any(m.get("status") == "thinking" for m in s["messages"])
            return {"rev": s["rev"], "messages": msgs, "busy": busy, "title": s["title"]}

    def add_user(self, sid, text, sender, client_id):
        """Adds a message; returns (message, is_new). Same client_id twice = same message."""
        with self.lock:
            s = self.sessions[sid]
            if client_id:
                for m in s["messages"]:
                    if m.get("client_id") == client_id:
                        return m, False
            m = {"id": len(s["messages"]) + 1, "role": "user", "from": sender, "text": text,
                 "time": time.time(), "status": "done", "client_id": client_id}
            s["messages"].append(m)
            self._bump(s, m)
            self._save(s)
            return m, True

    def start_reply(self, sid):
        with self.lock:
            s = self.sessions[sid]
            m = {"id": len(s["messages"]) + 1, "role": "assistant", "from": "gemma", "text": "",
                 "time": time.time(), "status": "thinking"}
            s["messages"].append(m)
            self._bump(s, m)
            history = [{"role": x["role"], "content": x["text"]} for x in s["messages"]
                       if x["status"] == "done" and x["text"]]
            return m, history

    def update_reply(self, sid, m, text=None, status=None, save=False):
        with self.lock:
            s = self.sessions[sid]
            if text is not None:
                m["text"] = text
            if status is not None:
                m["status"] = status
            self._bump(s, m)
            if save:
                self._save(s)


class Generator:
    """One reply at a time per session, in the background (survives the phone leaving)."""

    def __init__(self, store, ollama, speech=None):
        self.store = store
        self.ollama = ollama
        self.speech = speech
        self.running = set()
        self.lock = threading.Lock()

    def kick(self, sid):
        with self.lock:
            if sid in self.running:
                return
            self.running.add(sid)
        threading.Thread(target=self._run, args=(sid,), daemon=True).start()

    def _pending(self, sid):
        with self.store.lock:
            msgs = self.store.sessions[sid]["messages"]
            return bool(msgs) and msgs[-1]["role"] == "user"

    def _run(self, sid):
        try:
            # Messages sent while a reply was being written get answered next.
            while self._pending(sid):
                m, history = self.store.start_reply(sid)
                text, last_push = "", 0.0
                try:
                    for chunk in self.ollama.chat_stream(history):
                        text += chunk
                        if time.time() - last_push > 0.4:  # partial text for live viewers
                            self.store.update_reply(sid, m, text=text)
                            last_push = time.time()
                    self.store.update_reply(sid, m, text=text, status="done", save=True)
                    if self.speech and self.speech.engine:  # pre-cache the audio, so Play starts at once
                        threading.Thread(target=self.speech.wav, args=(text,), daemon=True).start()
                except (OSError, RuntimeError, urllib.error.URLError) as e:
                    self.store.update_reply(sid, m, text=(text + f"\n[error: {e}]").strip(), status="error", save=True)
        finally:
            with self.lock:
                self.running.discard(sid)


# --------------------------------------------------------------------------
# Audio: speech for replies, cached so "repeat" is instant and works offline
# --------------------------------------------------------------------------

class Speech:
    """Turns text into a .wav once, then serves the cached file every time after.

    Engines tried in order (install one on Ubuntu, e.g. `sudo apt install espeak-ng`):
      piper  (set PIPER_MODEL=/path/voice.onnx; most natural)
      espeak-ng, espeak, pico2wave
    """

    def __init__(self):
        os.makedirs(AUDIO_DIR, exist_ok=True)
        self.lock = threading.Lock()
        self.engine = None
        if shutil.which("piper") and os.environ.get("PIPER_MODEL"):
            self.engine = "piper"
        else:
            for name in ("espeak-ng", "espeak", "pico2wave"):
                if shutil.which(name):
                    self.engine = name
                    break

    def path_for(self, text):
        key = hashlib.sha1(f"{self.engine}|{text}".encode()).hexdigest()
        return os.path.join(AUDIO_DIR, key + ".wav")

    def wav(self, text):
        """Path to a cached .wav of `text` (made now if needed), or None."""
        if not self.engine or not text.strip():
            return None
        path = self.path_for(text)
        if os.path.exists(path):
            return path
        with self.lock:  # one synthesis at a time; others wait for the cache
            if os.path.exists(path):
                return path
            tmp = path + ".tmp.wav"
            try:
                if self.engine == "piper":
                    subprocess.run(["piper", "--model", os.environ["PIPER_MODEL"], "--output_file", tmp],
                                   input=text.encode(), check=True, capture_output=True, timeout=300)
                elif self.engine == "pico2wave":
                    subprocess.run(["pico2wave", "-w", tmp, text], check=True, capture_output=True, timeout=300)
                else:
                    subprocess.run([self.engine, "-w", tmp, text], check=True, capture_output=True, timeout=300)
                os.replace(tmp, path)
            except (OSError, subprocess.SubprocessError):
                if os.path.exists(tmp):
                    os.remove(tmp)
                return None
        return path


# --------------------------------------------------------------------------
# HTTP API (+ the laptop's chat page)
# --------------------------------------------------------------------------

def make_handler(store, gen, ollama, cfg, speech, reg=None):
    share_root = fileshare.share_root(cfg)
    reg = reg or registry_mod.Registry()
    class Handler(BaseHTTPRequestHandler):
        server_version = "GemmaBridge/1"

        def log_message(self, fmt, *args):  # quiet
            pass

        def _local(self):
            if os.environ.get("KOS_BRIDGE_TEST_REMOTE"):  # tests only: treat localhost as a phone
                return False
            return self.client_address[0] in ("127.0.0.1", "::1")

        def _allowed(self, scope):
            """The PIN is checked first (_authorized); then the registry decides what this client may do."""
            if self._local():
                return True
            client = self.headers.get("X-Bridge-Client") or ("unnamed@" + self.client_address[0])
            ok, reason = reg.check(client, self.client_address[0], scope)
            if not ok:
                self._json(403, {"error": reason, "client": client})
            return ok

        def _authorized(self):
            if self._local():
                return True
            q = parse_qs(urlparse(self.path).query)
            pin = self.headers.get("X-Bridge-Pin") or (q.get("pin") or [None])[0]
            return pin == cfg["pin"]

        def _json(self, code, obj):
            body = json.dumps(obj, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n) or b"{}")

        def do_GET(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            if u.path == "/":
                body = PAGE.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if not self._authorized():
                return self._json(401, {"error": "wrong or missing PIN"})
            if u.path == "/api/registry":
                if not self._local():
                    return self._json(403, {"error": "the registry can only be read on the laptop"})
                return self._json(200, reg.listing())
            if u.path == "/api/info":
                if not self._allowed("info"): return
                return self._json(200, {"name": socket.gethostname(), "model": ollama.pick_model(),
                                        "speech": speech.engine, "sessions": store.summary()})
            if u.path.startswith("/api/audio/"):
                if not self._allowed("audio"): return
                # /api/audio/<session>/<message id>.wav : the message read aloud (cached)
                bits = u.path[len("/api/audio/"):].split("/")
                text = None
                if len(bits) == 2 and bits[1].endswith(".wav") and bits[0] in store.sessions:
                    with store.lock:
                        for m in store.sessions[bits[0]]["messages"]:
                            if str(m["id"]) == bits[1][:-4] and m["status"] == "done":
                                text = m["text"]
                elif u.path == "/api/audio/say.wav":
                    text = (q.get("text") or [""])[0]
                if text is None:
                    return self._json(404, {"error": "no such finished message"})
                if not speech.engine:
                    return self._json(503, {"error": "no speech engine on the laptop: sudo apt install espeak-ng"})
                path = speech.wav(text)
                if not path:
                    return self._json(500, {"error": "speech failed"})
                with open(path, "rb") as f:
                    body = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "max-age=31536000")
                self.end_headers()
                self.wfile.write(body)
                return
            if u.path == "/api/files":
                if not self._allowed("files.read"): return
                items = fileshare.listing(share_root, (q.get("path") or [""])[0])
                if items is None:
                    return self._json(404, {"error": "no such folder"})
                return self._json(200, {"path": (q.get("path") or [""])[0], "items": items})
            if u.path == "/api/files/get":
                if not self._allowed("files.read"): return
                full = fileshare.safe_path(share_root, (q.get("path") or [""])[0])
                if full is None or not os.path.isfile(full):
                    return self._json(404, {"error": "no such file"})
                size = os.path.getsize(full)
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(size))
                self.end_headers()
                with open(full, "rb") as f:
                    while True:
                        chunk = f.read(65536)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                return
            if u.path == "/api/sessions":
                if not self._allowed("chat"): return
                return self._json(200, store.summary())
            parts = u.path.strip("/").split("/")
            if len(parts) == 4 and parts[:2] == ["api", "sessions"] and parts[3] == "messages":
                if not self._allowed("chat"): return
                since = int((q.get("since") or ["0"])[0])
                wait = float((q.get("wait") or ["0"])[0])
                res = store.changes(parts[2], since, wait)
                return self._json(200, res) if res else self._json(404, {"error": "no such session"})
            self._json(404, {"error": "not found"})

        def do_PUT(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            if not self._authorized():
                return self._json(401, {"error": "wrong or missing PIN"})
            if u.path == "/api/files/put":
                if not self._allowed("files.write"): return
                n = int(self.headers.get("Content-Length") or -1)
                ok, msg = fileshare.save_upload(share_root, (q.get("path") or [""])[0], self.rfile, n)
                return self._json(200 if ok else 400, {"ok": ok, "message": msg})
            self._json(404, {"error": "not found"})

        def do_POST(self):
            u = urlparse(self.path)
            if not self._authorized():
                return self._json(401, {"error": "wrong or missing PIN"})
            try:
                data = self._body()
            except ValueError:
                return self._json(400, {"error": "bad JSON"})
            if u.path == "/api/sessions":
                if not self._allowed("chat"): return
                return self._json(200, store.create(data.get("title") or "Chat"))
            parts = u.path.strip("/").split("/")
            if len(parts) == 4 and parts[:2] == ["api", "sessions"] and parts[3] == "messages":
                if not self._allowed("chat"): return
                sid = parts[2]
                if sid not in store.sessions:
                    return self._json(404, {"error": "no such session"})
                text = (data.get("text") or "").strip()
                if not text:
                    return self._json(400, {"error": "empty message"})
                m, new = store.add_user(sid, text, data.get("from") or ("laptop" if self._local() else "phone"),
                                        data.get("client_id"))
                gen.kick(sid)
                return self._json(200, {"message": m, "duplicate": not new})
            self._json(404, {"error": "not found"})

    return Handler


def discovery(port, stop):
    """Answers "GEMMA-BRIDGE?" broadcasts, so the phone finds the laptop on its own."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("", DISCOVERY_PORT))
    except OSError as e:
        print(f"  (auto-discovery off: {e})")
        return
    s.settimeout(1)
    reply = json.dumps({"port": port, "name": socket.gethostname()}).encode()
    while not stop.is_set():
        try:
            data, addr = s.recvfrom(256)
        except socket.timeout:
            continue
        if data.strip() == DISCOVERY_ASK:
            s.sendto(reply, addr)


def lan_ip():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gemma bridge</title>
<style>
body{margin:0;font:16px/1.45 system-ui,sans-serif;background:#faf8f1;color:#111;display:flex;flex-direction:column;height:100vh}
header{padding:10px 16px;border-bottom:2px solid #111;display:flex;gap:12px;align-items:center}
header b{font-size:18px}#model{color:#555;font-size:14px}
#log{flex:1;overflow:auto;padding:16px;max-width:820px;width:100%;box-sizing:border-box;margin:0 auto}
.m{margin:0 0 14px 0;white-space:pre-wrap}.who{font-size:12px;font-weight:700;text-transform:uppercase;color:#555;letter-spacing:.05em}
.user .txt{background:#fff;border:1.5px solid #111;border-radius:10px;padding:8px 12px;display:inline-block}
.thinking .txt::after{content:" …";color:#777}.error .txt{color:#a00}
form{display:flex;gap:8px;padding:10px 16px;border-top:2px solid #111;max-width:820px;width:100%;box-sizing:border-box;margin:0 auto}
textarea{flex:1;font:inherit;padding:8px;border:1.5px solid #111;border-radius:8px;min-height:44px;resize:vertical}
button{font:inherit;font-weight:700;padding:0 18px;border:2px solid #111;border-radius:8px;background:#111;color:#faf8f1;min-height:44px}
</style></head><body>
<header><b>Gemma bridge</b><span id="model"></span></header>
<main id="log" aria-live="polite"></main>
<form id="f"><label for="t" style="position:absolute;left:-9999px">Message</label>
<textarea id="t" placeholder="Message Gemma (Ctrl+Enter to send)"></textarea><button>Send</button></form>
<script>
const sid="main";let rev=0;const msgs=new Map();const log=document.getElementById("log");
function who(m){return m.role==="assistant"?"Gemma":("You · "+(m.from||""))}
function render(){log.innerHTML="";[...msgs.values()].sort((a,b)=>a.id-b.id).forEach(m=>{
 const d=document.createElement("div");d.className="m "+m.role+" "+m.status;
 const w=document.createElement("div");w.className="who";w.textContent=who(m);
 const t=document.createElement("div");t.className="txt";t.textContent=m.text||"";
 d.append(w,t);log.append(d)});log.scrollTop=log.scrollHeight}
async function poll(){for(;;){try{const r=await fetch(`/api/sessions/${sid}/messages?since=${rev}&wait=25`);
 const j=await r.json();j.messages.forEach(m=>msgs.set(m.id,m));if(j.messages.length)render();rev=j.rev}
 catch(e){await new Promise(r=>setTimeout(r,2000))}}}
document.getElementById("f").onsubmit=async e=>{e.preventDefault();const t=document.getElementById("t");
 const text=t.value.trim();if(!text)return;t.value="";
 await fetch(`/api/sessions/${sid}/messages`,{method:"POST",headers:{"Content-Type":"application/json"},
 body:JSON.stringify({text,from:"laptop",client_id:crypto.randomUUID()})})};
document.getElementById("t").onkeydown=e=>{if(e.key==="Enter"&&(e.ctrlKey||e.metaKey))document.getElementById("f").requestSubmit()};
fetch("/api/info").then(r=>r.json()).then(j=>document.getElementById("model").textContent=(j.model||"no model found")+" on "+j.name);
poll();
</script></body></html>"""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--ollama", default=os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434"))
    ap.add_argument("--model", default=None, help="Ollama model (default: first one with 'gemma' in its name)")
    args = ap.parse_args()
    ollama_url = args.ollama if args.ollama.startswith("http") else "http://" + args.ollama

    cfg = load_config()
    store = Store()
    ollama = Ollama(ollama_url, args.model)
    speech = Speech()
    gen = Generator(store, ollama, speech)
    model = ollama.pick_model()

    server = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(store, gen, ollama, cfg, speech))
    stop = threading.Event()
    threading.Thread(target=discovery, args=(args.port, stop), daemon=True).start()

    ip = lan_ip()
    print("Gemma bridge is running.")
    print(f"  Model:   {model or 'NOT FOUND, is Ollama running? (ollama serve)'}")
    print(f"  Speech:  {speech.engine or 'none (for read-aloud: sudo apt install espeak-ng)'}")
    print(f"  Laptop:  http://localhost:{args.port}")
    print(f"  Phone:   open the Gemma app in KOReader. Address {ip}:{args.port}, PIN {cfg['pin']}")
    print(f"  Shared folder: {fileshare.share_root(cfg)}  (files you send from the phone land here)")
    pend = registry_mod.Registry().pending()
    if pend:
        print("  Waiting for your approval: " + ", ".join(pend) + "   (python3 registry.py approve <id>)")
    print("  Registry and access log: ~/.gemmaBridge/registry.json, access.log. List: python3 registry.py list")
    print("  Stop with Ctrl+C. Conversations are kept in ~/.gemmaBridge/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()


if __name__ == "__main__":
    main()

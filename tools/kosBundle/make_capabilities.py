#!/usr/bin/env python3
"""Builds the capability directory: every module, app, REST route, protocol and library of KOReader OS, with what it
does and what it exposes. Read by people (capabilities.md) and by the embedded model through MCP (capabilities.json,
served by tools/gemmaBridge/mcp_capabilities.py). Run again whenever code changes; it is generated, never edited by hand.
Usage: make_capabilities.py [outdir]   (default doc/)"""
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "doc")

def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8", errors="replace") as f:
        return f.read()

def header(text):
    m = re.match(r"\s*--\[(=*)\[(--)?(.*?)\]\1\]", text, re.S)
    if m: return " ".join(m.group(3).strip().split())[:600]
    lines = []
    for l in text.splitlines():
        if l.startswith("--"): lines.append(l.lstrip("- ").strip())
        elif lines: break
    return " ".join(lines)[:600]

def exports(text):
    return sorted(set(re.findall(r"^function\s+[A-Za-z_][\w]*[.:]([A-Za-z_]\w*)\s*\(", text, re.M)))

modules = []
d = os.path.join(ROOT, "frontend/apps/kos")
for f in sorted(os.listdir(d)):
    if f.endswith(".lua"):
        t = read("frontend/apps/kos/" + f)
        modules.append({"name": "apps/kos/" + f[:-4], "file": "frontend/apps/kos/" + f, "about": header(t), "functions": exports(t)})

bundle = re.search(r"PLUGINS = \[(.*?)\]", read("tools/kosBundle/build_bundle.py"), re.S).group(1)
plugins = []
for n in re.findall(r'"(\w+)"', bundle):
    p = "plugins/%s.koplugin/_meta.lua" % n
    if not os.path.exists(os.path.join(ROOT, p)): continue
    t = read(p)
    full = re.search(r'fullname\s*=\s*_\("([^"]*)"\)', t)
    desc = re.search(r"description\s*=\s*_\(\[=*\[(.*?)\]=*\]\)", t, re.S)
    plugins.append({"id": n, "name": full.group(1) if full else n, "about": " ".join(desc.group(1).split()) if desc else "",
                    "is_app": "app" in t and "app =" in t, "file": "plugins/%s.koplugin/main.lua" % n})

routes = []
for m in re.finditer(r'\{ id = "(b\d+)", method = "(\w+)", path = "([^"]+)", scope = "(\w+)", about = "([^"]+)" \}', read("frontend/apps/kos/restrouter.lua")):
    routes.append({"id": m.group(1), "method": m.group(2), "path": m.group(3), "scope": m.group(4), "about": m.group(5)})

clib = []
h = read("embedded/kosLink/kosLink.h")
for m in re.finditer(r"^(?:uint16_t|void|int|size_t)\s+(kosLink\w+)\(([^)]*)\)", h, re.M):
    clib.append({"name": m.group(1), "args": m.group(2)})

protocols = [
    {"name": "kosLink", "about": "Frame protocol to small devices (ESP32, ATmega): 0x7E, version, type, seq, len, payload, CRC-16/CCITT. Lua: apps/kos/linkproto, C: embedded/kosLink.", "files": ["frontend/apps/kos/linkproto.lua", "embedded/kosLink/kosLink.c"]},
    {"name": "REST router", "about": "GET, PUT, POST, DELETE on paths; scopes read, write, control, admin; routes added at run time wait for approval on the screen.", "files": ["frontend/apps/kos/restrouter.lua"]},
    {"name": "Laptop bridge", "about": "HTTP with X-Bridge-Pin and X-Bridge-Client; registry of clients with scopes info, chat, audio, files.read, files.write.", "files": ["tools/gemmaBridge/gemma_bridge.py", "tools/gemmaBridge/registry.py"]},
    {"name": "Telegram front door", "about": "The device polls a bot; only listed chats are answered; messages become REST calls.", "files": ["frontend/apps/kos/telegrambot.lua"]},
]
policy = {"about": "What the model may do on its own: allow, confirm, deny, from apps/kos/sandboxpolicy.lua", "file": "frontend/apps/kos/sandboxpolicy.lua"}
data = {"version": read("kos/VERSION").strip(), "modules": modules, "plugins": plugins, "routes": routes, "clib": clib, "protocols": protocols, "policy": policy}

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "capabilities.json"), "w", encoding="utf-8") as f: json.dump(data, f, indent=1, ensure_ascii=False)
md = ["# KOReader OS capabilities (generated, do not edit)", "", "Version %s. %d modules, %d plugins, %d routes." % (data["version"], len(modules), len(plugins), len(routes)), "", "## Apps and plugins"]
for p in plugins: md.append("- **%s**%s: %s" % (p["name"], " (app)" if p["is_app"] else "", p["about"]))
md += ["", "## Shared modules"]
for m in modules: md.append("- `%s`: %s%s" % (m["name"], m["about"], ("  \n  functions: " + ", ".join(m["functions"])) if m["functions"] else ""))
md += ["", "## REST routes"] + ["- `%s %s` [%s]: %s" % (r["method"], r["path"], r["scope"], r["about"]) for r in routes]
md += ["", "## Protocols"] + ["- **%s**: %s" % (p["name"], p["about"]) for p in protocols]
md += ["", "## kosLink C library"] + ["- `%s(%s)`" % (c["name"], c["args"]) for c in clib]
with open(os.path.join(OUT, "capabilities.md"), "w", encoding="utf-8") as f: f.write("\n".join(md) + "\n")
print("capabilities: %d modules, %d plugins, %d routes, %d C functions" % (len(modules), len(plugins), len(routes), len(clib)))

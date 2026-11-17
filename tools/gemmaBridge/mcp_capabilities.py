#!/usr/bin/env python3
"""MCP server (stdio, JSON-RPC 2.0, one message per line) that lets the embedded model look up what exists in
KOReader OS instead of guessing. Read-only: it serves capabilities.json and nothing else.

Tools:  listModules, describe(name), search(query), listRoutes, listPlugins
Resources: kos://capabilities (the whole directory as JSON)
Run:  python3 mcp_capabilities.py [path/to/capabilities.json]
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = sys.argv[1] if len(sys.argv) > 1 else next((p for p in (os.path.join(HERE, "capabilities.json"), os.path.join(HERE, "..", "..", "doc", "capabilities.json")) if os.path.exists(p)), "capabilities.json")
DATA = json.load(open(PATH, encoding="utf-8"))

TOOLS = [
    {"name": "listModules", "description": "List every shared module with a one-line description.", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "listPlugins", "description": "List every app and plugin.", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "listRoutes", "description": "List the built-in REST routes with scopes.", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "describe", "description": "Full entry for a module, plugin, protocol or route by name.", "inputSchema": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}},
    {"name": "search", "description": "Find entries whose name or description contains the words.", "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}},
]

def entries():
    for m in DATA["modules"]: yield "module", m["name"], m
    for p in DATA["plugins"]: yield "plugin", p["id"], p
    for p in DATA["plugins"]: yield "plugin", p["name"], p
    for r in DATA["routes"]: yield "route", r["method"] + " " + r["path"], r
    for p in DATA["protocols"]: yield "protocol", p["name"], p
    for c in DATA["clib"]: yield "c function", c["name"], c

def call(name, args):
    if name == "listModules": return "\n".join("%s: %s" % (m["name"], m["about"][:120]) for m in DATA["modules"])
    if name == "listPlugins": return "\n".join("%s (%s): %s" % (p["id"], "app" if p["is_app"] else "plugin", p["about"][:120]) for p in DATA["plugins"])
    if name == "listRoutes": return "\n".join("%s %s [%s] %s" % (r["method"], r["path"], r["scope"], r["about"]) for r in DATA["routes"])
    if name == "describe":
        want = args.get("name", "").lower()
        hits = [e for e in entries() if e[1].lower() == want]
        if not hits: raise ValueError("nothing called " + args.get("name", ""))
        return json.dumps(hits[0][2], indent=1, ensure_ascii=False)
    if name == "search":
        words = args.get("query", "").lower().split()
        out, seen = [], set()
        for kind, n, e in entries():
            text = (n + " " + json.dumps(e, ensure_ascii=False)).lower()
            if words and all(w in text for w in words) and (kind, n) not in seen:
                seen.add((kind, n)); out.append("%s %s" % (kind, n))
        return "\n".join(out[:30]) or "no match"
    raise ValueError("unknown tool " + name)

def handle(msg):
    m, i = msg.get("method"), msg.get("id")
    if m == "initialize":
        return {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}, "resources": {}}, "serverInfo": {"name": "kosCapabilities", "version": DATA["version"]}}
    if m == "tools/list": return {"tools": TOOLS}
    if m == "tools/call":
        p = msg.get("params", {})
        return {"content": [{"type": "text", "text": call(p.get("name"), p.get("arguments") or {})}]}
    if m == "resources/list": return {"resources": [{"uri": "kos://capabilities", "name": "KOReader OS capabilities", "mimeType": "application/json"}]}
    if m == "resources/read":
        return {"contents": [{"uri": "kos://capabilities", "mimeType": "application/json", "text": json.dumps(DATA, ensure_ascii=False)}]}
    if m == "ping": return {}
    raise KeyError(m)

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: msg = json.loads(line)
        except ValueError:
            print(json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}), flush=True); continue
        if "id" not in msg: continue          # notifications get no answer
        try: res = {"jsonrpc": "2.0", "id": msg["id"], "result": handle(msg)}
        except KeyError: res = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": "method not found"}}
        except Exception as e: res = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32000, "message": str(e)}}
        print(json.dumps(res, ensure_ascii=False), flush=True)

if __name__ == "__main__": main()

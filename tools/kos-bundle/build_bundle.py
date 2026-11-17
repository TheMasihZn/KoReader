#!/usr/bin/env python3
"""Builds the one-file KOReader OS installer: koreader/patches/2-0-kos-bundle.lua.

    python3 tools/kos-bundle/build_bundle.py [output.lua]
"""
import hashlib, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "2-0-kos-bundle.lua")

# Add-ons shipped with the bundle (text files only; readingcomfort has fonts, so it stays in the APK).
PLUGINS = ["applauncher", "appinstaller", "studio", "sheets", "latexview", "focus", "gemma", "updates", "icons", "logcat", "preview", "share", "pendulums", "lightlab"]
ICONS = ["kos.audio.svg", "kos.chat.svg"]

files = {}
def add(rel, path):
    with open(path, "rb") as f:
        files[rel] = f.read().decode("utf-8")

kos = os.path.join(ROOT, "frontend/apps/kos")
for name in sorted(os.listdir(kos)):
    if not name.endswith(".lua"):
        continue
    if name == "overrides.lua":
        add("overrides/boot/overrides.lua", os.path.join(kos, name))
    else:
        add("overrides/files/apps/kos/" + name, os.path.join(kos, name))
for plugin in PLUGINS:
    base = os.path.join(ROOT, "plugins", plugin + ".koplugin")
    for dirpath, _, names in os.walk(base):
        for name in sorted(names):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, os.path.join(ROOT, "plugins"))
            add("overrides/plugins/" + rel, full)
# The start-up patch (diagnostics, safe mode, path bar, scaling, split-screen).
add("patches/2-fork-preview.lua", os.path.join(ROOT, "tools/kos-bundle/2-fork-preview.lua"))
for icon in ICONS:
    add("icons/" + icon, os.path.join(ROOT, "resources/icons/mdlight", icon))

def literal(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"

digest = hashlib.sha1()
for rel in sorted(files):
    digest.update(rel.encode()); digest.update(files[rel].encode())
version = digest.hexdigest()[:10]

body = "".join("    [%r] = %s,\n" % (rel, literal(files[rel])) for rel in sorted(files))
with open(os.path.join(ROOT, "tools/kos-bundle/template.lua"), encoding="utf-8") as f:
    template = f.read()
out = template.replace("@@VERSION@@", version).replace("@@FILES@@", body.rstrip("\n"))
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write(out)
print("wrote", OUT, len(out) // 1024, "KB,", len(files), "files, version", version)

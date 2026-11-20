#!/usr/bin/env python3
"""Rebuilds uiLedger.md: every KOReader screen, reader module, widget and app (plugin),
with its status in the new UI. Statuses already written in uiLedger.md are kept; anything
new in the code base is added as "original". Run from the repository root:
    python3 tools/uiLedger.py
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "uiLedger.md")
ROW = re.compile(r"^\| `([^`]+)` \| ([^|]+) \| ([^|]*) \|$")

def inventory():
    groups = []
    fm = os.path.join(ROOT, "frontend/apps/filemanager")
    groups.append(("Screens: file manager (the page under Overview)",
                   sorted("frontend/apps/filemanager/" + f for f in os.listdir(fm) if f.endswith(".lua"))))
    rm = os.path.join(ROOT, "frontend/apps/reader/modules")
    groups.append(("Layers: reader (open book)",
                   ["frontend/apps/reader/readerui.lua"] +
                   sorted("frontend/apps/reader/modules/" + f for f in os.listdir(rm) if f.endswith(".lua"))))
    wd = os.path.join(ROOT, "frontend/ui/widget")
    groups.append(("Widgets: shared building blocks",
                   sorted("frontend/ui/widget/" + f for f in os.listdir(wd) if f.endswith(".lua"))))
    pd = os.path.join(ROOT, "plugins")
    groups.append(("Apps: KOReader plugins built into this APK",
                   sorted("plugins/" + d for d in os.listdir(pd) if d.endswith(".koplugin"))))
    ad = "platform/android/luajit-launcher/app/src/main"
    android = [ad + "/AndroidManifest.xml"]
    for base, _, files in os.walk(os.path.join(ROOT, ad, "java")):
        android += sorted(os.path.relpath(os.path.join(base, f), ROOT) for f in files if f.endswith(".kt"))
    # files the Overview patch adds or changes, even when the patch is not applied on disk
    patch = os.path.join(ROOT, "platform/android/overviewLauncher.patch")
    if os.path.exists(patch):
        for line in open(patch, encoding="utf-8"):
            if line.startswith("+++ b/"):
                path = "platform/android/luajit-launcher/" + line[6:].strip()
                if path.endswith((".kt", ".xml")) and path not in android:
                    android.append(path)
    groups.append(("Android layer (the APK around the Lua shell)", sorted(set(android))))
    return groups

def read_existing():
    known = {}
    if os.path.exists(LEDGER):
        for line in open(LEDGER, encoding="utf-8"):
            m = ROW.match(line.rstrip("\n"))
            if m:
                known[m.group(1)] = (m.group(2).strip(), m.group(3).strip())
    return known

def main():
    known = read_existing()
    out = ["# UI ledger", "",
           "What has and has not been changed in KOReader for the new home-screen UI.",
           "Nothing in KOReader is deleted: every row still exists in the code.", "",
           "Statuses:",
           "- **original**: untouched, works as in KOReader",
           "- **covered**: still there, but Overview is drawn on top of it",
           "- **restyled**: same feature, new look",
           "- **ported**: the feature is reachable from the new UI",
           "- **new**: added for the new UI", "",
           "Regenerate with `python3 tools/uiLedger.py` (keeps the statuses below).", ""]
    counts = {}
    for title, items in inventory():
        out += ["## " + title, "", "| item | status | note |", "|---|---|---|"]
        for item in items:
            status, note = known.get(item, ("original", ""))
            counts[status] = counts.get(status, 0) + 1
            out.append(f"| `{item}` | {status} | {note} |")
        out.append("")
    summary = ", ".join(f"{k}: {v}" for k, v in sorted(counts.items()))
    out.insert(2, f"Totals: {summary}\n")
    open(LEDGER, "w", encoding="utf-8").write("\n".join(out))
    print(summary)

if __name__ == "__main__":
    main()

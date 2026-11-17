#!/usr/bin/env python3
"""Builds a versioned KOReader OS release into dist/.

    python3 tools/kosBundle/make_release.py [--check-tag TAG]

Reads kos/VERSION, kos/CHANGELOG.md and kos/RELEASE_TEMPLATE.md. Writes dist/ (bundle, apps/*.zip,
gemmaBridge.zip, osEmbedding.md, RELEASE.md). With --check-tag, fails unless TAG is `kosV<VERSION>`.
"""
import datetime, hashlib, os, re, shutil, subprocess, sys, zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DIST = os.path.join(ROOT, "dist")

APPS = [  # id, label, needs
    ("applauncher", "Home (app launcher)", "bundle"),
    ("appinstaller", "App installer", "bundle"),
    ("studio", "Studio (code editor, logs)", "bundle"),
    ("sheets", "Sheets", "bundle"),
    ("latexview", "LaTeX view", "bundle"),
    ("focus", "Focus", "bundle"),
    ("gemma", "Gemma (chat with the laptop model)", "laptop bridge"),
    ("share", "Share (files to and from the laptop)", "laptop bridge"),
    ("updates", "Updates", "bundle"),
    ("icons", "Icons (icon editor)", "bundle"),
    ("logcat", "Logcat (colour logs)", "bundle"),
    ("preview", "Preview (thumbnails)", "bundle"),
    ("pendulums", "Pendulums", "bundle"),
    ("lightlab", "Light lab (double slit)", "bundle"),
    ("viewer3d", "3D viewer (STL, design scripts)", "bundle"),
    ("snapshot", "Snapshots (save where a discussion stands)", "bundle"),
    ("versions", "File versions (change log, dotted copies)", "bundle"),
    ("settings", "Settings by Time, Space, Energy", "bundle"),
    ("idehandoff", "Open in IDE (IntelliJ, Android Studio)", "bundle"),
    ("canvas", "Canvas (endless page)", "bundle"),
    ("debugger", "Debugger (session, breakpoints, ADB)", "bundle"),
    ("restbot", "REST and bot (Telegram and HTTP to REST calls)", "bundle"),
    ("entropy", "Entropy (LaTeX applet)", "bundle"),
    ("themes", "Themes (default and per app)", "bundle"),
    ("folderfile", "Folder per file", "bundle"),
    ("terminal", "Terminal emulator with minimize", "bundle"),
]

def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()

def zip_dir(src, dest, prefix):
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, dirs, names in os.walk(src):
            dirs[:] = sorted(d for d in dirs if d != "__pycache__")
            for name in sorted(names):
                full = os.path.join(dirpath, name)
                z.write(full, os.path.join(prefix, os.path.relpath(full, src)))

def changes_for(version):
    m = re.search(r"^## " + re.escape(version) + r"\b.*?\n(.*?)(?=^## |\Z)", read("kos/CHANGELOG.md"), re.S | re.M)
    if not m or not m.group(1).strip():
        sys.exit("kos/CHANGELOG.md has no section for version " + version)
    return m.group(1).strip()

def main():
    version = read("kos/VERSION").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        sys.exit("kos/VERSION must look like 0.1.0, got: " + version)
    if "--check-tag" in sys.argv:
        tag = sys.argv[sys.argv.index("--check-tag") + 1]
        if tag != "kosV" + version:
            sys.exit("tag %s does not match kos/VERSION (expected kosV%s)" % (tag, version))
    changes = changes_for(version)

    os.makedirs(os.path.join(DIST, "apps"), exist_ok=True)
    bundle = os.path.join(DIST, "2-kosBundle.lua")
    subprocess.check_call([sys.executable, os.path.join(ROOT, "tools/kosBundle/build_bundle.py"), bundle])
    for app, _, _ in APPS:
        src = os.path.join(ROOT, "plugins", app + ".koplugin")
        if not os.path.isdir(src):
            sys.exit("missing plugin folder: " + src)
        zip_dir(src, os.path.join(DIST, "apps", app + ".zip"), app + ".koplugin")
    zip_dir(os.path.join(ROOT, "tools/gemmaBridge"), os.path.join(DIST, "gemmaBridge.zip"), "gemmaBridge")
    with open(os.path.join(DIST, "osEmbedding.md"), "w", encoding="utf-8") as f:
        f.write(read("doc/osEmbedding.md"))
    with open(os.path.join(DIST, "osItems.md"), "w", encoding="utf-8") as f:
        f.write(read("doc/osItems.md"))
    shutil.copy(os.path.join(ROOT, "kos/installKos.sh"), os.path.join(DIST, "installKos.sh"))
    os.chmod(os.path.join(DIST, "installKos.sh"), 0o755)

    try:
        commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:
        commit = "unknown"
    subprocess.check_call([sys.executable, os.path.join(ROOT, "tools/kosBundle/make_capabilities.py"), DIST])
    files = ["2-kosBundle.lua", "capabilities.json", "capabilities.md", "gemmaBridge.zip", "installKos.sh", "osEmbedding.md", "osItems.md"] + ["apps/%s.zip" % a for a, _, _ in APPS]
    checksums = "\n".join("`%s`  %s" % (sha(os.path.join(DIST, p))[:16], p) for p in files)
    apps = "\n".join("| %s | %s.zip | %s |" % (label, app, needs) for app, label, needs in APPS)
    notes = read("kos/RELEASE_TEMPLATE.md").format(
        version=version, date=datetime.date.today().isoformat(), changes=changes,
        apps=apps, checksums=checksums, commit=commit)
    with open(os.path.join(DIST, "RELEASE.md"), "w", encoding="utf-8") as f:
        f.write(notes)
    subprocess.check_call([sys.executable, os.path.join(ROOT, "tools/kosBundle/make_report.py"), os.path.join(DIST, "report.html")])
    print("built KOReader OS %s into %s (%d files)" % (version, DIST, len(files) + 1))

main()

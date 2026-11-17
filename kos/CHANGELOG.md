# KOReader OS changelog

One section per version. The release script copies the section matching `kos/VERSION` into the release notes.
Write what changed in plain facts, one line each.

## 0.2.0 (2026-11-17)
- Windows 11 style title bar on every app window: minimize (window stays in the switcher), maximize or
  restore (window shape), close. Panes in the split view keep their own bar. Setting `kos_win11_titlebar` off
  brings the classic bar back.
- Universal search: results follow the text after N characters (default 2, setting), searches Home apps,
  the home folder, Desktop, Downloads, Documents and folders you add. Dispatcher action "Search apps and files".
- 3D viewer: open STL files and Lua design scripts, outline view, turn and zoom, size, volume, surface, weight
  by material, closed-shape and overhang checks, Export STL.
- Snapshots: save where an unfinished discussion stands as one Markdown file; read it back.
- Install script `installKos.sh` for the laptop side.

## 0.1.1 (2026-11-17)
- Icons: new "Suits..." library with the 302 Holy Cart suit symbols (from TheMasihZn/HolyCart). Tap one to open
  it as a drawing you can change and save; hold to read its formula and parameters.
- Icons: shapes can have holes and islands (even-odd rings), kept when saving as SVG and as a drawing.
- Notes: sections 9 to 20 of `doc/osEmbedding.md`, item ledger `doc/osItems.md`.

## 0.1.0 (2026-11-17)
- First versioned release. Contains every app and shared library built so far.
- Home is the landing screen; icons are movable; window shape per app.
- Input layer, Logcat, debugger with crash trail, Share with laptop bridge, Preview thumbnails.
- Pendulums and Light lab (double slit), LaTeX art library, physics library, simulation window.
- Common library for "needs / under development" notices.
- Release packaging and CI (this file, `kos/VERSION`, `.github/workflows/kosRelease.yml`).

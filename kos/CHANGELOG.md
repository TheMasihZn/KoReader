# KOReader OS changelog

One section per version. The release script copies the section matching `kos/VERSION` into the release notes.
Write what changed in plain facts, one line each.

## 0.5.0 (2026-11-17)
- Simulation harness `tools/kosSim/sim.lua`: every bundled plugin loads and opens headless; a missing `require` is an error.
- REST router: Telegram bot (the phone polls, only listed chats), HTTP on 127.0.0.1, routes added on the fly, approval only on the screen, list in Studio.
- Virtual adapters: chains of perturbations ending in a real device over kosLink, held until armed. kosLink in Lua and C (ESP32, ATmega), tested against each other.
- Sandbox policy for the embedded model: allow, confirm, deny; hardware, network, packages and deleting ask first.
- Capability directory (generated) and an MCP server so the model can look things up. Release carries capabilities.json and .md.
- Entropy applet (LaTeX, Shannon stand-in), folder per file with a text note, John Doe starter app, themes (default plus per-app).
- Gestures you assigned now work inside full-screen menus such as Collections (setting kos_menu_gestures).
- Terminal: minimize button (the shell keeps running) and an app entry on Home.
- Hold a setting: a big touch menu. Keyboard: model for finger travel and a next-key button on the toolbar.
- Change journal and restore points (`tools/kosBundle/journal.sh`).

## 0.4.0 (2026-11-17)
- Debug session: breakpoints with conditions, snapshots of the variables, post-mortem on errors, most-called
  functions, timing spans, a log file. Debugger app with report, breakpoints and ADB devices.
- ADB wrapper: devices, connect, shell, logcat, install, push, pull (needs an `adb` program).
- HTML report of the whole ledger, for people in a browser and for LLMs (`report.html` in the release).

## 0.3.0 (2026-11-17)
- Home is now a chat of plain lines (name and one line of what it does) with an input line at the bottom; the icon
  grid is kept under Home view. Typing on a connected keyboard opens the input line.
- Input pipelines: first word picks one (`open gemma`, `bot hello`), otherwise it is a search. Telegram step needs
  settings `kos_telegram_token` and `kos_telegram_chat`.
- Settings app: Time, Space, Energy, entries ordered by entropy, search by any name, classic menu at the bottom.
- Canvas app: endless page, drag to pan, hold to put a note or an app anywhere.
- Open in IDE in the file menu (Android intent, package set by you).
- File versions app: dotted copies and a change log per file.
- Bridge registry: every client gets an id; new ones wait until approved (`python3 registry.py approve <id>`).

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

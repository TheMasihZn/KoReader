# KOReader OS changelog

One section per version. The release script copies the section matching `kos/VERSION` into the release notes.
Write what changed in plain facts, one line each.

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

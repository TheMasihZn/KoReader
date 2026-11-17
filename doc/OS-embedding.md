# KOReader OS: structures to carry into the OS (Hearth)

This is the running list of what exists in the KOReader shell, what each piece does, and what the
operating system needs to provide natively so the same pieces can sit on it. Update it whenever
a structure or common library is added. Source: `frontend/apps/kos/`, `plugins/`, `tools/`.

## 1. Common libraries (Lua layer, `frontend/apps/kos/`)

| Module | What it gives apps | Native support the OS needs |
| --- | --- | --- |
| `appregistry` | Home app list. An app is `app = { title, icon, order, needs, status, launch, event, action }` in a plugin's `_meta.lua`. User order (`kos_home_order`), sort modes (custom, A–Z, built-in). | A manifest format for apps and an app list service. |
| `appwindow` | Full-screen app frame: title bar, Home/Close, resize handling, `build(window, w, h)`. Closing the last app lands on Home. | Window manager API with resize events and a "no apps open" state. |
| `workspace`, `windows` | Tiling split view, several windows per app, switcher. | Tiling and window-list service. |
| `displayprofiles`, `scaling` | dp/sp sizes, DPI remembered per screen (fold/unfold). | Per-display density and a size unit that does not depend on pixels. |
| `flatstyle` | One look: line strength, corner radius, tonal depth. Settings `kos_flat_*`. | Theme service (colour roles, line, radius) that every toolkit reads. |
| `gestureforward` | The user's gestures keep working inside apps. | Global gesture layer above apps. |
| `overrides` | Replace built-in app modules by files; safety net after 3 failed starts. | Per-file override layer with rollback. |
| `filehandlers` | Which app opens which file type; "Open with…". | MIME/extension handler registry. |
| `keyboardtoolbar` | Row above every keyboard: Paste, read-aloud, repeat. | Input-method extension point. |
| `audiopipeline` | `play{url,title,source}`, repeat last, recent clips. | Audio routing service (Bluetooth, per-app). |
| `home` | `Home.get()` home folder on any build. | Home-folder lookup with a fallback chain. |
| `inputlayer` | One door to act like a user: `tap`, `hold`, `swipe`, `type`, `key(name)`, `keyNames()`, `listen(fn)`. Draws a ring on the overlay and logs each action to `kos-trace.log`. `enabled=false` blocks all. | Input injection service with a visible overlay and a trace; the local model uses it. Android system buttons need an accessibility service or ADB. |
| `debugger` | Start-up trail (`kos-debug.log`), crash detection with "switch app off", layout bounds overlay. | Per-app crash note and a debug overlay in the compositor. |
| `common` | `needs` and "under development" notices. **Rule: nothing is added without the owner's say-so.** | Shared app-requirements check (device, driver, network). |
| `latexart` | Scenes (line, circle, rect, dot, path, text) as LaTeX art: `tikz(scene)` real TikZ source, `paint(scene, bb, …)` pixels, `unicode(tex)` formula as text. | A vector scene format and a renderer for a virtual display. |
| `simwindow` | Simulation window: LaTeX-art picture, the formulas of this frame, Play/Step/Reset/Parameters/LaTeX source (saves the frame as .tex). A frame = one step. | Frame loop with a per-frame record. |
| `physlab` | `pendulum` (N pendulums, exact equations, RK4, energy check, per-frame formulas) and `slits` (one or two slits, photons landing by chance, histogram entropy, per-frame formulas). | A simulation step API: state, step, per-frame record. |
| `thumbs` | On-demand thumbnails in one cache (`cache/kos-thumbs`, cap `kos_thumb_cache_mb`, oldest first). | Shared thumbnail service with a size cap shown honestly. |

## 2. Apps (Home)

Continue, Files, History, Favorites, Collections, Search, Dictionary, Wikipedia, Audio, Windows,
Settings (built in) · Gemma, Share, Updates, Icons, Logcat, Studio, Sheets, LaTeX view, Focus,
Preview, Pendulums, Light lab (plugins).

## 3. Files and settings the shell writes

| Path (under the KOReader data folder) | Purpose |
| --- | --- |
| `patches/2-0-kos-bundle.lua` | The one-file installer. |
| `fork-preview.log` | Start-up and resize log of the patch. |
| `kos-trace.log` | Every action from `inputlayer`. |
| `kos-debug.log` | App start trail and crashes. |
| `cache/kos-thumbs/` | Thumbnail cache. |
| `icons/`, `icons-src/` | User icons and their drawings. |
| `overrides/` | Replacement files for built-in apps. |
| `settings/kos_gemma.lua` | Laptop address and PIN. |
| `<home>/KOS-Share/` | Files fetched from the laptop. |

Settings keys: `kos_flat_design`, `kos_flat_lines`, `kos_flat_radius`, `kos_home_order`, `kos_home_sort`,
`kos_home_cols`, `kos_home_icon`, `kos_home_landing`, `applauncher_at_startup`, `kos_keyboard_toolbar`,
`kos_layout_bounds`, `kos_disabled_apps`, `kos_thumb_cache_mb`, `android_ignore_volume_keys`.

## 4. Network contract (laptop bridge, `tools/gemma-bridge/`)

Port 8765 (HTTP), UDP 47801 discovery ("GEMMA-BRIDGE?"), header `X-Bridge-Pin`. Chat: `/api/sessions`,
`/api/sessions/<id>/messages?since=&wait=`, audio `/api/audio/<sid>/<id>.wav`. Files: `/api/files?path=`,
`/api/files/get?path=`, `PUT /api/files/put?path=` under `~/KOS-Share`. Paths that leave the folder are refused.

## 5. Not built yet (parked)

Home canvas replacing Recents · bottom reading menu redesign · dotted file versions with change log ·
per-space GitHub backup · webcam/audio-video pipeline across devices · system keyboard (needs a fork of
android-luajit-launcher) · local model wired to `inputlayer` · file hand-off to IntelliJ / Android Studio
(Android intent, user-chosen IDE) · 3D animation of the layered Lua idea.

## 6. OS layer, not Lua (asked for, to be designed in the OS chat)

**Software GPU driver.** One driver that looks like a real GPU to everything above it, same calls, same
ports, same rules, only slower because the work runs on the CPU (and "neural" units: the same idea for
an NPU). This sits below KOReader, in the kernel and graphics stack, so the shell only needs to *use* it.
Existing parts to build on instead of starting from zero:

| API the apps call | CPU implementation that already exists |
| --- | --- |
| OpenGL, OpenGL ES | Mesa llvmpipe |
| Vulkan | Mesa lavapipe, SwiftShader |
| OpenCL (compute) | pocl |
| Neural networks (NPU/NNAPI) | ONNX Runtime or XNNPACK on CPU |
| Kernel side (a device node that looks like a GPU) | a DRM/KMS virtual device (vkms or virtio-gpu style) |

What the shell needs from the OS: a way to ask "which GPUs are there" that also lists this one, and the
same device node and socket names as a real GPU. Open choice for the OS chat: build on Mesa and SwiftShader
(fast to get working) or write a new driver (full control, much more work).

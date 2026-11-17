# KOReader OS: structures to carry into the OS (Hearth)

This is the running list of what exists in the KOReader shell, what each piece does, and what the
operating system needs to provide natively so the same pieces can sit on it. Update it whenever
a structure or common library is added. Source: `frontend/apps/kos/`, `plugins/`, `tools/`.

## 1. Common libraries (Lua layer, `frontend/apps/kos/`)

| Module | What it gives apps | Native support the OS needs |
| --- | --- | --- |
| `appregistry` | Home app list. An app is `app = { title, icon, order, needs, status, launch, event, action }` in a plugin's `_meta.lua`. User order (`kos_home_order`), sort modes (custom, A–Z, built-in). | A manifest format for apps and an app list service. |
| `appwindow` | Full-screen app frame: title bar, Home/Close, resize handling, `build(window, w, h)`. Closing the last app lands on Home. Any aspect ratio per app (`kos_ratio_<app>`, `setRatio`). | Window manager API with resize events and a "no apps open" state. |
| `workspace`, `windows` | Tiling split view, several windows per app, switcher. | Tiling and window-list service. |
| `displayprofiles`, `scaling` | dp/sp sizes, DPI remembered per screen (fold/unfold). | Per-display density and a size unit that does not depend on pixels. |
| `flatstyle` | One look: line strength, corner radius, tonal depth. Settings `kos_flat_*`. | Theme service (colour roles, line, radius) that every toolkit reads. |
| `gestureforward` | The user's gestures keep working inside apps. | Global gesture layer above apps. |
| `overrides` | Replace built-in app modules by files; safety net after 3 failed starts. | Per-file override layer with rollback. |
| `filehandlers` | Which app opens which file type; "Open with…". | MIME/extension handler registry. |
| `keyboardtoolbar` | Row above every keyboard: Paste, read-aloud, repeat. | Input-method extension point. |
| `audiopipeline` | `play{url,title,source}`, repeat last, recent clips. | Audio routing service (Bluetooth, per-app). |
| `home` | `Home.get()` home folder on any build. | Home-folder lookup with a fallback chain. |
| `inputlayer` | One door to act like a user: `tap`, `hold`, `swipe`, `type`, `key(name)`, `keyNames()`, `listen(fn)`. Draws a ring on the overlay and logs each action to `kosTrace.log`. `enabled=false` blocks all. | Input injection service with a visible overlay and a trace; the local model uses it. Android system buttons need an accessibility service or ADB. |
| `debugger` | Start-up trail (`kosDebug.log`), crash detection with "switch app off", layout bounds overlay. | Per-app crash note and a debug overlay in the compositor. |
| `common` | `needs` and "under development" notices. **Rule: nothing is added without the owner's say-so.** | Shared app-requirements check (device, driver, network). |
| `latexart` | Scenes (line, circle, rect, dot, path, text) as LaTeX art: `tikz(scene)` real TikZ source, `paint(scene, bb, …)` pixels, `unicode(tex)` formula as text. | A vector scene format and a renderer for a virtual display. |
| `simwindow` | Simulation window: LaTeX-art picture, the formulas of this frame, Play/Step/Reset/Parameters/LaTeX source (saves the frame as .tex). A frame = one step. | Frame loop with a per-frame record. |
| `physlab` | `pendulum` (N pendulums, exact equations, RK4, energy check, per-frame formulas) and `slits` (one or two slits, photons landing by chance, histogram entropy, per-frame formulas). | A simulation step API: state, step, per-frame record. |
| `thumbs` | On-demand thumbnails in one cache (`cache/kosThumbs`, cap `kos_thumb_cache_mb`, oldest first). | Shared thumbnail service with a size cap shown honestly. |

## 2. Apps (Home)

Continue, Files, History, Favorites, Collections, Search, Dictionary, Wikipedia, Audio, Windows,
Settings (built in) · Gemma, Share, Updates, Icons, Logcat, Studio, Sheets, LaTeX view, Focus,
Preview, Pendulums, Light lab (plugins).

## 3. Files and settings the shell writes

| Path (under the KOReader data folder) | Purpose |
| --- | --- |
| `patches/2-kosBundle.lua` | The one-file installer. |
| `forkPreview.log` | Start-up and resize log of the patch. |
| `kosTrace.log` | Every action from `inputlayer`. |
| `kosDebug.log` | App start trail and crashes. |
| `cache/kosThumbs/` | Thumbnail cache. |
| `icons/`, `icons-src/` | User icons and their drawings. |
| `overrides/` | Replacement files for built-in apps. |
| `settings/kos_gemma.lua` | Laptop address and PIN. |
| `<home>/kosShare/` | Files fetched from the laptop. |

Settings keys: `kos_flat_design`, `kos_flat_lines`, `kos_flat_radius`, `kos_home_order`, `kos_home_sort`,
`kos_home_cols`, `kos_home_icon`, `kos_home_landing`, `applauncher_at_startup`, `kos_keyboard_toolbar`,
`kos_layout_bounds`, `kos_disabled_apps`, `kos_thumb_cache_mb`, `android_ignore_volume_keys`.

## 4. Network contract (laptop bridge, `tools/gemmaBridge/`)

Port 8765 (HTTP), UDP 47801 discovery ("GEMMA-BRIDGE?"), header `X-Bridge-Pin`. Chat: `/api/sessions`,
`/api/sessions/<id>/messages?since=&wait=`, audio `/api/audio/<sid>/<id>.wav`. Files: `/api/files?path=`,
`/api/files/get?path=`, `PUT /api/files/put?path=` under `~/kosShare`. Paths that leave the folder are refused.

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

## 7. Emulation drivers for any device (OS layer)

Goal: any device a program can ask for can be provided by software, so an app or another machine
cannot tell the difference except by speed. The GPU driver in section 6 is the first case of this.

**Accommodations the OS needs (design these first, once, for every device class):**

1. **Device registry.** One list of every device, real or emulated: class, name, capabilities, who provides it
   (hardware, software, another device in the space, a recording). The shell's Devices view and the `common`
   library's `needs` check read this list.
2. **Same face.** An emulated device uses the same device node, socket or port names, the same calls and the
   same error behaviour as a real one. Only speed (and, honestly reported, limits) may differ.
3. **Backends per device.** Each class can be backed by: software compute, another device in the space (the
   phone camera acting as a laptop webcam), a file or recording, or a generator. The user chooses.
4. **Capability descriptor.** Every device says what it really supports (formats, rates, sizes), so programs
   adapt instead of failing.
5. **Trace.** Every emulated device logs its calls in the same trace format as `inputlayer` (`kosTrace.log`
   style), so what an emulated device did is always visible.
6. **Honesty switch.** A setting for how an emulated device reports itself: as the real model it imitates, or
   as "software". Default: say what it is.

**Building blocks that already exist (use before writing new drivers):**

| Device class | Software or virtual way to provide it |
| --- | --- |
| GPU, display | Mesa llvmpipe, lavapipe, SwiftShader; vkms or virtio-gpu for the kernel side |
| NPU, neural | ONNX Runtime, XNNPACK on CPU |
| Camera | v4l2loopback (a virtual webcam fed by any source) |
| Microphone, speaker | snd-aloop, PipeWire or PulseAudio virtual devices |
| Keyboard, mouse, touch | uinput (also what the local model uses through `inputlayer`) |
| Storage | loop devices, null_blk, FUSE file systems |
| Network | tun/tap, veth, network namespaces |
| Bluetooth | vhci (virtual controller) |
| Sensors (accelerometer, light, …) | IIO dummy devices or a sensor shim fed by a generator |
| Location | a mock location source |
| Serial, USB | usbip, gadget framework, pty pairs |

Open choice for the OS chat: a single "virtual device" daemon that owns the registry and loads one plugin
per class, or one small driver per class that registers itself. The first is easier to keep consistent.

## 8. Pre-AI text corpus (declared, not built)

Goal from the user: a body of human writing from before AI-generated text and boilerplate existed, to use for
the consciousness work (a model trained on inputs the user picked, with a continuous training phase on top).

- Sources named: Internet Archive scans of books and newspapers, Project Gutenberg, Common Crawl snapshots from
  before 2022, dated Wikipedia dumps.
- Rule: a fixed cutoff date per source; old dumps stay old, so nothing newer enters.
- Why own corpus: an existing model cannot be split back into its training pages; only the inputs can be chosen.
- Not decided: which archives are still available, their sizes, and the model to train. Next step is a search for
  these, then a size and licence list.

## 9. Runner and bridge contract (declared, not built; replaces the Termux and Kotlin-engine ideas)

Termux is out of the project. Command-line apps run in the shell's own windowed terminal (Windows Terminal style),
an app window like any other.

- One contract. Lua apps call one API: run a command, open a file, read a sensor, use a device. They never know
  what is behind it. The contract is socket based, so any language can sit behind it.
- Providers by platform. Android: a Kotlin companion app with full Java access (also where an IDE hand-off to
  IntelliJ or Android Studio goes, through an intent). Linux PC: a small native service, or a JVM if installed.
  Kindle and other small Linux devices: a native provider, Java absent.
- Honest limits. A device reports what its provider supports (the capability list from section 7). An app that
  needs Java shows "needs Java" through the common library `common.lua` instead of failing.
- Every call is logged in the `inputlayer` trace format (`kosTrace.log`).
- Today: Lua starts programs with `io.popen`; Studio shows the output. That stays until a provider exists.

## 10. Stack order (declared, not built)

Opposite of today's Android: not Android, then Java, then an APK with a Lua engine inside it.
The target is the Lua engine directly on the OS, with the shell and our apps on top of it.

- Base: the lightest possible Android base (AOSP) or Linux, running only the processes the user wants.
- Lua is the interface and lifecycle interpreter, where Kotlin or Java would be on stock Android.
- Java is on demand: either embedded with our apps, or one shared Java runtime started when the Lua menu or Home
  screen opens an Android app. Apps that do not need Java never start it.
- Targets: every device the OS is installed on. The Kindle stays KOReader on its own Linux (no AOSP, no Java).
- Open: the AOSP route for PC hardware (Android-x86 style builds, a virtual machine, or an own x86 build) and
  whether it replaces Windows or runs next to it. Not decided.

## 11. Window style and the endless page (declared; title buttons next)

- Every window, in the launcher and on any base, gets a Windows 11 style title bar: minimize, maximize, close.
  Needs a custom title bar, because the KOReader title bar has one right-hand button. Minimize needs a place
  for the window to go (the endless page or the window switcher). Maximize and restore toggles the window
  shape from section 5.
- One endless page across the whole world: apps are arranged left and right, up and down, and a five-finger pull
  outward moves along a depth axis (layers of apps in front of and behind each other). Build the flat page
  first (the Home canvas), depth after. The five-finger gesture may be taken by Android or Samsung before the
  app sees it: test it on the Galaxy Z Fold 5 first.

## 12. Look: e-ink friendly, One UI style (declared)

- Same ideas as One UI (animation, shadow, depth, flatness), made friendly to e-paper: few redraws, no
  animation on e-ink, shadows drawn as lines.
- Default today: 100% black and white, with everything maximized. The user can change it.
- Colour version with accessible colours, maximized for the viewport of each screen: the OS reads the display's
  size, colour support and refresh behaviour and fits itself to it. Settings stay adjustable by the user.

## 13. Apps page and app transparency (declared)

- The only page built into the OS repository is `apps`. Only processes the user chose run.
- Rule: when the user names an application, the OS provides the application itself if they ask for it, or the
  recompiled free alternative.
- Transparency settings, per application (including every app written here): meaning not fixed yet. See the
  open question below.

Open question for the user: what "transparency settings" means. Window see-through level, or a per-app page
that shows what the app is, where it came from, what it runs and what it can access.

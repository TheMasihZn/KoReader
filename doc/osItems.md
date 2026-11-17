# Items for the OS, with where each came from

Tag: **you** = the user asked for it. **me** = I added it. **?** = I am not sure what is meant; question below.
Status: built, declared (written in `osEmbedding.md`, not built), or open.

| # | Item | From | Status |
| --- | --- | --- | --- |
| 1 | Fix home folder crashes | you | built |
| 2 | Debounced window resize (notification panel crash) | me | built, unconfirmed on device |
| 3 | Logcat app | you | built |
| 4 | Input layer: tap, hold, swipe, type, key, listen | you | built |
| 5 | Overlay ring and trace log for the input layer | me | built |
| 6 | Volume keys go to Android by default | you | built |
| 7 | Thumbnails and Preview | you | built |
| 8 | Thumbnail cache cap (100 MB default) | me | built |
| 9 | Share app and laptop shared folder | you | built |
| 10 | PIN on the laptop bridge | me | built |
| 11 | Home as landing screen | you | built |
| 12 | Menu look settings (lines, corners) | you | built |
| 13 | App debugger with crash trail | you | built |
| 14 | Layout bounds overlay | you | built |
| 15 | Switch off an app after repeated crashes | me | built |
| 16 | Movable Home icons, One UI style order | you | built |
| 17 | Home layout settings | you | built |
| 18 | Common "needs / under development" notice | you | built |
| 19 | Nothing enters the common library without your say | you | rule |
| 20 | LaTeX art library | you | built |
| 21 | Physics library | you | built |
| 22 | Simulation window | you | built |
| 23 | Pendulums app (2, 3, n) | you | built |
| 24 | Light lab: single and double slit | you | built |
| 25 | Shannon entropy per frame in Light lab | me | built |
| 26 | Aspect ratio per app window | you | built |
| 27 | Generated files flagged in git | you | built |
| 28 | Release package | you | built |
| 29 | Versioned releases and CI | you | built, not pushed |
| 30 | camelCase names, no hyphens | you | built |
| 31 | 3D animation of the layered Lua idea | you | open, meaning unclear |
| 32 | Hand files to IntelliJ or Android Studio | you | declared |
| 33 | Bottom reading menu redesign | you | open |
| 34 | Home canvas replaces Recents | you | open |
| 35 | Drag and drop for Home icons | you | open |
| 36 | Telegram-style Claude app | you | open, needs API key or laptop choice |
| 37 | Dotted file versions | you | declared in memory |
| 38 | GitHub backup per space | you | open |
| 39 | Webcam and audio-video pipeline | you | open |
| 40 | System keyboard | you | open, needs fork of the launcher |
| 41 | Local model through the input layer | you | open |
| 42 | Developer suite like IntelliJ's welcome screen | you | open |
| 43 | Software GPU that fools every program | you | declared |
| 44 | Mesa llvmpipe, lavapipe, SwiftShader as the means | me | declared |
| 45 | Emulate any device | you | declared |
| 46 | One virtual-device daemon or one driver per class | me | question for OS chat |
| 47 | Pre-AI text corpus | you | declared |
| 48 | Runner contract with providers per platform | me | declared |
| 49 | Remove Termux | you | declared |
| 50 | Windowed terminal | you | declared |
| 51 | Windows 11 title buttons | you | built (0.2.0), not tested on device |
| 52 | Endless page, left, right, up, down | you | declared |
| 53 | Five-finger pull for depth | you | declared, may be blocked by Android |
| 54 | Lua engine on the lightest AOSP kernel | you | declared |
| 55 | Java on demand, embedded or shared | you | declared |
| 56 | E-ink friendly One UI look, black and white default | you | declared |
| 57 | Accessible colour version fitted to each display | you | declared |
| 58 | Only an `apps` page in the repository | you | declared |
| 59 | A named app comes as itself or a recompiled free alternative | you | declared |
| 60 | Transparency settings per app | ? | question 1 |
| 61 | Remove temporal, spatial, energetical boilerplate | you | declared |
| 62 | Settings grouped by time, space, energy; classic out of sight | you | declared |
| 63 | Settings tree derived from entropy | you | declared |
| 64 | Simulation to feed cases into the tree | you | declared |
| 65 | Snapshot file for unfinished discussions | you | built (0.2.0): Snapshots app |
| 66 | Name the formula in every section that uses one | you | declared |
| 67 | Home as a chat of plain message lines | you | declared |
| 68 | One input box always connected to every keyboard | you | declared |
| 69 | Pipelines of AI or plain programs | you | declared |
| 70 | Bots, Telegram first | you | declared |
| 71 | WhatsApp automation held back (ban risk) | me | declared |
| 72 | Universal search, triggered by character count | you | built (0.2.0), not tested on device |
| 73 | Search places: fixed system ones plus the user's | you | built (0.2.0) |
| 74 | One root: your space, with Desktop, Downloads, Documents, cache | you | declared |
| 75 | Keep the icon grid as an option | ? | question 2 |
| 76 | Values reference and decision trace | me | offered, waiting for your answer |
| 77 | Crash reports: "KOReader exited", top menu will not open | you | open, needs `forkPreview.log` |
| 78 | HTTP inspector exits the app | you | open, probably native crash |
| 79 | Publish to GitHub | you | blocked, needs a valid token |
| 80 | Design 3D printable objects by voice through the assistant | you | partly built: design scripts in Lua, assistant writes them; voice cannot run them yet |
| 81 | 3D viewer: rotate, section, measure, outline mode for e-paper | me | built (0.2.0): outlines, turn, zoom |
| 82 | Calculations on another device of the OS, or on this one if fast enough | you | partly built: on this device only; sending jobs to other devices needs section 9 |
| 83 | Slicing and sending to a printer | me | declared |
| 84 | Merge HolyCart suit icons into the Icons app | you | built, not tested on device |
| 85 | Voice sessions run tasks, change hardware, run simulations; spoken confirmation for hardware | you | declared |
| 86 | Holes and islands in icon shapes (even-odd rings) | me | built |
| 87 | Mesh checks for printing: volume, weight by material, closed shape, overhang | me | built (0.2.0) |
| 88 | Installer script for the laptop side | you | built (0.2.0) |
| 89 | Git branch per feature: kosTitleBar, kosSearch, kosViewer3d, kosSnapshot | you | done |

## Still not built, and why
- Needs your decision: chat-style Home and the always-on input box (grid kept as option?), settings groups
  (where volume and contrast go), transparency settings (meaning), the 3D animation (what to show).
- Needs a device or an account: IDE hand-off (Android intent), Telegram bot (token), Claude app (API key),
  system keyboard (fork of the launcher), GitHub push (token), five-finger depth gesture (test on the Fold).
- Needs the OS layer, not this shell: AOSP base, Java on demand, software GPU, emulated devices, Kotlin
  provider, voice sessions with tools.
- Large and not started: endless page with depth, Home canvas, dotted file versions, per-space backup,
  webcam and audio-video pipeline, pre-AI corpus, developer suite.

## Questions
1. Transparency settings: window see-through level, or a page per app showing what it is, where it came from,
   what it runs and what it can access?
2. Does the icon grid stay as an option next to the chat-style Home?
3. In your example Documents sat inside Downloads. Intended nesting?
4. Where do volume, brightness and contrast go in the new settings groups?

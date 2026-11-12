# Writing apps for KOReader OS

In this fork, **an app is a normal KOReader plugin** with two additions. Everything you know about writing plugins still applies: `main.lua`, `_meta.lua`, `self.ui`, events, the Dispatcher, settings.

The home screen (`plugins/applauncher.koplugin`) shows the built-in apps and every plugin that declares itself an app.

## Quick start

1. Copy `doc/apps/hello.koplugin` into `koreader/plugins/` on your device.
2. Rename the folder (for example `notes.koplugin`) and set `name = "notes"` in `main.lua` to match.
3. Restart KOReader and open the home screen: the Tools menu → **Home screen**, or assign the **Home screen** action to a gesture.

## The two additions

### 1. An `app` table

Put it in `_meta.lua` (or as a field on your plugin class in `main.lua`):

```lua
app = {
    title = _("Notes"),        -- optional, defaults to fullname from _meta.lua
    icon = "edit",             -- a KOReader icon name (resources/icons/mdlight/), or a file in your folder: "icon.svg"
    description = _("…"),      -- optional, shown on long-press; defaults to description from _meta.lua
    order = 50,                -- optional, lower comes first (built-ins use 1–20)
}
```

### 2. A way to start it

The first one that exists is used:

| You write | When to use it |
|---|---|
| `function MyApp:launchApp() … end` | New apps. Usually opens an `AppWindow`. |
| `app.event = "ShowMyThing"` | Turning an existing plugin into an app: the event its menu entry already sends. |
| `app.action = "my_action"` | The plugin already registers a Dispatcher action. |

If launching throws an error, the home screen shows it in a message instead of crashing.

## AppWindow

`require("apps/kos/appwindow")` (inside `launchApp`, not at the top of `main.lua`) gives you a full-screen window with a title bar, a **Home** button (back to the home screen) and a **Close** button. The Back key closes it.

```lua
local window = AppWindow:open{
    title = _("Notes"),
    subtitle = nil,                 -- optional second line
    build = function(window, width, height)
        return MyContentWidget       -- lay out for exactly width × height
    end,
    on_close = function(window) end, -- optional
    confirm_close = function(window, do_close) end, -- optional: ask "Save changes?", then call do_close()
}
window:refresh()                    -- rebuild after your state changed
window:setTitle(title, subtitle)    -- update the title bar only
window:close()
```

**Resizing is handled for you.** `build` is called again whenever the screen changes: rotation, split-screen, a freeform window being resized, or the Fold opening or closing. Don't store sizes from `Screen:getWidth()` at startup. Always use the `width` and `height` you're given.

## Where an app shows up

Plugins are created separately for the file browser and for the reader. An app appears wherever its plugin is loaded:

- **Everywhere**: the default.
- **Only while a book is open**: set `is_doc_only = true` on the plugin, as for any plugin. Then `self.ui.document` is the open book.

## Built-in apps

These are listed in `frontend/apps/kos/appregistry.lua` (`AppRegistry.builtins`) and run Dispatcher actions: Continue, Files, History, Favorites, Collections, Search, Dictionary, Wikipedia, Settings. Add or remove entries there.

## Turning an existing plugin into an app

Most plugins already open a screen from a menu entry that sends an event. Add to its `_meta.lua`:

```lua
app = { icon = "appbar.tools", event = "ShowTheEventItAlreadyUses" },
```

## Settings

Use your own file so the app can be removed cleanly:

```lua
self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/notes.lua")
```

Also set `self.settings_file` to that path, so KOReader's plugin manager can delete your settings when asked.

## Sharing an app

Zip your plugin folder (the `.zip` must contain `yourapp.koplugin/main.lua`). Anyone with this fork can tap the zip in Files to install it with the **App installer**. A GitHub "Download ZIP" of a repo that contains a `.koplugin` folder works as-is.

The installer only extracts files. It never runs code from the zip, and an existing version is only replaced once the new one has extracted correctly. The app starts after KOReader restarts.

## Split view (several windows)

Every app that opens an `AppWindow` can also run in a window next to other apps. You don't change anything: in split view, `AppWindow:open` returns a pane with the same methods (`refresh`, `setTitle`, `close`), and `build` gets the pane's size.

- **Open beside or below:** long-press an app on the Home screen, or use a window's menu (top left).
- **Fills the screen:** each new window splits the largest one along its longer side. **Tidy** (window menu) lays all windows out as an even grid.
- **Rearrange:** drag a window by its title bar onto another window. Drop on an edge to put it on that side, or in the middle to swap the two.
- **Resize:** drag the divider between two windows. Tap it to cycle 1/3 · 1/2 · 2/3, or long-press it for equal sizes, swap or stack.
- **Any number of windows:** windows sit in a layout tree (`frontend/apps/kos/workspace.lua`), so splits can nest: side by side inside stacked, and so on. `Workspace:addPane(params, { next_to = pane, dir = "row" | "column" })` is the API.

Apps that open their own full-screen KOReader screens (History, the Text editor and so on) still open full screen.

## Opening files ("Open with")

An app can claim file types. Those files then show up in Files, tapping one opens your app, and their long-press menu gets **Open with…**. Register from `init()`:

```lua
function MyApp:init()
    local FileHandlers = require("apps/kos/filehandlers")
    FileHandlers:register{
        id = "myapp",
        title = _("My app"),
        extensions = { "md", "markdown" },
        open = function(file) self:openFile(file) end,
    }
end
```

If several apps claim a type, or KOReader can also open it as a book, you're asked which one to use.

## Office apps

- **Sheets:** `.csv`, `.tsv` and `.xlsx`. A paged grid for e-ink (buttons or swipes move a whole screen). Tap a cell to see it, tap again or long-press to edit. Formulas: `=SUM(A1:A9)`, `=A1*B2`, `AVERAGE`, `MIN`, `MAX`, `COUNT`, `ABS`, `ROUND`. `.xlsx` is read-only: **Save sheet as CSV** to edit it. Asks before closing with unsaved changes.
- **LaTeX view:** `.tex` files as formatted pages: title, sections, lists, tables, footnotes, theorems and math in Unicode (fractions, roots, sub- and superscripts, Greek, ℝ ℕ …). **Reload** re-reads the file, so you can edit the source in a window beside it. It isn't a TeX engine: custom macros and packages are skipped.

## Accessibility

- **Reading comfort:** dyslexia- and ADHD-friendly fonts (OpenDyslexic, Atkinson Hyperlegible, Lexend, Andika; all SIL OFL, licences in `plugins/readingcomfort.koplugin/fonts/`). Pick one for books, for menus and apps, or both. **Comfortable spacing** adds line, word and letter spacing and left-aligns text; turning it off restores your previous settings.
- **Focus:** ADHD helpers.
  - **Now:** one task broken into small steps you tick off. It also shows on the Home screen.
  - **Focus timer:** 15, 25 or 45 minutes, then a break. Updates once a minute and keeps running while you read.
  - **Jot it down:** an inbox (`koreader/focus-inbox.md`) for stray thoughts. Assign it to a gesture in Gestures › **Focus: jot it down**.
  - **Break reminders while reading:** optional.

## Developer tools in KOReader OS

**Built in, shown on the Home screen:**

- **Studio:** create apps from a template, edit their files, check every `.lua` file for errors (with line numbers), read the Android log (`logcat`, filtered to KOReader, to errors or unfiltered) and `crash.log`, and package an app as a `.zip`.
- **App installer:** tap a `.zip` to install it, and remove installed apps.
- **Text editor**, **Terminal**, **SSH server**, **HTTP inspector** and **QR from clipboard:** KOReader's own plugins, added as apps through `AppRegistry.plugin_wrappers`.

**Community plugins worth installing** (not bundled, because their licences vary; tap their zip to install):

| Plugin | What it gives a developer |
|---|---|
| [appstore.koplugin](https://github.com/omer-faruq/appstore.koplugin) | Browse, install and update plugins and patches from GitHub on the device |
| [storefront.koplugin](https://github.com/ultimatejimmy/storefront.koplugin) | A fork of AppStore with release versions and pre-releases |
| [githubbrowser.koplugin](https://github.com/right9code/githubbrowser.koplugin) | Browse repos, edit files and commit from the device (licence: non-commercial) |
| [filebrowser.koplugin](https://github.com/b-/filebrowser.koplugin) / [filebrowserplus.koplugin](https://github.com/patelneeraj/filebrowserplus.koplugin) | Manage and edit the device's files from a web browser (bundles a binary: check your platform) |
| [localsend.koplugin](https://github.com/kaikozlov/localsend.koplugin) | Send files to and from the device with LocalSend (binary for Kindle, Kobo and reMarkable) |

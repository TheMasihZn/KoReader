# KOReader OS {version} ({date})

## What changed
{changes}

## Install everything (recommended)
On the laptop, in the unzipped release folder, with the phone plugged in (USB debugging on):

    ./installKos.sh all

That puts `2-kosBundle.lua` into `koreader/patches/` on the phone, removes the old hyphenated files, then
starts the laptop bridge. Close KOReader completely and open it again.

Without adb: copy `2-kosBundle.lua` to `koreader/patches/` on the phone by hand, delete
`2-0-kos-bundle.lua` and `2-fork-preview.lua` there, restart KOReader. It contains every app and the shared
libraries they need.

## Install one app
Each file in `apps/` is one app as a plugin zip. Tap it in the file browser; the App installer offers to
install it. Install the bundle first, the apps need its shared libraries.

| App | Zip | Needs |
| --- | --- | --- |
{apps}

## Laptop bridge
`gemmaBridge.zip`: unzip, run `python3 gemma_bridge.py`. It prints the address and PIN.
Needs Ollama running; `espeak-ng` for read-aloud. Shared folder: `~/kosShare`.

## For the OS
`osEmbedding.md` lists every common library and what the OS must provide natively; `osItems.md` is the ledger of every item and its status.

## Checksums
{checksums}

Built by CI from commit {commit}. Send `koreader/forkPreview.log` for anything that fails.

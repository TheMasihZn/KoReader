# KOReader OS {version} ({date})

## What changed
{changes}

## Install everything (recommended)
Copy `2-kosBundle.lua` to `koreader/patches/` and restart KOReader. It contains every app and the shared
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
`osEmbedding.md` lists every common library and what the OS must provide natively.

## Checksums
{checksums}

Built by CI from commit {commit}. Send `koreader/forkPreview.log` for anything that fails.

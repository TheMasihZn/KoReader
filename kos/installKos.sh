#!/usr/bin/env bash
# KOReader OS installer for the laptop side. Run from the folder you unzipped the release into.
#
#   ./installKos.sh phone     put the bundle on the phone (USB debugging on, adb installed) and remove old files
#   ./installKos.sh bridge    unzip and start the laptop bridge (needs Python 3; Ollama for the chat)
#   ./installKos.sh all       phone, then bridge
#   ./installKos.sh check     only check this folder and what is installed; changes nothing
#
# On the phone afterwards: close KOReader completely and open it again.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
KOROOT="${KOS_PHONE_DIR:-/sdcard/koreader}"     # KOReader's data folder on the phone
BUNDLE="$HERE/2-kosBundle.lua"
BRIDGE_ZIP="$HERE/gemmaBridge.zip"

say() { printf '%s\n' "$*"; }
fail() { printf 'Stopped: %s\n' "$*" >&2; exit 1; }

check_files() {
  [ -f "$BUNDLE" ] || fail "2-kosBundle.lua is not in $HERE. Run this from the unzipped release folder."
  [ -f "$BRIDGE_ZIP" ] || say "Note: gemmaBridge.zip is not here; the bridge step will not work."
  say "Release folder: ok"
}

phone() {
  command -v adb >/dev/null 2>&1 || {
    say "adb is not installed. Do it by hand instead:"
    say "  1. Copy 2-kosBundle.lua into  koreader/patches/  on the phone."
    say "  2. Delete  2-0-kos-bundle.lua  and  2-fork-preview.lua  from that folder if they are there."
    say "  3. Close KOReader completely and open it again."
    say "(To use adb: install Android platform-tools, turn on USB debugging on the phone, plug it in.)"
    return 1
  }
  adb get-state >/dev/null 2>&1 || fail "no phone found. Plug it in, unlock it, allow USB debugging, run again."
  adb shell "mkdir -p $KOROOT/patches" || fail "could not reach $KOROOT on the phone."
  adb shell "rm -f $KOROOT/patches/2-0-kos-bundle.lua $KOROOT/patches/2-fork-preview.lua"
  adb push "$BUNDLE" "$KOROOT/patches/2-kosBundle.lua" || fail "copy to the phone failed."
  say "Bundle is on the phone. Close KOReader completely and open it again."
  say "Check: Home should show Icons, Logcat, 3D viewer, Snapshots; the title bar has three buttons on the right."
}

bridge() {
  [ -f "$BRIDGE_ZIP" ] || fail "gemmaBridge.zip is not in $HERE."
  command -v python3 >/dev/null 2>&1 || fail "Python 3 is not installed."
  command -v unzip >/dev/null 2>&1 || fail "unzip is not installed."
  unzip -qo "$BRIDGE_ZIP" -d "$HERE" || fail "could not unzip the bridge."
  say "Starting the bridge. It prints the address and PIN to type into Gemma and Share on the phone. Stop with Ctrl+C."
  cd "$HERE/gemmaBridge" && exec python3 gemma_bridge.py
}

case "${1:-}" in
  phone)  check_files; phone ;;
  bridge) bridge ;;
  all)    check_files; phone; bridge ;;
  check)  check_files; command -v adb >/dev/null 2>&1 && say "adb: found" || say "adb: not installed"
          command -v python3 >/dev/null 2>&1 && say "python3: found" || say "python3: missing" ;;
  *)      sed -n '2,10p' "$0" ;;
esac

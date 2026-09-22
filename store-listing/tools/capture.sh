#!/usr/bin/env bash
# Captures the store-listing screenshots from the real app, running on a demo
# history, and composes them into store-listing/screenshots/.
#
# THIS TAKES OVER YOUR SCREEN FOR ABOUT A MINUTE. The app's windows open and take
# focus, so keystrokes you type meanwhile go to them. Do not use the machine while
# it runs. Your own Pastiche is quit first and relaunched afterwards.
#
#   store-listing/tools/capture.sh          asks before starting
#   store-listing/tools/capture.sh --yes    no prompt
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLS="$ROOT/store-listing/tools"
OUT="$ROOT/store-listing/screenshots"
REAL_APP="/Applications/Pastiche.app"
WORK="$(mktemp -d)"

WAS_RUNNING=0
if pgrep -f "$REAL_APP/Contents/MacOS" > /dev/null; then WAS_RUNNING=1; fi

cleanup() {
  pkill -f "$WORK/Pastiche.app/Contents/MacOS" 2> /dev/null || true
  # Put things back however this script ended, in the background so it takes no focus.
  if [[ "$WAS_RUNNING" == 1 ]]; then open -g "$REAL_APP" || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "This opens windows and takes focus for about a minute. Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

echo "Preparing the demo app and history..."
make -C "$ROOT" app > /dev/null
cp -R "$ROOT/dist/Pastiche.app" "$WORK/Pastiche.app"
swift "$TOOLS/make_demo_images.swift" "$WORK/images" > /dev/null
python3 "$TOOLS/make_demo_history.py" "$WORK/images" "$WORK/data" > /dev/null
swiftc "$TOOLS/winlist.swift" -o "$WORK/winlist"
mkdir -p "$OUT"

# Only one copy may run: two would fight over the global shortcut.
pkill -f "$REAL_APP/Contents/MacOS" 2> /dev/null || true
sleep 1

launch() {   # launch [--env NAME=value ...]
  pkill -f "$WORK/Pastiche.app/Contents/MacOS" 2> /dev/null || true
  sleep 1
  # The demo history, and no recording of the real clipboard.
  open -n --env PASTICHE_DATA_DIR="$WORK/data" --env PASTICHE_NO_CAPTURE=1 "$@" "$WORK/Pastiche.app"
  sleep 2.5
}

# Window ids come from CoreGraphics. The popup floats (layer 3); Settings is layer 0.
capture_window() {   # capture_window <layer> <out.png>
  local id
  id="$("$WORK/winlist" | grep "layer=$1 " | head -1 | sed -E 's/id=([0-9]+).*/\1/')"
  [[ -n "$id" ]] || { echo "No window on layer $1 to capture." >&2; return 1; }
  screencapture -x -o -l"$id" "$2"
}

# The window opens on the screen the pointer is on. Move it to the main
# (Retina) display so the capture has twice the pixels.
move_to_main_display() {
  osascript -e 'tell application "System Events" to tell process "Pastiche" to set position of window 1 to {500, 150}'
  sleep 0.6
}

popup() {   # popup <name> [--env NAME=value ...]
  local name="$1"; shift
  launch "$@"
  open "$WORK/Pastiche.app"    # reopening a running menu bar app shows the popup
  sleep 1
  move_to_main_display
  capture_window 3 "$WORK/$name.png"
}

settings() {   # settings <name> <tab>
  launch --env PASTICHE_SETTINGS_TAB="$2"
  osascript -e 'tell application "System Events" to tell process "Pastiche" to click menu item "Settings…" of menu 1 of menu bar item 1 of menu bar 2'
  sleep 1.5
  move_to_main_display
  capture_window 0 "$WORK/$1.png"
}

compose() {   # compose <name> "<headline>" <file>
  swift "$TOOLS/compose.swift" "$WORK/$1.png" "$2" "$OUT/$3.png" > /dev/null
}

echo "Capturing..."
popup history
popup images --env PASTICHE_FILTER=image
popup search --env PASTICHE_QUERY=git
settings privacy privacy
settings keys general

echo "Composing..."
compose history "Your clipboard history, one shortcut away." 01-history
compose images  "Text and images, filtered by type."        02-images
compose search  "Search as you type."                       03-search
compose privacy "Secrets and ignored apps are never recorded." 04-privacy
compose keys    "Choose your shortcut, paste key and delete key." 05-keys

echo "Done:"
for f in "$OUT"/*.png; do
  printf '  %s  %sx%s\n' "$(basename "$f")" "$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')" "$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')"
done

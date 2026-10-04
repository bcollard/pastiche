#!/usr/bin/env bash
# Prepares the Mac for the App Review screen recording, and puts it back afterwards.
#
#   store-listing/tools/recording.sh prep       demo files, empty history, Accessibility reset
#   store-listing/tools/recording.sh restore    bring the real history back
#   store-listing/tools/recording.sh shrink <in.mov>   re-encode to 1080p for upload
#
# prep quits Pastiche, moves its history aside (both the direct-download and the
# sandboxed locations) and resets its Accessibility grant, so the recording shows
# a first launch. restore moves the history back; re-grant Accessibility yourself.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLS="$ROOT/store-listing/tools"
APP="/Applications/Pastiche.app"
BUNDLE_ID="io.github.bcollard.Pastiche"
DEMO="$HOME/Pastiche Recording"
BACKUP="$HOME/.pastiche-recording-backup"
HISTORY_DIRS=(
  "$HOME/Library/Application Support/Pastiche"
  "$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Pastiche"
)

quit_pastiche() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2> /dev/null || true
  sleep 1
  pkill -f "Pastiche.app/Contents/MacOS" 2> /dev/null || true
}

check_build() {
  [[ -d "$APP" ]] || { echo "No $APP. Install the build under review from TestFlight first." >&2; exit 1; }
  local version build signature authority
  version="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
  build="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
  # Capture first: awk exiting early would SIGPIPE codesign and trip pipefail.
  signature="$(codesign -dv --verbose=2 "$APP" 2>&1)"
  authority="$(awk -F= '/^Authority=/{print $2; exit}' <<< "$signature")"
  echo "Installed: Pastiche $version ($build), signed by: $authority"
  if [[ "$authority" == "Developer ID Application"* ]]; then
    echo "  WARNING: this is the direct-download build, not the one under review."
    echo "  Install build 5 from TestFlight (it replaces this copy), then run prep again."
  fi
}

write_demo_files() {
  rm -rf "$DEMO"
  mkdir -p "$DEMO"
  # Invented content only. Each line is copied on its own during the recording.
  cat > "$DEMO/Notes.txt" << 'EOF'
Team lunch moved to Thursday, 12:30.
git switch -c feature/search-filter
https://example.com/docs/getting-started

Pasted from Pastiche:

EOF
  swift "$TOOLS/make_demo_images.swift" "$DEMO/.images" > /dev/null
  # One image is enough on screen.
  mv "$DEMO/.images/landscape.png" "$DEMO/Sunset.png"
  rm -rf "$DEMO/.images"
}

prep() {
  check_build
  echo "Quitting Pastiche..."
  quit_pastiche

  if [[ -e "$BACKUP" ]]; then
    echo "A backup already exists at $BACKUP. Run restore first." >&2
    exit 1
  fi
  mkdir -p "$BACKUP"
  local i=0
  for dir in "${HISTORY_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      mv "$dir" "$BACKUP/$i"
      echo "$dir" > "$BACKUP/$i.path"
      echo "History moved aside: $dir"
    fi
    i=$((i + 1))
  done

  echo "Resetting the Accessibility grant, so the recording can show granting it..."
  tccutil reset Accessibility "$BUNDLE_ID" > /dev/null

  echo "Writing demo files to $DEMO..."
  write_demo_files
  open -a TextEdit "$DEMO/Notes.txt"
  open -a Preview "$DEMO/Sunset.png"
  open "$DEMO"

  cat << EOF

Ready. Before you record:
  - Turn on Do Not Disturb (Control Center > Focus).
  - Close other windows; keep TextEdit, Preview and the Finder window open.
  - Leave Pastiche quit: the recording starts with launching it.

Record with ⌘⇧5 > Record Entire Screen, then follow store-listing/review-reply.md.
Copy the image in Preview with Edit > Select All, then ⌘C.
Afterwards: $0 restore
EOF
}

restore() {
  quit_pastiche
  if [[ -d "$BACKUP" ]]; then
    for path_file in "$BACKUP"/*.path; do
      [[ -e "$path_file" ]] || continue
      local dir src
      dir="$(cat "$path_file")"
      src="${path_file%.path}"
      rm -rf "$dir"   # the history made during the recording
      mkdir -p "$(dirname "$dir")"
      mv "$src" "$dir"
      echo "History restored: $dir"
    done
    rm -rf "$BACKUP"
  else
    echo "No backup to restore."
  fi
  rm -rf "$DEMO"
  open "$APP"
  echo "Grant Accessibility again in System Settings > Privacy & Security > Accessibility."
}

shrink() {
  local in="${1:?usage: $0 shrink <recording.mov>}"
  local out="${in%.*}-1080p.mov"
  avconvert --preset Preset1920x1080 --source "$in" --output "$out" --replace
  ls -lh "$in" "$out" | awk '{print $5, $NF}'
}

case "${1:-}" in
  prep) prep ;;
  restore) restore ;;
  shrink) shift; shrink "$@" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

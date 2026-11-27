#!/bin/bash
# Launches a copy of the Debug build on a made-up library and captures only that copy's window. Handy
# for checking UI changes without showing anybody's real files. A Vibe Finder the user has open is
# left alone: the copy runs next to it and is quit after the capture. It only comes to the front for
# the moment of the capture.
#
# Usage:   scripts/snapshot.sh <output.png> <seconds-to-wait> [app arguments...]
# Example: scripts/snapshot.sh /tmp/screenshots.png 8 -VFSelect screenshots -VFSearch "sign in"
#
# Debug app arguments are listed above LaunchOptions in VibeFinder/App/AppContainer.swift.
# VF_SAMPLE_DIR  reuse a sample library (and its index) between runs; otherwise one is made in a
#                temporary folder. Keep it outside ~/Documents, ~/Desktop and ~/Downloads, where macOS
#                would ask for permission.
# VF_KEEP=1      leave the copy running and print its process id on a second line, to drive it further
#                (press its buttons with scripts/press.swift, capture again with scripts/capture.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

out="$1"
wait="$2"
shift 2

app="build/DerivedData/Build/Products/Debug/Vibe Finder.app"
sample="${VF_SAMPLE_DIR:-$(mktemp -d)}"
if [ ! -d "$sample/library" ]; then
    swift scripts/make-sample-library.swift "$sample/library" >/dev/null
fi
folders=""
for folder in "$sample"/library/*/; do folders="$folders${folders:+:}${folder%/}"; done

# The copy this script started last time, if it was kept.
if [ -f "$sample/app.pid" ]; then
    kill "$(cat "$sample/app.pid")" 2>/dev/null || true
    rm -f "$sample/app.pid"
fi

before=$(pgrep -x "Vibe Finder" || true)
open -n -g "$app" --args -VFFolders "$folders" -VFDataDirectory "$sample/index" -ApplePersistenceIgnoreState YES "$@"
sleep "$wait"
pid=$(comm -13 <(echo "$before" | sort) <(pgrep -x "Vibe Finder" | sort) | head -1)
if [ -z "$pid" ]; then
    echo "Vibe Finder didn't start" >&2
    exit 1
fi

if ! scripts/capture.sh "$pid" "$out"; then
    kill "$pid" 2>/dev/null || true
    exit 1
fi
if [ "${VF_KEEP:-}" = "1" ]; then
    echo "$pid" > "$sample/app.pid"
    echo "$pid"
else
    kill "$pid" 2>/dev/null || true
fi

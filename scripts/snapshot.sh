#!/bin/bash
# Launches the Debug build on a made-up library and captures only Vibe Finder's window. Handy for
# checking UI changes without showing anybody's real files.
#
# Usage:   scripts/snapshot.sh <output.png> <seconds-to-wait> [app arguments...]
# Example: scripts/snapshot.sh /tmp/screenshots.png 8 -VFSelect screenshots -VFSearch "sign in"
#
# Debug app arguments are listed above LaunchOptions in VibeFinder/App/AppContainer.swift.
# Set VF_SAMPLE_DIR to reuse a sample library (and its index) between runs; otherwise one is made
# in a temporary folder. Keep it outside ~/Documents, ~/Desktop and ~/Downloads, where macOS would ask
# for permission.
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

pkill -x "Vibe Finder" 2>/dev/null || true
sleep 0.5
open -n "$app" --args -VFFolders "$folders" -VFDataDirectory "$sample/index" -ApplePersistenceIgnoreState YES "$@"
sleep "$wait"

id=$(swift scripts/window-id.swift "Vibe Finder")
if [ "$id" = "0" ]; then
    echo "Vibe Finder has no window on screen" >&2
    exit 1
fi
screencapture -x -o -l "$id" "$out"
echo "$out"

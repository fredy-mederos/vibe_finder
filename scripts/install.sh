#!/bin/bash
# Builds an optimized Vibe Finder and installs it into ~/Applications (or the folder you pass), so it
# shows up in Launchpad and Spotlight.
#
# Usage: scripts/install.sh [destination folder]
set -euo pipefail
cd "$(dirname "$0")/.."

destination="${1:-$HOME/Applications}"
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
xcodebuild -project VibeFinder.xcodeproj -scheme VibeFinder -configuration Release \
    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION="$build_number" build -quiet

mkdir -p "$destination"
pkill -x "Vibe Finder" 2>/dev/null || true
rm -rf "$destination/Vibe Finder.app"
ditto "build/DerivedData/Build/Products/Release/Vibe Finder.app" "$destination/Vibe Finder.app"
echo "Installed $destination/Vibe Finder.app (build $build_number)"

open "$destination/Vibe Finder.app"

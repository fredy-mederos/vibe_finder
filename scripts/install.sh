#!/bin/bash
# Builds an optimized Vibe Finder and installs it into ~/Applications (or the folder you pass), so it
# shows up in Launchpad and Spotlight.
#
# Usage: scripts/install.sh [destination folder]
set -euo pipefail
cd "$(dirname "$0")/.."

destination="${1:-$HOME/Applications}"
# Settings › About shows these: the build number is the number of commits, the commit gets a "+" when
# there were uncommitted changes, and the build time. scripts/create_dmg.sh stamps releases the same way.
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "")
if [ -n "$commit" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then commit="$commit+"; fi
build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
xcodebuild -project VibeFinder.xcodeproj -scheme VibeFinder -configuration Release \
    -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION="$build_number" VF_BUILD_COMMIT="$commit" \
    VF_BUILD_DATE="$build_date" build -quiet

mkdir -p "$destination"
osascript -e 'tell application id "com.fredymederos.VibeFinder" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$destination/Vibe Finder.app"
ditto "build/DerivedData/Build/Products/Release/Vibe Finder.app" "$destination/Vibe Finder.app"
echo "Installed $destination/Vibe Finder.app (build $build_number${commit:+, $commit})"

open "$destination/Vibe Finder.app"

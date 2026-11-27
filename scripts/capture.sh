#!/bin/bash
# Captures the window of one running copy of Vibe Finder, by process id. The copy comes to the front
# for a moment (a window behind others, or parked by Stage Manager, captures as a thumbnail) and the
# app that was in front gets its place back.
#
# Usage: scripts/capture.sh <process id> <output.png> [part of the window's title]
# Without a title, the copy's largest window is captured.
set -euo pipefail
cd "$(dirname "$0")/.."

pid="$1"
out="$2"
title="${3:-}"

front() {
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $1) to true" >/dev/null 2>&1 || true
}

previous=$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true' 2>/dev/null || true)
front "$pid"
sleep 0.8
id=$(swift scripts/window-id.swift "Vibe Finder" "$pid" ${title:+"$title"})
if [ "$id" != "0" ]; then
    screencapture -x -o -l "$id" "$out"
fi
if [ -n "$previous" ] && [ "$previous" != "$pid" ]; then front "$previous"; fi
if [ "$id" = "0" ]; then
    echo "Vibe Finder has no window on screen" >&2
    exit 1
fi
echo "$out"

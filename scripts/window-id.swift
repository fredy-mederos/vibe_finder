// Prints the window number of an app's largest on-screen window, for `screencapture -l`.
// Usage: swift scripts/window-id.swift "Vibe Finder" [process id] [part of the window's title]
// With a process id, only that copy's windows count (the user may have their own copy open).
import CoreGraphics

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Vibe Finder"
let pid = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil
let title = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }
    .filter { pid == nil || ($0[kCGWindowOwnerPID as String] as? Int) == pid }
    .filter { title == nil || (($0[kCGWindowName as String] as? String)?.contains(title!) ?? false) }

func area(_ window: [String: Any]) -> Double {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Double] else { return 0 }
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
}

print(windows.max { area($0) < area($1) }?[kCGWindowNumber as String] as? Int ?? 0)

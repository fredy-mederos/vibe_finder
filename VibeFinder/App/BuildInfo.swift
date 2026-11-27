import Foundation

/// What Settings shows about this copy of Vibe Finder. `scripts/install.sh` and `scripts/create_dmg.sh` stamp
/// the build number (the number of commits), the commit and the build time into Info.plist.
enum BuildInfo {
    static let name = "Vibe Finder"

    /// `0.1.0`.
    static var version: String { info("CFBundleShortVersionString") ?? "–" }

    /// The number of commits it was built from; 1 in development builds.
    static var build: String { info("CFBundleVersion") ?? "–" }

    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// "Debug" or "Release".
    static var configuration: String { isDebug ? "Debug" : "Release" }

    /// The short hash it was built from; nil when built from Xcode.
    static var commit: String? {
        stampedCommit.map { $0.hasSuffix("+") ? String($0.dropLast()) : $0 }
    }

    /// It was built with changes that weren't committed yet (stamped as a `+` after the hash).
    static var hasLocalChanges: Bool { stampedCommit?.hasSuffix("+") ?? false }

    private static var stampedCommit: String? {
        info("VFBuildCommit").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// When it was built: the stamped time, or else when the executable was linked.
    static var date: Date? {
        if let stamp = info("VFBuildDate"), let date = ISO8601DateFormatter().date(from: stamp) { return date }
        guard let executable = Bundle.main.executableURL else { return nil }
        return (try? executable.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// `12 · a481f3a` or `12 · a481f3a + local changes`.
    static var buildDescription: String {
        var text = build
        if let commit { text += " · \(commit)" }
        if hasLocalChanges { text += " + " + String(localized: "local changes", comment: "A build made with uncommitted changes: 12 · a481f3a + local changes") }
        return text
    }

    /// For pasting into a bug report: `Vibe Finder 0.1.0 (12, a481f3a), Release, built 2026-11-27 08:01`.
    static var summary: String {
        let details = [build, commit.map { hasLocalChanges ? $0 + "+" : $0 }].compactMap { $0 }.joined(separator: ", ")
        let built = date.map { ", built " + $0.formatted(.iso8601.year().month().day().dateSeparator(.dash)) + " "
            + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "\(name) \(version) (\(details)), \(configuration)\(built)"
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

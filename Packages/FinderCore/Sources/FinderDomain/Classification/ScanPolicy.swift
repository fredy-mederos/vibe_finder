import Foundation

/// What a scan leaves out: folders nobody keeps their own things in.
public struct ScanPolicy: Sendable {
    /// Folders of downloaded or generated files, wherever they are.
    public var skippedEverywhere: Set<String>
    /// Build output, only skipped inside a project (elsewhere "build" may be the user's own folder).
    public var skippedInProjects: Set<String>
    /// Folders treated as one item even if the system doesn't flag them as packages.
    public var packageExtensions: Set<String>
    /// Formats macOS may mark as a screen capture.
    public var screenCaptureExtensions: Set<String>
    public var maxDepth: Int

    public init(skippedEverywhere: Set<String>, skippedInProjects: Set<String>, packageExtensions: Set<String>,
                screenCaptureExtensions: Set<String>, maxDepth: Int) {
        self.skippedEverywhere = skippedEverywhere
        self.skippedInProjects = skippedInProjects
        self.packageExtensions = packageExtensions
        self.screenCaptureExtensions = screenCaptureExtensions
        self.maxDepth = maxDepth
    }

    public static let standard = ScanPolicy(
        skippedEverywhere: ["node_modules", "Pods", "DerivedData", "Carthage", "__pycache__", "venv", "bower_components"],
        skippedInProjects: ["build", "dist", "target", "vendor", "out", "xcuserdata"],
        packageExtensions: ["app", "xcodeproj", "xcworkspace", "xcassets", "xcarchive", "photoslibrary", "musiclibrary",
                            "tvlibrary", "imovielibrary", "bundle", "framework", "rtfd", "pages", "numbers", "key",
                            "sketch", "playground", "lproj", "xcdatamodeld", "dSYM"],
        screenCaptureExtensions: ["png", "jpg", "jpeg", "heic", "mov", "mp4"],
        maxDepth: 24
    )

    /// Dotfiles, Office's lock files ("~$report.docx") and Finder's custom-icon file.
    public func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".") || name.hasPrefix("~$") || name == "Icon\r"
    }

    public func skipsDirectory(named name: String, inProject: Bool) -> Bool {
        skippedEverywhere.contains(name) || (inProject && skippedInProjects.contains(name))
    }

    /// A change at this path can't change the index: it's inside something a scan never enters.
    public func ignoresChange(at path: String) -> Bool {
        path.split(separator: "/").contains { component in
            component.hasPrefix(".") || skippedEverywhere.contains(String(component)) || component == "build"
        }
    }
}

/// How a folder shows it holds a code project.
public enum ProjectMarkers {
    /// The kind of project a folder with these entries is, or nil when it isn't one.
    public static func projectType(entries: some Sequence<String>) -> String? {
        var best: (rank: Int, type: String)?
        for name in entries {
            guard let candidate = marker(name), candidate.rank < (best?.rank ?? .max) else { continue }
            best = candidate
        }
        return best?.type
    }

    /// Lower ranks say more about the project, so they name it when several markers are there.
    private static func marker(_ name: String) -> (rank: Int, type: String)? {
        if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") { return (0, "Xcode") }
        switch name {
        case "pubspec.yaml": return (1, "Flutter")
        case "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts": return (2, "Gradle")
        case "Package.swift": return (3, "Swift Package")
        case "Cargo.toml": return (4, "Rust")
        case "go.mod": return (4, "Go")
        case "pyproject.toml", "setup.py": return (4, "Python")
        case "Gemfile": return (4, "Ruby")
        case "pom.xml": return (4, "Maven")
        case "composer.json": return (4, "PHP")
        case "package.json": return (5, "Node")
        case "CMakeLists.txt": return (6, "CMake")
        case ".git": return (9, "Git repository")
        default: return nil
        }
    }
}

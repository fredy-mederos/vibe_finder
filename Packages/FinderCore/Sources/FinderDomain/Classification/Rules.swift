import Foundation

/// A folder the scanner found a project in. Its tool gives a first idea of what it's for; reading
/// its manifests (`ProjectPlatformEnricher`) settles it.
struct ProjectFolderRule: ClassificationRule {
    func classify(_ file: FileFacts, format: FileFormat) -> Classification? {
        guard case .project(let type, _) = file.role else { return nil }
        let platform = ProjectPlatformRules.firstGuess(forTechnology: type)
        return Classification(kind: .projects, subkind: platform.subkind, source: .metadata)
    }
}

/// Keynote and private keys share ".key": presentations are packages or big, keys are tiny.
struct KeynoteOrPrivateKeyRule: ClassificationRule {
    func classify(_ file: FileFacts, format: FileFormat) -> Classification? {
        guard file.ext == "key" else { return nil }
        return file.isPackage || file.size > 64 * 1024
            ? Classification(kind: .presentations, subkind: "Keynote", source: .fileType)
            : Classification(kind: .keys, subkind: "Private keys", source: .fileType)
    }
}

/// The names apps and devices give what they save: "Simulator Screenshot …", "RPReplay_Final…".
struct NameConventionRule: ClassificationRule {
    /// The kinds (by format) whose names these conventions are about.
    let kinds: Set<Kind>
    let conventions: [NameConvention]

    func classify(_ file: FileFacts, format: FileFormat) -> Classification? {
        guard kinds.contains(format.kind) else { return nil }
        let name = file.name.lowercased()
        guard let convention = conventions.first(where: { $0.matches(name) }) else { return nil }
        return Classification(kind: convention.kind, subkind: convention.subkind, source: .fileName)
    }
}

/// macOS marks the screenshots and screen recordings it takes.
struct ScreenCaptureRule: ClassificationRule {
    func classify(_ file: FileFacts, format: FileFormat) -> Classification? {
        guard file.isScreenCapture else { return nil }
        switch format.kind {
        case .photos, .images: return Classification(kind: .screenshots, subkind: "Mac", source: .metadata)
        case .videos: return Classification(kind: .screenRecordings, subkind: "Mac", source: .metadata)
        default: return nil
        }
    }
}

/// A video kept in the Music folder is a music video.
struct MusicLibraryRule: ClassificationRule {
    let musicFolder: String

    func classify(_ file: FileFacts, format: FileFormat) -> Classification? {
        guard format.kind == .videos, file.path.hasPrefix(musicFolder + "/") else { return nil }
        return Classification(kind: .musicVideos, subkind: "Music library", source: .metadata)
    }
}

/// Short uncompressed clips are sound effects; a song in WAV is tens of megabytes.
struct SoundEffectRule: ClassificationRule {
    private static let extensions: Set<String> = ["wav", "aif", "aiff", "ogg", "caf"]

    func classify(_ file: FileFacts, format: FileFormat) -> Classification? {
        guard Self.extensions.contains(file.ext), file.size < 1_500_000 else { return nil }
        return Classification(kind: .audio, subkind: "Sound effects", source: .metadata)
    }
}

/// Formats that say how a file is stored but not what it is: kept by format for now and flagged, so
/// its metadata (and then a model) can still decide.
struct AmbiguousFormatRule: ClassificationRule {
    let musicFolder: String

    func classify(_ file: FileFacts, format: FileFormat) -> Classification? {
        let isAmbiguous: Bool
        switch format.kind {
        case .photos, .images: isAmbiguous = FileFormatCatalog.rasterExtensions.contains(file.ext)
        case .videos: isAmbiguous = true
        case .music: isAmbiguous = !file.path.hasPrefix(musicFolder + "/")
        default: isAmbiguous = false
        }
        guard isAmbiguous else { return nil }
        return Classification(kind: format.kind, subkind: format.subkind, source: .fileType, isUnclear: true)
    }
}

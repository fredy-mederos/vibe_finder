import Foundation

/// Decides what a file is from what the file system says about it. Deterministic: the same facts
/// always get the same answer, and nothing here opens the file.
public protocol FileClassifying: Sendable {
    func classify(_ file: FileFacts) -> Classification
}

/// One reason to call a file something. A rule answers only when it's sure it applies; new
/// conventions are added as new rules, not by editing the classifier.
public protocol ClassificationRule: Sendable {
    /// - Parameter format: what the file's extension alone says.
    func classify(_ file: FileFacts, format: FileFormat) -> Classification?
}

/// Asks its rules in order; the first one with an answer wins, and the format is the fallback.
public struct RuleBasedClassifier: FileClassifying {
    private let catalog: FileFormatCatalog
    private let rules: [any ClassificationRule]

    public init(catalog: FileFormatCatalog, rules: [any ClassificationRule]) {
        self.catalog = catalog
        self.rules = rules
    }

    public func classify(_ file: FileFacts) -> Classification {
        let format = catalog.format(forExtension: file.ext, isPackage: file.isPackage)
        for rule in rules {
            if let classification = rule.classify(file, format: format) { return classification }
        }
        return Classification(kind: format.kind, subkind: format.subkind, source: .fileType)
    }

    /// The rules the app ships with, most specific first.
    /// - Parameter musicFolder: the user's Music folder; what lives there is music.
    public static func standard(resolver: (any FileTypeResolving)? = nil, musicFolder: String) -> RuleBasedClassifier {
        RuleBasedClassifier(catalog: FileFormatCatalog(resolver: resolver), rules: [
            ProjectFolderRule(),
            KeynoteOrPrivateKeyRule(),
            NameConventionRule(kinds: [.photos, .images], conventions: NameConventions.images),
            NameConventionRule(kinds: [.videos], conventions: NameConventions.videos),
            NameConventionRule(kinds: [.music, .audio], conventions: NameConventions.audio),
            ScreenCaptureRule(),
            MusicLibraryRule(musicFolder: musicFolder),
            SoundEffectRule(),
            AmbiguousFormatRule(musicFolder: musicFolder),
        ])
    }
}

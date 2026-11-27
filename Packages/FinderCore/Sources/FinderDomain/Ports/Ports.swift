import Foundation

// The ports: what the domain needs from the outside world, each one small enough that an adapter
// (or a test double) only implements what it's about. FinderData has the real ones.

// MARK: - File system

public struct ScanRequest: Sendable, Equatable {
    /// Folders indexed with everything under them.
    public var folders: [String]
    /// Folders only looked into for apps.
    public var applicationFolders: [String]

    public init(folders: [String], applicationFolders: [String] = []) {
        self.folders = folders
        self.applicationFolders = applicationFolders
    }
}

public struct ScanOutput: Sendable, Equatable {
    public var files: [FileFacts]
    /// Folders that couldn't be read (missing, or the user didn't allow it).
    public var unreadableFolders: [String]

    public init(files: [FileFacts], unreadableFolders: [String] = []) {
        self.files = files
        self.unreadableFolders = unreadableFolders
    }
}

/// Lists what's in the user's folders. Blocking: call it off the main thread.
public protocol LibraryScanning: Sendable {
    func scan(_ request: ScanRequest) -> ScanOutput
}

/// The broad family of a file type the format table doesn't know, as the system sees it.
public enum FileFamily: Sendable, Equatable {
    case image, video, audio, sourceCode, archive, font, spreadsheet, presentation, text
}

public protocol FileTypeResolving: Sendable {
    func family(forExtension ext: String) -> FileFamily?
}

/// Tells when something changed under the indexed folders.
public protocol FolderWatching: AnyObject, Sendable {
    func watch(_ folders: [String], onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// Why a file is still where it was.
public struct TrashFailure: Sendable, Equatable {
    public var path: String
    /// The system's explanation, already in the user's language.
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// Moves files and folders to the Trash, where they can be put back from. Nothing is ever deleted
/// for good through this port.
public protocol ItemTrashing: Sendable {
    /// - Returns: what couldn't be moved; empty when everything went to the Trash.
    func moveToTrash(_ paths: [String]) async -> [TrashFailure]
}

// MARK: - Index

/// Remembers what enrichment learned, so files are only opened again when they change.
public protocol EnrichmentCaching: Sendable {
    func loadAll() -> [String: CachedEnrichment]
    func save(_ records: [EnrichmentRecord])
    func prune(keeping paths: Set<String>)
    func removeAll()
}

/// Finds files by the text inside them.
public protocol ContentSearching: Sendable {
    /// Files whose text has every term (a term matches the start of a word).
    func search(terms: [String], limit: Int) -> [ContentHit]
}

// MARK: - Looking inside files

public protocol ImageInspecting: Sendable {
    func facts(forImageAt path: String) -> ImageFacts?
}

public protocol MediaInspecting: Sendable {
    func facts(forMediaAt path: String) async -> MediaFacts?
}

public protocol TextExtracting: Sendable {
    func canExtractText(from item: FileItem) -> Bool
    func text(of item: FileItem) -> String?
}

/// Reads the text in a picture (OCR).
public protocol TextRecognizing: Sendable {
    func recognizeText(inImageAt path: String) -> String?
}

/// Finds the picture a project goes by, among the files in its folder.
public protocol ProjectArtworkFinding: Sendable {
    func artworkPath(forProjectAt path: String) -> String?
}

// MARK: - On-device models

public protocol ImageUnderstanding: Sendable {
    func labels(forImageAt path: String) -> [ImageLabel]
}

public protocol LanguageUnderstanding: Sendable {
    var isAvailable: Bool { get }
    func documentCategory(name: String, folder: String, excerpt: String) async -> DocumentCategory?
    func videoCategory(name: String, folder: String) async -> VideoCategory?
}

// MARK: - Settings

public protocol SettingsStoring: Sendable {
    func load() -> LibrarySettings
    func save(_ settings: LibrarySettings)
}

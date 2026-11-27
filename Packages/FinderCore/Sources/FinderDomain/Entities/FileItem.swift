import Foundation

/// What the file system says about one entry, before anything decides what it is.
public struct FileFacts: Sendable, Equatable {
    public enum Role: Sendable, Equatable {
        case file
        /// A folder the system shows as one document (a Pages file, a photo library).
        case package
        case application(version: String?)
        /// A folder holding a code project; `type` is "Xcode", "Node", "Swift Package"…
        case project(type: String, fileCount: Int)
    }

    public var path: String
    public var name: String
    /// Lowercased, without the dot.
    public var ext: String
    public var size: Int64
    public var modified: Date
    public var created: Date
    public var role: Role
    /// It lives inside a code project.
    public var inProject: Bool
    /// macOS marked it as its own screenshot or screen recording.
    public var isScreenCapture: Bool

    public init(path: String, size: Int64 = 0, modified: Date = .distantPast, created: Date = .distantPast,
                role: Role = .file, inProject: Bool = false, isScreenCapture: Bool = false) {
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.ext = (path as NSString).pathExtension.lowercased()
        self.size = size
        self.modified = modified
        self.created = created
        self.role = role
        self.inProject = inProject
        self.isScreenCapture = isScreenCapture
    }

    public var isPackage: Bool { role != .file }
}

/// One indexed thing: a file, a package (an app, a Pages document) or a project's folder.
public struct FileItem: Identifiable, Hashable, Sendable {
    public let path: String
    public let name: String
    public let ext: String
    public let size: Int64
    public let modified: Date
    public let created: Date
    public var kind: Kind
    public var subkind: String
    public var source: ClassificationSource
    public var isUnclear: Bool
    /// It lives inside a code project (kept out of the other kinds unless the user asks).
    public let inProject: Bool
    /// A short fact shown under the name: "1170 × 2532", "3:45", "120 files".
    public var detail: String
    /// The name without case or diacritics, for searching.
    public let folded: String

    public init(facts: FileFacts, classification: Classification, detail: String = "") {
        path = facts.path
        name = facts.name
        ext = facts.ext
        size = facts.size
        modified = facts.modified
        created = facts.created
        kind = classification.kind
        subkind = classification.subkind
        source = classification.source
        isUnclear = classification.isUnclear
        inProject = facts.inProject
        self.detail = detail
        folded = SearchTerms.fold(facts.name)
    }

    public var id: String { path }
    public var folder: String { (path as NSString).deletingLastPathComponent }

    public var classification: Classification {
        get { Classification(kind: kind, subkind: subkind, source: source, isUnclear: isUnclear) }
        set {
            kind = newValue.kind
            subkind = newValue.subkind
            source = newValue.source
            isUnclear = newValue.isUnclear
        }
    }
}

/// How search text is compared: without case or diacritics, every word must be there.
public enum SearchTerms {
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public static func parse(_ text: String) -> [String] {
        fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

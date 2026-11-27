import Foundation

/// What a thing on disk is, from the user's point of view. Folders don't matter here: every indexed
/// item has exactly one kind, and the library is browsed by kind.
public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
    case projects, apps
    case photos, screenshots, images
    case videos, screenRecordings, musicVideos
    case music, audio
    case pdfs, documents, notes, spreadsheets, presentations, books
    case archives, installers, design, fonts, code, keys, other

    public var id: String { rawValue }

    public var group: KindGroup {
        switch self {
        case .projects, .apps: .work
        case .photos, .screenshots, .images: .pictures
        case .videos, .screenRecordings, .musicVideos: .video
        case .music, .audio: .audio
        case .pdfs, .documents, .notes, .spreadsheets, .presentations, .books: .documents
        case .archives, .installers, .design, .fonts, .code, .keys, .other: .files
        }
    }

    /// Kinds whose items are pictures or frames, worth showing as large thumbnails.
    public var isVisual: Bool {
        switch self {
        case .photos, .screenshots, .images, .videos, .screenRecordings, .musicVideos, .design: true
        default: false
        }
    }
}

/// The families kinds are listed under.
public enum KindGroup: Int, CaseIterable, Identifiable, Sendable {
    case work, pictures, video, audio, documents, files

    public var id: Int { rawValue }

    public var kinds: [Kind] { Kind.allCases.filter { $0.group == self } }
}

/// How an item got its kind, most trusted first. Rules always run before a model, and a model's
/// answer is stored, so the same file keeps its kind until it changes.
public enum ClassificationSource: Int, Sendable, Codable {
    /// The file's type (its extension) settles it.
    case fileType = 0
    /// A naming convention: "Simulator Screenshot …", "RPReplay_Final…", "WhatsApp Video …".
    case fileName = 1
    /// What the file says about itself: camera model, the pixel size of a known screen, audio tags.
    case metadata = 2
    /// Apple's on-device image classifier (Vision).
    case vision = 3
    /// Apple's on-device language model (Foundation Models).
    case languageModel = 4

    public var isModel: Bool { self == .vision || self == .languageModel }
}

/// The answer to "what is this?" for one file.
public struct Classification: Sendable, Equatable {
    public var kind: Kind
    /// A finer type inside the kind: "iOS Simulator", "Markdown", "Invoices & receipts".
    public var subkind: String
    public var source: ClassificationSource
    /// The rules only know the file's format, not what it is (a PNG that could be a screenshot or a
    /// drawing): its metadata, and then a model, may still refine it.
    public var isUnclear: Bool

    public init(kind: Kind, subkind: String, source: ClassificationSource, isUnclear: Bool = false) {
        self.kind = kind
        self.subkind = subkind
        self.source = source
        self.isUnclear = isUnclear
    }
}

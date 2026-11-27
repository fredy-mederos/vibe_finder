import Foundation

/// What the user chose to index and how.
public struct LibrarySettings: Sendable, Equatable, Codable {
    /// The folders to index, with everything under them.
    public var folders: [String]
    /// Apps installed in the Applications folders are listed too.
    public var includesApplications: Bool
    /// Pictures and documents inside code projects show up in their kinds (they're always indexed).
    public var includesProjectFiles: Bool
    /// Text in screenshots and images is read (on this Mac) so it can be searched.
    public var readsTextInImages: Bool
    /// Apple's on-device models may decide what the rules can't.
    public var usesOnDeviceModels: Bool

    public init(folders: [String], includesApplications: Bool = true, includesProjectFiles: Bool = false,
                readsTextInImages: Bool = true, usesOnDeviceModels: Bool = true) {
        self.folders = folders
        self.includesApplications = includesApplications
        self.includesProjectFiles = includesProjectFiles
        self.readsTextInImages = readsTextInImages
        self.usesOnDeviceModels = usesOnDeviceModels
    }

    /// The folders people keep their things in.
    public static func standard(home: String) -> LibrarySettings {
        LibrarySettings(folders: ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music"].map { home + "/" + $0 })
    }

    /// The enrichment steps these settings turn off.
    public var disabledStages: EnrichmentStages {
        var stages: EnrichmentStages = []
        if !readsTextInImages { stages.insert(.imageText) }
        if !usesOnDeviceModels { stages.formUnion([.imageUnderstanding, .documentUnderstanding, .videoUnderstanding]) }
        return stages
    }
}

/// The steps that look inside a file after the scan. Stored with each file so a step that's turned
/// on later only runs for the files that missed it.
public struct EnrichmentStages: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let imageMetadata = EnrichmentStages(rawValue: 1 << 0)
    public static let mediaMetadata = EnrichmentStages(rawValue: 1 << 1)
    public static let text = EnrichmentStages(rawValue: 1 << 2)
    public static let imageText = EnrichmentStages(rawValue: 1 << 3)
    public static let imageUnderstanding = EnrichmentStages(rawValue: 1 << 4)
    public static let documentUnderstanding = EnrichmentStages(rawValue: 1 << 5)
    public static let videoUnderstanding = EnrichmentStages(rawValue: 1 << 6)
    public static let projectArtwork = EnrichmentStages(rawValue: 1 << 7)
    /// A step whose rules changed gets a new bit, so that step alone runs again for what's indexed
    /// (1 << 8 and 1 << 9 were the platform step's earlier sets of rules).
    public static let projectPlatform = EnrichmentStages(rawValue: 1 << 10)
    public static let folderSize = EnrichmentStages(rawValue: 1 << 11)
}

/// What was learned about a file the last time it was enriched, valid while its size and date stay.
public struct CachedEnrichment: Sendable, Equatable {
    public var size: Int64
    public var modified: Date
    public var classification: Classification
    public var detail: String
    public var artworkPath: String?
    public var measuredSize: Int64?
    public var stages: EnrichmentStages

    public init(size: Int64, modified: Date, classification: Classification, detail: String, artworkPath: String? = nil,
                measuredSize: Int64? = nil, stages: EnrichmentStages) {
        self.size = size
        self.modified = modified
        self.classification = classification
        self.detail = detail
        self.artworkPath = artworkPath
        self.measuredSize = measuredSize
        self.stages = stages
    }

    public func isCurrent(for facts: FileFacts) -> Bool {
        size == facts.size && abs(modified.timeIntervalSince(facts.modified)) < 0.001
    }
}

/// The outcome of enriching one item: what it is now, the steps it went through and its text.
public struct EnrichmentRecord: Sendable {
    public var item: FileItem
    public var stages: EnrichmentStages
    /// The text found in it, for content search; nil when it has none.
    public var text: String?

    public init(item: FileItem, stages: EnrichmentStages, text: String?) {
        self.item = item
        self.stages = stages
        self.text = text
    }
}

/// A file whose content matches a search, with the words around the match.
public struct ContentHit: Sendable, Equatable {
    public var path: String
    public var snippet: String

    public init(path: String, snippet: String) {
        self.path = path
        self.snippet = snippet
    }
}

// MARK: - Browsing

/// How a list of items is ordered and split into sections.
public enum Arrangement: String, CaseIterable, Sendable, Codable {
    case date, name, size, type, folder
}

/// What a section of a browsed list stands for; the UI puts it into words.
public enum SectionKey: Hashable, Sendable {
    case all
    case today
    case previous7Days
    case previous30Days
    case month(year: Int, month: Int)
    case year(Int)
    case subkind(String)
    case folder(String)
    case kind(Kind)
}

public struct ItemSection: Identifiable, Equatable, Sendable {
    public var key: SectionKey
    public var items: [FileItem]

    public init(key: SectionKey, items: [FileItem]) {
        self.key = key
        self.items = items
    }

    public var id: SectionKey { key }
}

public struct SubkindCount: Equatable, Sendable, Identifiable {
    public var name: String
    public var count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    public var id: String { name }
}

/// What to show: one kind or everything, narrowed by a search and a subkind.
public struct BrowseRequest: Sendable, Equatable {
    /// nil browses every kind at once (a search from the overview).
    public var kind: Kind?
    public var subkind: String?
    /// Folded words that must all be in the name…
    public var terms: [String]
    /// …unless the content search found the file.
    public var contentMatches: Set<String>
    public var arrangement: Arrangement

    public init(kind: Kind?, subkind: String? = nil, terms: [String] = [], contentMatches: Set<String> = [],
                arrangement: Arrangement = .date) {
        self.kind = kind
        self.subkind = subkind
        self.terms = terms
        self.contentMatches = contentMatches
        self.arrangement = arrangement
    }
}

public struct BrowseResult: Sendable, Equatable {
    public var sections: [ItemSection]
    public var count: Int
    /// The subkinds among the matches, before narrowing to one of them.
    public var subkinds: [SubkindCount]

    public init(sections: [ItemSection] = [], count: Int = 0, subkinds: [SubkindCount] = []) {
        self.sections = sections
        self.count = count
        self.subkinds = subkinds
    }
}

/// What there is of one kind.
public struct KindSummary: Sendable, Equatable {
    public var kind: Kind
    public var count: Int
    public var size: Int64
    public var subkinds: [SubkindCount]
    /// The latest few, for a glimpse.
    public var recent: [FileItem]

    public init(kind: Kind, count: Int, size: Int64, subkinds: [SubkindCount], recent: [FileItem]) {
        self.kind = kind
        self.count = count
        self.size = size
        self.subkinds = subkinds
        self.recent = recent
    }
}

public struct LibrarySummary: Sendable, Equatable {
    public var kinds: [Kind: KindSummary]
    public var count: Int
    public var size: Int64

    public init(kinds: [Kind: KindSummary] = [:], count: Int = 0, size: Int64 = 0) {
        self.kinds = kinds
        self.count = count
        self.size = size
    }

    public static let empty = LibrarySummary()
}

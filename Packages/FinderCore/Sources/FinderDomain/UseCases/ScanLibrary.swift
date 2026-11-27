import Foundation

/// The library after a scan: every item with its kind, and the ones still to look inside.
public struct LibraryScan: Sendable {
    public var items: [FileItem]
    /// Items enrichment hasn't seen in their current state, newest first.
    public var pending: [FileItem]
    public var unreadableFolders: [String]

    public init(items: [FileItem], pending: [FileItem], unreadableFolders: [String]) {
        self.items = items
        self.pending = pending
        self.unreadableFolders = unreadableFolders
    }
}

/// Says whether an item still has enrichment steps to go through.
public protocol EnrichmentPlanning: Sendable {
    func needsEnrichment(_ item: FileItem, cached: CachedEnrichment?, settings: LibrarySettings) -> Bool
}

/// Lists the user's folders and decides what each thing is: the rules first, then whatever an
/// earlier enrichment already learned about files that haven't changed since.
public struct ScanLibrary: Sendable {
    private let scanner: any LibraryScanning
    private let classifier: any FileClassifying
    private let cache: any EnrichmentCaching
    private let planner: any EnrichmentPlanning
    private let home: String

    /// Source and config files inside a project belong to the project, not to the library.
    private static let kindsLeftInsideProjects: Set<Kind> = [.code, .other, .keys, .fonts, .archives]

    public init(scanner: any LibraryScanning, classifier: any FileClassifying, cache: any EnrichmentCaching,
                planner: any EnrichmentPlanning, home: String) {
        self.scanner = scanner
        self.classifier = classifier
        self.cache = cache
        self.planner = planner
        self.home = home
    }

    /// Blocking: call it off the main thread.
    public func execute(_ settings: LibrarySettings) -> LibraryScan {
        let request = ScanRequest(
            folders: settings.folders,
            applicationFolders: settings.includesApplications ? ["/Applications", home + "/Applications"] : []
        )
        let output = scanner.scan(request)
        let cached = cache.loadAll()
        var items: [FileItem] = []
        var pending: [FileItem] = []
        items.reserveCapacity(output.files.count)
        for facts in output.files {
            let classification = classifier.classify(facts)
            if facts.inProject, Self.kindsLeftInsideProjects.contains(classification.kind) { continue }
            var item = FileItem(facts: facts, classification: classification, detail: Self.detail(for: facts))
            let known = cached[facts.path].flatMap { $0.isCurrent(for: facts) ? $0 : nil }
            if let known {
                item.classification = known.classification
                item.artworkPath = known.artworkPath
                if !known.detail.isEmpty { item.detail = known.detail }
            }
            if planner.needsEnrichment(item, cached: known, settings: settings) { pending.append(item) }
            items.append(item)
        }
        if !cached.isEmpty {
            cache.prune(keeping: Set(items.map(\.path)))
        }
        pending.sort { $0.modified > $1.modified }
        return LibraryScan(items: items, pending: pending, unreadableFolders: output.unreadableFolders)
    }

    private static func detail(for facts: FileFacts) -> String {
        switch facts.role {
        case .project(_, let fileCount): fileCount == 1 ? "1 file" : "\(fileCount) files"
        case .application(let version): version.map { "Version \($0)" } ?? ""
        case .file, .package: ""
        }
    }
}

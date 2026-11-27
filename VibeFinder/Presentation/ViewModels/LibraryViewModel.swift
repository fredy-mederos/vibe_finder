import Foundation
import Observation
import FinderDomain

/// How far the background pass that looks inside files is.
struct IndexingProgress: Equatable {
    var completed: Int
    var total: Int

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// The library as the UI sees it: what's indexed, the summary per kind, and what's still going on.
/// It only orchestrates use cases; scanning, classifying and enriching live in FinderDomain.
@Observable
final class LibraryViewModel {
    /// The items the library shows (files inside projects are left out unless the user asks).
    private(set) var items: [FileItem] = []
    private(set) var summary = LibrarySummary.empty
    /// Goes up every time `items` changes.
    private(set) var revision = 0
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var indexing: IndexingProgress?
    private(set) var unreadableFolders: [String] = []
    private(set) var settings: LibrarySettings

    private let scanLibrary: ScanLibrary
    private let enrichLibrary: EnrichLibrary
    private let summarize: SummarizeLibrary
    private let visibleItems: VisibleItems
    private let cache: any EnrichmentCaching
    private let settingsStore: any SettingsStoring
    private let watcher: any FolderWatching

    @ObservationIgnored private var allItems: [FileItem] = []
    @ObservationIgnored private var positions: [String: Int] = [:]
    @ObservationIgnored private var enrichment: Task<Void, Never>?
    @ObservationIgnored private var pendingRescan: Task<Void, Never>?
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored private var hasStarted = false

    init(scanLibrary: ScanLibrary, enrichLibrary: EnrichLibrary, summarize: SummarizeLibrary, visibleItems: VisibleItems,
         cache: any EnrichmentCaching, settingsStore: any SettingsStoring, watcher: any FolderWatching) {
        self.scanLibrary = scanLibrary
        self.enrichLibrary = enrichLibrary
        self.summarize = summarize
        self.visibleItems = visibleItems
        self.cache = cache
        self.settingsStore = settingsStore
        self.watcher = watcher
        settings = settingsStore.load()
    }

    /// The first scan, and watching the folders from then on.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        watch()
        rescan()
    }

    func rescan() {
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        let (scanLibrary, settings) = (scanLibrary, settings)
        Task {
            let scan = await Task.detached(priority: .userInitiated) { scanLibrary.execute(settings) }.value
            apply(scan)
            isScanning = false
            hasScanned = true
            if rescanRequested {
                rescanRequested = false
                rescan()
            }
        }
    }

    /// Changes the settings, saves them and brings the library in line.
    func update(_ change: (inout LibrarySettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        let foldersChanged = updated.folders != settings.folders
        settings = updated
        settingsStore.save(updated)
        if foldersChanged { watch() }
        publish()
        rescan()
    }

    /// Forgets everything learned about the files and looks inside all of them again.
    func rebuildIndex() {
        enrichment?.cancel()
        cache.removeAll()
        rescan()
    }

    func item(at path: String) -> FileItem? {
        positions[path].map { allItems[$0] }
    }

    // MARK: - Scanning and enriching

    private func apply(_ scan: LibraryScan) {
        unreadableFolders = scan.unreadableFolders
        // A scan the watcher asked for often finds nothing new: leave the UI alone then.
        if scan.items != allItems {
            allItems = scan.items
            positions = Dictionary(scan.items.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
            publish()
        }
        enrich(scan.pending)
    }

    private func enrich(_ pending: [FileItem]) {
        enrichment?.cancel()
        guard !pending.isEmpty else {
            indexing = nil
            return
        }
        indexing = IndexingProgress(completed: 0, total: pending.count)
        let batches = enrichLibrary.run(pending, settings: settings)
        enrichment = Task {
            for await batch in batches {
                guard !Task.isCancelled else { return }
                for item in batch.items {
                    if let position = positions[item.path] { allItems[position] = item }
                }
                indexing = IndexingProgress(completed: batch.completed, total: batch.total)
                publish()
            }
            if !Task.isCancelled { indexing = nil }
        }
    }

    private func publish() {
        items = visibleItems.execute(allItems, settings: settings)
        summary = summarize.execute(items)
        revision += 1
    }

    // MARK: - Watching

    private func watch() {
        watcher.watch(settings.folders) { [weak self] in
            Task { @MainActor in self?.scheduleRescan() }
        }
    }

    /// Changes come in bursts (a download, an unzip): wait for them to settle.
    private func scheduleRescan() {
        pendingRescan?.cancel()
        pendingRescan = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            rescan()
        }
    }
}

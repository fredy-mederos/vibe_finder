import Foundation
import Synchronization
import Testing
@testable import FinderDomain

/// Builds items the way a scan would, with only what a test cares about.
func makeItem(_ path: String, kind: Kind, subkind: String = "", size: Int64 = 1, modified: Date = .distantPast,
              inProject: Bool = false, isUnclear: Bool = false) -> FileItem {
    FileItem(facts: FileFacts(path: path, size: size, modified: modified, inProject: inProject),
             classification: Classification(kind: kind, subkind: subkind, source: .fileType, isUnclear: isUnclear))
}

@Suite struct ArrangeItemsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func byDateSplitsIntoPeriods() {
        let now = date(2026, 11, 27)
        let items = [
            makeItem("/a/today.png", kind: .screenshots, modified: date(2026, 11, 27)),
            makeItem("/a/week.png", kind: .screenshots, modified: date(2026, 11, 22)),
            makeItem("/a/month.png", kind: .screenshots, modified: date(2026, 11, 2)),
            makeItem("/a/march.png", kind: .screenshots, modified: date(2026, 3, 9)),
            makeItem("/a/march2.png", kind: .screenshots, modified: date(2026, 3, 2)),
            makeItem("/a/old.png", kind: .screenshots, modified: date(2023, 6, 1)),
            makeItem("/a/song.mp3", kind: .music, modified: date(2026, 11, 27)),
        ]
        let result = ArrangeItems(calendar: calendar).execute(items, request: BrowseRequest(kind: .screenshots), now: now)
        #expect(result.count == 6)
        #expect(result.sections.map(\.key) == [.today, .previous7Days, .previous30Days, .month(year: 2026, month: 3), .year(2023)])
        #expect(result.sections[3].items.map(\.name) == ["march.png", "march2.png"])
    }

    @Test func searchMatchesNamesWithoutCaseOrAccentsAndContentHits() {
        let items = [
            makeItem("/a/Factura Marzo.pdf", kind: .pdfs),
            makeItem("/a/contract.pdf", kind: .pdfs),
            makeItem("/a/scan.pdf", kind: .pdfs),
        ]
        let request = BrowseRequest(kind: .pdfs, terms: SearchTerms.parse("FACTÚRA marzo"), contentMatches: ["/a/scan.pdf"],
                                    arrangement: .name)
        let result = ArrangeItems().execute(items, request: request)
        #expect(result.sections.flatMap(\.items).map(\.name) == ["Factura Marzo.pdf", "scan.pdf"])
    }

    @Test func subkindsAreCountedBeforeNarrowing() {
        let items = [
            makeItem("/a/1.png", kind: .screenshots, subkind: "Mac"),
            makeItem("/a/2.png", kind: .screenshots, subkind: "Android"),
            makeItem("/a/3.png", kind: .screenshots, subkind: "Android"),
        ]
        let result = ArrangeItems().execute(items, request: BrowseRequest(kind: .screenshots, subkind: "Mac", arrangement: .size))
        #expect(result.count == 1)
        #expect(result.subkinds == [SubkindCount(name: "Android", count: 2), SubkindCount(name: "Mac", count: 1)])
    }

    @Test func everythingIsGroupedByKindInSidebarOrder() {
        let items = [makeItem("/a/x.mp3", kind: .music), makeItem("/a/x.png", kind: .screenshots), makeItem("/a/x.pdf", kind: .pdfs)]
        let result = ArrangeItems().execute(items, request: BrowseRequest(kind: nil, terms: ["x"]))
        #expect(result.sections.map(\.key) == [.kind(.screenshots), .kind(.music), .kind(.pdfs)])
    }

    @Test func byTypeAndFolder() {
        let items = [
            makeItem("/b/1.png", kind: .images, subkind: "PNG"),
            makeItem("/a/2.png", kind: .images, subkind: "PNG"),
            makeItem("/a/3.svg", kind: .images, subkind: "Vector"),
        ]
        let arrange = ArrangeItems()
        #expect(arrange.execute(items, request: BrowseRequest(kind: .images, arrangement: .type)).sections.map(\.key)
            == [.subkind("PNG"), .subkind("Vector")])
        #expect(arrange.execute(items, request: BrowseRequest(kind: .images, arrangement: .folder)).sections.map(\.key)
            == [.folder("/a"), .folder("/b")])
    }
}

@Suite struct SummaryTests {
    @Test func summarizesPerKind() {
        let items = [
            makeItem("/a/1.png", kind: .screenshots, subkind: "Mac", size: 10, modified: Date(timeIntervalSince1970: 1)),
            makeItem("/a/2.png", kind: .screenshots, subkind: "Mac", size: 20, modified: Date(timeIntervalSince1970: 2)),
            makeItem("/a/a.pdf", kind: .pdfs, subkind: "PDF", size: 5),
        ]
        let summary = SummarizeLibrary(recentCount: 1).execute(items)
        #expect(summary.count == 3)
        #expect(summary.size == 35)
        #expect(summary.kinds[.screenshots]?.count == 2)
        #expect(summary.kinds[.screenshots]?.recent.map(\.name) == ["2.png"])
        #expect(summary.kinds[.music] == nil)
    }

    @Test func projectFilesAreHiddenUnlessAsked() {
        let items = [makeItem("/p/icon.png", kind: .images, inProject: true), makeItem("/a/pic.png", kind: .images)]
        var settings = LibrarySettings(folders: [])
        #expect(VisibleItems().execute(items, settings: settings).map(\.name) == ["pic.png"])
        settings.includesProjectFiles = true
        #expect(VisibleItems().execute(items, settings: settings).count == 2)
    }
}

@Suite struct PolicyTests {
    @Test func imageFacts() {
        let png = makeItem("/a/x.png", kind: .images, isUnclear: true)
        let jpg = makeItem("/a/x.jpg", kind: .photos, isUnclear: true)
        #expect(ImageFactsPolicy.classification(for: jpg, facts: ImageFacts(width: 4032, height: 3024, cameraModel: "iPhone 15 Pro"))?.kind == .photos)
        #expect(ImageFactsPolicy.classification(for: png, facts: ImageFacts(width: 1179, height: 2556))
            == Classification(kind: .screenshots, subkind: "iPhone", source: .metadata))
        #expect(ImageFactsPolicy.classification(for: png, facts: ImageFacts(width: 2556, height: 1179))?.subkind == "iPhone")
        #expect(ImageFactsPolicy.classification(for: png, facts: ImageFacts(width: 800, height: 600, isMarkedScreenshot: true))?.kind == .screenshots)
        #expect(ImageFactsPolicy.classification(for: png, facts: ImageFacts(width: 64, height: 64))?.subkind == "Icons")
        // The same screen size in a JPEG says nothing, and neither does an ordinary size.
        #expect(ImageFactsPolicy.classification(for: jpg, facts: ImageFacts(width: 1179, height: 2556)) == nil)
        #expect(ImageFactsPolicy.classification(for: png, facts: ImageFacts(width: 1000, height: 700)) == nil)
    }

    @Test func imageLabelsOnlyMoveWhenConfident() {
        let png = makeItem("/a/x.png", kind: .images, isUnclear: true)
        #expect(ImageLabelPolicy.classification(for: png, labels: [ImageLabel("screenshot", 0.9)])?.kind == .screenshots)
        #expect(ImageLabelPolicy.classification(for: png, labels: [ImageLabel("screenshot", 0.3)]) == nil)
        #expect(ImageLabelPolicy.classification(for: png, labels: [ImageLabel("receipt", 0.8)])?.subkind == "Scans & documents")
        #expect(ImageLabelPolicy.classification(for: png, labels: [ImageLabel("chart", 0.8)])?.subkind == "Diagrams & charts")
        #expect(ImageLabelPolicy.classification(for: png, labels: [ImageLabel("beach", 0.99)]) == nil)
    }

    @Test func mediaFacts() {
        let video = makeItem("/a/x.mp4", kind: .videos, subkind: "MP4", isUnclear: true)
        #expect(MediaFactsPolicy.classification(for: video, facts: MediaFacts(width: 1179, height: 2556))?.kind == .screenRecordings)
        // 16:9 is what cameras film in, whatever the size: never a screen recording by size alone.
        #expect(MediaFactsPolicy.classification(for: video, facts: MediaFacts(width: 1920, height: 1080)) == nil)
        #expect(MediaFactsPolicy.classification(for: video, facts: MediaFacts(width: 720, height: 1280)) == nil)
        #expect(MediaFactsPolicy.classification(for: video, facts: MediaFacts(width: 1242, height: 2208)) == nil)
        #expect(MediaFactsPolicy.classification(for: video, facts: MediaFacts(artist: "Band"))?.kind == .musicVideos)
        let song = makeItem("/a/x.mp3", kind: .music, subkind: "MP3", isUnclear: true)
        #expect(MediaFactsPolicy.classification(for: song, facts: MediaFacts(duration: 200, artist: "Band"))?.source == .metadata)
        #expect(MediaFactsPolicy.classification(for: song, facts: MediaFacts(duration: 3))?.subkind == "Sound effects")
        let memo = makeItem("/a/x.m4a", kind: .music, subkind: "AAC", isUnclear: true)
        #expect(MediaFactsPolicy.classification(for: memo, facts: MediaFacts(duration: 90))?.subkind == "Voice & recordings")
        #expect(MediaFactsPolicy.detail(for: MediaFacts(duration: 225, width: 1920, height: 1080)) == "3:45 · 1920 × 1080")
        #expect(DetailFormat.duration(3729) == "1:02:09")
    }

    @Test func informativeVideoNames() {
        #expect(VideoCategoryPolicy.isInformative(name: "Daft Punk - Around the World.mp4"))
        #expect(!VideoCategoryPolicy.isInformative(name: "videoplayback (3).mp4"))
        #expect(!VideoCategoryPolicy.isInformative(name: "SpITfOQVyGpKJFSiRItoLA.mp4"))
    }
}

// MARK: - Enrichment

private final class MemoryCache: EnrichmentCaching {
    let records = Mutex<[String: EnrichmentRecord]>([:])

    func loadAll() -> [String: CachedEnrichment] {
        records.withLock { $0.mapValues {
            CachedEnrichment(size: $0.item.size, modified: $0.item.modified, classification: $0.item.classification,
                             detail: $0.item.detail, artworkPath: $0.item.artworkPath, stages: $0.stages)
        } }
    }

    func save(_ records: [EnrichmentRecord]) {
        self.records.withLock { stored in records.forEach { stored[$0.item.path] = $0 } }
    }

    func prune(keeping paths: Set<String>) {
        records.withLock { $0 = $0.filter { paths.contains($0.key) } }
    }

    func removeAll() {
        records.withLock { $0 = [:] }
    }
}

private struct StubImageInspector: ImageInspecting {
    var facts: ImageFacts?
    func facts(forImageAt path: String) -> ImageFacts? { facts }
}

private struct StubImageClassifier: ImageUnderstanding {
    var labels: [ImageLabel]
    func labels(forImageAt path: String) -> [ImageLabel] { labels }
}

private struct StubRecognizer: TextRecognizing {
    func recognizeText(inImageAt path: String) -> String? { "Sign in to continue" }
}

private struct StubLanguageModel: LanguageUnderstanding {
    var isAvailable = true
    func documentCategory(name: String, folder: String, excerpt: String) async -> DocumentCategory? {
        excerpt.contains("Total due") ? .invoice : .other
    }
    func videoCategory(name: String, folder: String) async -> VideoCategory? { .musicVideo }
}

private struct StubExtractor: TextExtracting {
    func canExtractText(from item: FileItem) -> Bool { item.kind == .pdfs }
    func text(of item: FileItem) -> String? { "Invoice 42\nTotal due: 10 €" }
}

private struct StubScanner: LibraryScanning {
    var files: [FileFacts]
    func scan(_ request: ScanRequest) -> ScanOutput { ScanOutput(files: files) }
}

@Suite struct EnrichmentTests {
    private let settings = LibrarySettings(folders: ["/a"])

    private func enrich(_ items: [FileItem], with useCase: EnrichLibrary, settings: LibrarySettings? = nil) async -> [FileItem] {
        var result: [FileItem] = []
        for await batch in useCase.run(items, settings: settings ?? self.settings) { result += batch.items }
        return result
    }

    @Test func unclearImageGoesThroughMetadataThenModelThenText() async {
        let cache = MemoryCache()
        let useCase = EnrichLibrary(enrichers: [
            ImageMetadataEnricher(inspector: StubImageInspector(facts: ImageFacts(width: 1000, height: 700))),
            ImageUnderstandingEnricher(classifier: StubImageClassifier(labels: [ImageLabel("screenshot", 0.9)])),
            ImageTextEnricher(recognizer: StubRecognizer()),
        ], cache: cache)
        let item = makeItem("/a/x.png", kind: .images, subkind: "PNG", isUnclear: true)
        let enriched = await enrich([item], with: useCase)
        #expect(enriched.count == 1)
        #expect(enriched[0].kind == .screenshots)
        #expect(enriched[0].source == .vision)
        #expect(enriched[0].detail == "1000 × 700")
        #expect(!enriched[0].isUnclear)
        let stored = cache.records.withLock { $0["/a/x.png"] }
        #expect(stored?.text == "Sign in to continue")
        #expect(stored?.stages == [.imageMetadata, .imageUnderstanding, .imageText])
    }

    @Test func metadataSettlesItBeforeAnyModelIsAsked() async {
        let useCase = EnrichLibrary(enrichers: [
            ImageMetadataEnricher(inspector: StubImageInspector(facts: ImageFacts(width: 1179, height: 2556))),
            ImageUnderstandingEnricher(classifier: StubImageClassifier(labels: [ImageLabel("illustrations", 0.99)])),
        ], cache: MemoryCache())
        let enriched = await enrich([makeItem("/a/x.png", kind: .images, isUnclear: true)], with: useCase)
        #expect(enriched[0].kind == .screenshots)
        #expect(enriched[0].source == .metadata)
    }

    @Test func documentsGetTheirTextAndThenACategory() async {
        let cache = MemoryCache()
        let useCase = EnrichLibrary(enrichers: [
            TextContentEnricher(extractor: StubExtractor()),
            DocumentUnderstandingEnricher(model: StubLanguageModel()),
        ], cache: cache)
        let enriched = await enrich([makeItem("/a/scan0042.pdf", kind: .pdfs, subkind: "PDF")], with: useCase)
        #expect(enriched[0].subkind == "Invoices & receipts")
        #expect(enriched[0].source == .languageModel)
    }

    @Test func settingsAndAvailabilityDecideWhichStepsRun() async {
        let cache = MemoryCache()
        let useCase = EnrichLibrary(enrichers: [
            TextContentEnricher(extractor: StubExtractor()),
            DocumentUnderstandingEnricher(model: StubLanguageModel()),
        ], cache: cache)
        var withoutModels = settings
        withoutModels.usesOnDeviceModels = false
        let item = makeItem("/a/scan0042.pdf", kind: .pdfs, subkind: "PDF")
        let enriched = await enrich([item], with: useCase, settings: withoutModels)
        #expect(enriched[0].subkind == "PDF")
        // Done for those settings, but pending again once models are allowed.
        let cached = cache.loadAll()["/a/scan0042.pdf"]
        #expect(!useCase.needsEnrichment(item, cached: cached, settings: withoutModels))
        #expect(useCase.needsEnrichment(item, cached: cached, settings: settings))

        let unavailable = EnrichLibrary(enrichers: [DocumentUnderstandingEnricher(model: StubLanguageModel(isAvailable: false))],
                                        cache: cache)
        #expect(!unavailable.needsEnrichment(item, cached: nil, settings: settings))
    }

    @Test func nothingToDoForFilesNoStepIsAbout() {
        let useCase = EnrichLibrary(enrichers: [TextContentEnricher(extractor: StubExtractor())], cache: MemoryCache())
        #expect(!useCase.needsEnrichment(makeItem("/a/a.zip", kind: .archives), cached: nil, settings: settings))
    }

    @Test func scanAppliesWhatWasLearnedWhileTheFileIsUnchanged() async {
        let cache = MemoryCache()
        let enrichLibrary = EnrichLibrary(enrichers: [
            ImageMetadataEnricher(inspector: StubImageInspector(facts: ImageFacts(width: 1179, height: 2556))),
        ], cache: cache)
        let modified = Date(timeIntervalSince1970: 1_000)
        func scan(size: Int64) -> LibraryScan {
            let files = [
                FileFacts(path: "/a/x.png", size: size, modified: modified),
                FileFacts(path: "/a/app/main.swift", size: 1, inProject: true),
                FileFacts(path: "/a/app/logo.png", size: 1, inProject: true),
            ]
            return ScanLibrary(scanner: StubScanner(files: files), classifier: RuleBasedClassifier.standard(musicFolder: "/m"),
                               cache: cache, planner: enrichLibrary, home: "/Users/me").execute(settings)
        }
        let first = scan(size: 10)
        // Source files inside a project aren't items; its pictures are.
        #expect(first.items.map(\.name) == ["x.png", "logo.png"])
        #expect(first.pending.map(\.name).sorted() == ["logo.png", "x.png"])
        _ = await enrich(first.pending, with: enrichLibrary)

        let second = scan(size: 10)
        #expect(second.items[0].kind == .screenshots)
        #expect(second.items[0].detail == "1179 × 2556")
        #expect(second.pending.isEmpty)

        // A changed file starts over from the rules.
        let third = scan(size: 11)
        #expect(third.items[0].kind == .images)
        #expect(third.pending.map(\.name) == ["x.png"])
    }
}

// MARK: - Project artwork

private struct StubArtworkFinder: ProjectArtworkFinding {
    func artworkPath(forProjectAt path: String) -> String? { path + "/App/Assets.xcassets/AppIcon.appiconset/icon.png" }
}

@Suite struct ProjectArtworkTests {
    @Test func placesThatSayThisIsTheIcon() {
        // An Xcode app icon beats an Android launcher icon, which beats what web projects ship.
        let appIcon = ProjectArtworkRules.score(fileName: "icon_512x512@2x.png", folderName: "AppIcon.appiconset")
        let otherIconSet = ProjectArtworkRules.score(fileName: "icon.png", folderName: "Widget.appiconset")
        let launcher = ProjectArtworkRules.score(fileName: "ic_launcher.webp", folderName: "mipmap-xxxhdpi")
        let lowDensity = ProjectArtworkRules.score(fileName: "ic_launcher.png", folderName: "mipmap-mdpi")
        let touchIcon = ProjectArtworkRules.score(fileName: "apple-touch-icon.png", folderName: "public")
        let favicon = ProjectArtworkRules.score(fileName: "favicon.ico", folderName: "public")
        let scores = [appIcon, otherIconSet, launcher, lowDensity, touchIcon, favicon].compactMap { $0 }
        #expect(scores.count == 6)
        #expect(scores == scores.sorted(by: >))
        #expect(Set(scores).count == 6)
    }

    @Test func placesThatSayNothing() {
        #expect(ProjectArtworkRules.score(fileName: "Contents.json", folderName: "AppIcon.appiconset") == nil)
        // Adaptive icons are XML: nothing to show.
        #expect(ProjectArtworkRules.score(fileName: "ic_launcher.xml", folderName: "mipmap-anydpi-v26") == nil)
        #expect(ProjectArtworkRules.score(fileName: "ic_launcher_foreground.png", folderName: "mipmap-xxxhdpi") == nil)
        // A generic name only counts where a project's own assets live, or at its root.
        #expect(ProjectArtworkRules.score(fileName: "icon.png", folderName: "screenshots") == nil)
        #expect(ProjectArtworkRules.score(fileName: "icon.png", folderName: "") != nil)
        #expect(ProjectArtworkRules.score(fileName: "logo.svg", folderName: "assets") != nil)
        #expect(ProjectArtworkRules.score(fileName: "photo.png", folderName: "public") == nil)
    }

    @Test func theBestCandidateNeverDependsOnTheOrderFound() {
        let small = ArtworkCandidate(path: "/p/App/Assets.xcassets/AppIcon.appiconset/16.png", score: 110, depth: 3, weight: 900)
        let large = ArtworkCandidate(path: "/p/App/Assets.xcassets/AppIcon.appiconset/1024.png", score: 110, depth: 3, weight: 400_000)
        let deeper = ArtworkCandidate(path: "/p/Extras/Watch/Assets.xcassets/AppIcon.appiconset/1024.png", score: 110, depth: 4, weight: 900_000)
        let favicon = ArtworkCandidate(path: "/p/public/favicon.ico", score: 63, depth: 1, weight: 5_000_000)
        for candidates in [[small, large, deeper, favicon], [favicon, deeper, large, small]] {
            #expect(ProjectArtworkRules.best(candidates) == large)
        }
        #expect(ProjectArtworkRules.best([]) == nil)
        #expect(ProjectArtworkRules.isArtworkContainer("Assets.xcassets"))
        #expect(!ProjectArtworkRules.isArtworkContainer("Vendor.framework"))
    }

    @Test func projectsGetTheirArtworkAndKeepItAcrossScans() async {
        let cache = MemoryCache()
        let enrichLibrary = EnrichLibrary(enrichers: [ProjectArtworkEnricher(finder: StubArtworkFinder())], cache: cache)
        let settings = LibrarySettings(folders: ["/code"])
        func scan() -> LibraryScan {
            let files = [
                FileFacts(path: "/code/app", size: 10, role: .project(type: "Xcode", fileCount: 3)),
                FileFacts(path: "/code/notes.txt", size: 1),
            ]
            return ScanLibrary(scanner: StubScanner(files: files), classifier: RuleBasedClassifier.standard(musicFolder: "/m"),
                               cache: cache, planner: enrichLibrary, home: "/Users/me").execute(settings)
        }
        let first = scan()
        #expect(first.pending.map(\.name) == ["app"])
        for await _ in enrichLibrary.run(first.pending, settings: settings) {}
        let second = scan()
        #expect(second.pending.isEmpty)
        #expect(second.items.first { $0.kind == .projects }?.artworkPath == "/code/app/App/Assets.xcassets/AppIcon.appiconset/icon.png")
        #expect(second.items.first { $0.kind == .notes }?.artworkPath == nil)
    }
}

// MARK: - Trash

private final class StubTrash: ItemTrashing {
    /// Paths it refuses to move.
    let locked: Set<String>
    let asked = Mutex<[String]>([])

    init(locked: Set<String> = []) {
        self.locked = locked
    }

    func moveToTrash(_ paths: [String]) async -> [TrashFailure] {
        asked.withLock { $0 += paths }
        return paths.filter { locked.contains($0) }.map { TrashFailure(path: $0, reason: "locked") }
    }
}

@Suite struct TrashItemsTests {
    @Test func trashedItemsLeaveTheLibraryAndFailuresStay() async {
        let items = [makeItem("/a/1.png", kind: .images), makeItem("/a/2.png", kind: .images), makeItem("/a/3.png", kind: .images)]
        let useCase = TrashItems(trash: StubTrash(locked: ["/a/2.png"]))
        let outcome = await useCase.execute(Array(items.prefix(2)))
        #expect(outcome.trashed == ["/a/1.png"])
        #expect(outcome.failures == [TrashFailure(path: "/a/2.png", reason: "locked")])
        #expect(useCase.remaining(of: items, after: outcome).map(\.name) == ["2.png", "3.png"])
    }

    @Test func aFolderTakesItsContentsAlong() async {
        let trash = StubTrash()
        let useCase = TrashItems(trash: trash)
        let project = makeItem("/code/app", kind: .projects)
        let inside = makeItem("/code/app/docs/logo.png", kind: .images, inProject: true)
        let sibling = makeItem("/code/app-notes.md", kind: .notes)
        // The picture is inside the project: asking for both moves the folder once.
        let outcome = await useCase.execute([inside, project])
        #expect(trash.asked.withLock { $0 } == ["/code/app"])
        #expect(useCase.remaining(of: [project, inside, sibling], after: outcome).map(\.name) == ["app-notes.md"])
    }

    @Test func nothingTrashedLeavesTheLibraryAlone() async {
        let items = [makeItem("/a/1.png", kind: .images)]
        let useCase = TrashItems(trash: StubTrash(locked: ["/a/1.png"]))
        let outcome = await useCase.execute(items)
        #expect(outcome.trashed.isEmpty)
        #expect(useCase.remaining(of: items, after: outcome) == items)
    }
}

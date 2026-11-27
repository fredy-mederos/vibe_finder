import Foundation
import FinderDomain
import FinderData

/// The composition root: the one place that picks the adapter behind each port and hands every
/// object what it depends on. Nothing else in the app imports FinderData.
struct AppContainer {
    let library: LibraryViewModel
    let browser: BrowserViewModel
    let appearance: AppearanceModel
    let thumbnails: any ThumbnailProviding
    let files: any FileActing

    static func live(options: LaunchOptions = .current) -> AppContainer {
        let home = NSHomeDirectory()
        let policy = ScanPolicy.standard
        let index = SQLiteIndexStore(directory: options.dataDirectory ?? defaultDataDirectory)
        let languageModel = FoundationModelsClassifier()

        // The order is the order the steps run in: what a file says about itself first, a model only
        // for what's still unclear, and text once it's known what the file is.
        let enrichLibrary = EnrichLibrary(enrichers: [
            ProjectArtworkEnricher(finder: FileSystemProjectArtworkFinder(policy: policy)),
            ImageMetadataEnricher(inspector: ImageIOInspector()),
            ImageUnderstandingEnricher(classifier: VisionImageClassifier()),
            ImageTextEnricher(recognizer: VisionTextRecognizer()),
            MediaMetadataEnricher(inspector: AVFoundationInspector()),
            VideoUnderstandingEnricher(model: languageModel),
            TextContentEnricher(extractor: DocumentTextExtractor()),
            DocumentUnderstandingEnricher(model: languageModel),
        ], cache: index)
        let scanLibrary = ScanLibrary(
            scanner: FileSystemScanner(policy: policy),
            classifier: RuleBasedClassifier.standard(resolver: SystemFileTypeResolver(), musicFolder: home + "/Music"),
            cache: index, planner: enrichLibrary, home: home
        )
        // A debug launch with its own folders never touches the user's settings.
        let settingsStore: any SettingsStoring = options.folders.map {
            InMemorySettingsStore(LibrarySettings(folders: $0, includesApplications: false))
        } ?? UserDefaultsSettingsStore()

        let library = LibraryViewModel(
            scanLibrary: scanLibrary, enrichLibrary: enrichLibrary, summarize: SummarizeLibrary(), visibleItems: VisibleItems(),
            trashItems: TrashItems(trash: FileManagerTrash()), cache: index, settingsStore: settingsStore,
            watcher: FSEventsFolderWatcher(policy: policy)
        )
        // …nor their view preferences (the same app, so the same preferences file otherwise).
        let preferences = options.folders == nil ? UserDefaults.standard : UserDefaults(suiteName: debugPreferences) ?? .standard
        let browser = BrowserViewModel(library: library, arrange: ArrangeItems(), searchContent: SearchContent(index: index),
                                       preferences: preferences)
        options.apply(to: browser)
        return AppContainer(library: library, browser: browser, appearance: AppearanceModel(preferences: preferences),
                            thumbnails: ProjectThumbnailProvider(base: QuickLookThumbnailProvider()), files: WorkspaceFileActions())
    }

    private static let debugPreferences = "com.fredymederos.VibeFinder.debug"

    private static var defaultDataDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("VibeFinder", isDirectory: true)
    }
}

/// Debug launch arguments, for trying the app on sample folders without touching the user's library:
///
///     -VFFolders "/path/one:/path/two"   index these folders instead of the ones in Settings
///     -VFDataDirectory /path             keep the index there
///     -VFSelect screenshots              open on a kind (its name in `Kind`)
///     -VFSearch "text"                   start with a search
///     -VFLayout list                     grid or list
///     -VFSelectItem "invoice"            select the first shown item with this in its name
struct LaunchOptions {
    var folders: [String]?
    var dataDirectory: URL?
    var kind: Kind?
    var search: String?
    var layout: BrowserLayout?
    var selectedName: String?

    static var current: LaunchOptions {
        let defaults = UserDefaults.standard
        return LaunchOptions(
            folders: defaults.string(forKey: "VFFolders")?.split(separator: ":").map(String.init),
            dataDirectory: defaults.string(forKey: "VFDataDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) },
            kind: defaults.string(forKey: "VFSelect").flatMap(Kind.init),
            search: defaults.string(forKey: "VFSearch"),
            layout: defaults.string(forKey: "VFLayout").flatMap(BrowserLayout.init),
            selectedName: defaults.string(forKey: "VFSelectItem")
        )
    }

    func apply(to browser: BrowserViewModel) {
        if let kind { browser.destination = .kind(kind) }
        if let layout { browser.layout = layout }
        if let search { browser.searchText = search }
        if let selectedName { browser.selectWhenShown(nameContaining: selectedName) }
    }
}

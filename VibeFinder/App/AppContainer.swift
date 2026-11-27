import Foundation
import FinderDomain
import FinderData

/// The composition root: the one place that picks the adapter behind each port and hands every
/// object what it depends on. Nothing else in the app imports FinderData.
struct AppContainer {
    let library: LibraryViewModel
    let browser: BrowserViewModel
    let appearance: AppearanceModel
    let inspectItem: InspectItem
    let thumbnails: any ThumbnailProviding
    let files: any FileActing

    static func live(options: LaunchOptions = .current) -> AppContainer {
        let home = NSHomeDirectory()
        let policy = ScanPolicy.standard
        let dataDirectory = options.dataDirectory ?? defaultDataDirectory
        let index = SQLiteIndexStore(directory: dataDirectory)
        let languageModel = FoundationModelsClassifier()
        let projectInspector = FileSystemProjectInspector()

        // The order is the order the steps run in: what a file says about itself first, a model only
        // for what's still unclear, and text once it's known what the file is.
        let enrichLibrary = EnrichLibrary(enrichers: [
            ProjectPlatformEnricher(inspector: projectInspector),
            ProjectSummaryEnricher(inspector: projectInspector),
            ProjectArtworkEnricher(finder: FileSystemProjectArtworkFinder(
                policy: policy, cacheDirectory: dataDirectory.appendingPathComponent("artwork", isDirectory: true)
            )),
            ImageMetadataEnricher(inspector: ImageIOInspector()),
            ImageUnderstandingEnricher(classifier: VisionImageClassifier()),
            ImageTextEnricher(recognizer: VisionTextRecognizer()),
            MediaMetadataEnricher(inspector: AVFoundationInspector()),
            VideoUnderstandingEnricher(model: languageModel),
            TextContentEnricher(extractor: DocumentTextExtractor()),
            DocumentUnderstandingEnricher(model: languageModel),
            // After the text is read: a document is described from it.
            DescriptionEnricher(describer: languageModel, texts: index),
            // Last: adding up a big folder takes a moment, and nothing else waits on it.
            FolderSizeEnricher(sizer: FileSystemFolderSizer()),
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
                            inspectItem: InspectItem(listing: FileSystemFolderListing(), texts: index, policy: policy),
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
///     -VFInspector YES                   open the inspector
struct LaunchOptions {
    var folders: [String]?
    var dataDirectory: URL?
    var kind: Kind?
    var search: String?
    var layout: BrowserLayout?
    var selectedName: String?
    var showsInspector: Bool?

    static var current: LaunchOptions {
        let defaults = UserDefaults.standard
        return LaunchOptions(
            folders: defaults.string(forKey: "VFFolders")?.split(separator: ":").map(String.init),
            dataDirectory: defaults.string(forKey: "VFDataDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) },
            kind: defaults.string(forKey: "VFSelect").flatMap(Kind.init),
            search: defaults.string(forKey: "VFSearch"),
            layout: defaults.string(forKey: "VFLayout").flatMap(BrowserLayout.init),
            selectedName: defaults.string(forKey: "VFSelectItem"),
            showsInspector: defaults.object(forKey: "VFInspector") == nil ? nil : defaults.bool(forKey: "VFInspector")
        )
    }

    func apply(to browser: BrowserViewModel) {
        if let kind { browser.destination = .kind(kind) }
        if let layout { browser.layout = layout }
        if let search { browser.searchText = search }
        if let selectedName { browser.selectWhenShown(nameContaining: selectedName) }
        if let showsInspector { browser.showsInspector = showsInspector }
    }
}

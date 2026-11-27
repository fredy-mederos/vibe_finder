import Foundation
import Observation
import FinderDomain

/// What the window shows: the overview or one kind.
enum Destination: Hashable {
    case overview
    case kind(Kind)

    var kind: Kind? {
        if case .kind(let kind) = self { kind } else { nil }
    }
}

enum BrowserLayout: String, CaseIterable {
    case grid, list
}

/// The state of the browsing side of the window: where the user is, what they typed, how things are
/// arranged, and the sections that come out of it. Filtering, sorting and grouping are the
/// `ArrangeItems` use case; this only gathers its inputs and keeps its latest answer.
@Observable
final class BrowserViewModel {
    var destination: Destination = .overview {
        didSet {
            guard destination != oldValue else { return }
            subkind = nil
            selection = []
            refresh()
        }
    }

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            searchTextChanged()
        }
    }

    /// Narrows the current kind to one of its subkinds.
    var subkind: String? {
        didSet {
            if subkind != oldValue { refresh() }
        }
    }

    var arrangement: Arrangement {
        didSet {
            guard arrangement != oldValue else { return }
            preferences.set(arrangement.rawValue, forKey: Keys.arrangement)
            refresh()
        }
    }

    var layout: BrowserLayout {
        didSet { preferences.set(layout.rawValue, forKey: Keys.layout) }
    }

    /// The side of a thumbnail in the grid, in points.
    var tileSize: Double {
        didSet { preferences.set(tileSize, forKey: Keys.tileSize) }
    }

    /// Paths of the selected items.
    var selection: Set<String> = []

    private(set) var result = BrowseResult()
    /// Goes up every time `result` changes, so the list knows without comparing thousands of items.
    private(set) var resultRevision = 0
    /// The words around the match, for files found by their content.
    private(set) var snippets: [String: String] = [:]
    /// The groups the user folded away in each place, for as long as the app runs.
    private var collapsedByPlace: [Place: Set<SectionKey>] = [:]
    /// Items waiting for the user to confirm they go to the Trash; empty when nothing is asked.
    var trashCandidates: [FileItem] = []
    /// What the last move to the Trash couldn't move, until the user has been told.
    var trashFailures: [TrashFailure] = []

    static let tileSizes: ClosedRange<Double> = 64...256

    private let library: LibraryViewModel
    private let arrange: ArrangeItems
    private let searchContent: SearchContent
    private let preferences: UserDefaults

    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var nameToSelect: String?
    @ObservationIgnored private var contentSearch: Task<Void, Never>?

    /// Where a set of folded groups belongs. A search has its own, so a group folded while browsing
    /// never hides matches.
    private struct Place: Hashable {
        let destination: Destination
        let isSearching: Bool
    }

    private enum Keys {
        static let arrangement = "browser.arrangement"
        static let layout = "browser.layout"
        static let tileSize = "browser.tileSize"
    }

    init(library: LibraryViewModel, arrange: ArrangeItems, searchContent: SearchContent, preferences: UserDefaults = .standard) {
        self.library = library
        self.arrange = arrange
        self.searchContent = searchContent
        self.preferences = preferences
        arrangement = preferences.string(forKey: Keys.arrangement).flatMap(Arrangement.init) ?? .date
        layout = preferences.string(forKey: Keys.layout).flatMap(BrowserLayout.init) ?? .grid
        let size = preferences.double(forKey: Keys.tileSize)
        tileSize = Self.tileSizes.contains(size) ? size : 128
    }

    var isSearching: Bool { !SearchTerms.parse(searchText).isEmpty }

    /// The overview gives way to results as soon as something is typed.
    var showsOverview: Bool { destination == .overview && !isSearching }

    var selectedItems: [FileItem] {
        selection.compactMap { library.item(at: $0) }
    }

    func libraryDidChange() {
        refresh()
    }

    /// Selects the first item whose name has this text, as soon as it's among the results.
    func selectWhenShown(nameContaining text: String) {
        nameToSelect = SearchTerms.fold(text)
    }

    // MARK: - Collapsing groups

    private var place: Place { Place(destination: destination, isSearching: isSearching) }

    /// The groups of the current list that are folded: their header stays, their items don't show.
    var collapsedSections: Set<SectionKey> { collapsedByPlace[place] ?? [] }

    /// A list that isn't split into groups (by name, by size) has nothing to fold.
    var canCollapseSections: Bool { result.sections.contains { $0.key != .all } }

    func toggleSection(_ key: SectionKey) {
        setSections([key], collapsed: !collapsedSections.contains(key))
    }

    /// Every group does what the given one is about to do (an Option-click on its header).
    func toggleAllSections(following key: SectionKey) {
        setAllSectionsCollapsed(!collapsedSections.contains(key))
    }

    func setAllSectionsCollapsed(_ collapsed: Bool) {
        setSections(result.sections.map(\.key).filter { $0 != .all }, collapsed: collapsed)
    }

    private func setSections(_ keys: [SectionKey], collapsed: Bool) {
        var folded = collapsedSections
        if collapsed {
            folded.formUnion(keys)
            // What can't be seen isn't selected.
            let hidden = result.sections.lazy.filter { keys.contains($0.key) }.flatMap(\.items).map(\.path)
            selection.subtract(hidden)
        } else {
            folded.subtract(keys)
        }
        collapsedByPlace[place] = folded
    }

    // MARK: - Trash

    /// Asks before anything moves: the view shows the question while there are candidates.
    func requestTrashOfSelection() {
        trashCandidates = selectedItems.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func confirmTrash() {
        let items = trashCandidates
        trashCandidates = []
        guard !items.isEmpty else { return }
        Task {
            let outcome = await library.moveToTrash(items)
            selection.subtract(items.map(\.path))
            trashFailures = outcome.failures
        }
    }

    // MARK: - Results

    private func searchTextChanged() {
        // Names answer at once; the index is asked once typing pauses.
        refresh()
        contentSearch?.cancel()
        let text = searchText
        guard isSearching else {
            snippets = [:]
            return
        }
        let searchContent = searchContent
        contentSearch = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) { searchContent.execute(text) }.value
            guard !Task.isCancelled, text == searchText else { return }
            snippets = found
            refresh()
        }
    }

    private func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        guard destination.kind != nil || isSearching else {
            publish(BrowseResult())
            return
        }
        let request = BrowseRequest(kind: destination.kind, subkind: subkind, terms: SearchTerms.parse(searchText),
                                    contentMatches: Set(snippets.keys), arrangement: arrangement)
        let (items, arrange) = (library.items, arrange)
        Task {
            let result = await Task.detached(priority: .userInitiated) { arrange.execute(items, request: request) }.value
            // A newer request may have been made while this one was sorting.
            guard generation == refreshGeneration else { return }
            publish(result)
        }
    }

    private func publish(_ newResult: BrowseResult) {
        guard newResult != result else { return }
        result = newResult
        resultRevision += 1
        if let name = nameToSelect, let item = newResult.sections.lazy.flatMap(\.items).first(where: { $0.folded.contains(name) }) {
            nameToSelect = nil
            selection = [item.path]
        }
    }
}

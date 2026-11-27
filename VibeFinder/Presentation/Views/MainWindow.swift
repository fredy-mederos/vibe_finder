import SwiftUI
import FinderDomain

/// The window: kinds on the left, and either the overview or one kind's items on the right.
struct MainWindow: View {
    let container: AppContainer

    var body: some View {
        @Bindable var browser = container.browser
        NavigationSplitView {
            SidebarView(library: container.library, browser: container.browser)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            DetailView(container: container)
        }
        .searchable(text: $browser.searchText, placement: .toolbar, prompt: "Search names and contents")
        .onChange(of: container.library.revision) {
            container.browser.libraryDidChange()
        }
        .task {
            container.library.start()
        }
        .frame(minWidth: 820, minHeight: 480)
    }
}

private struct DetailView: View {
    let container: AppContainer

    var body: some View {
        let browser = container.browser
        Group {
            if browser.showsOverview {
                OverviewView(library: container.library, browser: browser, thumbnails: container.thumbnails)
            } else {
                BrowserView(library: container.library, browser: browser, thumbnails: container.thumbnails, files: container.files)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }

    private var title: String {
        let browser = container.browser
        if let kind = browser.destination.kind { return kind.title }
        return browser.isSearching ? String(localized: "Search") : String(localized: "Overview")
    }

    private var subtitle: String {
        let browser = container.browser
        let count = browser.showsOverview ? container.library.summary.count : browser.result.count
        return String(localized: "\(count) items")
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let library: LibraryViewModel
    let browser: BrowserViewModel

    var body: some View {
        List(selection: destination) {
            Label("Overview", systemImage: "square.grid.2x2")
                .tag(Destination.overview)
            ForEach(KindGroup.allCases) { group in
                SidebarSection(group: group, summary: library.summary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LibraryStatusView(library: library)
        }
    }

    /// The list wants an optional selection; clearing it (a click on empty space) keeps the place.
    private var destination: Binding<Destination?> {
        Binding {
            browser.destination
        } set: { newValue in
            if let newValue { browser.destination = newValue }
        }
    }
}

private struct SidebarSection: View {
    let group: KindGroup
    let summary: LibrarySummary

    var body: some View {
        let kinds = group.kinds.filter { summary.kinds[$0] != nil }
        if !kinds.isEmpty {
            Section(group.title) {
                ForEach(kinds) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .badge(summary.kinds[kind]?.count ?? 0)
                        .tag(Destination.kind(kind))
                }
            }
        }
    }
}

/// What the library is doing, pinned under the sidebar. One line, so its height never depends on
/// the sidebar's width.
private struct LibraryStatusView: View {
    let library: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let indexing = library.indexing {
                ProgressView(value: indexing.fraction)
                    .controlSize(.small)
                Text("Looking inside files… \(indexing.completed) of \(indexing.total)")
            } else if library.isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                Text("Scanning folders…")
            } else {
                Text("\(library.summary.count) items · \(library.summary.size.formattedFileSize)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

import SwiftUI
import FinderDomain

/// One kind's items (or a search's matches): subkinds to narrow by, the items, and what's selected.
struct BrowserView: View {
    let library: LibraryViewModel
    let browser: BrowserViewModel
    let thumbnails: any ThumbnailProviding
    let files: any FileActing

    var body: some View {
        @Bindable var browser = browser
        VStack(spacing: 0) {
            if browser.result.subkinds.count > 1 {
                SubkindBar(subkinds: browser.result.subkinds, selection: $browser.subkind)
                Divider()
            }
            if browser.result.count == 0 {
                EmptyResultsView(isSearching: browser.isSearching, isScanning: !library.hasScanned)
            } else {
                ItemCollection(
                    sections: browser.result.sections, revision: browser.resultRevision, snippets: browser.snippets,
                    layout: browser.layout, tileSize: browser.tileSize, selection: $browser.selection,
                    thumbnails: thumbnails, files: files
                )
            }
            Divider()
            InfoBar(items: browser.selectedItems, total: browser.result.count, files: files)
        }
        .toolbar {
            BrowserToolbar(browser: browser)
        }
    }
}

private struct BrowserToolbar: ToolbarContent {
    let browser: BrowserViewModel

    var body: some ToolbarContent {
        @Bindable var browser = browser
        ToolbarItem {
            Picker("Layout", selection: $browser.layout) {
                Label("Grid", systemImage: "square.grid.2x2").tag(BrowserLayout.grid)
                Label("List", systemImage: "list.bullet").tag(BrowserLayout.list)
            }
            .pickerStyle(.segmented)
            .help("Show items as a grid or as a list")
        }
        ToolbarItem {
            Menu {
                Picker("Arrange By", selection: $browser.arrangement) {
                    ForEach(Arrangement.allCases, id: \.self) { arrangement in
                        Text(arrangement.title).tag(arrangement)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Arrange", systemImage: "arrow.up.arrow.down")
            }
            .help("Choose how items are ordered and grouped")
        }
        if browser.layout == .grid {
            ToolbarItem {
                Slider(value: $browser.tileSize, in: BrowserViewModel.tileSizes)
                    .controlSize(.small)
                    .frame(width: 110)
                    .help("Thumbnail size")
            }
        }
    }
}

/// The subkinds of what's shown, as chips: one click narrows to it, another widens again.
private struct SubkindBar: View {
    let subkinds: [SubkindCount]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Chip(title: String(localized: "All"), count: subkinds.reduce(0) { $0 + $1.count }, isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(subkinds) { subkind in
                    Chip(title: subkind.name, count: subkind.count, isSelected: selection == subkind.name) {
                        selection = selection == subkind.name ? nil : subkind.name
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

private struct Chip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Text(count.formatted())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyResultsView: View {
    let isSearching: Bool
    let isScanning: Bool

    var body: some View {
        Group {
            if isScanning {
                ProgressView("Scanning folders…")
            } else if isSearching {
                ContentUnavailableView.search
            } else {
                ContentUnavailableView("Nothing Here", systemImage: "tray", description: Text("No items of this kind in your folders."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What's selected, at the bottom of the window: what it is and how that's known, where it is,
/// its size and date. One line, so the list above never jumps.
private struct InfoBar: View {
    let items: [FileItem]
    let total: Int
    let files: any FileActing

    var body: some View {
        HStack(spacing: 10) {
            if items.count == 1, let item = items.first {
                SelectedItemInfo(item: item, files: files)
            } else if items.count > 1 {
                Text("\(items.count) selected · \(items.reduce(Int64(0)) { $0 + $1.size }.formattedFileSize)")
                Spacer(minLength: 0)
            } else {
                Text("\(total) items")
                Spacer(minLength: 0)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }
}

private struct SelectedItemInfo: View {
    let item: FileItem
    let files: any FileActing

    var body: some View {
        Label {
            Text(item.subkind.isEmpty ? item.kind.title : "\(item.kind.title) › \(item.subkind)")
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: item.source.isModel ? "sparkles" : item.kind.symbol)
        }
        .help(String(localized: "Recognized by \(item.source.title)"))
        .layoutPriority(1)
        Button {
            files.revealInFinder([item])
        } label: {
            Label(item.folder.abbreviatingHome, systemImage: "folder")
                .truncationMode(.head)
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        Spacer(minLength: 0)
        Text(item.sizeText)
        Text(item.modified.formatted(date: .abbreviated, time: .shortened))
    }
}

import SwiftUI
import FinderDomain

/// The panel on the right: a closer look at what's selected. What it shows depends on what the item
/// is: a picture's size, a recording's length, the text read inside a document or a screenshot, and
/// for a project what its folder holds.
struct InspectorView: View {
    let items: [FileItem]
    let inspectItem: InspectItem
    let thumbnails: any ThumbnailProviding
    let files: any FileActing

    var body: some View {
        if items.count == 1, let item = items.first {
            ItemInspector(item: item, inspectItem: inspectItem, thumbnails: thumbnails, files: files)
        } else if items.isEmpty {
            ContentUnavailableView("No Selection", systemImage: "sidebar.trailing",
                                   description: Text("Select an item to see its preview and details."))
        } else {
            SelectionSummary(items: items)
        }
    }
}

// MARK: - One item

private struct ItemInspector: View {
    let item: FileItem
    let inspectItem: InspectItem
    let thumbnails: any ThumbnailProviding
    let files: any FileActing

    /// What's read off the main thread when the item changes: its text, or its folder's outline.
    @State private var text: String?
    @State private var outline: [OutlineRow] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ThumbnailImage(item: item, side: 220, thumbnails: thumbnails)
                    .frame(maxWidth: .infinity)
                ItemHeading(item: item)
                ItemActions(item: item, files: files)
                Divider()
                ItemFacts(item: item)
                if !outline.isEmpty {
                    Divider()
                    FolderOutlineView(rows: outline)
                }
                if let text {
                    Divider()
                    IndexedTextView(text: text, isFromPicture: item.kind.isVisual)
                }
            }
            .padding(16)
        }
        // The whole item, not just its path: when the index learns more about it, look again.
        .task(id: item) {
            let (inspectItem, item) = (inspectItem, item)
            let inspection = await Task.detached(priority: .userInitiated) { inspectItem.execute(item) }.value
            guard !Task.isCancelled else { return }
            text = inspection.text
            outline = OutlineRow.rows(for: inspection)
        }
    }
}

private struct ItemHeading: View {
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
                .textSelection(.enabled)
            Label {
                Text(item.subkind.isEmpty ? item.kind.title : "\(item.kind.title) › \(item.subkind)")
            } icon: {
                Image(systemName: item.source.isModel ? "sparkles" : item.kind.symbol)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .help(String(localized: "Recognized by \(item.source.title)"))
            if let summary = item.summary {
                ItemSummary(text: summary, isWrittenByModel: item.kind != .projects)
            }
        }
    }
}

/// The line that says what the item is: a project's own words, or the on-device model's.
private struct ItemSummary: View {
    let text: String
    let isWrittenByModel: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if isWrittenByModel {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                    .help("Written by Apple Intelligence, on this Mac")
            }
            Text(text)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.top, 4)
    }
}

/// Looking only: moving to the Trash stays in the list's context menu, out of reach of a stray click.
private struct ItemActions: View {
    let item: FileItem
    let files: any FileActing

    var body: some View {
        HStack {
            Button("Open") { files.open([item]) }
            Button("Show in Finder") { files.revealInFinder([item]) }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }
}

/// The facts every item has, plus the one its kind adds (a picture's dimensions, an app's version…).
private struct ItemFacts: View {
    let item: FileItem

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 7) {
            FactRow(label: String(localized: "Size"), value: item.sizeText)
            if !item.detail.isEmpty {
                FactRow(label: detailLabel, value: item.detail)
            }
            FactRow(label: String(localized: "Modified"), value: item.modified.formatted(date: .abbreviated, time: .shortened))
            FactRow(label: String(localized: "Created"), value: item.created.formatted(date: .abbreviated, time: .shortened))
            FactRow(label: String(localized: "Where"), value: item.folder.abbreviatingHome)
            FactRow(label: String(localized: "Recognized by"), value: item.source.title)
        }
        .font(.callout)
    }

    /// What the item's detail is, by kind.
    private var detailLabel: String {
        switch item.kind {
        case .photos, .screenshots, .images, .design: String(localized: "Dimensions")
        case .videos, .screenRecordings, .musicVideos, .music, .audio: String(localized: "Length")
        case .projects: String(localized: "Built with")
        case .apps: String(localized: "App")
        default: String(localized: "Details")
        }
    }
}

private struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - A folder's outline

/// One line of the outline, already flattened: the tree is short and never changes while shown.
private struct OutlineRow: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let depth: Int
    /// A line that stands for entries left out ("12 more").
    let isRemainder: Bool

    static func rows(for inspection: ItemInspection) -> [OutlineRow] {
        var rows: [OutlineRow] = []
        func add(_ nodes: [OutlineNode], omitted: Int, parent: String, depth: Int) {
            for node in nodes {
                rows.append(OutlineRow(id: node.path, title: node.name, symbol: node.isFolder ? "folder.fill" : "doc",
                                       depth: depth, isRemainder: false))
                add(node.children, omitted: node.omitted, parent: node.path, depth: depth + 1)
            }
            if omitted > 0 {
                rows.append(OutlineRow(id: parent + "/…", title: String(localized: "\(omitted) more"), symbol: "ellipsis",
                                       depth: depth, isRemainder: true))
            }
        }
        add(inspection.outline, omitted: inspection.omitted, parent: "", depth: 0)
        return rows
    }
}

private struct FolderOutlineView: View {
    let rows: [OutlineRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Inside")
                .font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                Label {
                    Text(row.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: row.symbol)
                        .foregroundStyle(row.isRemainder ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                }
                .font(.callout)
                .foregroundStyle(row.isRemainder ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .padding(.leading, CGFloat(row.depth) * 18)
            }
        }
    }
}

// MARK: - Text and several items

/// The start of the text the index found in the file: what content search matches against.
private struct IndexedTextView: View {
    let text: String
    let isFromPicture: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isFromPicture ? "Text Read in the Picture" : "Text Inside")
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }
}

/// Several items at once: how many, what they weigh together and what they are.
private struct SelectionSummary: View {
    let items: [FileItem]

    var body: some View {
        let kinds = Dictionary(grouping: items, by: \.kind).map { (kind: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.kind.title) > ($1.count, $0.kind.title) }
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            Text("\(items.count) items selected")
                .font(.headline)
            Text(items.reduce(Int64(0)) { $0 + $1.sizeOnDisk }.formattedFileSize)
                .foregroundStyle(.secondary)
            Divider()
            ForEach(kinds, id: \.kind) { entry in
                Label("\(entry.kind.title): \(entry.count)", systemImage: entry.kind.symbol)
                    .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

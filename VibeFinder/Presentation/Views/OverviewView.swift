import SwiftUI
import FinderDomain

/// What's in the library at a glance: how much there is of each kind, with a peek at the latest.
struct OverviewView: View {
    let library: LibraryViewModel
    let browser: BrowserViewModel
    let thumbnails: any ThumbnailProviding

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 16, alignment: .top)]

    var body: some View {
        let summary = library.summary
        if summary.count == 0 {
            EmptyLibraryView(library: library)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    StorageBar(summary: summary)
                    ForEach(KindGroup.allCases) { group in
                        OverviewGroup(group: group, summary: summary, columns: columns, thumbnails: thumbnails) { kind in
                            browser.destination = .kind(kind)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct EmptyLibraryView: View {
    let library: LibraryViewModel

    var body: some View {
        if library.hasScanned {
            ContentUnavailableView {
                Label("Nothing to Show", systemImage: "tray")
            } description: {
                if library.unreadableFolders.isEmpty {
                    Text("The folders in Settings are empty.")
                } else {
                    Text("Vibe Finder couldn't read \(library.unreadableFolders.map(\.abbreviatingHome).formatted(.list(type: .and))). Allow it in System Settings › Privacy & Security › Files and Folders.")
                }
            } actions: {
                SettingsLink {
                    Text("Choose Folders…")
                }
            }
        } else {
            ProgressView("Scanning folders…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The library's size split by family of kinds.
private struct StorageBar: View {
    let summary: LibrarySummary

    var body: some View {
        let shares = KindGroup.allCases.map { group in
            (group: group, size: group.kinds.reduce(Int64(0)) { $0 + (summary.kinds[$1]?.size ?? 0) })
        }.filter { $0.size > 0 }
        VStack(alignment: .leading, spacing: 10) {
            Text("\(summary.count) items · \(summary.size.formattedFileSize)")
                .font(.title2.weight(.semibold))
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(shares, id: \.group) { share in
                        share.group.color
                            .frame(width: max(3, proxy.size.width * Double(share.size) / Double(max(summary.size, 1)) - 2))
                    }
                }
                .clipShape(.rect(cornerRadius: 5))
            }
            .frame(height: 12)
            HStack(spacing: 16) {
                ForEach(shares, id: \.group) { share in
                    HStack(spacing: 5) {
                        Circle().fill(share.group.color).frame(width: 8, height: 8)
                        Text(share.group.title)
                        Text(share.size.formattedFileSize).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .lineLimit(1)
        }
    }
}

private struct OverviewGroup: View {
    let group: KindGroup
    let summary: LibrarySummary
    let columns: [GridItem]
    let thumbnails: any ThumbnailProviding
    let open: (Kind) -> Void

    var body: some View {
        let summaries = group.kinds.compactMap { summary.kinds[$0] }
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(group.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(summaries, id: \.kind) { kindSummary in
                        KindCard(summary: kindSummary, thumbnails: thumbnails) { open(kindSummary.kind) }
                    }
                }
            }
        }
    }
}

/// One kind: how many, how big, its main subkinds and its latest items.
private struct KindCard: View {
    let summary: KindSummary
    let thumbnails: any ThumbnailProviding
    let open: () -> Void

    private static let previewCount = 5

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: summary.kind.symbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(summary.kind.color.gradient, in: .rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.kind.title)
                            .font(.headline)
                        Text("\(summary.count) items · \(summary.size.formattedFileSize)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    ForEach(summary.recent.prefix(Self.previewCount)) { item in
                        ThumbnailImage(item: item, side: 52, thumbnails: thumbnails)
                            .help(item.name)
                    }
                    Spacer(minLength: 0)
                }
                Text(subkinds)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// "iOS Simulator 278 · Android 47 · Mac 12".
    private var subkinds: String {
        summary.subkinds.prefix(4).map { "\($0.name) \($0.count.formatted())" }.joined(separator: " · ")
    }
}

/// An item's thumbnail in SwiftUI, loaded when it comes on screen.
struct ThumbnailImage: View {
    let item: FileItem
    let side: CGFloat
    let thumbnails: any ThumbnailProviding

    @State private var image: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
            }
        }
        .frame(width: side, height: side)
        .task(id: item.path) {
            image = thumbnails.cachedThumbnail(for: item, side: side)
            if image == nil {
                image = await thumbnails.thumbnail(for: item, side: side, scale: displayScale)
            }
        }
    }
}

import SwiftUI
import AppKit
import Quartz
import FinderDomain

/// The items of a kind as a grid of thumbnails or a list. AppKit's collection view, because a kind
/// can hold tens of thousands of items and it only builds the cells on screen.
struct ItemCollection: NSViewRepresentable {
    let sections: [ItemSection]
    /// Changes when `sections` does (comparing thousands of items on every update would be slow).
    let revision: Int
    let snippets: [String: String]
    let layout: BrowserLayout
    let tileSize: Double
    /// Groups whose items are folded away; their header stays.
    let collapsed: Set<SectionKey>
    @Binding var selection: Set<String>
    let thumbnails: any ThumbnailProviding
    let files: any FileActing
    /// A group's header was clicked; `true` when every group should follow it (Option-click).
    let onToggleSection: (SectionKey, Bool) -> Void
    /// The user asked to move the selection to the Trash.
    let onTrashRequest: () -> Void

    func makeCoordinator() -> ItemCollectionController {
        ItemCollectionController(thumbnails: thumbnails, files: files)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let controller = context.coordinator
        controller.onSelectionChange = { selection = $0 }
        controller.onToggleSection = onToggleSection
        controller.onTrashRequest = onTrashRequest
        controller.update(sections: sections, revision: revision, snippets: snippets, layout: layout,
                          tileSize: tileSize, collapsed: collapsed, selection: selection)
    }
}

/// Feeds the collection view and handles what the user does in it: selecting, opening, Quick Look,
/// the context menu and dragging files out.
final class ItemCollectionController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout,
    QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let thumbnails: any ThumbnailProviding
    private let files: any FileActing
    private let collectionView = FinderCollectionView()
    private let flowLayout = WidthTrackingFlowLayout()

    private var sections: [ItemSection] = []
    private var revision = -1
    private var snippets: [String: String] = [:]
    private var layout = BrowserLayout.grid
    private var tileSize: CGFloat = 0
    private var collapsed: Set<SectionKey> = []
    /// Where each item on show is; items of folded groups aren't in it.
    private var indexPaths: [String: IndexPath] = [:]
    var onSelectionChange: (Set<String>) -> Void = { _ in }
    var onToggleSection: (SectionKey, Bool) -> Void = { _, _ in }
    var onTrashRequest: () -> Void = {}

    private enum Metrics {
        static let rowHeight: CGFloat = 44
        static let headerHeight: CGFloat = 32
        static let sectionInset = NSEdgeInsets(top: 6, left: 12, bottom: 14, right: 12)
        /// Room around a tile's thumbnail and under it, for the name and the caption.
        static let tilePadding = NSSize(width: 20, height: 62)
    }

    init(thumbnails: any ThumbnailProviding, files: any FileActing) {
        self.thumbnails = thumbnails
        self.files = files
    }

    func makeScrollView() -> NSScrollView {
        flowLayout.sectionHeadersPinToVisibleBounds = true
        collectionView.controller = self
        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(TileItem.self, forItemWithIdentifier: TileItem.identifier)
        collectionView.register(RowItem.self, forItemWithIdentifier: RowItem.identifier)
        collectionView.register(SectionHeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: SectionHeaderView.identifier)
        collectionView.setDraggingSourceOperationMask([.copy, .link], forLocal: false)

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func update(sections: [ItemSection], revision: Int, snippets: [String: String], layout: BrowserLayout,
                tileSize: Double, collapsed: Set<SectionKey>, selection: Set<String>) {
        let contentChanged = revision != self.revision || snippets != self.snippets
        let layoutChanged = layout != self.layout
        let sizeChanged = CGFloat(tileSize) != self.tileSize
        let newlyCollapsed = collapsed.subtracting(self.collapsed)
        let collapseChanged = collapsed != self.collapsed
        self.snippets = snippets
        self.layout = layout
        self.tileSize = CGFloat(tileSize)
        self.collapsed = collapsed
        if contentChanged {
            self.sections = sections
            self.revision = revision
        }
        if contentChanged || collapseChanged {
            indexPaths.removeAll(keepingCapacity: true)
            for (sectionIndex, section) in self.sections.enumerated() where !collapsed.contains(section.key) {
                for (itemIndex, item) in section.items.enumerated() {
                    indexPaths[item.path] = IndexPath(item: itemIndex, section: sectionIndex)
                }
            }
        }
        if layoutChanged || sizeChanged {
            let isGrid = layout == .grid
            flowLayout.minimumInteritemSpacing = isGrid ? 4 : 0
            flowLayout.minimumLineSpacing = isGrid ? 6 : 0
        }
        if contentChanged || layoutChanged || collapseChanged {
            collectionView.reloadData()
        } else if sizeChanged {
            flowLayout.invalidateLayout()
            reconfigureVisibleItems()
        }
        if !contentChanged, !newlyCollapsed.isEmpty {
            keepHeaderInView(of: newlyCollapsed)
        }
        apply(selection)
    }

    /// Folding a group from its pinned header, deep inside it, would leave the list showing whatever
    /// slid up into that place: go to the folded group's header instead.
    private func keepHeaderInView(of keys: Set<SectionKey>) {
        guard let section = sections.firstIndex(where: { keys.contains($0.key) }) else { return }
        collectionView.layoutSubtreeIfNeeded()
        let header = flowLayout.layoutAttributesForSupplementaryView(ofKind: NSCollectionView.elementKindSectionHeader,
                                                                     at: IndexPath(item: 0, section: section))
        if let header, header.frame.minY < collectionView.visibleRect.minY {
            collectionView.scroll(NSPoint(x: 0, y: header.frame.minY))
        }
    }

    // MARK: - Data source

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        collapsed.contains(sections[section].key) ? 0 : sections[section].items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let identifier = layout == .grid ? TileItem.identifier : RowItem.identifier
        let cell = collectionView.makeItem(withIdentifier: identifier, for: indexPath)
        configure(cell, at: indexPath)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: SectionHeaderView.identifier, for: indexPath)
        if let header = view as? SectionHeaderView {
            let section = sections[indexPath.section]
            header.configure(title: section.key.title, count: section.items.count, isCollapsed: collapsed.contains(section.key)) {
                [weak self] everyGroup in
                self?.onToggleSection(section.key, everyGroup)
            }
        }
        return view
    }

    private func configure(_ cell: NSCollectionViewItem, at indexPath: IndexPath) {
        let item = sections[indexPath.section].items[indexPath.item]
        let snippet = snippets[item.path]
        if let tile = cell as? TileItem {
            tile.configure(item: item, caption: snippet ?? item.caption, side: tileSize, thumbnails: thumbnails)
        } else if let row = cell as? RowItem {
            row.configure(item: item, secondary: snippet ?? item.folder.abbreviatingHome, isSnippet: snippet != nil, thumbnails: thumbnails)
        }
    }

    private func reconfigureVisibleItems() {
        for cell in collectionView.visibleItems() {
            if let indexPath = collectionView.indexPath(for: cell) { configure(cell, at: indexPath) }
        }
    }

    // MARK: - Layout

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        switch layout {
        case .grid:
            NSSize(width: tileSize + Metrics.tilePadding.width, height: tileSize + Metrics.tilePadding.height)
        case .list:
            NSSize(width: max(240, collectionView.bounds.width - Metrics.sectionInset.left - Metrics.sectionInset.right),
                   height: Metrics.rowHeight)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> NSSize {
        // A list that isn't split into groups has nothing to title.
        sections[section].key == .all ? .zero : NSSize(width: 0, height: Metrics.headerHeight)
    }

    /// A folded group is just its header: no room kept for the items it doesn't show.
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        insetForSectionAt section: Int) -> NSEdgeInsets {
        collapsed.contains(sections[section].key) ? NSEdgeInsetsZero : Metrics.sectionInset
    }

    // MARK: - Selection

    private var selectedItems: [FileItem] {
        collectionView.selectionIndexPaths.sorted().compactMap { indexPath in
            guard indexPath.section < sections.count, indexPath.item < sections[indexPath.section].items.count else { return nil }
            return sections[indexPath.section].items[indexPath.item]
        }
    }

    private func apply(_ selection: Set<String>) {
        let wanted = Set(selection.compactMap { indexPaths[$0] })
        if wanted != collectionView.selectionIndexPaths {
            collectionView.selectionIndexPaths = wanted
        }
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selectionDidChange()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selectionDidChange()
    }

    func selectionDidChange() {
        onSelectionChange(Set(selectedItems.map(\.path)))
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
    }

    // MARK: - Actions

    @objc func openSelection() {
        files.open(selectedItems)
    }

    @objc func revealSelection() {
        files.revealInFinder(selectedItems)
    }

    @objc func copySelectionPaths() {
        files.copyPaths(selectedItems)
    }

    @objc func trashSelection() {
        guard !selectedItems.isEmpty else { return }
        onTrashRequest()
    }

    @objc func togglePreview() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else if !selectedItems.isEmpty {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, key: String = "") {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        add(String(localized: "Open"), #selector(openSelection))
        add(String(localized: "Quick Look"), #selector(togglePreview))
        menu.addItem(.separator())
        add(String(localized: "Show in Finder"), #selector(revealSelection))
        add(String(localized: "Copy Path"), #selector(copySelectionPaths))
        menu.addItem(.separator())
        add(String(localized: "Move to Trash"), #selector(trashSelection), key: "\u{8}")
        return menu
    }

    /// Items can be dragged out to other apps as files.
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        URL(fileURLWithPath: sections[indexPath.section].items[indexPath.item].path) as NSURL
    }

    // MARK: - Quick Look

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let items = selectedItems
        guard index < items.count else { return nil }
        return URL(fileURLWithPath: items[index].path) as NSURL
    }

    /// Arrow keys and the space bar keep working on the list while the preview is up.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        collectionView.keyDown(with: event)
        return true
    }
}

/// The collection view with a file browser's manners: double-click and Return open, the space bar
/// previews, a right-click selects what's under it first.
final class FinderCollectionView: NSCollectionView {
    weak var controller: ItemCollectionController?

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let delete: UInt16 = 51
        static let downArrow: UInt16 = 125
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            controller?.togglePreview()
        } else if event.keyCode == KeyCode.returnKey
                    || (event.keyCode == KeyCode.downArrow && event.modifierFlags.contains(.command)) {
            controller?.openSelection()
        } else if event.keyCode == KeyCode.delete, event.modifierFlags.contains(.command) {
            controller?.trashSelection()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil {
            controller?.openSelection()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
            controller?.selectionDidChange()
        }
        return controller?.contextMenu()
    }

    // Quick Look declares these on NSObject without an actor, but only ever calls them on the main
    // thread, with the shared panel.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            let panel = QLPreviewPanel.shared()
            panel?.dataSource = controller
            panel?.delegate = controller
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            let panel = QLPreviewPanel.shared()
            panel?.dataSource = nil
            panel?.delegate = nil
        }
    }
}

/// A flow layout that lays out again when its width changes, so list rows follow the window.
final class WidthTrackingFlowLayout: NSCollectionViewFlowLayout {
    private var width: CGFloat = 0

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        defer { width = newBounds.width }
        return newBounds.width != width || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}

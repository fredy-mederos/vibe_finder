import AppKit
import FinderDomain

/// What a tile and a row share: a thumbnail that loads when the cell comes on screen, and the look of
/// a selected cell.
class ThumbnailCell: NSCollectionViewItem {
    let thumbnailView = NSImageView()
    /// Sits behind the cell's content and lights up when it's selected.
    let highlightView = NSView()
    private var loading: Task<Void, Never>?
    private var path: String?

    override func loadView() {
        view = NSView()
        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 8
        highlightView.layer?.cornerCurve = .continuous
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        // A page of text is white on white without it.
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        thumbnailView.wantsLayer = true
        thumbnailView.shadow = shadow
        for subview in [highlightView, thumbnailView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
    }

    override var isSelected: Bool {
        didSet { updateHighlight() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        loading = nil
        path = nil
        thumbnailView.image = nil
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateHighlight()
    }

    func loadThumbnail(for item: FileItem, side: CGFloat, thumbnails: any ThumbnailProviding) {
        loading?.cancel()
        path = item.path
        if let cached = thumbnails.cachedThumbnail(for: item, side: side) {
            thumbnailView.image = cached
            return
        }
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        loading = Task { [weak self] in
            let image = await thumbnails.thumbnail(for: item, side: side, scale: scale)
            // The cell may have been reused for another item while the thumbnail was being made.
            guard !Task.isCancelled, let self, self.path == item.path else { return }
            self.thumbnailView.image = image
        }
    }

    private func updateHighlight() {
        let accent = NSColor.controlAccentColor
        highlightView.layer?.backgroundColor = isSelected ? accent.withAlphaComponent(0.2).cgColor : nil
        highlightView.layer?.borderColor = isSelected ? accent.cgColor : nil
        highlightView.layer?.borderWidth = isSelected ? 2 : 0
    }

    static func label(size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

/// A grid cell: the thumbnail, the name on up to two lines, a caption and the size.
final class TileItem: ThumbnailCell {
    static let identifier = NSUserInterfaceItemIdentifier("TileItem")

    private let nameField = ThumbnailCell.label(size: 12, color: .labelColor)
    private let captionField = ThumbnailCell.label(size: 11, color: .secondaryLabelColor)
    private let sizeField = ThumbnailCell.label(size: 11, color: .tertiaryLabelColor)

    override func loadView() {
        super.loadView()
        nameField.alignment = .center
        nameField.maximumNumberOfLines = 2
        nameField.lineBreakMode = .byWordWrapping
        nameField.cell?.truncatesLastVisibleLine = true
        captionField.alignment = .center
        captionField.lineBreakMode = .byTruncatingTail
        sizeField.alignment = .center
        sizeField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        view.addSubview(nameField)
        view.addSubview(captionField)
        view.addSubview(sizeField)
        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            thumbnailView.heightAnchor.constraint(equalTo: thumbnailView.widthAnchor),
            highlightView.topAnchor.constraint(equalTo: thumbnailView.topAnchor, constant: -5),
            highlightView.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 5),
            highlightView.leadingAnchor.constraint(equalTo: thumbnailView.leadingAnchor, constant: -5),
            highlightView.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 5),
            nameField.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            captionField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 1),
            captionField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            captionField.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            sizeField.topAnchor.constraint(equalTo: captionField.bottomAnchor, constant: 1),
            sizeField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            sizeField.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
        ])
    }

    func configure(item: FileItem, caption: String, side: CGFloat, thumbnails: any ThumbnailProviding) {
        nameField.stringValue = item.name
        captionField.stringValue = caption
        sizeField.stringValue = item.sizeText
        view.toolTip = item.path.abbreviatingHome
        loadThumbnail(for: item, side: side, thumbnails: thumbnails)
    }
}

/// A list row: a small thumbnail, the name over where it is (or the text that matched), then what
/// it is, its date and its size.
final class RowItem: ThumbnailCell {
    static let identifier = NSUserInterfaceItemIdentifier("RowItem")

    private let nameField = ThumbnailCell.label(size: 13, color: .labelColor)
    private let secondaryField = ThumbnailCell.label(size: 11, color: .secondaryLabelColor)
    private let typeField = ThumbnailCell.label(size: 12, color: .secondaryLabelColor)
    private let dateField = ThumbnailCell.label(size: 12, color: .secondaryLabelColor)
    private let sizeField = ThumbnailCell.label(size: 12, color: .secondaryLabelColor)
    private static let thumbnailSide: CGFloat = 32

    override func loadView() {
        super.loadView()
        secondaryField.lineBreakMode = .byTruncatingHead
        typeField.lineBreakMode = .byTruncatingTail
        sizeField.alignment = .right
        dateField.alignment = .right
        sizeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        for label in [nameField, secondaryField, typeField, dateField, sizeField] { view.addSubview(label) }
        NSLayoutConstraint.activate([
            highlightView.topAnchor.constraint(equalTo: view.topAnchor, constant: 1),
            highlightView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -1),
            highlightView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            thumbnailView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailSide),
            thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
            nameField.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            nameField.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: typeField.leadingAnchor, constant: -12),
            secondaryField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            secondaryField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 1),
            secondaryField.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            sizeField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            sizeField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sizeField.widthAnchor.constraint(equalToConstant: 76),
            dateField.trailingAnchor.constraint(equalTo: sizeField.leadingAnchor, constant: -12),
            dateField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dateField.widthAnchor.constraint(equalToConstant: 96),
            typeField.trailingAnchor.constraint(equalTo: dateField.leadingAnchor, constant: -12),
            typeField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            typeField.widthAnchor.constraint(equalToConstant: 190),
        ])
    }

    func configure(item: FileItem, secondary: String, isSnippet: Bool, thumbnails: any ThumbnailProviding) {
        nameField.stringValue = item.name
        secondaryField.stringValue = secondary
        // A matched text reads from its start; a path matters most at its end.
        secondaryField.lineBreakMode = isSnippet ? .byTruncatingTail : .byTruncatingHead
        typeField.stringValue = [item.subkind, item.detail].filter { !$0.isEmpty }.joined(separator: " · ")
        dateField.stringValue = item.modified.formatted(date: .abbreviated, time: .omitted)
        sizeField.stringValue = item.sizeText
        view.toolTip = item.path.abbreviatingHome
        loadThumbnail(for: item, side: Self.thumbnailSide, thumbnails: thumbnails)
    }
}

/// A group's header: a disclosure chevron, the title and how many items it has, over a material so
/// pinned headers stay readable. The whole header is a button that folds or unfolds the group.
final class SectionHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("SectionHeaderView")

    private let chevron = NSImageView()
    private let titleField = ThumbnailCell.label(size: 13, color: .labelColor, weight: .semibold)
    private let countField = ThumbnailCell.label(size: 12, color: .secondaryLabelColor)
    private let button = NSButton(title: "", target: nil, action: nil)
    private var onToggle: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let background = NSVisualEffectView()
        background.material = .headerView
        background.blendingMode = .withinWindow
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        chevron.contentTintColor = .secondaryLabelColor
        // Draws nothing itself: it only makes the whole header clickable, and a button to assistive apps.
        button.isTransparent = true
        button.target = self
        button.action = #selector(toggle)
        button.toolTip = String(localized: "Collapse or expand this group. Option-click to do it for every group.")
        for subview in [background, chevron, titleField, countField, button] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            titleField.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 4),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            countField.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
            countField.firstBaselineAnchor.constraint(equalTo: titleField.firstBaselineAnchor),
            countField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
        ])
        titleField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// - Parameter onToggle: called on a click, with `true` when every group should follow (Option).
    func configure(title: String, count: Int, isCollapsed: Bool, onToggle: @escaping (Bool) -> Void) {
        titleField.stringValue = title
        countField.stringValue = count.formatted()
        // "forward" points the way text runs, so it's right in right-to-left languages too.
        chevron.image = NSImage(systemSymbolName: isCollapsed ? "chevron.forward" : "chevron.down", accessibilityDescription: nil)
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(isCollapsed ? String(localized: "collapsed") : String(localized: "expanded"))
        self.onToggle = onToggle
    }

    @objc private func toggle() {
        onToggle(NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
    }
}

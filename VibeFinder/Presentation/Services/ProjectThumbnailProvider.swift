import AppKit
import FinderDomain

/// What stands for a kind of project when it has no picture of its own: a symbol or a couple of
/// letters on a color. Plain marks rather than anybody's logo.
struct ProjectBadge {
    enum Mark {
        case symbol(String)
        case letters(String)
    }

    let mark: Mark
    let color: NSColor

    /// - Parameter projectType: the project's subkind, as `ProjectMarkers` names it.
    static func badge(forProjectType projectType: String) -> ProjectBadge {
        func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }
        switch projectType {
        case "Xcode": return ProjectBadge(mark: .symbol("hammer.fill"), color: rgb(0.08, 0.46, 0.98))
        case "Swift Package": return ProjectBadge(mark: .symbol("swift"), color: rgb(0.94, 0.38, 0.20))
        case "Flutter": return ProjectBadge(mark: .letters("Fl"), color: rgb(0.16, 0.66, 0.92))
        case "Gradle": return ProjectBadge(mark: .letters("Gr"), color: rgb(0.02, 0.55, 0.50))
        case "Node": return ProjectBadge(mark: .letters("JS"), color: rgb(0.24, 0.58, 0.25))
        case "Rust": return ProjectBadge(mark: .letters("Rs"), color: rgb(0.70, 0.36, 0.16))
        case "Go": return ProjectBadge(mark: .letters("Go"), color: rgb(0.00, 0.62, 0.80))
        case "Python": return ProjectBadge(mark: .letters("Py"), color: rgb(0.21, 0.44, 0.66))
        case "Ruby": return ProjectBadge(mark: .letters("Rb"), color: rgb(0.80, 0.20, 0.18))
        case "Maven": return ProjectBadge(mark: .letters("Mv"), color: rgb(0.58, 0.25, 0.55))
        case "PHP": return ProjectBadge(mark: .letters("php"), color: rgb(0.45, 0.46, 0.70))
        case "CMake": return ProjectBadge(mark: .letters("C"), color: rgb(0.33, 0.43, 0.58))
        default: return ProjectBadge(mark: .symbol("arrow.triangle.branch"), color: rgb(0.42, 0.42, 0.46))
        }
    }
}

/// Folders all look alike, so projects get told apart on their folder: the project's own picture
/// (its app's icon, its site's favicon) with a small mark of its technology, or a large mark when it
/// has no picture. Everything else goes to the provider it wraps.
final class ProjectThumbnailProvider: ThumbnailProviding {
    private let base: any ThumbnailProviding
    private let cache = NSCache<NSString, NSImage>()

    init(base: any ThumbnailProviding) {
        self.base = base
        cache.countLimit = 500
    }

    func cachedThumbnail(for item: FileItem, side: CGFloat) -> NSImage? {
        guard item.kind == .projects else { return base.cachedThumbnail(for: item, side: side) }
        return cache.object(forKey: key(for: item, side: side))
    }

    func thumbnail(for item: FileItem, side: CGFloat, scale: CGFloat) async -> NSImage? {
        guard item.kind == .projects else { return await base.thumbnail(for: item, side: side, scale: scale) }
        let key = key(for: item, side: side)
        if let cached = cache.object(forKey: key) { return cached }
        let folder = await base.thumbnail(for: item, side: side, scale: scale) ?? NSWorkspace.shared.icon(forFile: item.path)
        guard !Task.isCancelled else { return nil }
        let artwork = item.artworkPath.flatMap { NSImage(contentsOfFile: $0) }
        let image = Self.compose(folder: folder, artwork: artwork, badge: .badge(forProjectType: item.subkind),
                                 side: ThumbnailSize.bucket(for: side), scale: scale)
        cache.setObject(image, forKey: key)
        return image
    }

    private func key(for item: FileItem, side: CGFloat) -> NSString {
        "\(item.path)|\(item.modified.timeIntervalSinceReferenceDate)|\(item.subkind)|\(item.artworkPath ?? "")|\(Int(ThumbnailSize.bucket(for: side)))" as NSString
    }

    // MARK: - Drawing

    /// Where things sit on a folder icon, as fractions of its side (the origin is bottom left).
    private enum Layout {
        /// The middle of the folder's front, under its tab.
        static let front = CGPoint(x: 0.5, y: 0.42)
        static let artworkSide: CGFloat = 0.46
        static let cornerBadge = CGPoint(x: 0.80, y: 0.19)
        static let cornerBadgeSide: CGFloat = 0.27
        static let centerBadgeSide: CGFloat = 0.40
    }

    private static func compose(folder: NSImage, artwork: NSImage?, badge: ProjectBadge, side: CGFloat, scale: CGFloat) -> NSImage {
        let pixels = Int((side * max(scale, 1)).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return folder }
        bitmap.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        folder.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        if let artwork {
            draw(artwork, centeredAt: Layout.front, side: Layout.artworkSide * side, in: side)
            draw(badge, centeredAt: Layout.cornerBadge, diameter: Layout.cornerBadgeSide * side, in: side)
        } else {
            draw(badge, centeredAt: Layout.front, diameter: Layout.centerBadgeSide * side, in: side)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// The project's picture as an app icon would sit there: rounded, with a soft shadow.
    private static func draw(_ artwork: NSImage, centeredAt center: CGPoint, side: CGFloat, in canvas: CGFloat) {
        let box = NSRect(x: center.x * canvas - side / 2, y: center.y * canvas - side / 2, width: side, height: side)
        // A favicon isn't always square: fit it, don't stretch it.
        let ratio = artwork.size.width > 0 && artwork.size.height > 0 ? artwork.size.width / artwork.size.height : 1
        let fitted = ratio >= 1
            ? NSRect(x: box.minX, y: box.midY - side / ratio / 2, width: side, height: side / ratio)
            : NSRect(x: box.midX - side * ratio / 2, y: box.minY, width: side * ratio, height: side)
        let shape = NSBezierPath(roundedRect: fitted, xRadius: side * 0.2, yRadius: side * 0.2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = max(1, canvas * 0.02)
        shadow.shadowOffset = NSSize(width: 0, height: -max(0.5, canvas * 0.01))
        shadow.set()
        NSColor.white.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        artwork.draw(in: fitted)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func draw(_ badge: ProjectBadge, centeredAt center: CGPoint, diameter: CGFloat, in canvas: CGFloat) {
        let circle = NSRect(x: center.x * canvas - diameter / 2, y: center.y * canvas - diameter / 2, width: diameter, height: diameter)
        let ring = max(1, diameter * 0.07)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: -ring, dy: -ring)).fill()
        badge.color.setFill()
        NSBezierPath(ovalIn: circle).fill()
        switch badge.mark {
        case .symbol(let name):
            let configuration = NSImage.SymbolConfiguration(pointSize: diameter * 0.5, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
            let size = symbol.size
            symbol.draw(in: NSRect(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2, width: size.width, height: size.height))
        case .letters(let letters):
            // Fewer letters, bigger letters.
            let pointSize = diameter * (letters.count > 2 ? 0.34 : letters.count == 2 ? 0.44 : 0.56)
            let font = NSFont.systemFont(ofSize: pointSize, weight: .heavy)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? font
            let text = NSAttributedString(string: letters, attributes: [.font: rounded, .foregroundColor: NSColor.white])
            let size = text.size()
            text.draw(at: NSPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
        }
    }
}

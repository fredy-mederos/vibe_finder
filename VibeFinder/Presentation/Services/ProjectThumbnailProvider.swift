import AppKit
import FinderDomain

/// The mark of what a project is for, drawn into its folder the way the system marks its own
/// folders (Documents, Downloads): one flat shape in a darker shade of the folder.
enum ProjectMark {
    case symbol(String)
    /// The head of Android's robot; SF Symbols has no such symbol, so it's drawn here.
    case robot

    /// - Parameter subkind: the project's platform, as `ProjectPlatform` names it.
    static func mark(forPlatform subkind: String) -> ProjectMark {
        switch ProjectPlatform.allCases.first(where: { $0.subkind == subkind }) ?? .other {
        case .iOS: .symbol("iphone")
        case .android: .robot
        case .mobile: .symbol("apps.iphone")
        case .web: .symbol("globe")
        case .server: .symbol("server.rack")
        case .desktop: .symbol("desktopcomputer")
        case .game: .symbol("gamecontroller.fill")
        case .library: .symbol("shippingbox.fill")
        case .other: .symbol("chevron.left.forwardslash.chevron.right")
        }
    }
}

/// Folders all look alike, so projects get told apart on their folder: what the project is for as
/// a mark in the folder itself, and the project's own picture (its app's icon, its site's favicon) in
/// a small circle at the corner when it has one. Everything else goes to the provider it wraps.
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
        let image = Self.compose(folder: folder, artwork: artwork, mark: .mark(forPlatform: item.subkind),
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
        static let markSide: CGFloat = 0.36
        static let artwork = CGPoint(x: 0.77, y: 0.22)
        static let artworkSide: CGFloat = 0.36
    }

    /// A darker shade of the folder's own blue, as if pressed into it.
    private static let markColor = NSColor(srgbRed: 0.02, green: 0.25, blue: 0.52, alpha: 0.55)

    private static func compose(folder: NSImage, artwork: NSImage?, mark: ProjectMark, side: CGFloat, scale: CGFloat) -> NSImage {
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
        draw(mark, centeredAt: Layout.front, side: Layout.markSide * side, in: side)
        if let artwork {
            draw(artwork, inCircleAt: Layout.artwork, diameter: Layout.artworkSide * side, in: side)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func draw(_ mark: ProjectMark, centeredAt center: CGPoint, side: CGFloat, in canvas: CGFloat) {
        let middle = NSPoint(x: center.x * canvas, y: center.y * canvas)
        switch mark {
        case .symbol(let name):
            let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.78, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [markColor]))
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
            // Symbols come in every shape: fit the longer side, keep the proportions.
            let fit = min(side / symbol.size.width, side / symbol.size.height, 1.25)
            let size = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
            symbol.draw(in: NSRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height))
        case .robot:
            drawRobot(in: NSRect(x: middle.x - side / 2, y: middle.y - side * 0.3, width: side, height: side * 0.6))
        }
    }

    /// A half disc with two eyes and two antennae.
    private static func drawRobot(in rect: NSRect) {
        let radius = rect.width / 2
        let base = NSPoint(x: rect.midX, y: rect.minY)
        let head = NSBezierPath()
        head.windingRule = .evenOdd
        head.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        head.appendArc(withCenter: base, radius: radius, startAngle: 0, endAngle: 180)
        head.close()
        for direction in [-1.0, 1.0] as [CGFloat] {
            let eye = radius * 0.1
            head.appendOval(in: NSRect(x: base.x + direction * radius * 0.42 - eye, y: base.y + radius * 0.4 - eye, width: eye * 2, height: eye * 2))
        }
        markColor.setFill()
        head.fill()
        let antennae = NSBezierPath()
        for direction in [-1.0, 1.0] as [CGFloat] {
            antennae.move(to: NSPoint(x: base.x + direction * radius * 0.48, y: base.y + radius * 0.84))
            antennae.line(to: NSPoint(x: base.x + direction * radius * 0.68, y: base.y + radius * 1.18))
        }
        antennae.lineWidth = radius * 0.1
        antennae.lineCapStyle = .round
        markColor.setStroke()
        antennae.stroke()
    }

    /// The project's own picture in a small circle with a white rim, like a profile picture.
    private static func draw(_ artwork: NSImage, inCircleAt center: CGPoint, diameter: CGFloat, in canvas: CGFloat) {
        let circle = NSRect(x: center.x * canvas - diameter / 2, y: center.y * canvas - diameter / 2, width: diameter, height: diameter)
        let rim = max(1, diameter * 0.06)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = max(1, canvas * 0.02)
        shadow.shadowOffset = NSSize(width: 0, height: -max(0.5, canvas * 0.008))
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: -rim, dy: -rim)).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: circle).addClip()
        // Fill the circle: a wide or tall picture is cropped at its middle rather than squeezed.
        let size = artwork.size
        let fill = size.width > 0 && size.height > 0 ? max(diameter / size.width, diameter / size.height) : 1
        let drawn = NSSize(width: size.width * fill, height: size.height * fill)
        artwork.draw(in: NSRect(x: circle.midX - drawn.width / 2, y: circle.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
    }
}

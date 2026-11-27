// Draws Vibe Finder's icon (a map of what's on disk, one block per family of content, with a
// magnifying glass) and writes every size the asset catalog needs.
// Usage: swift scripts/make-icon.swift
import AppKit

// MARK: - Drawing tools

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The colors the app gives its families of kinds.
enum Palette {
    static let pictures = rgb(0xFF9F0A)
    static let video = rgb(0xFF375F)
    static let audio = rgb(0xBF5AF2)
    static let documents = rgb(0x2F7BF6)
    static let work = rgb(0x30B0C7)
    static let files = rgb(0x8E8E93)
}

/// A bitmap of the given pixel size, drawn on the 1024-point canvas macOS icons are designed on.
func render(pixels: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// The rounded square every macOS icon sits in.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)

func shadowed(blur: CGFloat, offset: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -offset)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func clipped(to path: NSBezierPath, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// The body with its drop shadow, filled by `fill` (clipped to its shape).
func drawBody(_ fill: () -> Void) {
    shadowed(blur: 24, offset: 12, alpha: 0.3) {
        NSColor.black.setFill()
        body.fill()
    }
    clipped(to: body, fill)
}

func symbol(_ name: String, pointSize: CGFloat, color: NSColor, center: NSPoint, weight: NSFont.Weight = .bold) {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
    let size = image.size
    image.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
}

// MARK: - The icon

func drawIcon() {
    drawBody {
        NSGradient(starting: rgb(0x2F86FA), ending: rgb(0x5A3BD8))?.draw(in: NSRect(x: 100, y: 100, width: 824, height: 824), angle: -55)
    }
    let card = NSBezierPath(roundedRect: NSRect(x: 206, y: 222, width: 612, height: 612), xRadius: 84, yRadius: 84)
    shadowed(blur: 26, offset: 12, alpha: 0.28) {
        NSColor.white.setFill()
        card.fill()
    }
    // Each kind takes the room its files take, as in a disk map.
    let cells: [(rect: NSRect, color: NSColor, symbol: String?, size: CGFloat)] = [
        (NSRect(x: 236, y: 478, width: 300, height: 326), Palette.pictures, "photo.fill", 120),
        (NSRect(x: 236, y: 252, width: 300, height: 210), Palette.video, "film.fill", 96),
        (NSRect(x: 552, y: 586, width: 236, height: 218), Palette.documents, "doc.text.fill", 96),
        (NSRect(x: 552, y: 424, width: 236, height: 146), Palette.audio, "music.note", 78),
        (NSRect(x: 552, y: 252, width: 110, height: 156), Palette.work, nil, 0),
        (NSRect(x: 678, y: 252, width: 110, height: 156), Palette.files, nil, 0),
    ]
    for cell in cells {
        cell.color.setFill()
        NSBezierPath(roundedRect: cell.rect, xRadius: 30, yRadius: 30).fill()
        if let name = cell.symbol {
            symbol(name, pointSize: cell.size, color: .white, center: NSPoint(x: cell.rect.midX, y: cell.rect.midY), weight: .semibold)
        }
    }
    let badge = NSRect(x: 664, y: 132, width: 236, height: 236)
    shadowed(blur: 20, offset: 10, alpha: 0.3) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: badge).fill()
    }
    symbol("magnifyingglass", pointSize: 118, color: rgb(0x1D5FE0), center: NSPoint(x: badge.midX, y: badge.midY), weight: .heavy)
}

// MARK: - Output

let iconSet = URL(fileURLWithPath: "VibeFinder/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale, drawIcon).representation(using: .png, properties: [:])?.write(to: iconSet.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: iconSet.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")

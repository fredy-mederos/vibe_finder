// Draws Vibe Finder's icon (four tiles, one per family of content, on a blue background) and writes
// every size the asset catalog needs.
// Usage: swift scripts/make-icon.swift
import AppKit

let iconSet = URL(fileURLWithPath: "VibeFinder/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Everything is laid out on the 1024-point canvas macOS icons are designed on.
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.35, green: 0.25, blue: 0.85, alpha: 1))?.draw(in: shape, angle: -70)

    let tiles: [(symbol: String, color: NSColor)] = [
        ("photo.fill", .systemOrange), ("doc.text.fill", .systemBlue),
        ("film.fill", .systemPink), ("music.note", .systemPurple),
    ]
    let (side, gap): (CGFloat, CGFloat) = (290, 44)
    let origin = NSPoint(x: body.midX - side - gap / 2, y: body.midY - side - gap / 2)
    for (index, tile) in tiles.enumerated() {
        let (column, row) = (CGFloat(index % 2), CGFloat(1 - index / 2))
        let rect = NSRect(x: origin.x + column * (side + gap), y: origin.y + row * (side + gap), width: side, height: side)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 64, yRadius: 64).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: 150, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tile.color]))
        if let symbol = NSImage(systemSymbolName: tile.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(pixels: points * scale).representation(using: .png, properties: [:])?
            .write(to: iconSet.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")

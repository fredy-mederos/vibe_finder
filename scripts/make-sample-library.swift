// Builds a small made-up library (screenshots, photos, documents, videos, projects…) to try
// Vibe Finder on, without pointing it at anybody's real folders.
// Usage: swift scripts/make-sample-library.swift <folder>
import AppKit
import AVFoundation

guard CommandLine.arguments.count > 1 else {
    print("usage: swift scripts/make-sample-library.swift <folder>")
    exit(1)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
let day: TimeInterval = 24 * 3600

func url(_ path: String) -> URL {
    let url = root.appendingPathComponent(path)
    try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    return url
}

/// Sets how long ago the file was last changed, so the library has a history.
func age(_ path: String, days: Double) {
    try? fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -days * day)], ofItemAtPath: url(path).path)
}

func write(_ path: String, _ text: String, days: Double = 3) {
    try? Data(text.utf8).write(to: url(path))
    age(path, days: days)
}

// MARK: - Pictures

/// A picture of the given pixel size: a background and lines of text on it, like a screen would show.
func picture(_ path: String, width: Int, height: Int, background: NSColor, lines: [String] = [], jpeg: Bool = false, days: Double) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let unit = CGFloat(min(width, height)) / 20
    if !lines.isEmpty {
        // A bar on top and a button, so it reads as an app's screen.
        NSColor.black.withAlphaComponent(0.08).setFill()
        NSRect(x: 0, y: CGFloat(height) - unit * 2.4, width: CGFloat(width), height: unit * 2.4).fill()
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: unit * 2, y: unit * 2, width: CGFloat(width) - unit * 4, height: unit * 2),
                     xRadius: unit / 2, yRadius: unit / 2).fill()
    }
    for (index, line) in lines.enumerated() {
        let font = NSFont.systemFont(ofSize: index == 0 ? unit * 1.3 : unit * 0.9, weight: index == 0 ? .bold : .regular)
        let text = NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.black])
        text.draw(at: NSPoint(x: unit * 2, y: CGFloat(height) - unit * 5.5 - CGFloat(index) * unit * 2))
    }
    NSGraphicsContext.restoreGraphicsState()
    let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) : rep.representation(using: .png, properties: [:])
    try? data?.write(to: url(path))
    age(path, days: days)
}

/// A soft gradient, standing in for a photo.
func photo(_ path: String, from: NSColor, to: NSColor, days: Double) {
    let (width, height) = (1600, 1200)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(starting: from, ending: to)?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 70)
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: 1100, y: 800, width: 220, height: 220)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.write(to: url(path))
    age(path, days: days)
}

let paper = NSColor(white: 0.97, alpha: 1)
picture("Desktop/Simulator Screenshot - iPhone 16 Pro - 2026-11-26 at 10.11.12.png", width: 1206, height: 2622, background: paper,
        lines: ["Sign in to Acme", "Email address", "Password", "Forgot your password?"], days: 0.2)
picture("Desktop/Simulator Screenshot - iPhone 16 Pro - 2026-11-24 at 16.02.40.png", width: 1206, height: 2622, background: paper,
        lines: ["Your cart", "Oat milk  2 × 1.89", "Sourdough bread  3.40", "Checkout"], days: 3)
picture("Desktop/Screenshot 2026-11-25 at 09.30.00.png", width: 1440, height: 900, background: paper,
        lines: ["Quarterly revenue dashboard", "North region  +12 %", "South region  −3 %"], days: 2)
picture("Downloads/Screenshot_20261101-101112.png", width: 1080, height: 2400, background: NSColor(calibratedRed: 0.93, green: 0.97, blue: 0.93, alpha: 1),
        lines: ["Boarding pass", "Berlin → Lisbon", "Gate B12  Seat 14A"], days: 26)
// No telling name: only its pixel size (an iPhone's screen) says what it is.
picture("Downloads/stuff/old/12-34-56.png", width: 1179, height: 2556, background: paper,
        lines: ["Settings", "Notifications", "Privacy", "About"], days: 80)
// Neither name nor size: left for the image classifier.
picture("Documents/misc/untitled-3.png", width: 1000, height: 700, background: paper,
        lines: ["Error 404", "The page you are looking for does not exist", "Go back home"], days: 200)
picture("Documents/assets/star_1.png", width: 64, height: 64, background: .systemYellow, days: 300)
picture("Documents/assets/star_2.png", width: 64, height: 64, background: .systemOrange, days: 300)
picture("Downloads/ChatGPT Image 3 nov 2026, 10_11_12.png", width: 1024, height: 1024, background: .systemTeal, days: 24)
photo("Pictures/2025/summer/IMG_2041.jpeg", from: .systemBlue, to: .systemYellow, days: 420)
photo("Pictures/2025/summer/IMG_2042.jpeg", from: .systemIndigo, to: .systemOrange, days: 420)
photo("Downloads/holiday.jpg", from: .systemGreen, to: .systemTeal, days: 40)
photo("Downloads/photo_2026-10-02_18-20-11.jpg", from: .systemPink, to: .systemPurple, days: 56)
write("Documents/assets/logo.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><circle cx=\"5\" cy=\"5\" r=\"4\" fill=\"teal\"/></svg>", days: 300)

// MARK: - Documents

func pdf(_ path: String, _ lines: [String], days: Double) {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let context = CGContext(url(path) as CFURL, mediaBox: &box, nil) else { return }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for (index, line) in lines.enumerated() {
        let font = NSFont.systemFont(ofSize: index == 0 ? 22 : 12, weight: index == 0 ? .bold : .regular)
        NSAttributedString(string: line, attributes: [.font: font]).draw(at: NSPoint(x: 60, y: 760 - CGFloat(index) * 26))
    }
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    age(path, days: days)
}

pdf("Downloads/Invoice 2026-031.pdf", ["Invoice 2026-031", "Acme Bicycles Ltd.", "1 × City bicycle, 7 gears      1,180.00 EUR",
                                       "1 × Helmet                        60.00 EUR", "Total due: 1,240.00 EUR", "Payment within 14 days"], days: 9)
pdf("Documents/papers/home/scan0042.pdf", ["Rental agreement", "This agreement is made between the landlord and the tenant.",
                                            "The tenant agrees to pay the monthly rent on the first day of each month.",
                                            "Either party may terminate this contract with three months notice."], days: 400)
pdf("Documents/manuals/Espresso machine.pdf", ["User manual", "Fill the water tank before first use.",
                                               "Descale the machine every three months.", "Troubleshooting: the pump makes noise"], days: 150)
write("Documents/notes/ideas.md", "# Ideas\n\n- A finder by type of content\n- Sourdough starter schedule\n- Plan the trip to Lisbon\n", days: 1)
write("Documents/notes/todo.txt", "Renew passport\nCall the plumber about the kitchen tap\nBuy oat milk\n", days: 5)
write("Documents/finance/budget 2026.csv", "month,rent,groceries,savings\nJanuary,900,310,400\nFebruary,900,295,420\n", days: 60)
write("Downloads/letter.rtf", "{\\rtf1\\ansi Dear neighbours,\\par the courtyard will be repainted next week.\\par Kind regards}", days: 12)

// MARK: - Sound and video

func run(_ tool: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

let spoken = url("Music/voice.aiff").path
run("/usr/bin/say", ["-o", spoken, "Remember to water the plants and to call the plumber tomorrow morning."])
run("/usr/bin/afconvert", ["-f", "m4af", "-d", "aac", spoken, url("Documents/New Recording 3.m4a").path])
run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16", spoken, url("Documents/assets/sounds/notify.wav").path])
run("/usr/bin/afconvert", ["-f", "m4af", "-d", "aac", spoken, url("Music/Albums/Acme Band/01 First Song.m4a").path])
try? fileManager.removeItem(atPath: spoken)
age("Documents/New Recording 3.m4a", days: 6)
age("Music/Albums/Acme Band/01 First Song.m4a", days: 500)

/// A second of flat color as a movie.
func video(_ path: String, width: Int, height: Int, color: NSColor, days: Double) {
    let file = url(path)
    try? fileManager.removeItem(at: file)
    guard let writer = try? AVAssetWriter(outputURL: file, fileType: path.hasSuffix(".mov") ? .mov : .mp4) else { return }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let rgb = color.usingColorSpace(.deviceRGB) ?? .gray
    for frame in 0..<30 {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { continue }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let shade = 0.6 + 0.4 * Double(frame) / 30
            for offset in stride(from: 0, to: CVPixelBufferGetBytesPerRow(buffer) * height, by: 4) {
                bytes[offset] = UInt8(rgb.blueComponent * 255 * shade)
                bytes[offset + 1] = UInt8(rgb.greenComponent * 255 * shade)
                bytes[offset + 2] = UInt8(rgb.redComponent * 255 * shade)
                bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { usleep(2000) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    age(path, days: days)
}

video("Movies/RPReplay_Final1700000000.mov", width: 886, height: 1920, color: .systemIndigo, days: 15)
video("Desktop/Simulator Screen Recording - iPhone 16 Pro - 2026-11-20 at 12.00.00.mp4", width: 1206, height: 2622, color: .systemTeal, days: 7)
video("Downloads/Acme Band - First Song (Official Video).mp4", width: 1280, height: 720, color: .systemPink, days: 30)
video("Downloads/videoplayback (3).mp4", width: 1280, height: 720, color: .systemGray, days: 45)
video("Downloads/Sourdough bread tutorial for beginners.mp4", width: 1280, height: 720, color: .systemBrown, days: 70)
video("Movies/family/WhatsApp Video 2026-08-02 at 6.10.11 PM.mp4", width: 720, height: 1280, color: .systemGreen, days: 117)

// MARK: - Projects and other files

write("Documents/code/acme-app/Package.swift", "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"AcmeApp\")\n", days: 2)
write("Documents/code/acme-app/.git/HEAD", "ref: refs/heads/main\n", days: 2)
write("Documents/code/acme-app/Sources/AcmeApp/main.swift", "print(\"Hello from Acme\")\n", days: 2)
write("Documents/code/acme-app/README.md", "# Acme App\n\nA sample project.\n", days: 2)
picture("Documents/code/acme-app/docs/logo.png", width: 512, height: 512, background: .systemTeal, days: 90)
write("Documents/code/web-shop/package.json", "{\n  \"name\": \"web-shop\",\n  \"version\": \"1.0.0\"\n}\n", days: 35)
write("Documents/code/web-shop/index.js", "console.log('shop')\n", days: 35)
write("Documents/code/web-shop/node_modules/left-pad/index.js", "module.exports = () => ''\n", days: 35)
write("Documents/code/snippets/resize.py", "from PIL import Image\n\ndef resize(path):\n    return Image.open(path).resize((64, 64))\n", days: 190)
write("Documents/keys/AuthKey_ABC123.p8", "-----BEGIN PRIVATE KEY-----\nnot a real key\n-----END PRIVATE KEY-----\n", days: 220)
write("Downloads/Acme Installer.dmg", "not a real disk image", days: 18)
write("Downloads/fonts/Brand-Regular.ttf", "not a real font", days: 130)
write("Downloads/server.log", "2026-11-01 10:00:00 INFO started\n2026-11-01 10:00:02 WARN slow query\n", days: 26)
run("/usr/bin/zip", ["-j", "-q", url("Downloads/backup-october.zip").path, url("Documents/notes/todo.txt").path])
age("Downloads/backup-october.zip", days: 28)

print("Sample library in \(root.path)")

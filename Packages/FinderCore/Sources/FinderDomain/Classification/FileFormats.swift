import Foundation
import Synchronization

/// What a file's extension alone says: its kind and the format's name.
public struct FileFormat: Sendable, Equatable {
    public var kind: Kind
    public var subkind: String

    public init(_ kind: Kind, _ subkind: String) {
        self.kind = kind
        self.subkind = subkind
    }
}

/// The table of known extensions, with the system's opinion as a fallback for the ones it doesn't list.
public final class FileFormatCatalog: Sendable {
    private let resolver: (any FileTypeResolving)?
    private let resolved = Mutex<[String: FileFormat]>([:])

    public init(resolver: (any FileTypeResolving)? = nil) {
        self.resolver = resolver
    }

    public func format(forExtension ext: String, isPackage: Bool) -> FileFormat {
        if let known = Self.table[ext] { return known }
        if ext.isEmpty { return FileFormat(.other, isPackage ? "Bundles" : "No extension") }
        if let cached = resolved.withLock({ $0[ext] }) { return cached }
        let format = resolve(ext, isPackage: isPackage)
        resolved.withLock { $0[ext] = format }
        return format
    }

    private func resolve(_ ext: String, isPackage: Bool) -> FileFormat {
        let name = ext.uppercased()
        switch resolver?.family(forExtension: ext) {
        case .image: return FileFormat(.images, name)
        case .video: return FileFormat(.videos, name)
        case .audio: return FileFormat(.music, name)
        case .sourceCode: return FileFormat(.code, name)
        case .archive: return FileFormat(.archives, name)
        case .font: return FileFormat(.fonts, name)
        case .spreadsheet: return FileFormat(.spreadsheets, name)
        case .presentation: return FileFormat(.presentations, name)
        case .text: return FileFormat(.notes, "Plain text")
        case nil: return FileFormat(.other, isPackage ? "Bundles" : "." + ext)
        }
    }

    /// Formats a camera, a screen or a drawing app can all produce: the name or the pixels decide.
    public static let rasterExtensions: Set<String> = ["png", "jpg", "jpeg", "jfif", "webp", "tiff", "tif", "bmp", "avif"]

    /// Raster formats plus the ones only cameras write.
    public static let photographicExtensions: Set<String> = rasterExtensions.union(["heic", "heif"])

    static let table: [String: FileFormat] = {
        var table: [String: FileFormat] = [:]
        func add(_ kind: Kind, _ subkind: String, _ extensions: String) {
            for ext in extensions.split(separator: " ") { table[String(ext)] = FileFormat(kind, subkind) }
        }
        add(.apps, "Apps", "app")
        // Only cameras and phones write these.
        add(.photos, "Camera", "heic heif cr2 cr3 nef arw dng raf orf rw2 raw")
        add(.photos, "JPEG", "jpg jpeg jfif")
        add(.images, "PNG", "png")
        add(.images, "WebP", "webp")
        add(.images, "TIFF", "tiff tif")
        add(.images, "Bitmap", "bmp")
        add(.images, "AVIF", "avif")
        add(.images, "Vector", "svg")
        add(.images, "GIFs", "gif")
        add(.images, "Icons", "ico icns")
        add(.videos, "MP4", "mp4 m4v")
        add(.videos, "QuickTime", "mov")
        add(.videos, "Other formats", "avi mkv webm wmv flv mpg mpeg 3gp mts m2ts")
        add(.music, "MP3", "mp3")
        add(.music, "AAC", "m4a aac m4p")
        add(.music, "Lossless", "flac alac ape wav aif aiff")
        add(.music, "Other formats", "ogg wma")
        add(.music, "MIDI", "mid midi")
        add(.audio, "Voice & recordings", "opus amr caf")
        add(.books, "Audiobooks", "m4b aax")
        add(.pdfs, "PDF", "pdf")
        add(.documents, "Word", "doc docx dot dotx")
        add(.documents, "Pages", "pages")
        add(.documents, "Rich text", "rtf rtfd")
        add(.documents, "OpenDocument", "odt")
        add(.documents, "LaTeX", "tex")
        add(.notes, "Markdown", "md markdown mdx")
        add(.notes, "Plain text", "txt text")
        add(.books, "eBooks", "epub mobi azw azw3 ibooks")
        add(.spreadsheets, "Excel", "xls xlsx xlsm")
        add(.spreadsheets, "Numbers", "numbers")
        add(.spreadsheets, "CSV", "csv tsv")
        add(.spreadsheets, "OpenDocument", "ods")
        add(.presentations, "PowerPoint", "ppt pptx pps ppsx")
        add(.presentations, "OpenDocument", "odp")
        add(.archives, "ZIP", "zip")
        add(.archives, "Compressed", "rar 7z tar gz tgz bz2 xz zst")
        add(.archives, "Java", "jar aar war")
        add(.archives, "Xcode archives", "xcarchive")
        add(.installers, "Disk images", "dmg iso")
        add(.installers, "Installer packages", "pkg mpkg xip")
        add(.installers, "iOS apps", "ipa")
        add(.installers, "Android apps", "apk aab xapk")
        add(.design, "Sketch", "sketch")
        add(.design, "Figma", "fig")
        add(.design, "Adobe", "psd ai eps indd xd")
        add(.design, "Affinity", "afdesign afphoto afpub")
        add(.design, "Pixelmator", "pxd pxm")
        add(.design, "3D", "usdz usd obj fbx glb gltf stl blend dae")
        add(.fonts, "TrueType", "ttf ttc")
        add(.fonts, "OpenType", "otf")
        add(.fonts, "Web fonts", "woff woff2")
        add(.code, "Swift", "swift")
        add(.code, "Kotlin & Java", "kt kts java gradle groovy")
        add(.code, "JavaScript & TypeScript", "js mjs cjs jsx ts tsx vue svelte")
        add(.code, "Python", "py ipynb")
        add(.code, "C family", "c cc cpp cxx h hpp hh m mm")
        add(.code, "Web", "html htm css scss sass less")
        add(.code, "Shell", "sh zsh bash fish command")
        add(.code, "Other languages", "rb go rs cs php dart lua pl sql r scala ex exs erl hs clj proto tf")
        add(.code, "Data & config",
            "json xml yml yaml toml plist strings xcstrings xcconfig properties ini conf env lock pbxproj storyboard xib entitlements")
        add(.keys, "Certificates", "cer crt pem der p7b")
        add(.keys, "Private keys", "p12 pfx p8 jks keystore")
        add(.keys, "Provisioning profiles", "mobileprovision provisionprofile")
        add(.keys, "Signing requests", "certsigningrequest csr")
        add(.keys, "PGP & SSH", "pub asc gpg")
        add(.other, "Logs", "log err")
        add(.other, "Calendar", "ics")
        add(.other, "Contacts", "vcf")
        add(.other, "Wallet passes", "pkpass")
        add(.other, "Databases", "sqlite sqlite3 db realm")
        add(.other, "Web links", "webloc url webarchive")
        add(.other, "Media libraries", "photoslibrary musiclibrary tvlibrary imovielibrary")
        return table
    }()
}

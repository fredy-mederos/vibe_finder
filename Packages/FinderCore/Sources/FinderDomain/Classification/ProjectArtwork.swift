import Foundation

/// A file that may be the picture a project goes by.
public struct ArtworkCandidate: Sendable, Equatable {
    public var path: String
    /// How sure the place it's in makes it (see `ProjectArtworkRules.score`).
    public var score: Int
    /// Folders between the project's root and the file.
    public var depth: Int
    /// The file's size: among versions of the same icon, the biggest is the most detailed.
    public var weight: Int64

    public init(path: String, score: Int, depth: Int, weight: Int64) {
        self.path = path
        self.score = score
        self.depth = depth
        self.weight = weight
    }
}

/// Where a page or a manifest says its icon is.
public enum IconReference: Sendable, Equatable {
    /// A path as it was written: from the file's folder, or from the site's root when it starts with "/".
    case link(String)
    /// The picture itself, written into the page as a `data:` address.
    case inline(data: Data, fileExtension: String)
}

/// An icon a project's own files name, with how much that naming counts.
public struct DeclaredIcon: Sendable, Equatable {
    public var reference: IconReference
    public var score: Int

    public init(reference: IconReference, score: Int) {
        self.reference = reference
        self.score = score
    }
}

/// Where projects keep the picture that stands for them: an app's icon, a site's favicon. Only
/// conventions the tools themselves set, so the same project always gets the same picture.
public enum ProjectArtworkRules {
    /// How deep under the project's root an icon is still looked for.
    public static let maxDepth = 7

    private static let iconSetImages: Set<String> = ["png", "jpg", "jpeg"]
    private static let launcherNames: Set<String> = ["ic_launcher", "ic_launcher_round"]
    private static let launcherDensities = ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"]
    /// Icons web projects ship for home screens, biggest first.
    private static let touchIcons = ["android-chrome-512x512.png", "logo512.png", "icon-512.png", "apple-touch-icon.png",
                                     "apple-touch-icon-precomposed.png", "android-chrome-192x192.png", "logo192.png", "icon-192.png"]
    private static let favicons = ["favicon.svg", "favicon.png", "favicon.ico"]
    private static let plainIcons = ["icon.svg", "icon.png", "logo.svg", "logo.png"]
    /// Folders a generic "icon.png" has to be in (or the project's root) to count.
    private static let assetFolders: Set<String> = ["public", "static", "web", "www", "app", "src", "assets", "images", "img", "resources"]

    /// How much a file's place says "this is the project's icon"; nil when it says nothing.
    /// - Parameters:
    ///   - folderName: the name of the folder the file is in; empty for the project's root.
    public static func score(fileName: String, folderName: String) -> Int? {
        let name = fileName.lowercased()
        let folder = folderName.lowercased()
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        // An Xcode asset catalog's app icon: the surest sign, more so when it's the one called AppIcon.
        if folder.hasSuffix(".appiconset") {
            guard iconSetImages.contains(ext) else { return nil }
            return folder.hasPrefix("appicon") ? 110 : 100
        }
        // An Android launcher icon; the densest version is the sharpest.
        if folder.hasPrefix("mipmap-"), launcherNames.contains(stem), ext == "png" || ext == "webp" {
            let density = launcherDensities.firstIndex { folder == "mipmap-" + $0 } ?? -1
            return density < 0 ? nil : 85 + density
        }
        if let index = touchIcons.firstIndex(of: name) {
            return 79 - index
        }
        if let index = favicons.firstIndex(of: name) {
            return 65 - index
        }
        if let index = plainIcons.firstIndex(of: name), folder.isEmpty || assetFolders.contains(folder) {
            return 55 - index
        }
        return nil
    }

    // MARK: - Icons a project declares

    private static let manifestNames: Set<String> = ["manifest.json", "manifest.webmanifest", "site.webmanifest"]
    /// A web app's manifest lists its big icons: surer than a file's name, less than a native app's icon.
    private static let manifestScore = 82
    /// A page's own icon is small, often a dot: it counts less than a file named like a big icon
    /// (see `touchIcons`), more than one merely named favicon.
    private static let pageScores = (touchIcon: 71, icon: 70)
    /// Pages deeper than this aren't the site's front page.
    public static let maxDeclarationDepth = 3

    /// The file may say where the project's icon is: a site's front page, a web app's manifest.
    public static func declaresIcons(fileName: String) -> Bool {
        let name = fileName.lowercased()
        return name == "index.html" || manifestNames.contains(name)
    }

    /// The icons the file names, each with its score.
    public static func declaredIcons(fileName: String, text: String) -> [DeclaredIcon] {
        fileName.lowercased() == "index.html" ? icons(inPage: text) : icons(inManifest: text)
    }

    /// `<link rel="icon" href="…">` and `rel="apple-touch-icon"`.
    private static func icons(inPage html: String) -> [DeclaredIcon] {
        guard let tags = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive),
              let attributes = try? NSRegularExpression(pattern: #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return [] }
        var icons: [DeclaredIcon] = []
        let whole = html as NSString
        for tag in tags.matches(in: html, range: NSRange(location: 0, length: whole.length)) {
            let text = whole.substring(with: tag.range) as NSString
            var values: [String: String] = [:]
            for match in attributes.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                let value = (2...4).lazy.map { match.range(at: $0) }.first { $0.location != NSNotFound }
                values[text.substring(with: match.range(at: 1)).lowercased()] = value.map { text.substring(with: $0) } ?? ""
            }
            let relations = Set((values["rel"] ?? "").lowercased().split(separator: " ").map(String.init))
            guard let address = values["href"], !address.isEmpty else { continue }
            let score: Int
            if relations.contains("apple-touch-icon") || relations.contains("apple-touch-icon-precomposed") {
                score = pageScores.touchIcon
            } else if relations.contains("icon") {
                score = pageScores.icon
            } else {
                continue
            }
            if let reference = reference(for: address) {
                icons.append(DeclaredIcon(reference: reference, score: score))
            }
        }
        return icons
    }

    /// The biggest of a web app manifest's `icons`.
    private static func icons(inManifest json: String) -> [DeclaredIcon] {
        guard let manifest = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let entries = manifest["icons"] as? [[String: Any]] else { return [] }
        func size(_ entry: [String: Any]) -> Int {
            // "192x192 512x512" or, for a vector that fits any size, "any".
            let sizes = (entry["sizes"] as? String ?? "").lowercased()
            if sizes.contains("any") { return .max }
            return sizes.split { !$0.isNumber }.compactMap { Int($0) }.max() ?? 0
        }
        guard let largest = entries.filter({ $0["src"] is String }).max(by: { size($0) < size($1) }),
              let address = largest["src"] as? String, let reference = reference(for: address) else { return [] }
        return [DeclaredIcon(reference: reference, score: manifestScore)]
    }

    private static let inlineExtensions = ["image/svg+xml": "svg", "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif",
                                           "image/webp": "webp", "image/x-icon": "ico", "image/vnd.microsoft.icon": "ico"]

    /// An address from a page or a manifest as something to look for; nil for what isn't in the
    /// project (an address on the web) or can't be shown.
    static func reference(for address: String) -> IconReference? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.lowercased().hasPrefix("data:") else {
            let path = address.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
            return path.isEmpty || path.contains("://") || path.hasPrefix("//") ? nil : .link(path)
        }
        // data:<type>[;base64],<the picture>
        guard let comma = address.firstIndex(of: ",") else { return nil }
        let header = address[address.index(address.startIndex, offsetBy: 5)..<comma].lowercased().split(separator: ";")
        let payload = String(address[address.index(after: comma)...])
        guard let type = header.first, let fileExtension = inlineExtensions[String(type)] else { return nil }
        let data = header.contains("base64")
            ? Data(base64Encoded: payload.removingPercentEncoding ?? payload)
            : (payload.removingPercentEncoding ?? payload).data(using: .utf8)
        return data.flatMap { $0.isEmpty ? nil : .inline(data: $0, fileExtension: fileExtension) }
    }

    /// Folders worth entering although the system shows them as one item: asset catalogs and the
    /// icon sets inside them.
    public static func isArtworkContainer(_ folderName: String) -> Bool {
        let ext = (folderName as NSString).pathExtension.lowercased()
        return ext == "xcassets" || ext == "appiconset"
    }

    /// The candidate to use: the surest place, then the one closest to the root, then the most
    /// detailed, then by path so the choice never depends on the order files were found in.
    public static func best(_ candidates: [ArtworkCandidate]) -> ArtworkCandidate? {
        candidates.min { first, second in
            if first.score != second.score { return first.score > second.score }
            if first.depth != second.depth { return first.depth < second.depth }
            if first.weight != second.weight { return first.weight > second.weight }
            return first.path < second.path
        }
    }
}

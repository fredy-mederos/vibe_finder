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
            return density < 0 ? nil : 80 + density
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

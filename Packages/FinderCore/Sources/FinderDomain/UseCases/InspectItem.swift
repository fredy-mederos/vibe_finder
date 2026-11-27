import Foundation

/// One entry of a folder, as a listing gives it.
public struct FolderEntry: Sendable, Equatable {
    public var name: String
    public var isFolder: Bool

    public init(name: String, isFolder: Bool) {
        self.name = name
        self.isFolder = isFolder
    }
}

/// A folder's contents as a short tree: enough to see how it's laid out, not everything in it.
public struct OutlineNode: Sendable, Equatable, Identifiable {
    public var path: String
    public var name: String
    public var isFolder: Bool
    public var children: [OutlineNode]
    /// How many of this folder's entries were left out to keep the outline short.
    public var omitted: Int

    public init(path: String, name: String, isFolder: Bool, children: [OutlineNode] = [], omitted: Int = 0) {
        self.path = path
        self.name = name
        self.isFolder = isFolder
        self.children = children
        self.omitted = omitted
    }

    public var id: String { path }
}

/// What looking closer at one item adds to what the list already shows.
public struct ItemInspection: Sendable, Equatable {
    /// For a folder: what's inside, a couple of levels deep.
    public var outline: [OutlineNode]
    /// Entries at the folder's top level left out of the outline.
    public var omitted: Int
    /// The start of the text found in the file (its own, or read from the picture).
    public var text: String?

    public init(outline: [OutlineNode] = [], omitted: Int = 0, text: String? = nil) {
        self.outline = outline
        self.omitted = omitted
        self.text = text
    }
}

/// Gathers what the inspector shows beyond an item's basic facts: a project's folder as a short tree,
/// and for everything else the text the index found in it.
public struct InspectItem: Sendable {
    private let listing: any FolderListing
    private let texts: any IndexedTextReading
    private let policy: ScanPolicy
    /// Levels of folders shown.
    private let depth: Int
    private let entriesPerFolder: Int
    private let excerptLength: Int

    public init(listing: any FolderListing, texts: any IndexedTextReading, policy: ScanPolicy = .standard, depth: Int = 2,
                entriesPerFolder: Int = 12, excerptLength: Int = 1200) {
        self.listing = listing
        self.texts = texts
        self.policy = policy
        self.depth = depth
        self.entriesPerFolder = entriesPerFolder
        self.excerptLength = excerptLength
    }

    /// Blocking: call it off the main thread.
    public func execute(_ item: FileItem) -> ItemInspection {
        if item.kind == .projects {
            let (nodes, omitted) = outline(ofFolderAt: item.path, levels: depth)
            return ItemInspection(outline: nodes, omitted: omitted)
        }
        let text = texts.indexedText(forPath: item.path)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ItemInspection(text: text.flatMap { $0.isEmpty ? nil : String($0.prefix(excerptLength)) })
    }

    /// Folders first, then files, by name; hidden entries left out, and no more than a handful per folder.
    private func outline(ofFolderAt path: String, levels: Int) -> (nodes: [OutlineNode], omitted: Int) {
        let entries = listing.entries(ofFolderAtPath: path)
            .filter { !policy.isHidden($0.name) }
            .sorted { first, second in
                first.isFolder != second.isFolder ? first.isFolder : first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        let nodes = entries.prefix(entriesPerFolder).map { entry -> OutlineNode in
            let entryPath = path + "/" + entry.name
            // Dependencies, build output and packages are shown, not opened: what's in them isn't the project's layout.
            guard entry.isFolder, levels > 1, !policy.skipsDirectory(named: entry.name, inProject: true),
                  !policy.packageExtensions.contains((entry.name as NSString).pathExtension.lowercased()) else {
                return OutlineNode(path: entryPath, name: entry.name, isFolder: entry.isFolder)
            }
            let (children, omitted) = outline(ofFolderAt: entryPath, levels: levels - 1)
            return OutlineNode(path: entryPath, name: entry.name, isFolder: true, children: children, omitted: omitted)
        }
        return (nodes, max(0, entries.count - entriesPerFolder))
    }
}

import Foundation
import FinderDomain

/// Lists a folder with FileManager: names, and which of them are folders.
public struct FileSystemFolderListing: FolderListing {
    public init() {}

    public func entries(ofFolderAtPath path: String) -> [FolderEntry] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.map { entry in
            FolderEntry(name: entry.lastPathComponent, isFolder: (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true)
        }
    }
}

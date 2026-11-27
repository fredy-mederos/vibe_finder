import Foundation
import FinderDomain

/// Adds up the space every file under a folder takes on disk, hidden ones included: what Finder
/// would say the folder weighs.
public struct FileSystemFolderSizer: FolderSizing {
    public init() {}

    public func sizeOfFolder(atPath path: String) -> Int64? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        // A folder inside that can't be read is skipped, not a reason to give up on the rest.
        guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: path, isDirectory: true),
                                                         includingPropertiesForKeys: Array(keys), options: [],
                                                         errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

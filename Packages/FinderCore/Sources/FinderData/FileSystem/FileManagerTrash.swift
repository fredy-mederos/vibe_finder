import Foundation
import FinderDomain

/// Moves files to the user's Trash with FileManager, the same place Finder puts them: they keep
/// "Put Back" and nothing is deleted.
public struct FileManagerTrash: ItemTrashing {
    public init() {}

    public func moveToTrash(_ paths: [String]) async -> [TrashFailure] {
        var failures: [TrashFailure] = []
        for path in paths {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            } catch {
                failures.append(TrashFailure(path: path, reason: error.localizedDescription))
            }
        }
        return failures
    }
}

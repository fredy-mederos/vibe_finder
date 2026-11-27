import Foundation

/// What happened to the items the user sent to the Trash.
public struct TrashOutcome: Sendable, Equatable {
    /// Paths now in the Trash.
    public var trashed: [String]
    public var failures: [TrashFailure]

    public init(trashed: [String], failures: [TrashFailure]) {
        self.trashed = trashed
        self.failures = failures
    }
}

/// Moves items to the Trash: the only change Vibe Finder ever makes to the user's files, and one
/// they can undo from the Trash.
public struct TrashItems: Sendable {
    private let trash: any ItemTrashing

    public init(trash: any ItemTrashing) {
        self.trash = trash
    }

    public func execute(_ items: [FileItem]) async -> TrashOutcome {
        let paths = Self.outermost(items.map(\.path))
        let failures = await trash.moveToTrash(paths)
        let failed = Set(failures.map(\.path))
        return TrashOutcome(trashed: paths.filter { !failed.contains($0) }, failures: failures)
    }

    /// The library without what went to the Trash: the items themselves and, for a folder (a project),
    /// everything that was inside it.
    public func remaining(of items: [FileItem], after outcome: TrashOutcome) -> [FileItem] {
        guard !outcome.trashed.isEmpty else { return items }
        let trashed = Set(outcome.trashed)
        let folders = outcome.trashed.map { $0 + "/" }
        return items.filter { item in
            !trashed.contains(item.path) && !folders.contains { item.path.hasPrefix($0) }
        }
    }

    /// A folder takes what's inside it along: paths under another chosen path are left out, so nothing
    /// is asked to move twice.
    static func outermost(_ paths: [String]) -> [String] {
        let unique = Array(Set(paths)).sorted()
        return unique.filter { path in
            !unique.contains { other in other != path && path.hasPrefix(other + "/") }
        }
    }
}

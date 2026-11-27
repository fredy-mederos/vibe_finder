import AppKit
import FinderDomain

/// What the user can do with items. Vibe Finder only looks: nothing here moves, renames or deletes.
protocol FileActing {
    func open(_ items: [FileItem])
    func revealInFinder(_ items: [FileItem])
    func copyPaths(_ items: [FileItem])
    func openFolder(_ path: String)
}

struct WorkspaceFileActions: FileActing {
    func open(_ items: [FileItem]) {
        for item in items {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
    }

    func revealInFinder(_ items: [FileItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map { URL(fileURLWithPath: $0.path) })
    }

    func copyPaths(_ items: [FileItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}

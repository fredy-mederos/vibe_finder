import Foundation
import FinderDomain

/// Looks through a project's folder for the picture it goes by, where `ProjectArtworkRules` says
/// projects keep one. Dependencies and build output are never entered, and the search gives up after
/// a fixed number of folders, so a huge repository costs no more than a small one.
public struct FileSystemProjectArtworkFinder: ProjectArtworkFinding {
    private let policy: ScanPolicy
    /// Folders looked into per project, at most.
    private let folderBudget: Int

    public init(policy: ScanPolicy = .standard, folderBudget: Int = 3000) {
        self.policy = policy
        self.folderBudget = folderBudget
    }

    public func artworkPath(forProjectAt path: String) -> String? {
        var candidates: [ArtworkCandidate] = []
        // Breadth first, in name order: what's nearest the root is seen first, whatever the disk's order.
        var queue: [(path: String, name: String, depth: Int)] = [(path, "", 0)]
        var visited = 0
        while !queue.isEmpty, visited < folderBudget {
            let folder = queue.removeFirst()
            visited += 1
            let url = URL(fileURLWithPath: folder.path, isDirectory: true)
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys) else { continue }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = entry.lastPathComponent
                guard !policy.isHidden(name), !policy.isSealed(name),
                      let values = try? entry.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                let entryPath = folder.path + "/" + name
                if values.isDirectory == true {
                    if folder.depth < ProjectArtworkRules.maxDepth, enters(name) {
                        queue.append((entryPath, name, folder.depth + 1))
                    }
                } else if let score = ProjectArtworkRules.score(fileName: name, folderName: folder.name) {
                    candidates.append(ArtworkCandidate(path: entryPath, score: score, depth: folder.depth, weight: Int64(values.fileSize ?? 0)))
                }
            }
        }
        return ProjectArtworkRules.best(candidates)?.path
    }

    /// Ordinary folders, plus the asset catalogs icons live in; no other package, and nothing a scan skips.
    private func enters(_ name: String) -> Bool {
        if ProjectArtworkRules.isArtworkContainer(name) { return true }
        if policy.skipsDirectory(named: name, inProject: true) { return false }
        return !policy.packageExtensions.contains((name as NSString).pathExtension.lowercased())
    }
}

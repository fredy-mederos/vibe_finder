import Foundation
import FinderDomain

/// Looks through a project's folder for the picture it goes by, where `ProjectArtworkRules` says
/// projects keep one: files in the places tools put icons, and the icons a site's front page or a
/// web app's manifest name. Dependencies and build output are never entered, and the search gives up
/// after a fixed number of folders, so a huge repository costs no more than a small one.
public struct FileSystemProjectArtworkFinder: ProjectArtworkFinding {
    private let policy: ScanPolicy
    /// Where pictures written inside a page (`data:` addresses) are kept as files; nil leaves them out.
    private let cacheDirectory: URL?
    /// Folders looked into per project, at most.
    private let folderBudget: Int
    private static let maxDeclarationBytes = 512 * 1024

    public init(policy: ScanPolicy = .standard, cacheDirectory: URL? = nil, folderBudget: Int = 3000) {
        self.policy = policy
        self.cacheDirectory = cacheDirectory
        self.folderBudget = folderBudget
    }

    public func artworkPath(forProjectAt path: String) -> String? {
        var candidates: [ArtworkCandidate] = []
        var inlineCount = 0
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
                    continue
                }
                if let score = ProjectArtworkRules.score(fileName: name, folderName: folder.name) {
                    candidates.append(ArtworkCandidate(path: entryPath, score: score, depth: folder.depth, weight: Int64(values.fileSize ?? 0)))
                }
                if folder.depth <= ProjectArtworkRules.maxDeclarationDepth, ProjectArtworkRules.declaresIcons(fileName: name),
                   let text = FileSystemProjectInspector.text(atPath: entryPath, limit: Self.maxDeclarationBytes) {
                    for icon in ProjectArtworkRules.declaredIcons(fileName: name, text: text) {
                        guard let file = file(for: icon.reference, declaredIn: folder.path, project: path, number: &inlineCount) else { continue }
                        candidates.append(ArtworkCandidate(path: file.path, score: icon.score, depth: folder.depth, weight: file.size))
                    }
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

    // MARK: - Declared icons

    /// The file a declared icon is: one of the project's own, or a picture written into the page,
    /// saved so it can be shown like any other.
    private func file(for reference: IconReference, declaredIn folder: String, project: String, number: inout Int) -> (path: String, size: Int64)? {
        switch reference {
        case .link(let address):
            // "/icon.png" is from the site's root, which build tools serve from a "public" folder.
            let fromRoot = address.hasPrefix("/")
            let relative = fromRoot ? String(address.dropFirst()) : address
            let bases = fromRoot ? [folder + "/public", project + "/public", folder, project] : [folder, folder + "/public"]
            for base in bases {
                let path = URL(fileURLWithPath: base + "/" + relative).standardizedFileURL.path
                // An address may climb out with "..": only what's inside the project counts.
                guard path.hasPrefix(project + "/"), let size = Self.regularFileSize(path) else { continue }
                return (path, size)
            }
            return nil
        case .inline(let data, let fileExtension):
            guard let cacheDirectory else { return nil }
            number += 1
            let file = cacheDirectory.appendingPathComponent("\(Self.stableName(for: project))-\(number).\(fileExtension)")
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                if (try? Data(contentsOf: file)) != data { try data.write(to: file, options: .atomic) }
            } catch {
                return nil
            }
            return (file.path, Int64(data.count))
        }
    }

    private static func regularFileSize(_ path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// The same name for the same project on every launch (FNV-1a; `hashValue` changes between runs).
    private static func stableName(for path: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

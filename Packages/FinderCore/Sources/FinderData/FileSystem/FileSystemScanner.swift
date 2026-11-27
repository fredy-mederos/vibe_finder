import Foundation
import FinderDomain

/// Walks the user's folders with FileManager. Packages count as one item, projects are found by
/// their markers, and what the policy skips (dependencies, build output, hidden files) is never entered.
public struct FileSystemScanner: LibraryScanning {
    private let policy: ScanPolicy

    public init(policy: ScanPolicy = .standard) {
        self.policy = policy
    }

    public func scan(_ request: ScanRequest) -> ScanOutput {
        let walk = Walk(policy: policy)
        for folder in request.folders {
            walk.walk(folder, project: nil, depth: 0)
        }
        for folder in request.applicationFolders {
            walk.collectApplications(in: folder, depth: 0)
        }
        return ScanOutput(files: walk.files, unreadableFolders: walk.unreadable)
    }
}

/// What a project's folder adds up to while it's walked.
private final class ProjectTally {
    let type: String
    var fileCount = 0
    var size: Int64 = 0
    var latest = Date.distantPast

    init(type: String) {
        self.type = type
    }

    func add(size: Int64, modified: Date) {
        fileCount += 1
        self.size += size
        if modified > latest { latest = modified }
    }
}

/// One scan's state.
private final class Walk {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
    ]
    private static let keySet = Set(keys)

    private let policy: ScanPolicy
    private let fileManager = FileManager.default
    private var seen: Set<String> = []
    private(set) var files: [FileFacts] = []
    private(set) var unreadable: [String] = []

    init(policy: ScanPolicy) {
        self.policy = policy
    }

    func walk(_ folder: String, project: ProjectTally?, depth: Int) {
        guard depth <= policy.maxDepth else { return }
        let folderURL = URL(fileURLWithPath: folder, isDirectory: true)
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: Self.keys)
        } catch {
            // A missing or forbidden subfolder is just skipped; a root the user chose is worth telling.
            if depth == 0 { unreadable.append(folder) }
            return
        }
        // The folders the user chose are never projects themselves: a stray package.json in Documents
        // must not hide everything under it.
        var project = project
        var ownProject: ProjectTally?
        if project == nil, depth > 0, let type = ProjectMarkers.projectType(entries: entries.lazy.map(\.lastPathComponent)) {
            ownProject = ProjectTally(type: type)
            project = ownProject
        }
        for url in entries {
            let name = url.lastPathComponent
            if policy.isHidden(name) { continue }
            guard let values = try? url.resourceValues(forKeys: Self.keySet), values.isSymbolicLink != true else { continue }
            let path = folder + "/" + name
            let ext = (name as NSString).pathExtension.lowercased()
            let isDirectory = values.isDirectory == true
            let isPackage = isDirectory && (values.isPackage == true || policy.packageExtensions.contains(ext))
            if isDirectory, !isPackage {
                if !policy.skipsDirectory(named: name, inProject: project != nil) {
                    walk(path, project: project, depth: depth + 1)
                }
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            let modified = values.contentModificationDate ?? .distantPast
            project?.add(size: size, modified: modified)
            let role: FileFacts.Role = !isPackage ? .file : ext == "app" ? .application(version: Self.version(ofAppAt: path)) : .package
            append(FileFacts(
                path: path, size: size, modified: modified, created: values.creationDate ?? modified, role: role,
                inProject: project != nil,
                isScreenCapture: policy.screenCaptureExtensions.contains(ext) && Self.isScreenCapture(path)
            ))
        }
        if let ownProject {
            let values = try? folderURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let modified = ownProject.fileCount > 0 ? ownProject.latest : values?.contentModificationDate ?? .distantPast
            append(FileFacts(path: folder, size: ownProject.size, modified: modified, created: values?.creationDate ?? modified,
                             role: .project(type: ownProject.type, fileCount: ownProject.fileCount)))
        }
    }

    /// Apps in an Applications folder and in the folders right inside it (Utilities, a vendor's folder).
    func collectApplications(in folder: String, depth: Int) {
        let folderURL = URL(fileURLWithPath: folder, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: Self.keys) else { return }
        for url in entries {
            let name = url.lastPathComponent
            if policy.isHidden(name) { continue }
            guard let values = try? url.resourceValues(forKeys: Self.keySet), values.isDirectory == true,
                  values.isSymbolicLink != true else { continue }
            let path = folder + "/" + name
            if (name as NSString).pathExtension.lowercased() == "app" {
                let modified = values.contentModificationDate ?? .distantPast
                append(FileFacts(path: path, modified: modified, created: values.creationDate ?? modified,
                                 role: .application(version: Self.version(ofAppAt: path))))
            } else if depth == 0, values.isPackage != true {
                collectApplications(in: path, depth: 1)
            }
        }
    }

    /// Folders can overlap (~/Applications is an applications folder and may be under a chosen one).
    private func append(_ facts: FileFacts) {
        if seen.insert(facts.path).inserted { files.append(facts) }
    }

    private static func version(ofAppAt path: String) -> String? {
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        return info?["CFBundleShortVersionString"] as? String
    }

    /// macOS marks its own screenshots and screen recordings with this attribute.
    private static func isScreenCapture(_ path: String) -> Bool {
        getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }
}

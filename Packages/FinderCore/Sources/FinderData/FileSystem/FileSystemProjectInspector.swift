import Foundation
import FinderDomain

/// Reads what `ProjectPlatformRules` asks for from a project's folder: the names at its root, the
/// manifests its tools keep there, and its Xcode project file. A handful of small files, never the sources.
public struct FileSystemProjectInspector: ProjectInspecting {
    private static let maxManifestBytes = 512 * 1024
    /// Xcode project files of big apps run to several megabytes.
    private static let maxProjectFileBytes = 16 * 1024 * 1024
    /// Folders under the root looked into for a module's build file, at most.
    private static let maxModules = 40

    public init() {}

    public func facts(forProjectAt path: String) -> ProjectFacts {
        let fileManager = FileManager.default
        var facts = ProjectFacts(rootEntries: Set((try? fileManager.contentsOfDirectory(atPath: path)) ?? []))
        for relativePath in ProjectPlatformRules.manifestPaths {
            if let text = Self.text(atPath: path + "/" + relativePath, limit: Self.maxManifestBytes) {
                facts.manifests[relativePath] = text
            }
        }
        // Modules: in name order, so a project with more of them than the limit is always read the same way.
        for folder in facts.rootEntries.sorted().filter({ !$0.hasPrefix(".") }).prefix(Self.maxModules) {
            for name in ProjectPlatformRules.moduleManifestNames where facts.manifests[folder + "/" + name] == nil {
                if let text = Self.text(atPath: path + "/" + folder + "/" + name, limit: Self.maxManifestBytes) {
                    facts.manifests[folder + "/" + name] = text
                }
            }
        }
        for relativePath in ProjectPlatformRules.probedPaths where fileManager.fileExists(atPath: path + "/" + relativePath) {
            facts.existing.insert(relativePath)
        }
        if let project = facts.rootEntries.filter({ $0.hasSuffix(".xcodeproj") }).sorted().first {
            facts.xcodeProject = Self.text(atPath: path + "/" + project + "/project.pbxproj", limit: Self.maxProjectFileBytes)
        }
        return facts
    }

    static func text(atPath path: String, limit: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

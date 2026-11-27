import Foundation
import Testing
import FinderDomain
@testable import FinderData

/// A throwaway folder for one test.
private struct TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("FinderDataTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, _ text: String = "x") throws {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    var path: String { url.path }
}

@Suite struct FileSystemScannerTests {
    @Test func walksFoldersFindsProjectsAndSkipsWhatNobodyKeeps() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("notes.txt")
        try folder.write("deep/er/photo.jpg")
        try folder.write(".hidden/secret.txt")
        try folder.write("node_modules/lib/index.js")
        try folder.write("app/.git/HEAD")
        try folder.write("app/Package.swift")
        try folder.write("app/Sources/main.swift")
        try folder.write("app/build/output.o")
        try folder.write("app/docs/logo.png")
        try folder.write("Report.pages/Data/preview.jpg")

        let output = FileSystemScanner().scan(ScanRequest(folders: [folder.path]))
        let byName = Dictionary(uniqueKeysWithValues: output.files.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["notes.txt", "photo.jpg", "Package.swift", "main.swift", "logo.png", "Report.pages", "app"])
        #expect(byName["app"]?.role == .project(type: "Swift Package", fileCount: 3))
        #expect(byName["logo.png"]?.inProject == true)
        #expect(byName["notes.txt"]?.inProject == false)
        #expect(byName["Report.pages"]?.role == .package)
        #expect(byName["photo.jpg"]?.path == folder.path + "/deep/er/photo.jpg")
        #expect(output.unreadableFolders.isEmpty)
    }

    @Test func aChosenFolderIsNeverAProjectItself() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("package.json", "{}")
        try folder.write("photo.jpg")
        let output = FileSystemScanner().scan(ScanRequest(folders: [folder.path]))
        #expect(output.files.allSatisfy { !$0.inProject && $0.role == .file })
    }

    @Test func reportsFoldersItCannotRead() {
        let output = FileSystemScanner().scan(ScanRequest(folders: ["/nonexistent-\(UUID().uuidString)"]))
        #expect(output.files.isEmpty)
        #expect(output.unreadableFolders.count == 1)
    }
}

@Suite struct SQLiteIndexStoreTests {
    private func record(_ path: String, kind: Kind, text: String?, stages: EnrichmentStages = .text) -> EnrichmentRecord {
        let facts = FileFacts(path: path, size: 42, modified: Date(timeIntervalSinceReferenceDate: 1_000.5))
        let item = FileItem(facts: facts, classification: Classification(kind: kind, subkind: "Sub", source: .vision, isUnclear: true),
                            detail: "1 × 2")
        return EnrichmentRecord(item: item, stages: stages, text: text)
    }

    @Test func remembersEnrichmentAcrossInstances() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        SQLiteIndexStore(directory: folder.url).save([record("/a/x.png", kind: .screenshots, text: nil, stages: [.imageMetadata, .imageText])])

        let cached = SQLiteIndexStore(directory: folder.url).loadAll()["/a/x.png"]
        #expect(cached?.classification == Classification(kind: .screenshots, subkind: "Sub", source: .vision, isUnclear: true))
        #expect(cached?.detail == "1 × 2")
        #expect(cached?.stages == [.imageMetadata, .imageText])
        #expect(cached?.isCurrent(for: FileFacts(path: "/a/x.png", size: 42, modified: Date(timeIntervalSinceReferenceDate: 1_000.5))) == true)
        #expect(cached?.isCurrent(for: FileFacts(path: "/a/x.png", size: 43, modified: Date(timeIntervalSinceReferenceDate: 1_000.5))) == false)
    }

    @Test func anIndexMadeWithOtherRulesStartsOver() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        SQLiteIndexStore(directory: folder.url, rulesVersion: 1).save([record("/a/x.png", kind: .screenshots, text: "hello")])
        #expect(SQLiteIndexStore(directory: folder.url, rulesVersion: 1).loadAll().count == 1)
        let newer = SQLiteIndexStore(directory: folder.url, rulesVersion: 2)
        #expect(newer.loadAll().isEmpty)
        #expect(newer.search(terms: ["hello"], limit: 10).isEmpty)
    }

    @Test func findsFilesByTheirText() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        let store = SQLiteIndexStore(directory: folder.url)
        store.save([
            record("/a/invoice.pdf", kind: .pdfs, text: "Factura número 42\nTotal a pagar: 120 euros"),
            record("/a/notes.md", kind: .notes, text: "Remember to pay the electricity bill"),
            record("/a/empty.pdf", kind: .pdfs, text: nil),
        ])
        #expect(store.search(terms: ["factura"], limit: 10).map(\.path) == ["/a/invoice.pdf"])
        // Words match from their start, without accents, and all of them must be there.
        #expect(store.search(terms: ["numero", "pag"], limit: 10).map(\.path) == ["/a/invoice.pdf"])
        #expect(store.search(terms: ["pay", "factura"], limit: 10).isEmpty)
        #expect(store.search(terms: ["electricity"], limit: 10).first?.snippet.contains("electricity") == true)
        // Typed punctuation is never read as search syntax.
        #expect(store.search(terms: ["\"", "AND", "("], limit: 10).isEmpty)

        // New text replaces the old one, and pruning forgets files that are gone.
        store.save([record("/a/invoice.pdf", kind: .pdfs, text: "Receipt for a bicycle")])
        #expect(store.search(terms: ["factura"], limit: 10).isEmpty)
        #expect(store.search(terms: ["bicycle"], limit: 10).count == 1)
        store.prune(keeping: ["/a/invoice.pdf"])
        #expect(store.search(terms: ["electricity"], limit: 10).isEmpty)
        #expect(Set(store.loadAll().keys) == ["/a/invoice.pdf"])
        store.removeAll()
        #expect(store.loadAll().isEmpty)
    }
}

@Suite struct TextExtractorTests {
    @Test func readsPlainTextAndRefusesBinary() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("notes.md", "# Shopping\n- oat milk")
        try Data([0x00, 0x01, 0x02, 0x00]).write(to: folder.url.appendingPathComponent("blob.txt"))
        let extractor = DocumentTextExtractor()
        func item(_ name: String, _ kind: Kind) -> FileItem {
            FileItem(facts: FileFacts(path: folder.path + "/" + name), classification: Classification(kind: kind, subkind: "", source: .fileType))
        }
        #expect(extractor.canExtractText(from: item("notes.md", .notes)))
        #expect(!extractor.canExtractText(from: item("photo.jpg", .photos)))
        #expect(extractor.text(of: item("notes.md", .notes))?.contains("oat milk") == true)
        #expect(extractor.text(of: item("blob.txt", .notes)) == nil)
    }
}

@Suite struct SettingsStoreTests {
    @Test func defaultsToTheStandardFoldersAndRemembersChanges() throws {
        let suite = "FinderDataTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults: defaults, home: "/Users/me")
        #expect(store.load().folders.first == "/Users/me/Documents")
        var settings = store.load()
        settings.folders = ["/Volumes/Work"]
        settings.readsTextInImages = false
        store.save(settings)
        #expect(UserDefaultsSettingsStore(defaults: defaults, home: "/Users/me").load() == settings)
    }
}

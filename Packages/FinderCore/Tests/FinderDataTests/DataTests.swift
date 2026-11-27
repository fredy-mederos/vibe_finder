import Foundation
import SQLite3
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

    @Test func thePhotosLibraryIsLeftAlone() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("Photos Library.photoslibrary/originals/0/IMG_0001.heic")
        try folder.write("Photos Library.photoslibrary/database/Photos.sqlite")
        try folder.write("beach.jpg")
        let output = FileSystemScanner().scan(ScanRequest(folders: [folder.path]))
        #expect(output.files.map(\.name) == ["beach.jpg"])
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

@Suite struct ProjectArtworkFinderTests {
    @Test func findsAnAppsIconInItsAssetCatalog() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("App.xcodeproj/project.pbxproj")
        try folder.write("App/Assets.xcassets/AppIcon.appiconset/Contents.json", "{}")
        try folder.write("App/Assets.xcassets/AppIcon.appiconset/icon_16.png", "small")
        try folder.write("App/Assets.xcassets/AppIcon.appiconset/icon_1024.png", String(repeating: "x", count: 5_000))
        try folder.write("App/Assets.xcassets/Logo.imageset/logo.png", String(repeating: "x", count: 9_000))
        try folder.write("docs/favicon.ico", String(repeating: "x", count: 9_000))
        #expect(FileSystemProjectArtworkFinder().artworkPath(forProjectAt: folder.path)
            == folder.path + "/App/Assets.xcassets/AppIcon.appiconset/icon_1024.png")
    }

    @Test func findsAnAndroidLauncherIconAndAWebFavicon() throws {
        let android = try TempFolder()
        defer { android.remove() }
        try android.write("build.gradle")
        try android.write("app/src/main/res/mipmap-mdpi/ic_launcher.png")
        try android.write("app/src/main/res/mipmap-xxxhdpi/ic_launcher.png")
        try android.write("app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml")
        #expect(FileSystemProjectArtworkFinder().artworkPath(forProjectAt: android.path)
            == android.path + "/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png")

        let web = try TempFolder()
        defer { web.remove() }
        try web.write("package.json", "{}")
        try web.write("public/favicon.ico")
        // A dependency's own icon is never the project's.
        try web.write("node_modules/some-lib/apple-touch-icon.png")
        #expect(FileSystemProjectArtworkFinder().artworkPath(forProjectAt: web.path) == web.path + "/public/favicon.ico")
    }

    @Test func usesTheIconASitesFrontPageNames() throws {
        let cache = try TempFolder()
        defer { cache.remove() }
        let finder = FileSystemProjectArtworkFinder(cacheDirectory: cache.url)

        // Named by address: "/…" is served from the page's "public" folder.
        let linked = try TempFolder()
        defer { linked.remove() }
        try linked.write("package.json", "{}")
        try linked.write("client/index.html", #"<link rel="icon" href="/brand/mark.svg">"#)
        try linked.write("client/public/brand/mark.svg", "<svg/>")
        #expect(finder.artworkPath(forProjectAt: linked.path) == linked.path + "/client/public/brand/mark.svg")

        // Written into the page: saved as a file, the same one every time.
        let inline = try TempFolder()
        defer { inline.remove() }
        try inline.write("client/index.html", #"<link rel="icon" href="data:image/svg+xml,%3Csvg%3E%3C/svg%3E">"#)
        let saved = try #require(finder.artworkPath(forProjectAt: inline.path))
        #expect(saved.hasPrefix(cache.path + "/"))
        #expect(saved.hasSuffix(".svg"))
        #expect(try String(contentsOfFile: saved, encoding: .utf8) == "<svg></svg>")
        #expect(finder.artworkPath(forProjectAt: inline.path) == saved)
        // Without somewhere to save it, it's left out.
        #expect(FileSystemProjectArtworkFinder().artworkPath(forProjectAt: inline.path) == nil)

        // A big icon file beats the page's own little one; nothing outside the project is ever used.
        try inline.write("client/public/icon-512.png", "big")
        #expect(finder.artworkPath(forProjectAt: inline.path) == inline.path + "/client/public/icon-512.png")
        let escaping = try TempFolder()
        defer { escaping.remove() }
        try escaping.write("index.html", #"<link rel="icon" href="../../../etc/hosts">"#)
        #expect(finder.artworkPath(forProjectAt: escaping.path) == nil)
    }

    @Test func usesTheIconAWebAppManifestNames() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("public/manifest.webmanifest", #"{ "icons": [{ "src": "/art/pwa.png", "sizes": "512x512" }] }"#)
        try folder.write("public/art/pwa.png", "png")
        try folder.write("public/favicon.ico", "ico")
        #expect(FileSystemProjectArtworkFinder().artworkPath(forProjectAt: folder.path) == folder.path + "/public/art/pwa.png")
    }

    @Test func aProjectWithoutAnIconHasNone() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("Package.swift")
        try folder.write("Sources/App/main.swift")
        try folder.write("docs/screenshot.png")
        #expect(FileSystemProjectArtworkFinder().artworkPath(forProjectAt: folder.path) == nil)
    }
}

@Suite struct ProjectInspectorTests {
    @Test func readsWhatTheRulesAskFor() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("package.json", #"{ "dependencies": { "express": "5" } }"#)
        try folder.write("App.xcodeproj/project.pbxproj", "SDKROOT = macosx;")
        try folder.write("app/src/main/AndroidManifest.xml", "<manifest/>")
        try folder.write("src/main.js", "console.log(1)")
        try folder.write("sdk/build.gradle.kts", "plugins { id(\"com.android.library\") }")
        try folder.write("sdk/src/deep/build.gradle.kts", "too deep to be a module")
        let facts = FileSystemProjectInspector().facts(forProjectAt: folder.path)
        #expect(facts.rootEntries == ["package.json", "App.xcodeproj", "app", "src", "sdk"])
        #expect(facts.manifests.keys.sorted() == ["package.json", "sdk/build.gradle.kts"])
        #expect(facts.existing == ["app/src/main/AndroidManifest.xml"])
        #expect(facts.xcodeProject == "SDKROOT = macosx;")
        // Node's manifest is read before the Xcode project's: this one is a server.
        #expect(ProjectPlatformRules.profile(for: facts).platform == .server)
    }
}

@Suite struct FolderListingTests {
    @Test func listsNamesAndWhichAreFolders() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("src/main.swift")
        try folder.write("README.md")
        let entries = FileSystemFolderListing().entries(ofFolderAtPath: folder.path).sorted { $0.name < $1.name }
        #expect(entries == [FolderEntry(name: "README.md", isFolder: false), FolderEntry(name: "src", isFolder: true)])
        #expect(FileSystemFolderListing().entries(ofFolderAtPath: folder.path + "/missing").isEmpty)
    }
}

@Suite struct FolderSizerTests {
    @Test func addsUpEverythingInsideAFolder() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        try folder.write("app/main.js", String(repeating: "x", count: 10_000))
        try folder.write("app/node_modules/lib/index.js", String(repeating: "x", count: 50_000))
        try folder.write("app/.git/objects/pack", String(repeating: "x", count: 20_000))
        let size = try #require(FileSystemFolderSizer().sizeOfFolder(atPath: folder.path + "/app"))
        // Space on disk comes in blocks, so at least the bytes written.
        #expect(size >= 80_000)
        #expect(size < 400_000)
        #expect(FileSystemFolderSizer().sizeOfFolder(atPath: folder.path + "/app/main.js") == nil)
        #expect(FileSystemFolderSizer().sizeOfFolder(atPath: folder.path + "/missing") == nil)
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

    @Test func remembersAProjectsArtwork() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        var project = record("/code/app", kind: .projects, text: nil, stages: .projectArtwork)
        project.item.artworkPath = "/code/app/public/favicon.png"
        SQLiteIndexStore(directory: folder.url).save([project, record("/code/x.png", kind: .images, text: nil)])
        let cached = SQLiteIndexStore(directory: folder.url).loadAll()
        #expect(cached["/code/app"]?.artworkPath == "/code/app/public/favicon.png")
        #expect(cached["/code/x.png"]?.artworkPath == nil)
    }

    @Test func remembersAFoldersMeasuredSize() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        var app = record("/Applications/Notes.app", kind: .apps, text: nil, stages: .folderSize)
        app.item.measuredSize = 123_456_789
        SQLiteIndexStore(directory: folder.url).save([app, record("/a/x.png", kind: .images, text: nil)])
        let cached = SQLiteIndexStore(directory: folder.url).loadAll()
        #expect(cached["/Applications/Notes.app"]?.measuredSize == 123_456_789)
        #expect(cached["/a/x.png"]?.measuredSize == nil)
    }

    @Test func anIndexFromBeforeArtworkKeepsWhatItLearned() throws {
        let folder = try TempFolder()
        defer { folder.remove() }
        // The index as version 1 of the app left it.
        var database: OpaquePointer?
        sqlite3_open(folder.url.appendingPathComponent("index.sqlite").path, &database)
        sqlite3_exec(database, """
            CREATE TABLE files(id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, size INTEGER NOT NULL, modified REAL NOT NULL,
                kind TEXT NOT NULL, subkind TEXT NOT NULL, source INTEGER NOT NULL, unclear INTEGER NOT NULL,
                detail TEXT NOT NULL, stages INTEGER NOT NULL);
            INSERT INTO files(path, size, modified, kind, subkind, source, unclear, detail, stages)
                VALUES('/a/x.png', 42, 1000.5, 'screenshots', 'Mac', 1, 0, '10 × 10', 9);
            PRAGMA user_version = 10007;
            """, nil, nil, nil)
        sqlite3_close(database)

        let store = SQLiteIndexStore(directory: folder.url, rulesVersion: 7)
        #expect(store.loadAll()["/a/x.png"]?.classification.kind == .screenshots)
        var project = record("/code/app", kind: .projects, text: nil)
        project.item.artworkPath = "/code/app/icon.png"
        project.item.measuredSize = 99
        store.save([project])
        #expect(store.loadAll()["/code/app"]?.artworkPath == "/code/app/icon.png")
        #expect(store.loadAll()["/code/app"]?.measuredSize == 99)
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

        #expect(store.indexedText(forPath: "/a/notes.md") == "Remember to pay the electricity bill")
        #expect(store.indexedText(forPath: "/a/empty.pdf") == nil)
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

@Suite struct FileManagerTrashTests {
    // Only the failure is tried here: a success would leave test files in the Trash of whoever runs this.
    @Test func reportsWhatItCouldNotMove() async {
        let missing = "/nonexistent-" + UUID().uuidString + "/file.txt"
        let failures = await FileManagerTrash().moveToTrash([missing])
        #expect(failures.map(\.path) == [missing])
        #expect(failures.first?.reason.isEmpty == false)
    }
}

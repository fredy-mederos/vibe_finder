import Foundation
import Testing
@testable import FinderDomain

@Suite struct ClassifierTests {
    private let classifier = RuleBasedClassifier.standard(musicFolder: "/Users/me/Music")

    private func classify(_ name: String, size: Int64 = 100_000, in folder: String = "/Users/me/Downloads",
                          role: FileFacts.Role = .file, isScreenCapture: Bool = false) -> Classification {
        classifier.classify(FileFacts(path: folder + "/" + name, size: size, role: role, isScreenCapture: isScreenCapture))
    }

    @Test(arguments: [
        ("Simulator Screenshot - iPhone 16 Pro - 2026-01-02 at 10.11.12.png", "iOS Simulator"),
        ("Simulator Screen Shot - iPhone 14 Pro - 2023-01-02 at 10.11.12.png", "iOS Simulator"),
        ("Screenshot_20260102-101112.png", "Android"),
        ("Screenshot 2026-01-02 at 10.11.12.png", "Mac"),
        ("Captura de pantalla 2026-01-02 a las 10.11.12.png", "Mac"),
        ("Bildschirmfoto 2026-01-02 um 10.11.12.png", "Mac"),
        ("IMG_0042.PNG", "iPhone"),
        ("login-screenshot-final.jpg", "Other screenshots"),
    ])
    func screenshotsByName(name: String, subkind: String) {
        let result = classify(name)
        #expect(result.kind == .screenshots)
        #expect(result.subkind == subkind)
        #expect(result.source == .fileName)
        #expect(!result.isUnclear)
    }

    @Test(arguments: [
        ("RPReplay_Final1700000000.mov", "iPhone"),
        ("Simulator Screen Recording - iPhone 16 Pro - 2026-01-02 at 10.11.12.mp4", "iOS Simulator"),
        ("Screen Recording 2026-01-02 at 10.11.12.mov", "Mac"),
        ("Grabación de pantalla 2026-01-02 a las 10.11.12.mov", "Mac"),
        ("screen-20260102-101112.mp4", "Android"),
    ])
    func screenRecordingsByName(name: String, subkind: String) {
        let result = classify(name)
        #expect(result.kind == .screenRecordings)
        #expect(result.subkind == subkind)
    }

    @Test func musicVideosByNameAndPlace() {
        #expect(classify("Some Band - Some Song (Official Video).mp4").kind == .musicVideos)
        #expect(classify("concert.mp4", in: "/Users/me/Music/Clips").kind == .musicVideos)
    }

    @Test func videosWithoutASignalStayUnclear() {
        let result = classify("clip.mp4")
        #expect(result.kind == .videos)
        #expect(result.isUnclear)
        #expect(classify("videoplayback (3).mp4").subkind == "Web downloads")
        #expect(classify("WhatsApp Video 2026-01-02 at 10.11.12 PM.mp4").subkind == "Messaging")
    }

    @Test func photosAndImages() {
        #expect(classify("IMG_1234.HEIC").kind == .photos)
        #expect(classify("IMG_1234.jpeg").subkind == "Camera")
        #expect(classify("photo_2026-01-02_10-11-12.jpg").subkind == "Messaging")
        #expect(classify("ChatGPT Image 2 abr 2026, 10_11_12 p.m..png").subkind == "AI generated")
        #expect(classify("logo.svg") == Classification(kind: .images, subkind: "Vector", source: .fileType))
        // A plain PNG or JPEG could be anything: its metadata or a model decides later.
        #expect(classify("12-34-56.png").isUnclear)
        #expect(classify("holiday.jpg").kind == .photos)
        #expect(classify("holiday.jpg").isUnclear)
    }

    @Test func macScreenCaptureFlagWins() {
        #expect(classify("untitled.png", isScreenCapture: true) == Classification(kind: .screenshots, subkind: "Mac", source: .metadata))
        #expect(classify("untitled.mov", isScreenCapture: true).kind == .screenRecordings)
    }

    @Test func audio() {
        #expect(classify("song.mp3", in: "/Users/me/Music/Album") == Classification(kind: .music, subkind: "MP3", source: .fileType))
        #expect(classify("song.mp3").isUnclear)
        #expect(classify("click.wav", size: 40_000).subkind == "Sound effects")
        #expect(classify("New Recording 3.m4a").subkind == "Voice & recordings")
        #expect(classify("note.opus").kind == .audio)
    }

    @Test func keynoteAndPrivateKeysShareAnExtension() {
        #expect(classify("deck.key", size: 12_000_000).kind == .presentations)
        #expect(classify("deck.key", size: 0, role: .package).kind == .presentations)
        #expect(classify("AuthKey.key", size: 1_700).kind == .keys)
    }

    @Test func documentsAndFiles() {
        #expect(classify("report.pdf").kind == .pdfs)
        #expect(classify("letter.docx").subkind == "Word")
        #expect(classify("README.md").kind == .notes)
        #expect(classify("data.csv").kind == .spreadsheets)
        #expect(classify("Installer.dmg").kind == .installers)
        #expect(classify("build.ipa").subkind == "iOS apps")
        #expect(classify("profile.mobileprovision").kind == .keys)
        #expect(classify("Safari.app", role: .application(version: "18.0")).kind == .apps)
        #expect(classify("mystery.xyz") == Classification(kind: .other, subkind: ".xyz", source: .fileType))
        #expect(classify("LICENSE").subkind == "No extension")
    }

    @Test func projectsAreFolders() {
        let result = classify("vibe_finder", in: "/Users/me/Documents", role: .project(type: "Xcode", fileCount: 40))
        #expect(result == Classification(kind: .projects, subkind: "Xcode", source: .metadata))
    }

    @Test func unknownExtensionsAskTheResolver() {
        struct Resolver: FileTypeResolving {
            func family(forExtension ext: String) -> FileFamily? { ext == "jxl" ? .image : nil }
        }
        let classifier = RuleBasedClassifier.standard(resolver: Resolver(), musicFolder: "/Users/me/Music")
        #expect(classifier.classify(FileFacts(path: "/tmp/a.jxl")).kind == .images)
        #expect(classifier.classify(FileFacts(path: "/tmp/a.qqq")).kind == .other)
    }

    @Test func projectMarkers() {
        #expect(ProjectMarkers.projectType(entries: ["README.md", "App.xcodeproj", ".git", "Package.swift"]) == "Xcode")
        #expect(ProjectMarkers.projectType(entries: ["package.json", ".git"]) == "Node")
        #expect(ProjectMarkers.projectType(entries: [".git", "notes.txt"]) == "Git repository")
        #expect(ProjectMarkers.projectType(entries: ["notes.txt", "photo.jpg"]) == nil)
    }

    @Test func scanPolicy() {
        let policy = ScanPolicy.standard
        #expect(policy.isHidden(".DS_Store"))
        #expect(policy.isHidden("~$report.docx"))
        #expect(policy.skipsDirectory(named: "node_modules", inProject: false))
        #expect(policy.skipsDirectory(named: "build", inProject: true))
        #expect(!policy.skipsDirectory(named: "build", inProject: false))
        #expect(policy.isSealed("Photos Library.photoslibrary"))
        #expect(!policy.isSealed("Holiday.pages"))
        // The Photos app writes into its library all day: none of it concerns the index.
        #expect(policy.ignoresChange(at: "/Users/me/Pictures/Photos Library.photoslibrary/database/Photos.sqlite-wal"))
        #expect(policy.ignoresChange(at: "/Users/me/Documents/app/.git/index"))
        #expect(!policy.ignoresChange(at: "/Users/me/Documents/app/notes.txt"))
    }
}

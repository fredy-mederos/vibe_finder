import Foundation

/// What a code project is for, which is how projects are told apart: the app someone runs on a
/// phone, a website, a server… The tool it's built with (Xcode, Gradle, Node) is a detail next to it.
public enum ProjectPlatform: String, CaseIterable, Sendable {
    case iOS, android, mobile, web, server, desktop, game, library, docs, other

    /// The subkind projects of this platform are listed under.
    public var subkind: String {
        switch self {
        case .iOS: "iOS"
        case .android: "Android"
        case .mobile: "Mobile"
        case .web: "Web"
        case .server: "Server"
        case .desktop: "Desktop"
        case .game: "Games"
        case .library: "Libraries & tools"
        case .docs: "Docs"
        case .other: "Other"
        }
    }
}

/// Whether a project is something people run or something other projects build on.
public enum ProjectRole: Sendable, Equatable {
    case app, library
}

/// What a project is: what it's for and whether it's an app or a library. Projects are listed by it.
public struct ProjectProfile: Sendable, Equatable {
    public var platform: ProjectPlatform
    public var role: ProjectRole

    public init(platform: ProjectPlatform, role: ProjectRole = .app) {
        self.platform = platform
        // Only where both are common is the difference worth a place of its own.
        self.role = Self.platformsWithLibraries.contains(platform) ? role : .app
    }

    private static let platformsWithLibraries: Set<ProjectPlatform> = [.iOS, .android, .mobile, .web, .server, .desktop]
    private static let librarySuffix = " libraries"

    /// The subkind its projects are listed under: "Android", "Android libraries".
    public var subkind: String {
        role == .library ? platform.subkind + Self.librarySuffix : platform.subkind
    }

    /// Reads a subkind back; nil when it isn't a project's.
    public init?(subkind: String) {
        let isLibrary = subkind.hasSuffix(Self.librarySuffix)
        let name = isLibrary ? String(subkind.dropLast(Self.librarySuffix.count)) : subkind
        guard let platform = ProjectPlatform.allCases.first(where: { $0.subkind == name }) else { return nil }
        self.init(platform: platform, role: isLibrary ? .library : .app)
    }
}

/// What a project's own files say about it: just the few its tools use to describe it.
public struct ProjectFacts: Sendable, Equatable {
    /// The names in the project's root folder.
    public var rootEntries: Set<String>
    /// The text of the manifests found, by path from the root ("package.json", "app/build.gradle").
    public var manifests: [String: String]
    /// Which of `ProjectPlatformRules.probedPaths` exist.
    public var existing: Set<String>
    /// The text of the Xcode project in the root, when there is one.
    public var xcodeProject: String?

    public init(rootEntries: Set<String> = [], manifests: [String: String] = [:], existing: Set<String> = [],
                xcodeProject: String? = nil) {
        self.rootEntries = rootEntries
        self.manifests = manifests
        self.existing = existing
        self.xcodeProject = xcodeProject
    }
}

/// Decides what a project is from its manifests: what it declares it builds and depends on.
/// Rules only, most telling first, so the same project always lands in the same place.
public enum ProjectPlatformRules {
    /// Files read to decide, by path from the project's root.
    public static let manifestPaths = [
        "package.json", "pubspec.yaml", "build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts",
        "pom.xml", "Package.swift", "pyproject.toml", "requirements.txt", "Pipfile", "Gemfile", "Cargo.toml", "go.mod",
        "composer.json",
    ]

    /// Build files read in every folder right under the root too: a Gradle project's modules are
    /// folders of any name ("app", "library", "sdk"), each saying what it builds.
    public static let moduleManifestNames = ["build.gradle", "build.gradle.kts"]

    /// Paths whose mere existence says something.
    public static let probedPaths = [
        "app/src/main/AndroidManifest.xml", "src/main/AndroidManifest.xml", "android", "ios", "macos", "windows", "linux",
        "index.html", "public/index.html", "src/index.html", "ProjectSettings/ProjectVersion.txt", "manage.py",
        "src/main.rs", "src/lib.rs", "main.go", "cmd",
    ]

    /// Where a project goes before its files have been read, from the tool that marks it alone.
    public static func firstGuess(forTechnology technology: String) -> ProjectPlatform {
        switch technology {
        case "Xcode": .iOS
        case "Flutter": .mobile
        case "Godot": .game
        case "Node": .web
        case "PHP": .server
        case "Git repository": .other
        default: .library
        }
    }

    public static func profile(for facts: ProjectFacts) -> ProjectProfile {
        // Game engines keep their own project files, whatever else is in the folder.
        if facts.existing.contains("ProjectSettings/ProjectVersion.txt") || facts.rootEntries.contains("project.godot") {
            return app(.game)
        }
        if let pubspec = facts.manifests["pubspec.yaml"] {
            return flutter(pubspec, facts)
        }
        if let package = facts.manifests["package.json"] {
            return node(package, facts)
        }
        if let project = facts.xcodeProject {
            return apple(project)
        }
        if facts.rootEntries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            return app(.iOS)
        }
        let gradle = facts.manifests.filter { moduleManifestNames.contains(($0.key as NSString).lastPathComponent) }
            .sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n").lowercased()
        let hasAndroidManifest = facts.existing.contains { $0.hasSuffix("AndroidManifest.xml") }
        if !gradle.isEmpty || hasAndroidManifest {
            if hasAndroidManifest || mentions(gradle, ["com.android", "android.application", "android.library", "androidx."]) {
                // A build that only ever applies the library plugin makes something for other apps to use.
                let isLibrary = mentions(gradle, ["android.library"]) && !mentions(gradle, ["android.application"])
                return ProjectProfile(platform: .android, role: isLibrary ? .library : .app)
            }
            if mentions(gradle, ["org.jetbrains.compose", "javafx"]) { return app(.desktop) }
            return app(mentions(gradle, ["springframework", "spring-boot", "io.ktor", "micronaut", "quarkus", "dropwizard", "vertx"]) ? .server : .library)
        }
        if let pom = facts.manifests["pom.xml"]?.lowercased() {
            if mentions(pom, ["javafx"]) { return app(.desktop) }
            return app(mentions(pom, ["spring-boot", "springframework", "jakarta", "javax.servlet", "quarkus", "micronaut"]) ? .server : .library)
        }
        if let package = facts.manifests["Package.swift"]?.lowercased() {
            return swiftPackage(package)
        }
        let python = text(of: ["pyproject.toml", "requirements.txt", "Pipfile"], in: facts)
        if !python.isEmpty || facts.existing.contains("manage.py") || facts.rootEntries.contains("setup.py") {
            if facts.existing.contains("manage.py") { return app(.server) }
            if mentions(python, ["django", "flask", "fastapi", "starlette", "aiohttp", "tornado", "sanic", "uvicorn", "gunicorn"]) { return app(.server) }
            if mentions(python, ["pygame", "arcade", "panda3d"]) { return app(.game) }
            return app(mentions(python, ["pyqt", "pyside", "kivy", "wxpython", "toga", "customtkinter"]) ? .desktop : .library)
        }
        if let gemfile = facts.manifests["Gemfile"]?.lowercased() {
            if mentions(gemfile, ["jekyll", "middleman"]) { return app(.web) }
            return app(mentions(gemfile, ["rails", "sinatra", "hanami", "roda", "puma"]) ? .server : .library)
        }
        if let cargo = facts.manifests["Cargo.toml"]?.lowercased() {
            // A crate with a library and no program of its own is for other crates.
            let role: ProjectRole = facts.existing.contains("src/lib.rs") && !facts.existing.contains("src/main.rs") ? .library : .app
            if mentions(cargo, ["bevy", "macroquad", "ggez"]) { return app(.game) }
            if mentions(cargo, ["tauri", "egui", "iced", "gtk", "slint", "druid"]) { return ProjectProfile(platform: .desktop, role: role) }
            if mentions(cargo, ["wasm-bindgen", "yew", "leptos", "dioxus"]) { return ProjectProfile(platform: .web, role: role) }
            let isServer = mentions(cargo, ["actix-web", "axum", "rocket", "warp", "tide", "tonic", "hyper", "poem"])
            return ProjectProfile(platform: isServer ? .server : .library, role: role)
        }
        if let module = facts.manifests["go.mod"]?.lowercased() {
            if mentions(module, ["fyne.io", "wailsapp"]) { return app(.desktop) }
            guard mentions(module, ["gin-gonic", "labstack/echo", "gofiber", "go-chi", "gorilla/mux", "grpc", "julienschmidt/httprouter"]) else {
                return app(.library)
            }
            // A Go program has a main package, at the root or under cmd.
            let hasProgram = facts.existing.contains("main.go") || facts.existing.contains("cmd")
            return ProjectProfile(platform: .server, role: hasProgram ? .app : .library)
        }
        // PHP is run by a web server, whatever framework it uses.
        if let composer = facts.manifests["composer.json"] {
            let isLibrary = mentions(composer.lowercased().filter { !$0.isWhitespace }, ["\"type\":\"library\""])
            return ProjectProfile(platform: .server, role: isLibrary ? .library : .app)
        }
        // Nothing at the root says, but the apps are one folder down, each in its platform's.
        switch (facts.existing.contains("ios"), facts.existing.contains("android")) {
        case (true, true): return app(.mobile)
        case (true, false): return app(.iOS)
        case (false, true): return app(.android)
        case (false, false): break
        }
        // No manifest at all, but a page to open: a site kept as plain files.
        if hasIndexPage(facts) {
            return app(.web)
        }
        if facts.rootEntries.contains("CMakeLists.txt") {
            return app(.library)
        }
        return app(isWriting(facts) ? .docs : .other)
    }

    private static func app(_ platform: ProjectPlatform) -> ProjectProfile {
        ProjectProfile(platform: platform, role: .app)
    }

    private static let codeExtensions: Set<String> = [
        "js", "ts", "py", "rb", "go", "rs", "java", "kt", "swift", "c", "cc", "cpp", "h", "m", "cs", "php", "html", "css",
        "sh", "groovy", "sql", "lua", "dart",
    ]

    /// A repository of writing (notes, specs, guides): Markdown at its root and no code next to it.
    private static func isWriting(_ facts: ProjectFacts) -> Bool {
        let extensions = facts.rootEntries.map { ($0 as NSString).pathExtension.lowercased() }
        return extensions.contains("md") && codeExtensions.isDisjoint(with: extensions)
    }

    // MARK: - By tool

    private static func flutter(_ pubspec: String, _ facts: ProjectFacts) -> ProjectProfile {
        let pubspec = pubspec.lowercased()
        // A Dart package without Flutter has nothing to show on a screen.
        guard mentions(pubspec, ["flutter:", "sdk: flutter"]) else { return app(.library) }
        // A plugin brings android and ios folders too, but only to be used by apps.
        if mentions(pubspec, ["plugin:"]) { return ProjectProfile(platform: .mobile, role: .library) }
        if facts.existing.contains("android") || facts.existing.contains("ios") { return app(.mobile) }
        if !facts.existing.isDisjoint(with: ["macos", "windows", "linux"]) { return app(.desktop) }
        if facts.rootEntries.contains("web") { return app(.web) }
        // Flutter code with no platform to run on: a package of widgets.
        return ProjectProfile(platform: .mobile, role: .library)
    }

    private static let mobilePackages: Set<String> = ["react-native", "expo", "@capacitor/core", "@ionic/react", "@ionic/vue",
                                                      "@ionic/angular", "nativescript", "@nativescript/core", "cordova"]
    private static let desktopPackages: Set<String> = ["electron", "@tauri-apps/api", "@tauri-apps/cli", "nw", "neutralinojs"]
    private static let webPackages: Set<String> = [
        "react", "react-dom", "next", "vue", "nuxt", "svelte", "@sveltejs/kit", "@angular/core", "solid-js", "preact", "astro",
        "vite", "webpack", "parcel", "gatsby", "@remix-run/react", "lit", "three", "phaser", "pixi.js", "tailwindcss", "jquery",
        "@11ty/eleventy", "alpinejs", "htmx.org",
    ]
    private static let serverPackages: Set<String> = [
        "express", "fastify", "koa", "@nestjs/core", "@hapi/hapi", "hono", "restify", "socket.io", "apollo-server", "graphql-yoga",
        "@trpc/server", "mongoose", "pg", "mysql2", "redis", "discord.js", "telegraf", "grammy", "ws", "@modelcontextprotocol/sdk",
    ]

    private static func node(_ package: String, _ facts: ProjectFacts) -> ProjectProfile {
        let manifest = (try? JSONSerialization.jsonObject(with: Data(package.utf8)) as? [String: Any]) ?? [:]
        let packages = dependencies(in: manifest)
        let role: ProjectRole = isPublishedPackage(manifest) ? .library : .app
        if !packages.isDisjoint(with: mobilePackages) { return ProjectProfile(platform: .mobile, role: role) }
        if !packages.isDisjoint(with: desktopPackages) { return app(.desktop) }
        // A site's framework before a server's: full-stack projects are sites that bring their server along.
        if !packages.isDisjoint(with: webPackages) { return ProjectProfile(platform: .web, role: role) }
        if !packages.isDisjoint(with: serverPackages) { return ProjectProfile(platform: .server, role: role) }
        return app(hasIndexPage(facts) ? .web : .library)
    }

    /// The names a package.json depends on, for running or for building.
    private static func dependencies(in manifest: [String: Any]) -> Set<String> {
        var names: Set<String> = []
        for key in ["dependencies", "devDependencies", "peerDependencies"] {
            names.formUnion((manifest[key] as? [String: Any] ?? [:]).keys)
        }
        return names
    }

    /// What only a package meant to be installed by others declares: what it exports, its types, the
    /// files it ships, what it expects its host to provide. An app is private and says none of it.
    private static func isPublishedPackage(_ manifest: [String: Any]) -> Bool {
        guard manifest["private"] as? Bool != true else { return false }
        return ["exports", "types", "typings", "module", "files", "peerDependencies", "publishConfig"].contains { manifest[$0] != nil }
    }

    /// A Swift package says which Apple platforms it's for and whether it builds a program.
    private static func swiftPackage(_ package: String) -> ProjectProfile {
        if mentions(package, ["vapor", "hummingbird", "swift-nio"]) { return app(.server) }
        let role: ProjectRole = mentions(package, [".executabletarget(", ".executable("]) ? .app : .library
        if mentions(package, [".ios("]) { return ProjectProfile(platform: .iOS, role: role) }
        if mentions(package, [".macos("]) { return ProjectProfile(platform: .desktop, role: role) }
        return app(.library)
    }

    /// An Xcode project says what it builds for in every target's settings: whichever of the Mac and
    /// the devices is named more wins, and the devices win a tie (apps for both are phone apps first).
    /// It's a library when it builds frameworks or libraries and no app.
    private static func apple(_ project: String) -> ProjectProfile {
        let devices = ["IPHONEOS_DEPLOYMENT_TARGET", "SDKROOT = iphoneos", "WATCHOS_DEPLOYMENT_TARGET", "TVOS_DEPLOYMENT_TARGET",
                       "XROS_DEPLOYMENT_TARGET"].reduce(0) { $0 + occurrences(of: $1, in: project) }
        let mac = ["MACOSX_DEPLOYMENT_TARGET", "SDKROOT = macosx"].reduce(0) { $0 + occurrences(of: $1, in: project) }
        let buildsApp = project.contains("com.apple.product-type.application")
        let buildsLibrary = project.contains("com.apple.product-type.framework") || project.contains("com.apple.product-type.library")
        return ProjectProfile(platform: mac > devices ? .desktop : .iOS, role: buildsLibrary && !buildsApp ? .library : .app)
    }

    // MARK: - Reading

    private static func hasIndexPage(_ facts: ProjectFacts) -> Bool {
        !facts.existing.isDisjoint(with: ["index.html", "public/index.html", "src/index.html"]) || facts.rootEntries.contains("index.html")
    }

    /// The manifests at these paths, lowercased and joined.
    private static func text(of paths: [String], in facts: ProjectFacts) -> String {
        paths.compactMap { facts.manifests[$0] }.joined(separator: "\n").lowercased()
    }

    private static func mentions(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    private static func occurrences(of word: String, in text: String) -> Int {
        text.components(separatedBy: word).count - 1
    }
}

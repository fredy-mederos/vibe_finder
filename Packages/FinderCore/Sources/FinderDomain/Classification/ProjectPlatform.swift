import Foundation

/// What a code project is for, which is how projects are told apart: the app someone runs on a
/// phone, a website, a server… The tool it's built with (Xcode, Gradle, Node) is a detail next to it.
public enum ProjectPlatform: String, CaseIterable, Sendable {
    case iOS, android, mobile, web, server, desktop, game, library, other

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
        case .other: "Other"
        }
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

/// Decides a project's platform from its manifests: what it declares it builds and depends on.
/// Rules only, most telling first, so the same project always lands in the same place.
public enum ProjectPlatformRules {
    /// Files read to decide, by path from the project's root.
    public static let manifestPaths = [
        "package.json", "pubspec.yaml", "build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts",
        "pom.xml", "Package.swift", "pyproject.toml", "requirements.txt", "Pipfile", "Gemfile", "Cargo.toml", "go.mod",
        "composer.json",
    ]

    /// Paths whose mere existence says something.
    public static let probedPaths = [
        "app/src/main/AndroidManifest.xml", "src/main/AndroidManifest.xml", "android", "ios", "macos", "windows", "linux",
        "index.html", "public/index.html", "src/index.html", "ProjectSettings/ProjectVersion.txt", "manage.py",
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

    public static func platform(for facts: ProjectFacts) -> ProjectPlatform {
        // Game engines keep their own project files, whatever else is in the folder.
        if facts.existing.contains("ProjectSettings/ProjectVersion.txt") || facts.rootEntries.contains("project.godot") {
            return .game
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
            return .iOS
        }
        let gradle = text(of: ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts"], in: facts)
        let hasAndroidManifest = facts.existing.contains { $0.hasSuffix("AndroidManifest.xml") }
        if !gradle.isEmpty || hasAndroidManifest {
            if hasAndroidManifest || mentions(gradle, ["com.android", "android.application", "android.library", "androidx."]) { return .android }
            if mentions(gradle, ["org.jetbrains.compose", "javafx"]) { return .desktop }
            return mentions(gradle, ["springframework", "spring-boot", "io.ktor", "micronaut", "quarkus", "dropwizard", "vertx"]) ? .server : .library
        }
        if let pom = facts.manifests["pom.xml"]?.lowercased() {
            if mentions(pom, ["javafx"]) { return .desktop }
            return mentions(pom, ["spring-boot", "springframework", "jakarta", "javax.servlet", "quarkus", "micronaut"]) ? .server : .library
        }
        if let package = facts.manifests["Package.swift"]?.lowercased() {
            return mentions(package, ["vapor", "hummingbird", "swift-nio"]) ? .server : .library
        }
        let python = text(of: ["pyproject.toml", "requirements.txt", "Pipfile"], in: facts)
        if !python.isEmpty || facts.existing.contains("manage.py") || facts.rootEntries.contains("setup.py") {
            if facts.existing.contains("manage.py") { return .server }
            if mentions(python, ["django", "flask", "fastapi", "starlette", "aiohttp", "tornado", "sanic", "uvicorn", "gunicorn"]) { return .server }
            if mentions(python, ["pygame", "arcade", "panda3d"]) { return .game }
            return mentions(python, ["pyqt", "pyside", "kivy", "wxpython", "toga", "customtkinter"]) ? .desktop : .library
        }
        if let gemfile = facts.manifests["Gemfile"]?.lowercased() {
            if mentions(gemfile, ["jekyll", "middleman"]) { return .web }
            return mentions(gemfile, ["rails", "sinatra", "hanami", "roda", "puma"]) ? .server : .library
        }
        if let cargo = facts.manifests["Cargo.toml"]?.lowercased() {
            if mentions(cargo, ["bevy", "macroquad", "ggez"]) { return .game }
            if mentions(cargo, ["tauri", "egui", "iced", "gtk", "slint", "druid"]) { return .desktop }
            if mentions(cargo, ["wasm-bindgen", "yew", "leptos", "dioxus"]) { return .web }
            return mentions(cargo, ["actix-web", "axum", "rocket", "warp", "tide", "tonic", "hyper", "poem"]) ? .server : .library
        }
        if let module = facts.manifests["go.mod"]?.lowercased() {
            if mentions(module, ["fyne.io", "wailsapp"]) { return .desktop }
            return mentions(module, ["gin-gonic", "labstack/echo", "gofiber", "go-chi", "gorilla/mux", "grpc", "julienschmidt/httprouter"]) ? .server : .library
        }
        // PHP is run by a web server, whatever framework it uses.
        if facts.manifests["composer.json"] != nil {
            return .server
        }
        // No manifest at all, but a page to open: a site kept as plain files.
        if hasIndexPage(facts) {
            return .web
        }
        return facts.rootEntries.contains("CMakeLists.txt") ? .library : .other
    }

    // MARK: - By tool

    private static func flutter(_ pubspec: String, _ facts: ProjectFacts) -> ProjectPlatform {
        // A Dart package without Flutter has nothing to show on a screen.
        guard mentions(pubspec.lowercased(), ["flutter:", "sdk: flutter"]) else { return .library }
        if facts.existing.contains("android") || facts.existing.contains("ios") { return .mobile }
        if !facts.existing.isDisjoint(with: ["macos", "windows", "linux"]) { return .desktop }
        return facts.rootEntries.contains("web") ? .web : .mobile
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

    private static func node(_ package: String, _ facts: ProjectFacts) -> ProjectPlatform {
        let packages = dependencies(inPackageJSON: package)
        if !packages.isDisjoint(with: mobilePackages) { return .mobile }
        if !packages.isDisjoint(with: desktopPackages) { return .desktop }
        // A site's framework before a server's: full-stack projects are sites that bring their server along.
        if !packages.isDisjoint(with: webPackages) { return .web }
        if !packages.isDisjoint(with: serverPackages) { return .server }
        return hasIndexPage(facts) ? .web : .library
    }

    /// The names a package.json depends on, for running or for building.
    static func dependencies(inPackageJSON text: String) -> Set<String> {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return [] }
        var names: Set<String> = []
        for key in ["dependencies", "devDependencies", "peerDependencies"] {
            names.formUnion((object[key] as? [String: Any] ?? [:]).keys)
        }
        return names
    }

    /// An Xcode project says what it builds for in every target's settings: whichever of the Mac and
    /// the devices is named more wins, and the devices win a tie (apps for both are phone apps first).
    private static func apple(_ project: String) -> ProjectPlatform {
        let devices = ["IPHONEOS_DEPLOYMENT_TARGET", "SDKROOT = iphoneos", "WATCHOS_DEPLOYMENT_TARGET", "TVOS_DEPLOYMENT_TARGET",
                       "XROS_DEPLOYMENT_TARGET"].reduce(0) { $0 + occurrences(of: $1, in: project) }
        let mac = ["MACOSX_DEPLOYMENT_TARGET", "SDKROOT = macosx"].reduce(0) { $0 + occurrences(of: $1, in: project) }
        return mac > devices ? .desktop : .iOS
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

// swift-tools-version: 6.2
import PackageDescription

// FinderCore holds everything that is not tied to the UI, split by the dependency rule:
//
//   FinderDomain  entities, classification rules, enrichment steps, use cases and the ports
//                 (protocols) they need. Foundation only: no file system, database or model here.
//   FinderData    the adapters behind those ports: the file system scanner, the SQLite index,
//                 ImageIO, AVFoundation, PDFKit, Vision and Foundation Models.
//
// The app depends on both, but only its composition root (App/AppContainer.swift) names FinderData.
let package = Package(
    name: "FinderCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FinderDomain", targets: ["FinderDomain"]),
        .library(name: "FinderData", targets: ["FinderData"]),
    ],
    targets: [
        .target(name: "FinderDomain"),
        .target(name: "FinderData", dependencies: ["FinderDomain"]),
        .testTarget(name: "FinderDomainTests", dependencies: ["FinderDomain"]),
        .testTarget(name: "FinderDataTests", dependencies: ["FinderData", "FinderDomain"]),
    ],
    swiftLanguageModes: [.v6]
)

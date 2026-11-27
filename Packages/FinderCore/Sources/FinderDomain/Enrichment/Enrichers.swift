import Foundation

private let pictureKinds: Set<Kind> = [.photos, .screenshots, .images]
private let mediaKinds: Set<Kind> = [.videos, .screenRecordings, .musicVideos, .music, .audio]

/// Pixel size and camera of an image; settles unclear ones the file itself explains.
public struct ImageMetadataEnricher: ItemEnricher {
    private let inspector: any ImageInspecting

    public init(inspector: any ImageInspecting) {
        self.inspector = inspector
    }

    public let stage: EnrichmentStages = .imageMetadata

    public func applies(to item: FileItem) -> Bool {
        pictureKinds.contains(item.kind) && FileFormatCatalog.photographicExtensions.contains(item.ext)
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        guard let facts = inspector.facts(forImageAt: draft.item.path) else { return }
        draft.item.detail = DetailFormat.joined([DetailFormat.dimensions(width: facts.width, height: facts.height), facts.cameraModel])
        if draft.item.isUnclear, let classification = ImageFactsPolicy.classification(for: draft.item, facts: facts) {
            draft.item.classification = classification
        }
    }
}

/// Asks the on-device image classifier about the images nothing else could settle.
public struct ImageUnderstandingEnricher: ItemEnricher {
    private let classifier: any ImageUnderstanding

    public init(classifier: any ImageUnderstanding) {
        self.classifier = classifier
    }

    public let stage: EnrichmentStages = .imageUnderstanding

    public func applies(to item: FileItem) -> Bool {
        item.isUnclear && !item.inProject && pictureKinds.contains(item.kind)
            && FileFormatCatalog.rasterExtensions.contains(item.ext)
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        let labels = classifier.labels(forImageAt: draft.item.path)
        if let classification = ImageLabelPolicy.classification(for: draft.item, labels: labels) {
            draft.item.classification = classification
        }
        // The model had its say: what it didn't move stays where its format put it.
        draft.item.isUnclear = false
    }
}

/// Reads the text in screenshots and other non-photo images so it can be searched.
public struct ImageTextEnricher: ItemEnricher {
    private let recognizer: any TextRecognizing
    private static let withoutText: Set<String> = ["Icons", "Vector", "GIFs"]

    public init(recognizer: any TextRecognizing) {
        self.recognizer = recognizer
    }

    public let stage: EnrichmentStages = .imageText

    public func applies(to item: FileItem) -> Bool {
        guard !item.inProject, FileFormatCatalog.rasterExtensions.contains(item.ext) else { return false }
        return item.kind == .screenshots || (item.kind == .images && !Self.withoutText.contains(item.subkind))
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        guard let text = recognizer.recognizeText(inImageAt: draft.item.path), !text.isEmpty else { return }
        draft.text = [draft.text, text].compactMap { $0 }.joined(separator: "\n")
    }
}

/// Duration, size and tags of audio and video; settles unclear ones the file itself explains.
public struct MediaMetadataEnricher: ItemEnricher {
    private let inspector: any MediaInspecting

    public init(inspector: any MediaInspecting) {
        self.inspector = inspector
    }

    public let stage: EnrichmentStages = .mediaMetadata

    public func applies(to item: FileItem) -> Bool {
        mediaKinds.contains(item.kind)
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        guard let facts = await inspector.facts(forMediaAt: draft.item.path) else { return }
        draft.item.detail = MediaFactsPolicy.detail(for: facts)
        if draft.item.isUnclear, let classification = MediaFactsPolicy.classification(for: draft.item, facts: facts) {
            draft.item.classification = classification
        }
    }
}

/// How much room a folder takes with everything in it: a project with its dependencies and build
/// output, an app, any document kept as a package. A scan only adds up what it lists.
public struct FolderSizeEnricher: ItemEnricher {
    private let sizer: any FolderSizing

    public init(sizer: any FolderSizing) {
        self.sizer = sizer
    }

    public let stage: EnrichmentStages = .folderSize

    public func applies(to item: FileItem) -> Bool {
        // Packages come out of a scan without a size; a file that's really empty costs nothing to ask about.
        item.kind == .projects || item.kind == .apps || item.size == 0
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        draft.item.measuredSize = sizer.sizeOfFolder(atPath: draft.item.path)
    }
}

/// What a project is (an iOS app, an Android library, a website, a server…), from what its manifests declare.
public struct ProjectPlatformEnricher: ItemEnricher {
    private let inspector: any ProjectInspecting

    public init(inspector: any ProjectInspecting) {
        self.inspector = inspector
    }

    public let stage: EnrichmentStages = .projectPlatform

    public func applies(to item: FileItem) -> Bool {
        item.kind == .projects
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        let profile = ProjectPlatformRules.profile(for: inspector.facts(forProjectAt: draft.item.path))
        draft.item.classification = Classification(kind: .projects, subkind: profile.subkind, source: .metadata)
    }
}

/// The picture a project goes by: its app's icon or its site's favicon, found where its tools keep it.
public struct ProjectArtworkEnricher: ItemEnricher {
    private let finder: any ProjectArtworkFinding

    public init(finder: any ProjectArtworkFinding) {
        self.finder = finder
    }

    public let stage: EnrichmentStages = .projectArtwork

    public func applies(to item: FileItem) -> Bool {
        item.kind == .projects
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        draft.item.artworkPath = finder.artworkPath(forProjectAt: draft.item.path)
    }
}

/// The text of documents, notes, code and tables, for content search.
public struct TextContentEnricher: ItemEnricher {
    private let extractor: any TextExtracting

    public init(extractor: any TextExtracting) {
        self.extractor = extractor
    }

    public let stage: EnrichmentStages = .text

    public func applies(to item: FileItem) -> Bool {
        extractor.canExtractText(from: item)
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        guard let text = extractor.text(of: draft.item), !text.isEmpty else { return }
        draft.text = [draft.text, text].compactMap { $0 }.joined(separator: "\n")
    }
}

/// Asks the on-device language model what a document is about (an invoice, a contract, a manual…).
public struct DocumentUnderstandingEnricher: ItemEnricher {
    private let model: any LanguageUnderstanding
    /// As much of the text as the model needs to tell.
    private static let excerptLength = 1200

    public init(model: any LanguageUnderstanding) {
        self.model = model
    }

    public let stage: EnrichmentStages = .documentUnderstanding

    public var isAvailable: Bool { model.isAvailable }

    public func applies(to item: FileItem) -> Bool {
        !item.inProject && (item.kind == .pdfs || item.kind == .documents)
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        let excerpt = String((draft.text ?? "").prefix(Self.excerptLength))
        let folder = (draft.item.folder as NSString).lastPathComponent
        guard let category = await model.documentCategory(name: draft.item.name, folder: folder, excerpt: excerpt),
              let subkind = category.subkind else { return }
        draft.item.subkind = subkind
        draft.item.source = .languageModel
    }
}

/// Asks the on-device language model what an unclear video is, when its name says something.
public struct VideoUnderstandingEnricher: ItemEnricher {
    private let model: any LanguageUnderstanding

    public init(model: any LanguageUnderstanding) {
        self.model = model
    }

    public let stage: EnrichmentStages = .videoUnderstanding

    public var isAvailable: Bool { model.isAvailable }

    public func applies(to item: FileItem) -> Bool {
        item.isUnclear && !item.inProject && item.kind == .videos && VideoCategoryPolicy.isInformative(name: item.name)
    }

    public func enrich(_ draft: inout EnrichmentDraft) async {
        let folder = (draft.item.folder as NSString).lastPathComponent
        if let category = await model.videoCategory(name: draft.item.name, folder: folder),
           let classification = VideoCategoryPolicy.classification(for: category) {
            draft.item.classification = classification
        }
        draft.item.isUnclear = false
    }
}

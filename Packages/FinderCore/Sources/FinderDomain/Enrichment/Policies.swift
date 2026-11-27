import Foundation

// What metadata and model answers mean for an item's kind. Pure decisions, kept apart from the
// steps that fetch the facts so they can be tested with plain values.

/// Refines an unclear image from what its file says about itself.
public enum ImageFactsPolicy {
    /// Images this small are icons or sprites, not pictures.
    static let iconSide = 256

    public static func classification(for item: FileItem, facts: ImageFacts) -> Classification? {
        if facts.cameraModel != nil {
            return Classification(kind: .photos, subkind: "Camera", source: .metadata)
        }
        if facts.isMarkedScreenshot {
            return Classification(kind: .screenshots, subkind: "iPhone", source: .metadata)
        }
        // Cameras don't save PNG, so an exact screen size there is a screenshot.
        if item.ext == "png", let device = ScreenSizes.device(width: facts.width, height: facts.height) {
            return Classification(kind: .screenshots, subkind: device, source: .metadata)
        }
        if item.ext != "jpg", item.ext != "jpeg", max(facts.width, facts.height) <= iconSide {
            return Classification(kind: .images, subkind: "Icons", source: .metadata)
        }
        return nil
    }
}

/// Refines an unclear image from what an image classifier sees in it. A model only moves an item
/// when it's confident; otherwise the format's kind stays.
public enum ImageLabelPolicy {
    static let threshold = 0.5
    private static let scans: Set<String> = ["document", "receipt", "handwriting", "whiteboard", "credit_card", "passport", "checkbook"]
    private static let diagrams: Set<String> = ["diagram", "chart", "map", "flipchart"]
    private static let illustrations: Set<String> = ["illustrations", "art"]

    public static func classification(for item: FileItem, labels: [ImageLabel]) -> Classification? {
        let confident = Set(labels.filter { $0.confidence >= threshold }.map(\.identifier))
        if confident.contains("screenshot") {
            return Classification(kind: .screenshots, subkind: "Other screenshots", source: .vision)
        }
        if !confident.isDisjoint(with: scans) {
            return Classification(kind: .images, subkind: "Scans & documents", source: .vision)
        }
        if !confident.isDisjoint(with: diagrams) {
            return Classification(kind: .images, subkind: "Diagrams & charts", source: .vision)
        }
        if !confident.isDisjoint(with: illustrations) {
            return Classification(kind: .images, subkind: "Illustrations", source: .vision)
        }
        return nil
    }
}

/// Refines unclear audio and video from their duration, size and tags.
public enum MediaFactsPolicy {
    /// Shorter than this, an untagged sound is an effect, not a song.
    static let effectDuration: TimeInterval = 20

    public static func classification(for item: FileItem, facts: MediaFacts) -> Classification? {
        switch item.kind {
        case .videos:
            // Cameras film in 16:9 at any size; a phone's or a Mac's own screen has another shape.
            if let width = facts.width, let height = facts.height, !isSixteenByNine(width, height),
               let device = ScreenSizes.device(width: width, height: height) {
                return Classification(kind: .screenRecordings, subkind: device, source: .metadata)
            }
            if facts.artist != nil {
                return Classification(kind: .musicVideos, subkind: "Music videos", source: .metadata)
            }
            return nil
        case .music:
            if facts.artist != nil || facts.album != nil {
                return Classification(kind: .music, subkind: item.subkind, source: .metadata)
            }
            if let duration = facts.duration, duration < effectDuration {
                return Classification(kind: .audio, subkind: "Sound effects", source: .metadata)
            }
            // Untagged AAC is what voice memos and recorders write; other formats stay music.
            if item.ext == "m4a" {
                return Classification(kind: .audio, subkind: "Voice & recordings", source: .metadata)
            }
            return Classification(kind: .music, subkind: item.subkind, source: .fileType)
        default:
            return nil
        }
    }

    private static func isSixteenByNine(_ width: Int, _ height: Int) -> Bool {
        max(width, height) * 9 == min(width, height) * 16
    }

    public static func detail(for facts: MediaFacts) -> String {
        let size = facts.width.flatMap { width in facts.height.map { DetailFormat.dimensions(width: width, height: $0) } }
        let song = [facts.artist, facts.title].compactMap { $0 }.joined(separator: " — ")
        return DetailFormat.joined([facts.duration.map(DetailFormat.duration), size, song])
    }
}

/// Where a language model's reading of a video's name puts it.
public enum VideoCategoryPolicy {
    public static func classification(for category: VideoCategory) -> Classification? {
        switch category {
        case .musicVideo: Classification(kind: .musicVideos, subkind: "Music videos", source: .languageModel)
        case .movie: Classification(kind: .videos, subkind: "Movies & TV", source: .languageModel)
        case .tutorial: Classification(kind: .videos, subkind: "Tutorials & talks", source: .languageModel)
        case .personal: Classification(kind: .videos, subkind: "Personal", source: .languageModel)
        case .other: nil
        }
    }

    /// A name a model can read something into: at least two words of letters, not a hash or a counter.
    public static func isInformative(name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension
        let words = stem.split { !$0.isLetter }.filter { $0.count >= 3 }
        return words.count >= 2
    }
}

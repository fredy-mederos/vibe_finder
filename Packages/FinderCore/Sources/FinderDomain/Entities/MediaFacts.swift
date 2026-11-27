import Foundation

/// What an image file says about itself, without looking at its pixels.
public struct ImageFacts: Sendable, Equatable {
    public var width: Int
    public var height: Int
    /// The camera or phone that took it, when the file records one.
    public var cameraModel: String?
    /// iOS writes "Screenshot" into the screenshots it saves.
    public var isMarkedScreenshot: Bool

    public init(width: Int, height: Int, cameraModel: String? = nil, isMarkedScreenshot: Bool = false) {
        self.width = width
        self.height = height
        self.cameraModel = cameraModel
        self.isMarkedScreenshot = isMarkedScreenshot
    }
}

/// What an audio or video file says about itself.
public struct MediaFacts: Sendable, Equatable {
    public var duration: TimeInterval?
    public var width: Int?
    public var height: Int?
    public var hasAudio: Bool
    public var title: String?
    public var artist: String?
    public var album: String?

    public init(duration: TimeInterval? = nil, width: Int? = nil, height: Int? = nil, hasAudio: Bool = true,
                title: String? = nil, artist: String? = nil, album: String? = nil) {
        self.duration = duration
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
        self.title = title
        self.artist = artist
        self.album = album
    }
}

/// One thing an image classifier sees in a picture, with how sure it is (0…1).
public struct ImageLabel: Sendable, Equatable {
    public var identifier: String
    public var confidence: Double

    public init(_ identifier: String, _ confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

/// What a document is about, as a language model reads it.
public enum DocumentCategory: String, Sendable, CaseIterable {
    case invoice, contract, finance, travel, identity, manual, book, resume, slides, letter, notes, other

    /// The subkind shown for it; nil when the model couldn't say.
    public var subkind: String? {
        switch self {
        case .invoice: "Invoices & receipts"
        case .contract: "Contracts & legal"
        case .finance: "Bank & taxes"
        case .travel: "Travel & tickets"
        case .identity: "IDs & official forms"
        case .manual: "Manuals & guides"
        case .book: "Books & papers"
        case .resume: "Résumés"
        case .slides: "Slides"
        case .letter: "Letters"
        case .notes: "Notes"
        case .other: nil
        }
    }
}

/// What a video is, as a language model reads its name.
public enum VideoCategory: String, Sendable, CaseIterable {
    case musicVideo, movie, tutorial, personal, other
}

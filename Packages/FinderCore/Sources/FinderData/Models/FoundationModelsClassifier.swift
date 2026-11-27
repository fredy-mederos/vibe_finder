import Foundation
import FoundationModels
import OSLog
import FinderDomain

/// Asks Apple's on-device language model what a document or a video is. Nothing leaves the Mac. The
/// answers are constrained to a fixed list and sampled greedily, so the same input gives the same
/// answer; an actor, so the model gets one question at a time.
public actor FoundationModelsClassifier: LanguageUnderstanding, ItemDescribing {
    public init() {}

    public nonisolated var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }

    public func documentCategory(name: String, folder: String, excerpt: String) async throws -> DocumentCategory? {
        let session = LanguageModelSession(instructions: """
            You classify one of a person's documents from its file name, its folder and how its text starts. \
            Pick the category that fits best, and "other" when nothing fits or you can't tell.
            """)
        let prompt = """
            File name: \(name)
            Folder: \(folder)
            Text:
            \(excerpt.isEmpty ? "(no text could be read)" : excerpt)
            """
        return try await ask {
            try await session.respond(to: prompt, generating: DocumentVerdict.self, options: Self.options).content.category.domain
        }
    }

    public func videoCategory(name: String, folder: String) async throws -> VideoCategory? {
        // The folder is left out on purpose: "Downloads" or "Movies" only pulls the answer off the name.
        let session = LanguageModelSession(instructions: """
            You classify a video file from its file name alone. Categories:
            - musicVideo: an artist and a song, a concert, a music clip.
            - movieOrTVShow: the title of a film or a series, often with a year or an episode number.
            - tutorialOrTalk: a lesson, how-to, course, lecture or conference talk.
            - personalVideo: family, friends, trips, parties, pets.
            - other: anything else. Generic names (clip, video, export, final, demo, untitled, a feature or a \
            bug being shown) say nothing about the category: pick other for them, and whenever you are unsure.
            """)
        return try await ask {
            try await session.respond(to: "File name: \(name)", generating: VideoVerdict.self, options: Self.options).content.category.domain
        }
    }

    // MARK: - ItemDescribing

    public func describe(_ source: DescriptionSource, kind: Kind) async throws -> String? {
        let session = LanguageModelSession(instructions: Self.descriptionInstructions)
        switch source {
        case .text(let text):
            return try await ask {
                try await session.respond(to: "Kind of file: \(Self.label(for: kind))\nText found in it:\n\(text)", options: Self.options).content
            }
        case .image(let path):
            // The model only takes pictures from macOS 27 on; before that, pictures go undescribed.
            guard #available(macOS 27.0, *) else { return nil }
            return try await ask {
                try await session.respond(options: Self.options) {
                    "Say what this \(Self.label(for: kind)) shows."
                    Attachment(imageURL: URL(fileURLWithPath: path))
                }.content
            }
        }
    }

    // MARK: - Asking

    /// While the system is holding the model back, it isn't asked at all.
    private var pausedUntil: ContinuousClock.Instant?
    private static let pause: Duration = .seconds(60)
    /// What the framework calls the errors that pass: the system limiting requests (it does that to
    /// apps in the background), another request in the way, the model's files not there yet.
    private static let passingErrors = ["rateLimited", "concurrentRequests", "assetsUnavailable"]

    /// Asks the model. nil when this one question can't be answered (the model refused it, the text is
    /// in a language it doesn't read…), which is an answer; `ModelUnavailable` when the model couldn't
    /// be asked at all, which isn't, and the question is put again later.
    private func ask<Answer: Sendable>(_ question: () async throws -> Answer) async throws -> Answer? {
        if let pausedUntil, ContinuousClock.now < pausedUntil { throw ModelUnavailable() }
        do {
            return try await question()
        } catch {
            // Never silently: which errors pass and which don't is read off these names.
            Self.log.error("The on-device model didn't answer: \(String(describing: error), privacy: .public)")
            guard Self.passingErrors.contains(where: String(describing: error).contains) else { return nil }
            pausedUntil = .now + Self.pause
            throw ModelUnavailable()
        }
    }

    private static let log = Logger(subsystem: "com.fredymederos.VibeFinder", category: "model")

    /// Written in the language the Mac is used in, so the lines read like the rest of the app.
    private static var descriptionInstructions: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let language = code == "en" ? "U.S. English" : Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "U.S. English"
        return """
            You write the one line that tells a person what a file is, for a list of their files. At most 12 words. \
            Say what it is and what it's about, concretely: names, amounts, places, dates when they're there. \
            No quotes, no file name, never start with "This" or "A screenshot of". You MUST respond in \(language).
            """
    }

    private static func label(for kind: Kind) -> String {
        switch kind {
        case .screenshots: "screenshot"
        case .photos: "photo"
        case .images: "picture"
        case .pdfs: "PDF document"
        case .presentations: "presentation"
        default: "document"
        }
    }

    private static var options: GenerationOptions { GenerationOptions(samplingMode: .greedy) }
}

@Generable
private struct DocumentVerdict {
    @Guide(description: "What kind of document it is")
    var category: GeneratedDocumentCategory
}

@Generable
private enum GeneratedDocumentCategory {
    case invoiceOrReceipt
    case contractOrLegal
    case bankStatementOrTaxes
    case travelTicketOrBooking
    case identityOrOfficialForm
    case manualOrGuide
    case bookOrPaper
    case resume
    case presentationSlides
    case letter
    case personalNotes
    case other

    var domain: DocumentCategory {
        switch self {
        case .invoiceOrReceipt: .invoice
        case .contractOrLegal: .contract
        case .bankStatementOrTaxes: .finance
        case .travelTicketOrBooking: .travel
        case .identityOrOfficialForm: .identity
        case .manualOrGuide: .manual
        case .bookOrPaper: .book
        case .resume: .resume
        case .presentationSlides: .slides
        case .letter: .letter
        case .personalNotes: .notes
        case .other: .other
        }
    }
}

@Generable
private struct VideoVerdict {
    @Guide(description: "What kind of video it is")
    var category: GeneratedVideoCategory
}

@Generable
private enum GeneratedVideoCategory {
    case musicVideo
    case movieOrTVShow
    case tutorialOrTalk
    case personalVideo
    case other

    var domain: VideoCategory {
        switch self {
        case .musicVideo: .musicVideo
        case .movieOrTVShow: .movie
        case .tutorialOrTalk: .tutorial
        case .personalVideo: .personal
        case .other: .other
        }
    }
}

import Foundation
import FoundationModels
import FinderDomain

/// Asks Apple's on-device language model what a document or a video is. Nothing leaves the Mac. The
/// answers are constrained to a fixed list and sampled greedily, so the same input gives the same
/// answer; an actor, so the model gets one question at a time.
public actor FoundationModelsClassifier: LanguageUnderstanding {
    public init() {}

    public nonisolated var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }

    public func documentCategory(name: String, folder: String, excerpt: String) async -> DocumentCategory? {
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
        do {
            let response = try await session.respond(to: prompt, generating: DocumentVerdict.self, options: Self.options)
            return response.content.category.domain
        } catch {
            return nil
        }
    }

    public func videoCategory(name: String, folder: String) async -> VideoCategory? {
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
        do {
            let response = try await session.respond(to: "File name: \(name)", generating: VideoVerdict.self, options: Self.options)
            return response.content.category.domain
        } catch {
            return nil
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

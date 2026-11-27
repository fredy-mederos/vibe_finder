import Foundation
import Vision
import FinderDomain

/// Reads the text in a picture with Vision, on this Mac.
public struct VisionTextRecognizer: TextRecognizing {
    private static let maxCharacters = 20_000

    public init() {}

    public func recognizeText(inImageAt path: String) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path))
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: "\n").prefix(Self.maxCharacters))
    }
}

/// Says what a picture shows with Vision's built-in classifier, on this Mac.
public struct VisionImageClassifier: ImageUnderstanding {
    /// Labels below this aren't worth reporting.
    private static let minimumConfidence: Float = 0.1

    public init() {}

    public func labels(forImageAt path: String) -> [ImageLabel] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path))
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return [] }
        return observations.filter { $0.confidence >= Self.minimumConfidence }
            .map { ImageLabel($0.identifier, Double($0.confidence)) }
    }
}

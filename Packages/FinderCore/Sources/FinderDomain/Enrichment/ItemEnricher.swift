import Foundation

/// An item on its way through enrichment: each step may refine what it is and add to its text.
public struct EnrichmentDraft: Sendable {
    public var item: FileItem
    /// The text found so far, for content search.
    public var text: String?

    public init(item: FileItem, text: String? = nil) {
        self.item = item
        self.text = text
    }
}

/// One step that looks inside a file: reading its metadata, its text, or asking a model. Each step
/// has one job and depends only on the port it needs; the pipeline runs the ones that apply, in order.
public protocol ItemEnricher: Sendable {
    var stage: EnrichmentStages { get }
    /// False while what the step relies on can't be used (a model that isn't downloaded yet): the step
    /// is left out, and the files it would have looked at get it once it's back.
    var isAvailable: Bool { get }
    /// Asked with the item as it is when the step's turn comes, so a step can depend on what the
    /// earlier ones found (text is only read from an image once it's known to be a screenshot).
    func applies(to item: FileItem) -> Bool
    func enrich(_ draft: inout EnrichmentDraft) async
}

public extension ItemEnricher {
    var isAvailable: Bool { true }
}

/// What enrichment learns is stored per file and reused while the file doesn't change. Bump this
/// when a policy or a step changes what it would answer, so stored answers are worked out again.
public enum EnrichmentRules {
    public static let version = 1
}

/// The short facts shown under a name.
public enum DetailFormat {
    public static func dimensions(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }

    /// "0:07", "3:45", "1:02:09".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        let tail = String(format: "%02d", secs)
        return hours > 0 ? "\(hours):" + String(format: "%02d", minutes) + ":" + tail : "\(minutes):" + tail
    }

    public static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

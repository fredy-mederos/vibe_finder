import AppKit
import QuickLookThumbnailing
import FinderDomain

/// Gives the picture that stands for an item: a preview of its content when the system can make one,
/// its icon otherwise.
protocol ThumbnailProviding: AnyObject {
    /// The thumbnail if it's already in memory, without waiting.
    func cachedThumbnail(for item: FileItem, side: CGFloat) -> NSImage?
    func thumbnail(for item: FileItem, side: CGFloat, scale: CGFloat) async -> NSImage?
}

/// Lets a request be cancelled from wherever the task is cancelled: the generator's `cancel` is safe
/// to call from any thread, and the request is only read.
private nonisolated struct PendingRequest: @unchecked Sendable {
    let generator: QLThumbnailGenerator
    let request: QLThumbnailGenerator.Request

    func cancel() {
        generator.cancel(request)
    }
}

/// Thumbnails from Quick Look, the same ones Finder shows, kept in memory by size bucket.
final class QuickLookThumbnailProvider: ThumbnailProviding {
    private let cache = NSCache<NSString, NSImage>()
    private let generator = QLThumbnailGenerator.shared
    /// Thumbnails are made at these sizes, so dragging the size slider doesn't regenerate each step.
    private static let buckets: [CGFloat] = [48, 128, 256, 512]

    init() {
        cache.countLimit = 3000
    }

    func cachedThumbnail(for item: FileItem, side: CGFloat) -> NSImage? {
        cache.object(forKey: key(for: item, bucket: Self.bucket(for: side)))
    }

    func thumbnail(for item: FileItem, side: CGFloat, scale: CGFloat) async -> NSImage? {
        let bucket = Self.bucket(for: side)
        let key = key(for: item, bucket: bucket)
        if let cached = cache.object(forKey: key) { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: item.path), size: CGSize(width: bucket, height: bucket),
                                                   scale: scale, representationTypes: .all)
        // A request that scrolled away is withdrawn, so the ones on screen come first.
        let pending = PendingRequest(generator: generator, request: request)
        let image: NSImage? = await withTaskCancellationHandler {
            try? await generator.generateBestRepresentation(for: request).nsImage
        } onCancel: {
            pending.cancel()
        }
        guard !Task.isCancelled else { return nil }
        let result = image ?? NSWorkspace.shared.icon(forFile: item.path)
        cache.setObject(result, forKey: key)
        return result
    }

    private func key(for item: FileItem, bucket: CGFloat) -> NSString {
        "\(item.path)|\(item.modified.timeIntervalSinceReferenceDate)|\(Int(bucket))" as NSString
    }

    private static func bucket(for side: CGFloat) -> CGFloat {
        buckets.first { $0 >= side } ?? buckets[buckets.count - 1]
    }
}

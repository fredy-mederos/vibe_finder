import Foundation
import ImageIO
import AVFoundation
import FinderDomain

/// Reads an image's header with ImageIO: its size and what the camera or the system wrote into it.
/// The pixels are never decoded.
public struct ImageIOInspector: ImageInspecting {
    public init() {}

    public func facts(forImageAt path: String) -> ImageFacts? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // Orientations 5 to 8 are stored on their side.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String) ?? (exif?[kCGImagePropertyExifLensModel] as? String)
        let comment = exif?[kCGImagePropertyExifUserComment] as? String
        return ImageFacts(
            width: width, height: height,
            cameraModel: model?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            isMarkedScreenshot: comment?.caseInsensitiveCompare("Screenshot") == .orderedSame
        )
    }
}

/// Reads duration, picture size and tags of audio and video with AVFoundation.
public struct AVFoundationInspector: MediaInspecting {
    public init() {}

    public func facts(forMediaAt path: String) async -> MediaFacts? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        var facts = MediaFacts(duration: duration.seconds)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let shown = size.applying(transform)
            facts.width = Int(abs(shown.width).rounded())
            facts.height = Int(abs(shown.height).rounded())
        }
        facts.hasAudio = ((try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false)
        if let metadata = try? await asset.load(.commonMetadata) {
            facts.title = await Self.string(.commonIdentifierTitle, in: metadata)
            facts.artist = await Self.string(.commonIdentifierArtist, in: metadata)
            facts.album = await Self.string(.commonIdentifierAlbumName, in: metadata)
        }
        return facts
    }

    private static func string(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first else { return nil }
        return (try? await item.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

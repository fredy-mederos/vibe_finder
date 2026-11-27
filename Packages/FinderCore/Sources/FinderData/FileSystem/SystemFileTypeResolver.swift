import Foundation
import UniformTypeIdentifiers
import FinderDomain

/// Asks the system's type database about extensions the domain's table doesn't list.
public struct SystemFileTypeResolver: FileTypeResolving {
    public init() {}

    public func family(forExtension ext: String) -> FileFamily? {
        guard let type = UTType(filenameExtension: ext), !type.isDynamic else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .sourceCode }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .font) { return .font }
        if type.conforms(to: .spreadsheet) { return .spreadsheet }
        if type.conforms(to: .presentation) { return .presentation }
        if type.conforms(to: .plainText) { return .text }
        return nil
    }
}

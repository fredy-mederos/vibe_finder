import Foundation
import AppKit
import PDFKit
import FinderDomain

/// Gets the text out of the document formats the system can read: plain text and code, PDF (PDFKit),
/// Word, RTF and OpenDocument (the system's importers), and the XML inside Excel and PowerPoint files.
public struct DocumentTextExtractor: TextExtracting {
    /// Bytes read from a plain-text file; more than enough to find it by what it says.
    private static let maxPlainBytes = 512 * 1024
    private static let maxCharacters = 200_000
    private static let maxPDFPages = 60

    private static let plainKinds: Set<Kind> = [.notes, .code]
    private static let plainExtensions: Set<String> = ["csv", "tsv", "log", "tex", "srt", "vtt", "ics", "vcf"]
    private static let richExtensions: Set<String> = ["doc", "docx", "rtf", "rtfd", "odt"]
    /// Office files are zip archives; these are the parts with the words in them.
    private static let officeParts: [String: [String]] = [
        "xlsx": ["xl/sharedStrings.xml"],
        "xlsm": ["xl/sharedStrings.xml"],
        "pptx": ["ppt/slides/slide*.xml"],
        "ppsx": ["ppt/slides/slide*.xml"],
    ]

    public init() {}

    public func canExtractText(from item: FileItem) -> Bool {
        if item.kind == .pdfs || Self.richExtensions.contains(item.ext) || Self.officeParts[item.ext] != nil { return true }
        return Self.plainKinds.contains(item.kind) || Self.plainExtensions.contains(item.ext)
    }

    public func text(of item: FileItem) -> String? {
        let url = URL(fileURLWithPath: item.path)
        let text: String?
        if item.ext == "pdf" {
            text = pdfText(url)
        } else if Self.richExtensions.contains(item.ext) {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        } else if let parts = Self.officeParts[item.ext] {
            text = officeText(url, parts: parts)
        } else {
            text = plainText(url)
        }
        return text.map { String($0.prefix(Self.maxCharacters)) }
    }

    private func plainText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maxPlainBytes), !data.isEmpty else { return nil }
        // A NUL near the start means it isn't text, whatever its extension says.
        if data.prefix(4096).contains(0) { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func pdfText(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url), !document.isLocked else { return nil }
        var text = ""
        for index in 0..<min(document.pageCount, Self.maxPDFPages) {
            if let page = document.page(at: index)?.string {
                text += page + "\n"
            }
            if text.count >= Self.maxCharacters { break }
        }
        return text
    }

    private func officeText(_ url: URL, parts: [String]) -> String? {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", url.path] + parts
        let output = Pipe()
        unzip.standardOutput = output
        unzip.standardError = FileHandle.nullDevice
        guard (try? unzip.run()) != nil else { return nil }
        let data = (try? output.fileHandleForReading.read(upToCount: 4 * 1024 * 1024)) ?? Data()
        if unzip.isRunning { unzip.terminate() }
        let xml = String(decoding: data, as: UTF8.self)
        return xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

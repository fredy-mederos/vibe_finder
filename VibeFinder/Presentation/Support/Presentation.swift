import SwiftUI
import FinderDomain

// How the domain's values are put into words, symbols and colors. The domain knows nothing of these.

extension Kind {
    var title: String {
        switch self {
        case .projects: String(localized: "Projects")
        case .apps: String(localized: "Apps")
        case .photos: String(localized: "Photos")
        case .screenshots: String(localized: "Screenshots")
        case .images: String(localized: "Images")
        case .videos: String(localized: "Videos")
        case .screenRecordings: String(localized: "Screen Recordings")
        case .musicVideos: String(localized: "Music Videos")
        case .music: String(localized: "Music")
        case .audio: String(localized: "Recordings & Sounds")
        case .pdfs: String(localized: "PDFs")
        case .documents: String(localized: "Documents")
        case .notes: String(localized: "Notes & Text")
        case .spreadsheets: String(localized: "Spreadsheets")
        case .presentations: String(localized: "Presentations")
        case .books: String(localized: "Books")
        case .archives: String(localized: "Archives")
        case .installers: String(localized: "Installers")
        case .design: String(localized: "Design")
        case .fonts: String(localized: "Fonts")
        case .code: String(localized: "Code")
        case .keys: String(localized: "Keys & Certificates")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .projects: "hammer"
        case .apps: "app.dashed"
        case .photos: "photo"
        case .screenshots: "camera.viewfinder"
        case .images: "photo.on.rectangle.angled"
        case .videos: "film"
        case .screenRecordings: "record.circle"
        case .musicVideos: "music.note.tv"
        case .music: "music.note"
        case .audio: "waveform"
        case .pdfs: "doc.richtext"
        case .documents: "doc.text"
        case .notes: "note.text"
        case .spreadsheets: "tablecells"
        case .presentations: "play.rectangle"
        case .books: "book"
        case .archives: "archivebox"
        case .installers: "shippingbox"
        case .design: "paintbrush.pointed"
        case .fonts: "textformat"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .keys: "key"
        case .other: "questionmark.folder"
        }
    }

    var color: Color { group.color }
}

extension KindGroup {
    var title: String {
        switch self {
        case .work: String(localized: "Work")
        case .pictures: String(localized: "Pictures")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .documents: String(localized: "Documents")
        case .files: String(localized: "Files")
        }
    }

    var color: Color {
        switch self {
        case .work: .indigo
        case .pictures: .orange
        case .video: .pink
        case .audio: .purple
        case .documents: .blue
        case .files: .gray
        }
    }
}

extension ClassificationSource {
    /// "Recognized by …".
    var title: String {
        switch self {
        case .fileType: String(localized: "file type")
        case .fileName: String(localized: "file name")
        case .metadata: String(localized: "file metadata")
        case .vision: String(localized: "Apple Vision, on this Mac")
        case .languageModel: String(localized: "Apple Intelligence, on this Mac")
        }
    }
}

extension Arrangement {
    var title: String {
        switch self {
        case .date: String(localized: "Date")
        case .name: String(localized: "Name")
        case .size: String(localized: "Size")
        case .type: String(localized: "Type")
        case .folder: String(localized: "Folder")
        }
    }
}

extension SectionKey {
    var title: String {
        switch self {
        case .all: ""
        case .today: String(localized: "Today")
        case .previous7Days: String(localized: "Previous 7 Days")
        case .previous30Days: String(localized: "Previous 30 Days")
        case .month(let year, let month):
            Calendar.current.date(from: DateComponents(year: year, month: month))?
                .formatted(.dateTime.month(.wide).year()) ?? String(year)
        case .year(let year): String(year)
        case .subkind(let name): name
        case .folder(let path): path.abbreviatingHome
        case .kind(let kind): kind.title
        }
    }
}

extension String {
    /// "/Users/me/Documents" as "~/Documents".
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}

extension Int64 {
    var formattedFileSize: String {
        formatted(.byteCount(style: .file))
    }
}

extension FileItem {
    /// The line under the name in the grid: what's known about the file, or else when it's from.
    var caption: String {
        detail.isEmpty ? modified.formatted(date: .abbreviated, time: .omitted) : detail
    }

    /// Packages and folders don't report a size.
    var sizeText: String {
        size > 0 ? size.formattedFileSize : "—"
    }
}

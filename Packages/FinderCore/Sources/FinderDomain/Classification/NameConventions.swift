import Foundation

/// A pattern in a file's (lowercased) name that tells what the file is.
struct NameConvention: @unchecked Sendable {
    // NSRegularExpression is immutable and documented as thread-safe.
    private let regex: NSRegularExpression
    let kind: Kind
    let subkind: String

    init(_ pattern: String, _ kind: Kind, _ subkind: String) {
        // The patterns are constants; one that doesn't compile is a programming error.
        regex = try! NSRegularExpression(pattern: pattern)
        self.kind = kind
        self.subkind = subkind
    }

    func matches(_ name: String) -> Bool {
        regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}

/// The naming conventions the app knows, first match wins. Names are matched lowercased, with the
/// extension.
enum NameConventions {
    /// How macOS names a screenshot, in the languages it's most used in.
    private static let macScreenshot = "captura de pantalla|bildschirmfoto|capture d[’']écran|schermata|schermafbeelding"
        + "|captura de ecrã|captura de tela|snímek obrazovky|zrzut ekranu|skärmavbild|ekran resmi|снимок экрана"
        + "|スクリーンショット|截屏|截圖|스크린샷"

    private static let macRecording = "screen recording|grabación de pantalla|bildschirmaufnahme"
        + "|enregistrement de l[’']écran|registrazione schermo|gravação de (ecrã|tela)|schermopname"

    static let images: [NameConvention] = [
        NameConvention(#"^simulator screen ?shot"#, .screenshots, "iOS Simulator"),
        NameConvention(#"^screenshot_\d"#, .screenshots, "Android"),
        NameConvention(#"^(screenshot|screen shot) \d{4}-\d{2}-\d{2}"#, .screenshots, "Mac"),
        NameConvention("^(\(macScreenshot))", .screenshots, "Mac"),
        NameConvention(#"^cleanshot"#, .screenshots, "Mac"),
        // An iPhone only saves PNG for screenshots; its photos are HEIC or JPEG.
        NameConvention(#"^img_\d{3,}\.png$"#, .screenshots, "iPhone"),
        NameConvention(#"screenshot|screen[ _-]shot|screen[ _-]capture|screencap"#, .screenshots, "Other screenshots"),
        NameConvention(#"^(chatgpt image|dall[·-]?e|gemini_generated_image|midjourney|firefly )"#, .images, "AI generated"),
        NameConvention(#"^whatsapp image|^img-\d{8}-wa\d+"#, .photos, "Messaging"),
        NameConvention(#"^photo_\d{4}-\d{2}-\d{2}|^signal-\d{4}"#, .photos, "Messaging"),
        NameConvention(#"^(img|dsc|dscn|dscf|pxl|mvimg|dji|gopr)[_-]?\d{3,}.*\.(jpe?g|tiff?)$"#, .photos, "Camera"),
        NameConvention(#"^\d{8}_\d{6}.*\.jpe?g$"#, .photos, "Camera"),
    ]

    static let videos: [NameConvention] = [
        NameConvention(#"^simulator screen recording"#, .screenRecordings, "iOS Simulator"),
        // ReplayKit's and iOS's own names for a recording of the screen.
        NameConvention(#"^rpreplay[_-]final|^screenrecording_\d"#, .screenRecordings, "iPhone"),
        NameConvention("^(\(macRecording))", .screenRecordings, "Mac"),
        NameConvention(#"^(screen-\d{8}|screenrecorder|screen_recording|screenrecord)"#, .screenRecordings, "Android"),
        NameConvention(#"screen[ _-]?record|screencast|screen[ _-]capture"#, .screenRecordings, "Other recordings"),
        NameConvention(#"official (music |lyric )?video|music video|video oficial|videoclip|lyrics? video|\(lyrics?\)|\[mv\]|\(mv\)|vevo|official audio|visualizer"#,
                       .musicVideos, "Music videos"),
        NameConvention(#"^whatsapp video|^vid-\d{8}-wa\d+|^video_\d{4}-\d{2}-\d{2}|^signal-\d{4}"#, .videos, "Messaging"),
        NameConvention(#"^(img|mvi|dji|gx|gh|gopr|pxl|vid)[_-]?\d{4,}"#, .videos, "Camera"),
        NameConvention(#"^videoplayback"#, .videos, "Web downloads"),
    ]

    static let audio: [NameConvention] = [
        NameConvention(#"^(new recording|recording|grabación|nueva grabación|aufnahme|neue aufnahme|voice|memo)\b"#,
                       .audio, "Voice & recordings"),
        NameConvention(#"^whatsapp (audio|ptt)|^(ptt|aud)-\d{8}-wa\d+|^audio_\d{4}-\d{2}-\d{2}"#, .audio, "Voice & recordings"),
    ]
}

/// Pixel sizes only a screen produces, to tell a screenshot from a drawing when the name says nothing.
public enum ScreenSizes {
    /// The kind of device whose screen is exactly this big, in either orientation.
    public static func device(width: Int, height: Int) -> String? {
        table[Size(short: min(width, height), long: max(width, height))]
    }

    private struct Size: Hashable {
        let short: Int
        let long: Int
    }

    private static let table: [Size: String] = {
        var table: [Size: String] = [:]
        func add(_ device: String, _ sizes: [(Int, Int)]) {
            for (a, b) in sizes { table[Size(short: min(a, b), long: max(a, b))] = device }
        }
        // Later lines win where two devices share a size.
        add("Android", [(1080, 2400), (1080, 2340), (1440, 3200), (1440, 3120), (1080, 2280), (1080, 2160), (1440, 2560),
                        (1344, 2992), (1008, 2244), (1080, 2424), (1440, 3088), (720, 1600), (1080, 2408), (1080, 2412),
                        (1220, 2712), (1080, 2316), (1080, 2310), (1440, 2960), (1280, 2856)])
        add("Desktop", [(1920, 1080), (2560, 1440), (3840, 2160), (1366, 768), (1440, 900), (1680, 1050), (1920, 1200),
                        (3440, 1440), (2560, 1080)])
        add("Mac", [(2880, 1800), (2560, 1600), (3024, 1964), (3456, 2234), (2560, 1664), (2880, 1864), (5120, 2880),
                    (4480, 2520), (6016, 3384), (2304, 1440), (4096, 2304), (3420, 2214), (2940, 1912)])
        add("iPad", [(1536, 2048), (2048, 2732), (1668, 2224), (1668, 2388), (1640, 2360), (1620, 2160), (1488, 2266),
                     (2064, 2752), (1668, 2420), (768, 1024)])
        add("iPhone", [(640, 1136), (750, 1334), (1242, 2208), (1125, 2436), (828, 1792), (1242, 2688), (1170, 2532),
                       (1284, 2778), (1179, 2556), (1290, 2796), (1206, 2622), (1320, 2868), (1260, 2736)])
        return table
    }()
}

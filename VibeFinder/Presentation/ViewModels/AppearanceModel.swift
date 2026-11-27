import AppKit
import Observation

/// How the app looks: like the rest of the system, or always light or dark.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The user's choice of appearance: remembered between launches and applied to every window.
@Observable
final class AppearanceModel {
    var choice: AppAppearance {
        didSet {
            guard choice != oldValue else { return }
            preferences.set(choice.rawValue, forKey: Self.key)
            apply()
        }
    }

    private let preferences: UserDefaults
    private static let key = "appearance"

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        choice = preferences.string(forKey: Self.key).flatMap(AppAppearance.init) ?? .system
        apply()
    }

    private func apply() {
        NSApplication.shared.appearance = choice.appearance
    }
}

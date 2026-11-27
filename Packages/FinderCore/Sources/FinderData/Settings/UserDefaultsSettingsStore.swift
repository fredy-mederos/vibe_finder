import Foundation
import FinderDomain

/// Keeps the library's settings in the app's preferences, as JSON under one key.
public struct UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
    // UserDefaults is thread-safe.
    private let defaults: UserDefaults
    private let home: String
    private static let key = "library.settings"

    public init(defaults: UserDefaults = .standard, home: String = NSHomeDirectory()) {
        self.defaults = defaults
        self.home = home
    }

    public func load() -> LibrarySettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(LibrarySettings.self, from: data) else {
            return .standard(home: home)
        }
        return settings
    }

    public func save(_ settings: LibrarySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Settings that only live for one run: tests and debug launches that mustn't touch the user's own.
public final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: LibrarySettings

    public init(_ settings: LibrarySettings) {
        self.settings = settings
    }

    public func load() -> LibrarySettings {
        lock.withLock { settings }
    }

    public func save(_ settings: LibrarySettings) {
        lock.withLock { self.settings = settings }
    }
}

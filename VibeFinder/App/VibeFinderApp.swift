import SwiftUI
import FinderDomain

@main
struct VibeFinderApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        Window("Vibe Finder", id: "main") {
            MainWindow(container: container)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            LibraryCommands(library: container.library, browser: container.browser)
        }

        Settings {
            SettingsView(library: container.library)
        }
    }
}

struct LibraryCommands: Commands {
    let library: LibraryViewModel
    let browser: BrowserViewModel

    var body: some Commands {
        @Bindable var browser = browser
        CommandGroup(after: .toolbar) {
            Picker("Layout", selection: $browser.layout) {
                Text("as Grid").tag(BrowserLayout.grid).keyboardShortcut("1")
                Text("as List").tag(BrowserLayout.list).keyboardShortcut("2")
            }
            .pickerStyle(.inline)
            Picker("Arrange By", selection: $browser.arrangement) {
                ForEach(Arrangement.allCases, id: \.self) { arrangement in
                    Text(arrangement.title).tag(arrangement)
                }
            }
            Divider()
            Button("Scan Folders Again") { library.rescan() }
                .keyboardShortcut("r")
            Divider()
        }
    }
}

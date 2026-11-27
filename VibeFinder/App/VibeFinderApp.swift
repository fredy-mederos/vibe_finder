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
            LibraryCommands(library: container.library, browser: container.browser, updater: container.updater)
        }

        Settings {
            SettingsView(library: container.library, appearance: container.appearance, updater: container.updater)
        }
    }
}

struct LibraryCommands: Commands {
    let library: LibraryViewModel
    let browser: BrowserViewModel
    let updater: AppUpdater

    var body: some Commands {
        @Bindable var browser = browser
        CommandGroup(after: .appInfo) {
            Button(updater.isChecking ? "Checking for Updates…" : "Check for Updates…") { updater.checkFromMenu() }
                .disabled(updater.isChecking)
        }
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
            Button(browser.showsInspector ? "Hide Inspector" : "Show Inspector") { browser.showsInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Button("Collapse All Groups") { browser.setAllSectionsCollapsed(true) }
                .disabled(!browser.canCollapseSections)
            Button("Expand All Groups") { browser.setAllSectionsCollapsed(false) }
                .disabled(browser.collapsedSections.isEmpty)
            Divider()
            Button("Scan Folders Again") { library.rescan() }
                .keyboardShortcut("r")
            Divider()
        }
        // No shortcut here on purpose: Command-Delete works in the list (and shows in its menu), and
        // must stay what it is while typing in the search field.
        CommandGroup(replacing: .newItem) {
            Button("Move to Trash…") { browser.requestTrashOfSelection() }
                .disabled(browser.selection.isEmpty)
        }
    }
}

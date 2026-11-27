import SwiftUI
import FinderDomain

struct SettingsView: View {
    let library: LibraryViewModel
    let appearance: AppearanceModel
    let updater: AppUpdater

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(library: library, appearance: appearance)
            }
            Tab("About", systemImage: "info.circle") {
                Form {
                    AboutSection()
                    UpdatesSection(updater: updater)
                }
                .formStyle(.grouped)
            }
        }
        // A fixed size the forms scroll in: with many folders the list would grow past the screen.
        .frame(width: 540, height: 560)
    }
}

/// What's indexed, what's shown and how files are understood.
private struct GeneralSettings: View {
    let library: LibraryViewModel
    let appearance: AppearanceModel

    var body: some View {
        @Bindable var appearance = appearance
        Form {
            Section {
                Picker("Appearance", selection: $appearance.choice) {
                    ForEach(AppAppearance.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            }
            FoldersSection(library: library)
            Section {
                Toggle("Include apps from the Applications folders", isOn: binding(\.includesApplications))
                Toggle("Show pictures and documents inside code projects", isOn: binding(\.includesProjectFiles))
            } header: {
                Text("What to Show")
            } footer: {
                Text("A project's folder is always listed under Projects. Its source files never are.")
            }
            Section {
                Toggle("Read the text in screenshots and images", isOn: binding(\.readsTextInImages))
                Toggle("Let Apple's on-device models decide what the rules can't", isOn: binding(\.usesOnDeviceModels))
                Toggle("Describe pictures and documents in a line", isOn: binding(\.describesItems))
                    .disabled(!library.settings.usesOnDeviceModels)
                    .help("The on-device model writes one line about each picture and document, once. It's kept, shown in the inspector and the list, and found by search.")
                LabeledContent("Index") {
                    Button("Rebuild…") { library.rebuildIndex() }
                        .help("Forget what was learned about every file and look inside all of them again")
                }
            } header: {
                Text("Understanding Files")
            } footer: {
                Text("File types and naming conventions always decide first. Everything about your files runs on this Mac; nothing about them is sent anywhere.")
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: WritableKeyPath<LibrarySettings, Bool>) -> Binding<Bool> {
        Binding {
            library.settings[keyPath: keyPath]
        } set: { newValue in
            library.update { $0[keyPath: keyPath] = newValue }
        }
    }
}

private struct FoldersSection: View {
    let library: LibraryViewModel
    @State private var isChoosing = false

    var body: some View {
        Section {
            ForEach(library.settings.folders, id: \.self) { folder in
                HStack {
                    Label(folder.abbreviatingHome, systemImage: "folder")
                    Spacer()
                    if library.unreadableFolders.contains(folder) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help("Vibe Finder can't read this folder")
                    }
                    Button {
                        library.update { $0.folders.removeAll { $0 == folder } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop indexing this folder")
                }
            }
            Button("Add Folder…") { isChoosing = true }
        } header: {
            Text("Folders")
        } footer: {
            Text("Everything under these folders is indexed, however deep. Files are never moved or changed.")
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            library.update { settings in
                for url in urls where !settings.folders.contains(url.path) {
                    settings.folders.append(url.path)
                }
            }
        }
    }
}

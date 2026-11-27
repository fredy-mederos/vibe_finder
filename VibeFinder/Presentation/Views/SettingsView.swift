import SwiftUI
import FinderDomain

struct SettingsView: View {
    let library: LibraryViewModel

    var body: some View {
        Form {
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
                LabeledContent("Index") {
                    Button("Rebuild…") { library.rebuildIndex() }
                        .help("Forget what was learned about every file and look inside all of them again")
                }
            } header: {
                Text("Understanding Files")
            } footer: {
                Text("File types and naming conventions always decide first. Everything runs on this Mac; nothing is sent anywhere.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
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

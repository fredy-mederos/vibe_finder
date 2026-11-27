# CLAUDE.md

Personal side project: Vibe Finder, a native macOS app that shows what's in your folders by what
things are (projects, apps, photos, screenshots, screen recordings, music videos, PDFs…) instead of
by where they are. It indexes the folders as they are; the only change it can make to them is moving
what the user selects to the Trash, after asking. Read `README.md` first: it describes what's shipped.

## Architecture: Clean Architecture, enforced by modules

Dependencies point inward, and the compiler checks it: the two inner layers are targets of the local
package `Packages/FinderCore`, the outer one is the app.

- **`FinderDomain`** (Foundation only): entities (`Kind`, `FileItem`, `FileFacts`…), the
  classification rules, the enrichment steps and their policies, the use cases (`ScanLibrary`,
  `EnrichLibrary`, `ArrangeItems`, `SummarizeLibrary`, `SearchContent`) and the ports they need
  (`Ports/Ports.swift`). No file system, database, UI or model framework is imported here, ever.
- **`FinderData`**: one adapter per port (`FileSystemScanner`, `SQLiteIndexStore`, `ImageIOInspector`,
  `AVFoundationInspector`, `DocumentTextExtractor`, `VisionTextRecognizer`, `VisionImageClassifier`,
  `FoundationModelsClassifier`, `FSEventsFolderWatcher`, `UserDefaultsSettingsStore`). Adapters fetch
  facts; they don't decide what a file is.
- **App** (`VibeFinder/`): `Presentation/` has the view models (`@Observable`, they only gather
  inputs and call use cases), the SwiftUI views, the AppKit collection view and the presentation
  services behind their own protocols (`ThumbnailProviding`, `FileActing`). `App/AppContainer.swift`
  is the composition root: the only file that imports `FinderData` and wires adapters to ports.

SOLID, concretely:

- A new naming convention or a new way to recognize something is a new `ClassificationRule`,
  `NameConvention` or `ItemEnricher` added to the list in `RuleBasedClassifier.standard` or
  `AppContainer`; the classifier and the pipeline don't change (open/closed).
- Ports are small and named for what the domain needs (`ImageInspecting`, `TextRecognizing`,
  `ContentSearching`…). One class may implement several (`SQLiteIndexStore`), but nothing depends on
  more than it uses.
- What a fact *means* is a pure policy in the domain (`ImageFactsPolicy`, `ImageLabelPolicy`,
  `MediaFactsPolicy`, `VideoCategoryPolicy`), tested with plain values. The step that fetches the
  fact (`…Enricher`) only calls the port and the policy.
- How things are shown (titles, SF Symbols, colors, section titles) lives in
  `Presentation/Support/Presentation.swift`, never in the domain.

## How a file gets its kind (keep this order)

1. **Rules, always first and deterministic**: the extension (`FileFormatCatalog`), then naming
   conventions, the macOS screen-capture flag, where it lives. Nothing opens the file.
2. **What the file says about itself** (enrichment): pixel size and camera (ImageIO), duration and
   tags (AVFoundation).
3. **Apple's on-device models, only for what's still unclear**: Vision's classifier for images, the
   Foundation Models language model for what a document or a video is. Constrained to a fixed list,
   greedy sampling, and a model only moves an item when it's confident.

A project's picture follows the same idea (`ProjectArtworkRules`): only the places tools themselves
keep an icon in (an asset catalog's app icon, an Android launcher icon, a web project's favicon),
scored so the same project always gets the same one; the folder search is `FileSystemProjectArtworkFinder`.
How it's drawn on the folder, and the technology marks (plain symbols and letters, never a
third-party logo), is `Presentation/Services/ProjectThumbnailProvider.swift`.

Answers are stored in the index with the file's size and date and reused until the file changes, so
the same file keeps its kind. `ClassificationSource` records which of these decided, and the UI shows
it. When a rule, policy or prompt changes what it would answer, bump `EnrichmentRules.version`: the
stored answers are dropped and worked out again. Nothing leaves the Mac; don't add network calls.

## Working on it

- Package: `cd Packages/FinderCore && swift test`. Every rule and policy change comes with a test.
  Swift 6 language mode, tools 6.2, macOS 26.
- App: `xcodebuild -project VibeFinder.xcodeproj -scheme VibeFinder -configuration Debug -derivedDataPath build/DerivedData build`.
  Swift 6, default MainActor isolation, macOS 26 deployment target. Keep the build free of warnings.
  The project uses a synchronized folder: files added under `VibeFinder/` are compiled automatically;
  don't add them to `project.pbxproj` by hand.
- Big lists stay in AppKit (`Presentation/Collection/`): a kind can hold tens of thousands of items.
- Check UI changes with `scripts/snapshot.sh <out.png> <seconds> [debug launch args]`. It runs a
  separate copy of the Debug build on a made-up library (`scripts/make-sample-library.swift`) with
  its own index and its own preferences, and captures only that copy's window. The user usually has
  their own Vibe Finder open on their real library: never quit it (no `pkill`), never take
  screenshots of it, and keep sample folders outside ~/Documents, ~/Desktop and ~/Downloads (macOS
  would ask for a permission nobody is there to give). Debug launch arguments are listed above
  `LaunchOptions` in `App/AppContainer.swift`.
- To try what a click does, keep the copy running (`VF_KEEP=1 scripts/snapshot.sh …` prints its
  process id), press things by their accessibility label with `swift scripts/press.swift <pid> "Move
  to Trash"` (buttons, group headers, menu items, a dialog's buttons) and capture again with
  `scripts/capture.sh <pid> <out.png>`. Never post synthetic mouse clicks at screen coordinates: they
  land on whatever window is on top. So new controls need to be real buttons with a label.
- The app looks, it doesn't reorganize: it opens, previews, reveals and copies paths. The one
  exception is Move to Trash (`TrashItems`), which the user asked for: only on an explicit action,
  always after a confirmation, and only ever to the Trash (`ItemTrashing` has no way to delete for
  good; don't add one). Don't add anything else that moves or renames the user's files unless the
  user asks for that feature.
- Libraries behind a privacy permission of their own (`ScanPolicy.sealedExtensions`: the Photos
  library) are never listed, never asked for a thumbnail and never watched: touching one makes macOS
  ask the user for access to their photos. If the app should ever show what's inside Photos, that's
  PhotoKit with the permission asked on purpose, not the file system.
- The appearance (system, light, dark) is `AppearanceModel`, applied to the whole app.
- Collapsed groups are view state (`BrowserViewModel.collapsedSections`, per place, kept while the
  app runs). A folded group still has its header and count; its items aren't selected.
- `scripts/install.sh` builds Release into ~/Applications. `scripts/make-icon.swift` draws the icon
  into the asset catalog.

## Text

- The UI is in English. SwiftUI literals are localizable as they are; text that becomes a `String`
  first goes through `String(localized:)`. Counts are `Int` interpolations with the English singular
  in `VibeFinder/Localizable.xcstrings`. Subkind names ("iOS Simulator", "Invoices & receipts") are
  data from the domain and aren't translated yet.

## Git

- Remote: `github.com/fredy-mederos/vibe_finder`. Commits use the repo-local identity
  `Fredy Mederos <fmfredd@gmail.com>`; don't change it to the work address.
- Nothing about the user's employer goes into the repository: no names, ticket keys or real file
  names, in code, samples, tests or commit messages. Use neutral samples (Acme, `scan0042.pdf`).

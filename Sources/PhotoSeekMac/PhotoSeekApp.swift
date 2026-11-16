import SwiftUI
import AppKit
import PhotoSeekCore

@main
struct PhotoSeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(viewModel: delegate.viewModel, onSearch: delegate.togglePanel)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
    }

    private struct MenuBarContent: View {
        @Bindable var viewModel: SearchViewModel
        let onSearch: () -> Void

        var body: some View {
            Button("Search Photos") { onSearch() }
            if viewModel.isIndexing {
                Button("Indexing (\(viewModel.indexingDone)/\(viewModel.indexingTotal))") {}
                    .disabled(true)
            }
            Divider()
            Button("Quit PhotoSeek") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private static var menuBarIcon: NSImage {
        guard let path = AppResourceBundle.bundle.path(forResource: "MenuBarIcon", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return NSImage()
        }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController!
    private let store: VectorStore
    let viewModel: SearchViewModel

    override init() {
        let store = VectorStore()
        self.store = store
        self.viewModel = SearchViewModel(store: store)
        super.init()
        viewModel.photoActions = MacPhotoActionsAdapter()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = PanelController(viewModel: viewModel)
        promptForPhotosLibraryAccessIfNeeded()
    }

    /// One-time prompt on launch when the Photos Library can't be read. Avoids
    /// silently presenting an empty grid / zero-count scan after a fresh
    /// install or after a TCC grant was lost (e.g. signing identity changed).
    private func promptForPhotosLibraryAccessIfNeeded() {
        let access = PhotosLibraryAccess.shared
        guard !access.canReadLibrary else { return }

        let alert = NSAlert()
        alert.messageText = "Grant access to your Photos Library"
        alert.informativeText = "PhotoSeek reads your Photos Library directly from disk to index photos and load thumbnails. macOS requires you to grant this access once."
        alert.addButton(withTitle: "Choose Library…")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            access.requestAccess()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await store.close() }
    }

    func togglePanel() {
        panelController.toggle()
    }
}

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await store.close() }
    }

    func togglePanel() {
        panelController.toggle()
    }
}

import SwiftUI
import AppKit
import PhotoSeekCore

@main
struct PhotoSeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            Button("Search Photos") {
                delegate.togglePanel()
            }
            Divider()
            Button("Quit PhotoSeek") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
    }

    private static var menuBarIcon: NSImage {
        guard let path = Bundle.module.path(forResource: "MenuBarIcon", ofType: "png"),
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
    private let store = VectorStore()
    private(set) var viewModel: SearchViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        viewModel = SearchViewModel(store: store)
        viewModel.photoActions = MacPhotoActionsAdapter()
        panelController = PanelController(viewModel: viewModel)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await store.close() }
    }

    func togglePanel() {
        panelController.toggle()
    }
}

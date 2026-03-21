import SwiftUI
import AppKit

@main
struct PhotoSeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("PhotoSeek", systemImage: "sparkle.magnifyingglass") {
            Button("Search Photos  \u{2318}\u{21E7}F") {
                delegate.togglePanel()
            }
            Divider()
            Button("Quit PhotoSeek") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController!
    private let hotkeyManager = HotkeyManager()
    private let store = VectorStore()
    private var viewModel: SearchViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        viewModel = SearchViewModel(store: store)
        panelController = PanelController(viewModel: viewModel)

        hotkeyManager.onToggle = { [weak self] in
            DispatchQueue.main.async {
                self?.togglePanel()
            }
        }
        hotkeyManager.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
    }

    func togglePanel() {
        panelController.toggle()
    }
}

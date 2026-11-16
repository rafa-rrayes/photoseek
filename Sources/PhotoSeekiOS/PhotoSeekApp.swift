#if os(iOS)
import SwiftUI
import Photos
import PhotoSeekCore

@main
struct PhotoSeekApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = VectorStore()
    @State private var viewModel: SearchViewModel?
    @State private var authStatus: PHAuthorizationStatus = .notDetermined

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel {
                    iOSContentView(viewModel: viewModel)
                } else {
                    ProgressView("Loading...")
                }
            }
            .task {
                authStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                let vm = SearchViewModel(store: store)
                vm.photoProvider = iOSPhotoProvider()
                vm.photoActions = iOSPhotoActions()
                viewModel = vm
                await vm.loadStore()

                // Wire the background indexer to the live view model and resume
                // anything that was left unfinished by a prior suspension.
                BackgroundIndexer.shared.attach(viewModel: vm)
                await vm.resumeIndexingIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                BackgroundIndexer.shared.applicationDidEnterBackground()
            case .active:
                BackgroundIndexer.shared.applicationDidBecomeActive()
            default:
                break
            }
        }
    }
}

/// SwiftUI has no modifier for BGTaskScheduler registration, and BGTask
/// identifiers must be registered before launch finishes, so we bridge in a
/// UIApplicationDelegate for that one responsibility.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundIndexer.shared.registerBackgroundTask()
        return true
    }
}
#endif

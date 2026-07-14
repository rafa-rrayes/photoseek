#if os(iOS)
import SwiftUI
import Photos
import DejaViCore

@main
struct DejaViApp: App {
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
            }
        }
    }
}
#endif

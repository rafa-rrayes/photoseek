#if os(iOS)
import Foundation
import UIKit
import BackgroundTasks
import DejaViCore

/// Coordinates iOS background execution for photo/video indexing.
///
/// Three complementary pieces:
///
/// 1. `beginBackgroundTask` assertion — when the app is backgrounded *while*
///    indexing, we request the extra ~30s of runtime iOS grants so in-flight
///    embeds can finish and commit to the store instead of being killed
///    instantly. The assertion is ended on expiration or on return to
///    foreground.
///
/// 2. `BGProcessingTask` (`BGTaskScheduler`) — a deferrable task iOS launches
///    later (typically on charger + Wi-Fi) to resume indexing. Each run chips
///    away at the backlog and reschedules itself while work remains.
///
/// 3. Foreground / launch auto-resume — `SearchViewModel.resumeIndexingIfNeeded()`
///    picks up where indexing left off (the store skips already-indexed items).
///
/// iOS never guarantees enough background time to index thousands of items in a
/// single window, so the design chips away in the background and relies on
/// foreground auto-resume to finish the remainder. This is the standard,
/// App-Store-acceptable pattern.
@MainActor
final class BackgroundIndexer {
    static let shared = BackgroundIndexer()

    /// Must match an entry in `BGTaskSchedulerPermittedIdentifiers` (Info.plist).
    static let taskIdentifier = "com.rafa.dejavi.indexing"

    private var viewModel: SearchViewModel?
    private var backgroundAssertionID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // MARK: - Wiring

    /// Provide the shared view model once the App has constructed it. The App's
    /// foreground view model always wins over any fallback built for a
    /// background launch.
    func attach(viewModel: SearchViewModel) {
        self.viewModel = viewModel
    }

    /// Return the attached view model, or lazily build one. iOS may cold-launch
    /// the app directly into the background to run a BGProcessingTask, in which
    /// case the SwiftUI scene's `.task` (which normally builds and attaches the
    /// view model) has not run. Building one here lets background indexing work
    /// even with no UI. Retained strongly so it survives the background window.
    private func makeOrGetViewModel() async -> SearchViewModel {
        if let viewModel { return viewModel }
        let vm = SearchViewModel(store: VectorStore())
        vm.photoProvider = iOSPhotoProvider()
        vm.photoActions = iOSPhotoActions()
        await vm.loadStore()
        self.viewModel = vm
        return vm
    }

    /// Register the BGProcessingTask handler. MUST be called from
    /// `application(_:didFinishLaunchingWithOptions:)`, before launch finishes.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            // The launch handler runs on a background queue; hop to the main
            // actor, where the view model lives, before touching it.
            Task { @MainActor in
                BackgroundIndexer.shared.handle(task)
            }
        }
    }

    // MARK: - Scene transitions

    /// Call when the scene enters the background.
    func applicationDidEnterBackground() {
        guard let viewModel else { return }
        if viewModel.isIndexing {
            // Keep current indexing alive for the ~30s iOS grants so in-flight
            // embeds finish and commit.
            beginBackgroundAssertion()
        }
        // If there is any pending indexing work, ask iOS to resume it later.
        if viewModel.isIndexing || viewModel.isIndexingInProgressPersisted {
            scheduleProcessingTask()
        }
    }

    /// Call when the scene becomes active (foreground / launch).
    func applicationDidBecomeActive() {
        endBackgroundAssertion()
        Task { @MainActor in
            await self.viewModel?.resumeIndexingIfNeeded()
            // If indexing finished in the foreground with work still pending
            // (e.g. it was interrupted), queue a background task to finish later.
            if self.viewModel?.isIndexingInProgressPersisted == true {
                self.scheduleProcessingTask()
            }
        }
    }

    // MARK: - beginBackgroundTask assertion

    private func beginBackgroundAssertion() {
        endBackgroundAssertion()
        backgroundAssertionID = UIApplication.shared.beginBackgroundTask(withName: "DejaViIndexing") { [weak self] in
            // UIKit invokes this expiration handler synchronously on the main
            // thread, so we can safely assume main-actor isolation and end the
            // assertion before returning (required, or the app is terminated).
            MainActor.assumeIsolated {
                self?.viewModel?.stopIndexing()
                self?.endBackgroundAssertion()
            }
        }
    }

    private func endBackgroundAssertion() {
        guard backgroundAssertionID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundAssertionID)
        backgroundAssertionID = .invalid
    }

    // MARK: - BGProcessingTask

    /// Submit a request for iOS to resume indexing later. Idempotent: submitting
    /// again replaces any pending request for the same identifier.
    func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true   // Gemini embedding calls need the network.
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common causes: identifier missing from Info.plist, running in the
            // simulator, or Background App Refresh disabled. Nothing user-facing.
        }
    }

    private func handle(_ task: BGTask) {
        guard let processingTask = task as? BGProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }

        let work = Task { @MainActor [weak self] in
            await self?.runBackgroundIndexing(processingTask)
        }

        processingTask.expirationHandler = {
            // Invoked when the task is about to be suspended. Cancel the work and
            // stop indexing gracefully; runBackgroundIndexing then unwinds,
            // reschedules if needed, and calls setTaskCompleted.
            work.cancel()
            Task { @MainActor in
                BackgroundIndexer.shared.viewModel?.stopIndexing()
            }
        }
    }

    private func runBackgroundIndexing(_ task: BGProcessingTask) async {
        let vm = await makeOrGetViewModel()
        await vm.resumeIndexingIfNeeded()

        // If work still remains (the window expired mid-run), queue another task.
        if vm.isIndexingInProgressPersisted {
            scheduleProcessingTask()
        }
        task.setTaskCompleted(success: true)
    }
}
#endif

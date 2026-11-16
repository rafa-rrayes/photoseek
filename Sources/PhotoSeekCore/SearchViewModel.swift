import Foundation
import AVFoundation
#if os(macOS)
import AppKit
import SQLite3
import Photos
#endif

public enum MediaTypeFilter: String, Sendable, CaseIterable {
    case all
    case photos
    case videos

    var storeFilter: MediaType? {
        switch self {
        case .all: return nil
        case .photos: return .photo
        case .videos: return .video
        }
    }
}

@MainActor
@Observable
public final class SearchViewModel {
    public var query: String = "" {
        didSet { debounceSearch() }
    }

    public var mediaTypeFilter: MediaTypeFilter = .all {
        didSet {
            guard mediaTypeFilter != oldValue else { return }
            refilter()
        }
    }

    public var results: [SearchResult] = []
    public var isLoading = false
    public var errorMessage: String?
    public var indexedCount = 0
    public var isStoreLoaded = false
    public var isLoadingMore = false
    public var hasMore = true

    private var lastEmbedding: [Float]?
    private let pageSize = 20

    // Indexing state
    public var isIndexing = false
    public var indexingTotal = 0
    public var indexingDone = 0

    // Selection state
    public var isSelectMode = false
    public var selectedUUIDs: Set<String> = []
    public var showDeleteConfirmation = false
    public var hasSelection: Bool { !selectedUUIDs.isEmpty }
    public var selectedCount: Int { selectedUUIDs.count }

    public var hasApiKey: Bool { SettingsManager.shared.hasApiKey }

    private var searchTask: Task<Void, Never>?
    public let store: VectorStore
    private let gemini = GeminiClient()

    // Platform-specific providers (set after init for Phase 2+)
    public var photoProvider: (any PhotoProvider)?
    public var photoActions: (any PhotoActionsProtocol)?

    public init(store: VectorStore) {
        self.store = store
    }

    public func loadStore() async {
        do {
            let dbPath = SettingsManager.shared.databasePath
            try await store.open(at: dbPath)
            try await store.loadAll()
            indexedCount = await store.count
            isStoreLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func debounceSearch() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isLoading = false
            errorMessage = nil
            lastEmbedding = nil
            hasMore = true
            return
        }

        guard SettingsManager.shared.hasApiKey else {
            errorMessage = "Set your Gemini API key first"
            return
        }

        isLoading = true
        errorMessage = nil

        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let apiKey = SettingsManager.shared.apiKey
                let embedding = try await gemini.embedText(trimmed, apiKey: apiKey)
                guard !Task.isCancelled else { return }
                self.lastEmbedding = embedding
                let searchResults = await store.search(
                    queryEmbedding: embedding,
                    limit: pageSize,
                    mediaType: mediaTypeFilter.storeFilter
                )
                guard !Task.isCancelled else { return }
                self.results = searchResults
                self.hasMore = searchResults.count == pageSize
                self.isLoading = false
            } catch is CancellationError {
                // expected
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func loadMore() async {
        guard !isLoadingMore, hasMore, let embedding = lastEmbedding else { return }
        isLoadingMore = true
        let nextPage = results.count + pageSize
        let moreResults = await store.search(
            queryEmbedding: embedding,
            limit: nextPage,
            mediaType: mediaTypeFilter.storeFilter
        )
        let newItems = Array(moreResults.dropFirst(results.count))
        hasMore = !newItems.isEmpty
        results.append(contentsOf: newItems)
        isLoadingMore = false
    }

    private func refilter() {
        guard let embedding = lastEmbedding else { return }
        Task {
            let searchResults = await store.search(
                queryEmbedding: embedding,
                limit: pageSize,
                mediaType: mediaTypeFilter.storeFilter
            )
            self.results = searchResults
            self.hasMore = searchResults.count == pageSize
        }
    }

    // MARK: - Indexing (provider-based)

    public func indexPhotos() async {
        guard let provider = photoProvider else { return }
        guard SettingsManager.shared.hasApiKey else {
            errorMessage = "Set your Gemini API key first"
            return
        }

        isIndexing = true
        indexingDone = 0
        errorMessage = nil
        setIndexingInProgress(true)

        let indexedUUIDs = await store.indexedPhotoUUIDs()
        let toIndex = await provider.photosToIndex(excluding: indexedUUIDs)

        indexingTotal = toIndex.count
        if toIndex.isEmpty {
            isIndexing = false
            setIndexingInProgress(false)
            return
        }

        let apiKey = SettingsManager.shared.apiKey
        let concurrency = 5

        await withTaskGroup(of: Void.self) { group in
            var iter = toIndex.makeIterator()

            for _ in 0..<concurrency {
                guard let item = iter.next() else { break }
                group.addTask { await self.indexSinglePhoto(item, apiKey: apiKey) }
            }

            for await _ in group {
                guard self.isIndexing else {
                    group.cancelAll()
                    break
                }
                if let item = iter.next() {
                    group.addTask { await self.indexSinglePhoto(item, apiKey: apiKey) }
                }
            }
        }

        // Only clear the resume flag if the queue fully drained (not stopped/interrupted).
        let completed = isIndexing && indexingDone >= indexingTotal
        isIndexing = false
        if completed { setIndexingInProgress(false) }
        SettingsManager.shared.lastIndexedDate = Date()
    }

    private func indexSinglePhoto(_ photo: PhotoInfo, apiKey: String) async {
        guard let provider = photoProvider else {
            indexingDone += 1
            return
        }

        guard let jpegData = await provider.imageDataForEmbedding(photo) else {
            indexingDone += 1
            return
        }

        var attempt = 0
        while attempt < 3 {
            do {
                let embedding = try await gemini.embedImage(jpegData, apiKey: apiKey)

                try await store.addPhoto(
                    uuid: photo.uuid,
                    filename: photo.filename,
                    date: photo.date,
                    path: photo.path,
                    title: "",
                    albums: [],
                    persons: [],
                    embedding: embedding
                )
                indexingDone += 1
                indexedCount = await store.count
                return
            } catch let error as GeminiClient.GeminiError where error == .rateLimited {
                attempt += 1
                try? await Task.sleep(for: .seconds(Double(attempt) * 2))
            } catch let error as GeminiClient.GeminiError where error == .invalidKey {
                errorMessage = error.localizedDescription
                isIndexing = false
                indexingDone += 1
                return
            } catch {
                indexingDone += 1
                return
            }
        }
        indexingDone += 1
    }

    public func indexVideos() async {
        guard SettingsManager.shared.indexVideosEnabled else { return }
        guard let provider = photoProvider else { return }
        guard SettingsManager.shared.hasApiKey else {
            errorMessage = "Set your Gemini API key first"
            return
        }

        isIndexing = true
        indexingDone = 0
        errorMessage = nil
        setIndexingInProgress(true)

        let indexedUUIDs = await store.indexedVideoUUIDs()
        let toIndex = await provider.videosToIndex(excluding: indexedUUIDs)

        indexingTotal = toIndex.count
        if toIndex.isEmpty {
            isIndexing = false
            setIndexingInProgress(false)
            return
        }

        let apiKey = SettingsManager.shared.apiKey
        let concurrency = 6

        await withTaskGroup(of: Void.self) { group in
            var iter = toIndex.makeIterator()

            for _ in 0..<concurrency {
                guard let item = iter.next() else { break }
                group.addTask { await self.indexSingleVideo(item, apiKey: apiKey) }
            }

            for await _ in group {
                guard self.isIndexing else {
                    group.cancelAll()
                    break
                }
                if let item = iter.next() {
                    group.addTask { await self.indexSingleVideo(item, apiKey: apiKey) }
                }
            }
        }

        // Only clear the resume flag if the queue fully drained (not stopped/interrupted).
        let completed = isIndexing && indexingDone >= indexingTotal
        isIndexing = false
        if completed { setIndexingInProgress(false) }
        SettingsManager.shared.lastIndexedDate = Date()
    }

    private func indexSingleVideo(_ video: VideoInfo, apiKey: String) async {
        guard let provider = photoProvider else {
            indexingDone += 1
            return
        }

        guard let bytes = await provider.videoBytesForEmbedding(video) else {
            indexingDone += 1
            return
        }

        await embedAndStoreVideo(
            uuid: video.uuid,
            filename: video.filename,
            date: video.date,
            path: video.path,
            durationSeconds: video.durationSeconds,
            bytes: bytes,
            apiKey: apiKey
        )
    }

    private func embedAndStoreVideo(uuid: String, filename: String, date: String, path: String,
                                    durationSeconds: Double, bytes: VideoBytes, apiKey: String) async {
        let inlineThreshold = 20 * 1024 * 1024 // 20 MB

        var attempt = 0
        while attempt < 3 {
            do {
                let embedding: [Float]
                if bytes.data.count < inlineThreshold {
                    embedding = try await gemini.embedVideo(bytes.data, mimeType: bytes.mimeType, apiKey: apiKey)
                } else {
                    let uploaded = try await gemini.uploadFile(
                        bytes.data,
                        mimeType: bytes.mimeType,
                        displayName: filename.isEmpty ? uuid : filename,
                        apiKey: apiKey
                    )
                    do {
                        embedding = try await gemini.embedVideoByFileUri(
                            uploaded.uri,
                            mimeType: bytes.mimeType,
                            apiKey: apiKey
                        )
                    } catch {
                        await gemini.deleteFile(name: uploaded.name, apiKey: apiKey)
                        throw error
                    }
                    await gemini.deleteFile(name: uploaded.name, apiKey: apiKey)
                }

                try await store.addVideo(
                    uuid: uuid,
                    filename: filename,
                    date: date,
                    path: path,
                    title: "",
                    albums: [],
                    persons: [],
                    durationSeconds: durationSeconds,
                    embedding: embedding
                )
                indexingDone += 1
                indexedCount = await store.count
                return
            } catch let error as GeminiClient.GeminiError where error == .rateLimited {
                attempt += 1
                try? await Task.sleep(for: .seconds(Double(attempt) * 2))
            } catch let error as GeminiClient.GeminiError where error == .invalidKey {
                errorMessage = error.localizedDescription
                isIndexing = false
                indexingDone += 1
                return
            } catch {
                indexingDone += 1
                return
            }
        }
        indexingDone += 1
    }

    public func stopIndexing() {
        isIndexing = false
    }

    // MARK: - Background resume support

    /// Persisted marker (UserDefaults) recording that an indexing session was
    /// started and has not yet fully completed. The iOS background-execution
    /// layer reads this to decide whether to resume indexing on foreground or
    /// on a BGProcessingTask relaunch. Cross-platform safe (UserDefaults only).
    private static let indexingInProgressKey = "photoseek.indexing_in_progress"

    private func setIndexingInProgress(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.indexingInProgressKey)
    }

    /// Whether an indexing session is persisted as incomplete (may be resumed).
    public var isIndexingInProgressPersisted: Bool {
        UserDefaults.standard.bool(forKey: Self.indexingInProgressKey)
    }

    /// Resume a previously-interrupted indexing session. Safe to call on launch
    /// or when returning to the foreground: it no-ops unless a session was left
    /// incomplete, nothing is already running, and an API key exists. The store
    /// skips already-indexed items (`indexedPhotoUUIDs()` / `indexedVideoUUIDs()`),
    /// so simply re-running continues from where it stopped.
    public func resumeIndexingIfNeeded() async {
        guard isIndexingInProgressPersisted else { return }
        guard !isIndexing else { return }
        guard SettingsManager.shared.hasApiKey else { return }
        await indexPhotos()
        if Task.isCancelled { return }
        await indexVideos()
    }

    #if os(macOS)
    public func indexAllFolders(includeVideos: Bool, includeICloud: Bool) async {
        let folders = SettingsManager.shared.indexFolders
        for folder in folders {
            await indexPhotosFromDirectory(folder)
        }
        if includeVideos {
            await indexVideosViaPhotoKit(allowICloud: includeICloud)
        }
        SettingsManager.shared.lastIndexedDate = Date()
    }

    /// Legacy macOS filesystem-based indexing (used until MacPhotoProvider is wired up)
    public func indexPhotosFromDirectory(_ directoryPath: String) async {
        guard SettingsManager.shared.hasApiKey else {
            errorMessage = "Set your Gemini API key first"
            return
        }

        isIndexing = true
        indexingDone = 0
        errorMessage = nil

        let fm = FileManager.default
        let extensions = Set(["heic", "heif", "jpg", "jpeg", "png", "tiff", "webp"])

        let visibleUUIDs = loadVisiblePhotoUUIDs()

        var uuidToPath: [String: String] = [:]
        if let enumerator = fm.enumerator(atPath: directoryPath) {
            while let file = enumerator.nextObject() as? String {
                let ext = (file as NSString).pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
                let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                guard visibleUUIDs.contains(name) else { continue }
                uuidToPath[name] = (directoryPath as NSString).appendingPathComponent(file)
            }
        }

        let derivativesPath = PhotosLibraryAccess.shared.libraryURL
            .appendingPathComponent("resources/derivatives").path
        let missingUUIDs = visibleUUIDs.subtracting(uuidToPath.keys)
        if !missingUUIDs.isEmpty, let enumerator = fm.enumerator(atPath: derivativesPath) {
            while let file = enumerator.nextObject() as? String {
                let ext = (file as NSString).pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
                let basename = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                guard let underscoreIdx = basename.firstIndex(of: "_") else { continue }
                let uuid = String(basename[..<underscoreIdx])
                guard missingUUIDs.contains(uuid), uuidToPath[uuid] == nil else { continue }
                let fullPath = (derivativesPath as NSString).appendingPathComponent(file)
                if let existing = uuidToPath[uuid],
                   let existingSize = try? fm.attributesOfItem(atPath: existing)[.size] as? Int,
                   let newSize = try? fm.attributesOfItem(atPath: fullPath)[.size] as? Int,
                   newSize <= existingSize { continue }
                uuidToPath[uuid] = fullPath
            }
        }

        let indexedUUIDs = await store.indexedPhotoUUIDs()
        let toIndex: [(path: String, uuid: String)] = uuidToPath.compactMap { uuid, path in
            guard !indexedUUIDs.contains(uuid) else { return nil }
            return (path, uuid)
        }

        indexingTotal = toIndex.count
        if toIndex.isEmpty {
            isIndexing = false
            return
        }

        let apiKey = SettingsManager.shared.apiKey
        let concurrency = 5

        await withTaskGroup(of: Void.self) { group in
            var iter = toIndex.makeIterator()

            for _ in 0..<concurrency {
                guard let item = iter.next() else { break }
                group.addTask { await self.indexSinglePhotoFromPath(path: item.path, uuid: item.uuid, apiKey: apiKey) }
            }

            for await _ in group {
                guard self.isIndexing else {
                    group.cancelAll()
                    break
                }
                if let item = iter.next() {
                    group.addTask { await self.indexSinglePhotoFromPath(path: item.path, uuid: item.uuid, apiKey: apiKey) }
                }
            }
        }

        isIndexing = false
        SettingsManager.shared.lastIndexedDate = Date()
    }

    private func indexSinglePhotoFromPath(path: String, uuid: String, apiKey: String) async {
        let prepTask = Task.detached(priority: .userInitiated) {
            EmbeddingPreparer.prepareFromFile(at: path)
        }
        guard let jpegData = await prepTask.value else {
            indexingDone += 1
            return
        }

        var attempt = 0
        let fm = FileManager.default
        while attempt < 3 {
            do {
                let embedding = try await gemini.embedImage(jpegData, apiKey: apiKey)
                let filename = (path as NSString).lastPathComponent
                let attrs = try? fm.attributesOfItem(atPath: path)
                let date = (attrs?[.modificationDate] as? Date)?.ISO8601Format() ?? ""

                try await store.addPhoto(
                    uuid: uuid,
                    filename: filename,
                    date: date,
                    path: path,
                    title: "",
                    albums: [],
                    persons: [],
                    embedding: embedding
                )
                indexingDone += 1
                indexedCount = await store.count
                return
            } catch let error as GeminiClient.GeminiError where error == .rateLimited {
                attempt += 1
                try? await Task.sleep(for: .seconds(Double(attempt) * 2))
            } catch let error as GeminiClient.GeminiError where error == .invalidKey {
                errorMessage = error.localizedDescription
                isIndexing = false
                indexingDone += 1
                return
            } catch {
                indexingDone += 1
                return
            }
        }
        indexingDone += 1
    }

    /// macOS video indexing via PhotoKit. PhotoKit handles iCloud-optimized
    /// libraries — when allowICloud is true, originals are downloaded on demand
    /// via isNetworkAccessAllowed; when false, iCloud-only videos are skipped.
    public func indexVideosViaPhotoKit(allowICloud: Bool) async {
        guard SettingsManager.shared.hasApiKey else {
            errorMessage = "Set your Gemini API key first"
            return
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let authorized: Bool
        if status == .authorized || status == .limited {
            authorized = true
        } else if status == .notDetermined {
            let new = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            authorized = (new == .authorized || new == .limited)
        } else {
            authorized = false
        }
        guard authorized else {
            errorMessage = "Photo library access required to index videos. Grant access in System Settings → Privacy & Security → Photos."
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        let indexedUUIDs = await store.indexedVideoUUIDs()

        var toIndex: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            guard !indexedUUIDs.contains(asset.localIdentifier) else { return }
            toIndex.append(asset)
        }

        if toIndex.isEmpty { return }

        isIndexing = true
        indexingDone = 0
        indexingTotal = toIndex.count

        let apiKey = SettingsManager.shared.apiKey
        let concurrency = 6

        await withTaskGroup(of: Void.self) { group in
            var iter = toIndex.makeIterator()

            for _ in 0..<concurrency {
                guard let asset = iter.next() else { break }
                group.addTask { await self.indexSingleVideoFromAsset(asset, allowICloud: allowICloud, apiKey: apiKey) }
            }

            for await _ in group {
                guard self.isIndexing else {
                    group.cancelAll()
                    break
                }
                if let asset = iter.next() {
                    group.addTask { await self.indexSingleVideoFromAsset(asset, allowICloud: allowICloud, apiKey: apiKey) }
                }
            }
        }

        isIndexing = false
    }

    private func indexSingleVideoFromAsset(_ asset: PHAsset, allowICloud: Bool, apiKey: String) async {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = allowICloud
        options.version = .current
        options.deliveryMode = .highQualityFormat

        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: avAsset)
            }
        }

        guard let urlAsset = avAsset as? AVURLAsset else {
            indexingDone += 1
            return
        }

        guard let prepared = await EmbeddingPreparer.prepareVideoSlice(from: urlAsset.url) else {
            indexingDone += 1
            return
        }

        let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
        let date = asset.creationDate?.ISO8601Format() ?? ""
        let videoBytes = VideoBytes(data: prepared.data, mimeType: prepared.mimeType)

        await embedAndStoreVideo(
            uuid: asset.localIdentifier,
            filename: filename,
            date: date,
            path: urlAsset.url.path,
            durationSeconds: asset.duration,
            bytes: videoBytes,
            apiKey: apiKey
        )
    }

    public func scanLibraryStats() async -> LibraryStats {
        var stats = LibraryStats()
        let dbPath = PhotosLibraryAccess.shared.libraryURL
            .appendingPathComponent("database/Photos.sqlite").path

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return stats
        }
        defer { sqlite3_close(db) }

        stats.totalPhotos = queryCount(db, """
            SELECT COUNT(*) FROM ZASSET
            WHERE ZKIND = 0 AND ZTRASHEDSTATE = 0 AND ZHIDDEN = 0 AND ZVISIBILITYSTATE = 0
            """)

        stats.localAvailable = queryCount(db, """
            SELECT COUNT(*) FROM ZASSET
            WHERE ZKIND = 0 AND ZTRASHEDSTATE = 0 AND ZHIDDEN = 0 AND ZVISIBILITYSTATE = 0
            AND ZCLOUDLOCALSTATE = 1
            """)

        stats.totalVideos = queryCount(db, """
            SELECT COUNT(*) FROM ZASSET
            WHERE ZKIND = 1 AND ZTRASHEDSTATE = 0 AND ZHIDDEN = 0 AND ZVISIBILITYSTATE = 0
            """)

        // Videos have no usable derivative for embedding — only the original counts as local.
        // ZINTERNALRESOURCE.ZDATASTORESUBTYPE=1 + ZLOCALAVAILABILITY=1 means the original is on disk.
        stats.localAvailableVideos = queryCount(db, """
            SELECT COUNT(DISTINCT ZASSET.ZUUID)
            FROM ZASSET
            JOIN ZINTERNALRESOURCE ON ZASSET.Z_PK = ZINTERNALRESOURCE.ZASSET
            WHERE ZASSET.ZKIND = 1
            AND ZASSET.ZTRASHEDSTATE = 0 AND ZASSET.ZHIDDEN = 0 AND ZASSET.ZVISIBILITYSTATE = 0
            AND ZINTERNALRESOURCE.ZDATASTORESUBTYPE = 1
            AND ZINTERNALRESOURCE.ZLOCALAVAILABILITY = 1
            """)

        return stats
    }

    private func queryCount(_ db: OpaquePointer?, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func loadVisiblePhotoUUIDs() -> Set<String> {
        loadVisibleUUIDs(kind: 0)
    }

    private func loadVisibleVideoUUIDs() -> Set<String> {
        loadVisibleUUIDs(kind: 1)
    }

    private func loadVisibleUUIDs(kind: Int) -> Set<String> {
        let dbPath = PhotosLibraryAccess.shared.libraryURL
            .appendingPathComponent("database/Photos.sqlite").path

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT ZUUID FROM ZASSET
            WHERE ZKIND = \(kind) AND ZTRASHEDSTATE = 0 AND ZHIDDEN = 0 AND ZVISIBILITYSTATE = 0
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var uuids: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                uuids.insert(String(cString: cStr))
            }
        }
        return uuids
    }
    #endif

    public func reindexAll() async {
        do {
            try await store.clearAll()
            indexedCount = 0
            #if os(macOS)
            await indexAllFolders(
                includeVideos: SettingsManager.shared.indexVideosEnabled,
                includeICloud: SettingsManager.shared.indexIncludeICloud
            )
            #else
            await indexPhotos()
            await indexVideos()
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearIndex() async {
        do {
            try await store.clearAll()
            indexedCount = 0
            results = []
            lastEmbedding = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Selection

    public func toggleSelection(_ uuid: String) {
        if selectedUUIDs.contains(uuid) {
            selectedUUIDs.remove(uuid)
        } else {
            selectedUUIDs.insert(uuid)
        }
    }

    public func selectAll() {
        selectedUUIDs = Set(results.map(\.uuid))
    }

    public func clearSelection() {
        selectedUUIDs.removeAll()
        isSelectMode = false
    }

    public func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode {
            selectedUUIDs.removeAll()
        }
    }

    /// Enter select mode directly (e.g. from a long-press on a photo),
    /// optionally selecting the pressed item.
    public func enterSelectMode(selecting uuid: String? = nil) {
        isSelectMode = true
        if let uuid { selectedUUIDs.insert(uuid) }
    }

    public func removeFromResults(_ uuids: Set<String>) {
        results.removeAll { uuids.contains($0.uuid) }
    }

    /// Delete arbitrary items (used by the photo viewer). Removes them from
    /// the current results only when the deletion actually happened.
    @discardableResult
    public func deleteItems(_ uuids: [String]) async -> Bool {
        guard let actions = photoActions else { return false }
        let deleted = await actions.deletePhotos(uuids)
        if deleted { removeFromResults(Set(uuids)) }
        return deleted
    }

    public func favoriteSelected() async {
        if let actions = photoActions {
            if let error = await actions.favorite(Array(selectedUUIDs)) {
                errorMessage = error
            }
        }
        clearSelection()
    }

    public func unfavoriteSelected() async {
        if let actions = photoActions {
            if let error = await actions.unfavorite(Array(selectedUUIDs)) {
                errorMessage = error
            }
        }
        clearSelection()
    }

    public func confirmDelete() {
        showDeleteConfirmation = true
    }

    public func deleteSelected() async {
        await deleteItems(Array(selectedUUIDs))
        clearSelection()
    }

    public func addSelectedToAlbum(_ albumName: String) async {
        if let actions = photoActions {
            if let error = await actions.addToAlbum(Array(selectedUUIDs), albumName: albumName) {
                errorMessage = error
            }
        }
        clearSelection()
    }

    public func createAlbumWithSelected(_ albumName: String) async {
        if let actions = photoActions {
            if let error = await actions.createAlbumAndAdd(Array(selectedUUIDs), albumName: albumName) {
                errorMessage = error
            }
        }
        clearSelection()
    }
}

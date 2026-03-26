import Foundation
import AppKit
import SQLite3

@MainActor
@Observable
final class SearchViewModel {
    var query: String = "" {
        didSet { debounceSearch() }
    }

    var results: [SearchResult] = []
    var isLoading = false
    var errorMessage: String?
    var indexedCount = 0
    var isStoreLoaded = false
    var isLoadingMore = false
    var hasMore = true

    private var lastEmbedding: [Float]?
    private let pageSize = 20

    // Indexing state
    var isIndexing = false
    var indexingTotal = 0
    var indexingDone = 0

    // Selection state
    var isSelectMode = false
    var selectedUUIDs: Set<String> = []
    var showDeleteConfirmation = false
    var hasSelection: Bool { !selectedUUIDs.isEmpty }
    var selectedCount: Int { selectedUUIDs.count }

    var hasApiKey: Bool { SettingsManager.shared.hasApiKey }

    private var searchTask: Task<Void, Never>?
    private let store: VectorStore
    private let gemini = GeminiClient()

    init(store: VectorStore) {
        self.store = store
    }

    func loadStore() async {
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

    func debounceSearch() {
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
                let searchResults = await store.search(queryEmbedding: embedding, limit: pageSize)
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

    func loadMore() async {
        guard !isLoadingMore, hasMore, let embedding = lastEmbedding else { return }
        isLoadingMore = true
        let nextPage = results.count + pageSize
        let moreResults = await store.search(queryEmbedding: embedding, limit: nextPage)
        let newItems = Array(moreResults.dropFirst(results.count))
        hasMore = !newItems.isEmpty
        results.append(contentsOf: newItems)
        isLoadingMore = false
    }

    func indexPhotos(from directoryPath: String) async {
        guard SettingsManager.shared.hasApiKey else {
            errorMessage = "Set your Gemini API key first"
            return
        }

        isIndexing = true
        indexingDone = 0
        errorMessage = nil

        let fm = FileManager.default
        let extensions = Set(["heic", "heif", "jpg", "jpeg", "png", "tiff", "webp"])

        // Load visible photo UUIDs from Photos.sqlite
        let visibleUUIDs = loadVisiblePhotoUUIDs()

        // Gather image files from originals, filtering to visible photos only
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

        // Fill in missing photos from derivatives (locally cached iCloud photos)
        let home = fm.homeDirectoryForCurrentUser.path
        let derivativesPath = "\(home)/Pictures/Photos Library.photoslibrary/resources/derivatives"
        let missingUUIDs = visibleUUIDs.subtracting(uuidToPath.keys)
        if !missingUUIDs.isEmpty, let enumerator = fm.enumerator(atPath: derivativesPath) {
            while let file = enumerator.nextObject() as? String {
                let ext = (file as NSString).pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
                let basename = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                // Derivative filenames: UUID_1_105_c — extract UUID before first underscore
                guard let underscoreIdx = basename.firstIndex(of: "_") else { continue }
                let uuid = String(basename[..<underscoreIdx])
                guard missingUUIDs.contains(uuid), uuidToPath[uuid] == nil else { continue }
                let fullPath = (derivativesPath as NSString).appendingPathComponent(file)
                // Prefer larger files (better quality)
                if let existing = uuidToPath[uuid],
                   let existingSize = try? fm.attributesOfItem(atPath: existing)[.size] as? Int,
                   let newSize = try? fm.attributesOfItem(atPath: fullPath)[.size] as? Int,
                   newSize <= existingSize { continue }
                uuidToPath[uuid] = fullPath
            }
        }

        // Bulk check already-indexed (single actor hop instead of N)
        let indexedUUIDs = await store.indexedUUIDs()
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

            // Seed with initial concurrent tasks
            for _ in 0..<concurrency {
                guard let item = iter.next() else { break }
                group.addTask { await self.indexSinglePhoto(path: item.path, uuid: item.uuid, apiKey: apiKey) }
            }

            // As each completes, start the next
            for await _ in group {
                guard self.isIndexing else {
                    group.cancelAll()
                    break
                }
                if let item = iter.next() {
                    group.addTask { await self.indexSinglePhoto(path: item.path, uuid: item.uuid, apiKey: apiKey) }
                }
            }
        }

        isIndexing = false
        SettingsManager.shared.lastIndexedDate = Date()
    }

    private func indexSinglePhoto(path: String, uuid: String, apiKey: String) async {
        let fm = FileManager.default

        let prepTask = Task.detached(priority: .userInitiated) {
            ImageCache.shared.prepareForEmbedding(at: path)
        }
        guard let jpegData = await prepTask.value else {
            indexingDone += 1
            return
        }

        var attempt = 0
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
            } catch {
                errorMessage = error.localizedDescription
                indexingDone += 1
                return
            }
        }
        indexingDone += 1 // exhausted retries
    }

    func stopIndexing() {
        isIndexing = false
    }

    func indexAllFolders() async {
        let folders = SettingsManager.shared.indexFolders
        for folder in folders {
            guard isIndexing || !isIndexing else { break }
            await indexPhotos(from: folder)
        }
        SettingsManager.shared.lastIndexedDate = Date()
    }

    func reindexAll() async {
        do {
            try await store.clearAll()
            indexedCount = 0
            await indexAllFolders()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearIndex() async {
        do {
            try await store.clearAll()
            indexedCount = 0
            results = []
            lastEmbedding = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    struct LibraryStats {
        var totalPhotos: Int = 0
        var localAvailable: Int = 0
        var iCloudOnly: Int { max(totalPhotos - localAvailable, 0) }
    }

    func scanLibraryStats() async -> LibraryStats {
        var stats = LibraryStats()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Pictures/Photos Library.photoslibrary/database/Photos.sqlite"

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return stats
        }
        defer { sqlite3_close(db) }

        // Total visible photos (not trashed, not hidden, visible)
        stats.totalPhotos = queryCount(db, """
            SELECT COUNT(*) FROM ZASSET
            WHERE ZKIND = 0 AND ZTRASHEDSTATE = 0 AND ZHIDDEN = 0 AND ZVISIBILITYSTATE = 0
            """)

        // Locally available photos
        stats.localAvailable = queryCount(db, """
            SELECT COUNT(*) FROM ZASSET
            WHERE ZKIND = 0 AND ZTRASHEDSTATE = 0 AND ZHIDDEN = 0 AND ZVISIBILITYSTATE = 0
            AND ZCLOUDLOCALSTATE = 1
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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Pictures/Photos Library.photoslibrary/database/Photos.sqlite"

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT ZUUID FROM ZASSET
            WHERE ZKIND = 0 AND ZTRASHEDSTATE = 0 AND ZHIDDEN = 0 AND ZVISIBILITYSTATE = 0
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

    // MARK: - Selection

    func toggleSelection(_ uuid: String) {
        if selectedUUIDs.contains(uuid) {
            selectedUUIDs.remove(uuid)
        } else {
            selectedUUIDs.insert(uuid)
        }
    }

    func selectAll() {
        selectedUUIDs = Set(results.map(\.uuid))
    }

    func clearSelection() {
        selectedUUIDs.removeAll()
        isSelectMode = false
    }

    func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode {
            selectedUUIDs.removeAll()
        }
    }

    func favoriteSelected() {
        if let error = PhotosActions.favorite(Array(selectedUUIDs)) {
            errorMessage = error
        }
        clearSelection()
    }

    func unfavoriteSelected() {
        if let error = PhotosActions.unfavorite(Array(selectedUUIDs)) {
            errorMessage = error
        }
        clearSelection()
    }

    func confirmDelete() {
        showDeleteConfirmation = true
    }

    func deleteSelected() {
        PhotosActions.deletePhotos(Array(selectedUUIDs))
        clearSelection()
    }

    func addSelectedToAlbum(_ albumName: String) {
        if let error = PhotosActions.addToAlbum(Array(selectedUUIDs), albumName: albumName) {
            errorMessage = error
        }
        clearSelection()
    }

    func createAlbumWithSelected(_ albumName: String) {
        if let error = PhotosActions.createAlbumAndAdd(Array(selectedUUIDs), albumName: albumName) {
            errorMessage = error
        }
        clearSelection()
    }
}

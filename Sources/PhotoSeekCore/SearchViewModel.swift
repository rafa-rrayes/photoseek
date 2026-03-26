import Foundation
#if os(macOS)
import AppKit
import SQLite3
#endif

@MainActor
@Observable
public final class SearchViewModel {
    public var query: String = "" {
        didSet { debounceSearch() }
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

    public func loadMore() async {
        guard !isLoadingMore, hasMore, let embedding = lastEmbedding else { return }
        isLoadingMore = true
        let nextPage = results.count + pageSize
        let moreResults = await store.search(queryEmbedding: embedding, limit: nextPage)
        let newItems = Array(moreResults.dropFirst(results.count))
        hasMore = !newItems.isEmpty
        results.append(contentsOf: newItems)
        isLoadingMore = false
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

        let indexedUUIDs = await store.indexedUUIDs()
        let toIndex = await provider.photosToIndex(excluding: indexedUUIDs)

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

        isIndexing = false
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
            } catch {
                errorMessage = error.localizedDescription
                indexingDone += 1
                return
            }
        }
        indexingDone += 1
    }

    public func stopIndexing() {
        isIndexing = false
    }

    #if os(macOS)
    public func indexAllFolders() async {
        let folders = SettingsManager.shared.indexFolders
        for folder in folders {
            guard isIndexing || !isIndexing else { break }
            await indexPhotosFromDirectory(folder)
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

        let home = fm.homeDirectoryForCurrentUser.path
        let derivativesPath = "\(home)/Pictures/Photos Library.photoslibrary/resources/derivatives"
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
            } catch {
                errorMessage = error.localizedDescription
                indexingDone += 1
                return
            }
        }
        indexingDone += 1
    }

    public func scanLibraryStats() async -> LibraryStats {
        var stats = LibraryStats()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Pictures/Photos Library.photoslibrary/database/Photos.sqlite"

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
    #endif

    public func reindexAll() async {
        do {
            try await store.clearAll()
            indexedCount = 0
            #if os(macOS)
            await indexAllFolders()
            #else
            await indexPhotos()
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
        if let actions = photoActions {
            await actions.deletePhotos(Array(selectedUUIDs))
        }
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

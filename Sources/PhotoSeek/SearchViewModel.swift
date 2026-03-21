import Foundation
import AppKit

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

        // Gather image files
        var imagePaths: [String] = []
        if let enumerator = fm.enumerator(atPath: directoryPath) {
            while let file = enumerator.nextObject() as? String {
                let ext = (file as NSString).pathExtension.lowercased()
                if extensions.contains(ext) {
                    imagePaths.append((directoryPath as NSString).appendingPathComponent(file))
                }
            }
        }

        // Filter out already-indexed
        var toIndex: [(path: String, uuid: String)] = []
        for path in imagePaths {
            let filename = (path as NSString).lastPathComponent
            let uuid = (filename as NSString).deletingPathExtension
            let alreadyIndexed = await store.contains(uuid: uuid)
            if !alreadyIndexed {
                toIndex.append((path, uuid))
            }
        }

        indexingTotal = toIndex.count
        if toIndex.isEmpty {
            isIndexing = false
            return
        }

        let apiKey = SettingsManager.shared.apiKey

        for (path, uuid) in toIndex {
            guard isIndexing else { break } // allow cancellation

            guard let jpegData = await ImageCache.shared.prepareForEmbedding(at: path) else {
                indexingDone += 1
                continue
            }

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
            } catch {
                errorMessage = "Index error: \(error.localizedDescription)"
                indexingDone += 1
            }
        }

        isIndexing = false
    }

    func stopIndexing() {
        isIndexing = false
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
        PhotosActions.favorite(Array(selectedUUIDs))
        clearSelection()
    }

    func unfavoriteSelected() {
        PhotosActions.unfavorite(Array(selectedUUIDs))
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
        PhotosActions.addToAlbum(Array(selectedUUIDs), albumName: albumName)
        clearSelection()
    }

    func createAlbumWithSelected(_ albumName: String) {
        PhotosActions.createAlbumAndAdd(Array(selectedUUIDs), albumName: albumName)
        clearSelection()
    }
}

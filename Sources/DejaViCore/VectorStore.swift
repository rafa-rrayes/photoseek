import Foundation
import SQLite3
import Accelerate

private let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public actor VectorStore {
    private var db: OpaquePointer?
    private var photos: [StoredPhoto] = []
    private var videos: [StoredVideo] = []
    private var photoUUIDSet: Set<String> = []
    private var videoUUIDSet: Set<String> = []

    public struct StoredPhoto: Sendable {
        public let uuid: String
        public let filename: String
        public let date: String
        public let path: String
        public let derivative: String
        public let title: String
        public let albums: [String]
        public let persons: [String]
        public let embedding: [Float]
        public let magnitude: Float
    }

    public struct StoredVideo: Sendable {
        public let uuid: String
        public let filename: String
        public let date: String
        public let path: String
        public let title: String
        public let albums: [String]
        public let persons: [String]
        public let durationSeconds: Double
        public let embedding: [Float]
        public let magnitude: Float
    }

    public var count: Int { photos.count + videos.count }
    public var photoCount: Int { photos.count }
    public var videoCount: Int { videos.count }

    public init() {}

    public func contains(uuid: String) -> Bool {
        photoUUIDSet.contains(uuid) || videoUUIDSet.contains(uuid)
    }

    public func indexedPhotoUUIDs() -> Set<String> {
        photoUUIDSet
    }

    public func indexedVideoUUIDs() -> Set<String> {
        videoUUIDSet
    }

    public func open(at path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if sqlite3_open(path, &db) != SQLITE_OK {
            throw StoreError.cannotOpen(path)
        }

        // Crash-hardening pragmas. Best-effort: a non-OK PRAGMA (e.g. journal_mode
        // failing to switch on some filesystems) must not fail the whole open, so we
        // attempt each and ignore its result. WAL + synchronous=NORMAL keeps every
        // committed row durable across a hard app kill (swipe-to-close / SIGKILL).
        applyPragmas()

        try createTables()
    }

    /// Enable WAL journaling and crash-safe pragmas. Called right after open.
    private func applyPragmas() {
        guard let db else { return }
        // Write-Ahead Logging: commits append to the -wal file and survive a hard
        // process kill; the DB is never left mid-write like the default rollback journal.
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        // NORMAL fsyncs at checkpoint (and WAL commits are still durable across an app
        // kill because the OS flushes the -wal file) — full data safety without the
        // per-write fsync cost of FULL.
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        // Wait up to 5s on a locked DB instead of failing immediately.
        sqlite3_exec(db, "PRAGMA busy_timeout=5000;", nil, nil, nil)
    }

    public func loadAll() throws {
        guard let db else { throw StoreError.notOpen }

        // Load photos
        var stmt: OpaquePointer?
        let photoQuery = "SELECT uuid, filename, date, path, title, albums, persons, embedding, derivative FROM photos"

        guard sqlite3_prepare_v2(db, photoQuery, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        var loadedPhotos: [StoredPhoto] = []
        var photoIds: Set<String> = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let uuid = columnText(stmt, 0)
            let filename = columnText(stmt, 1)
            let date = columnText(stmt, 2)
            let path = columnText(stmt, 3)
            let title = columnText(stmt, 4)
            let albumsJson = columnText(stmt, 5)
            let personsJson = columnText(stmt, 6)
            let embedding = columnFloats(stmt, 7)
            guard !embedding.isEmpty else { continue }
            let derivative = columnText(stmt, 8)

            var mag: Float = 0
            vDSP_svesq(embedding, 1, &mag, vDSP_Length(embedding.count))
            mag = sqrt(mag)

            loadedPhotos.append(StoredPhoto(
                uuid: uuid,
                filename: filename,
                date: date,
                path: path,
                derivative: derivative,
                title: title,
                albums: parseJsonArray(albumsJson),
                persons: parseJsonArray(personsJson),
                embedding: embedding,
                magnitude: mag
            ))
            photoIds.insert(uuid)
        }
        sqlite3_finalize(stmt)
        stmt = nil

        // Load videos
        let videoQuery = "SELECT uuid, filename, date, path, title, albums, persons, duration_seconds, embedding FROM videos"

        guard sqlite3_prepare_v2(db, videoQuery, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var loadedVideos: [StoredVideo] = []
        var videoIds: Set<String> = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let uuid = columnText(stmt, 0)
            let filename = columnText(stmt, 1)
            let date = columnText(stmt, 2)
            let path = columnText(stmt, 3)
            let title = columnText(stmt, 4)
            let albumsJson = columnText(stmt, 5)
            let personsJson = columnText(stmt, 6)
            let duration = sqlite3_column_double(stmt, 7)
            let embedding = columnFloats(stmt, 8)
            guard !embedding.isEmpty else { continue }

            var mag: Float = 0
            vDSP_svesq(embedding, 1, &mag, vDSP_Length(embedding.count))
            mag = sqrt(mag)

            loadedVideos.append(StoredVideo(
                uuid: uuid,
                filename: filename,
                date: date,
                path: path,
                title: title,
                albums: parseJsonArray(albumsJson),
                persons: parseJsonArray(personsJson),
                durationSeconds: duration,
                embedding: embedding,
                magnitude: mag
            ))
            videoIds.insert(uuid)
        }

        self.photos = loadedPhotos
        self.videos = loadedVideos
        self.photoUUIDSet = photoIds
        self.videoUUIDSet = videoIds
    }

    public func search(queryEmbedding: [Float], limit: Int = 20, mediaType: MediaType? = nil) -> [SearchResult] {
        let includePhotos = mediaType != .video
        let includeVideos = mediaType != .photo
        guard (includePhotos && !photos.isEmpty) || (includeVideos && !videos.isEmpty) else { return [] }

        var queryMag: Float = 0
        vDSP_svesq(queryEmbedding, 1, &queryMag, vDSP_Length(queryEmbedding.count))
        queryMag = sqrt(queryMag)
        guard queryMag > 0 else { return [] }

        // (kind: 0 = photo, 1 = video, index, score)
        var scores: [(kind: Int, index: Int, score: Float)] = []
        scores.reserveCapacity(photos.count + videos.count)

        if includePhotos {
            for (i, photo) in photos.enumerated() {
                guard photo.magnitude > 0 else { continue }
                var dot: Float = 0
                vDSP_dotpr(queryEmbedding, 1, photo.embedding, 1, &dot, vDSP_Length(queryEmbedding.count))
                scores.append((0, i, dot / (queryMag * photo.magnitude)))
            }
        }

        if includeVideos {
            for (i, video) in videos.enumerated() {
                guard video.magnitude > 0 else { continue }
                var dot: Float = 0
                vDSP_dotpr(queryEmbedding, 1, video.embedding, 1, &dot, vDSP_Length(queryEmbedding.count))
                scores.append((1, i, dot / (queryMag * video.magnitude)))
            }
        }

        scores.sort { $0.score > $1.score }

        return Array(scores.prefix(limit)).enumerated().map { rank, item in
            if item.kind == 0 {
                let photo = photos[item.index]
                return SearchResult(
                    rank: rank + 1,
                    score: Double(item.score),
                    uuid: photo.uuid,
                    filename: photo.filename,
                    date: photo.date,
                    path: photo.path,
                    derivative: photo.derivative,
                    title: photo.title,
                    albums: photo.albums,
                    persons: photo.persons,
                    mediaType: .photo,
                    durationSeconds: nil
                )
            } else {
                let video = videos[item.index]
                return SearchResult(
                    rank: rank + 1,
                    score: Double(item.score),
                    uuid: video.uuid,
                    filename: video.filename,
                    date: video.date,
                    path: video.path,
                    derivative: "",
                    title: video.title,
                    albums: video.albums,
                    persons: video.persons,
                    mediaType: .video,
                    durationSeconds: video.durationSeconds
                )
            }
        }
    }

    public func addPhoto(uuid: String, filename: String, date: String, path: String,
                  title: String, albums: [String], persons: [String],
                  embedding: [Float]) throws {
        guard let db else { throw StoreError.notOpen }

        var stmt: OpaquePointer?
        let insert = """
            INSERT OR REPLACE INTO photos
            (uuid, filename, date, path, title, description, keywords, albums, persons, latitude, longitude, embedding)
            VALUES (?, ?, ?, ?, ?, '', '[]', ?, ?, NULL, NULL, ?)
            """

        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, uuid)
        bindText(stmt, 2, filename)
        bindText(stmt, 3, date)
        bindText(stmt, 4, path)
        bindText(stmt, 5, title)
        bindText(stmt, 6, jsonEncode(albums))
        bindText(stmt, 7, jsonEncode(persons))

        _ = embedding.withUnsafeBufferPointer { buf in
            sqlite3_bind_blob(stmt, 8, buf.baseAddress, Int32(buf.count * MemoryLayout<Float>.size), SQLITE_TRANSIENT_PTR)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        var mag: Float = 0
        vDSP_svesq(embedding, 1, &mag, vDSP_Length(embedding.count))
        mag = sqrt(mag)

        photos.append(StoredPhoto(
            uuid: uuid, filename: filename, date: date, path: path,
            derivative: "", title: title, albums: albums, persons: persons,
            embedding: embedding, magnitude: mag
        ))
        photoUUIDSet.insert(uuid)
    }

    public func addVideo(uuid: String, filename: String, date: String, path: String,
                         title: String, albums: [String], persons: [String],
                         durationSeconds: Double, embedding: [Float]) throws {
        guard let db else { throw StoreError.notOpen }

        var stmt: OpaquePointer?
        let insert = """
            INSERT OR REPLACE INTO videos
            (uuid, filename, date, path, title, albums, persons, duration_seconds, embedding)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, uuid)
        bindText(stmt, 2, filename)
        bindText(stmt, 3, date)
        bindText(stmt, 4, path)
        bindText(stmt, 5, title)
        bindText(stmt, 6, jsonEncode(albums))
        bindText(stmt, 7, jsonEncode(persons))
        sqlite3_bind_double(stmt, 8, durationSeconds)

        _ = embedding.withUnsafeBufferPointer { buf in
            sqlite3_bind_blob(stmt, 9, buf.baseAddress, Int32(buf.count * MemoryLayout<Float>.size), SQLITE_TRANSIENT_PTR)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        var mag: Float = 0
        vDSP_svesq(embedding, 1, &mag, vDSP_Length(embedding.count))
        mag = sqrt(mag)

        videos.append(StoredVideo(
            uuid: uuid, filename: filename, date: date, path: path,
            title: title, albums: albums, persons: persons,
            durationSeconds: durationSeconds, embedding: embedding, magnitude: mag
        ))
        videoUUIDSet.insert(uuid)
    }

    public func clearAll() throws {
        guard let db else { throw StoreError.notOpen }
        guard sqlite3_exec(db, "DELETE FROM photos", nil, nil, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_exec(db, "DELETE FROM videos", nil, nil, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        photos.removeAll()
        videos.removeAll()
        photoUUIDSet.removeAll()
        videoUUIDSet.removeAll()
    }

    /// Fold the WAL back into the main database file. Cheap enough to call when the
    /// app backgrounds so the -wal file doesn't grow unbounded between clean shutdowns.
    /// PASSIVE never blocks on active readers/writers.
    public func checkpoint() {
        guard let db else { return }
        sqlite3_exec(db, "PRAGMA wal_checkpoint(PASSIVE);", nil, nil, nil)
    }

    public func close() {
        if let db {
            // Truncate-checkpoint on clean shutdown so the WAL is fully merged back into
            // the main db file and the -wal/-shm files are reset to zero length.
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Private

    private func createTables() throws {
        guard let db else { throw StoreError.notOpen }
        let photoSql = """
            CREATE TABLE IF NOT EXISTS photos (
                uuid TEXT PRIMARY KEY,
                filename TEXT,
                date TEXT,
                path TEXT,
                title TEXT,
                description TEXT,
                keywords TEXT,
                albums TEXT,
                persons TEXT,
                latitude REAL,
                longitude REAL,
                embedding BLOB
            )
            """
        guard sqlite3_exec(db, photoSql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        let videoSql = """
            CREATE TABLE IF NOT EXISTS videos (
                uuid TEXT PRIMARY KEY,
                filename TEXT,
                date TEXT,
                path TEXT,
                title TEXT,
                albums TEXT,
                persons TEXT,
                duration_seconds REAL,
                embedding BLOB
            )
            """
        guard sqlite3_exec(db, videoSql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    private func columnFloats(_ stmt: OpaquePointer?, _ col: Int32) -> [Float] {
        guard let ptr = sqlite3_column_blob(stmt, col) else { return [] }
        let bytes = Int(sqlite3_column_bytes(stmt, col))
        let count = bytes / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: ptr.assumingMemoryBound(to: Float.self), count: count))
    }

    private func bindText(_ stmt: OpaquePointer?, _ col: Int32, _ value: String) {
        sqlite3_bind_text(stmt, col, value, -1, SQLITE_TRANSIENT_PTR)
    }

    private func parseJsonArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
    }

    private func jsonEncode(_ array: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    public enum StoreError: LocalizedError {
        case cannotOpen(String)
        case notOpen
        case queryFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotOpen(let p): return "Cannot open database at \(p)"
            case .notOpen: return "Database not open"
            case .queryFailed(let m): return "Database error: \(m)"
            }
        }
    }
}

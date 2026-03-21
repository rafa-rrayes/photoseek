import Foundation
import SQLite3
import Accelerate

private let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor VectorStore {
    private var db: OpaquePointer?
    private var photos: [StoredPhoto] = []
    private var uuidSet: Set<String> = []

    struct StoredPhoto {
        let uuid: String
        let filename: String
        let date: String
        let path: String
        let derivative: String
        let title: String
        let albums: [String]
        let persons: [String]
        let embedding: [Float]
        let magnitude: Float
    }

    var count: Int { photos.count }

    func contains(uuid: String) -> Bool {
        uuidSet.contains(uuid)
    }

    func open(at path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if sqlite3_open(path, &db) != SQLITE_OK {
            throw StoreError.cannotOpen(path)
        }

        try createTable()
    }

    func loadAll() throws {
        guard let db else { throw StoreError.notOpen }

        var stmt: OpaquePointer?
        let query = "SELECT uuid, filename, date, path, title, albums, persons, embedding, derivative FROM photos"

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var loaded: [StoredPhoto] = []
        var ids: Set<String> = []

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

            loaded.append(StoredPhoto(
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
            ids.insert(uuid)
        }

        self.photos = loaded
        self.uuidSet = ids
    }

    func search(queryEmbedding: [Float], limit: Int = 20) -> [SearchResult] {
        guard !photos.isEmpty else { return [] }

        var queryMag: Float = 0
        vDSP_svesq(queryEmbedding, 1, &queryMag, vDSP_Length(queryEmbedding.count))
        queryMag = sqrt(queryMag)
        guard queryMag > 0 else { return [] }

        var scores: [(index: Int, score: Float)] = []
        scores.reserveCapacity(photos.count)

        for (i, photo) in photos.enumerated() {
            guard photo.magnitude > 0 else { continue }
            var dot: Float = 0
            vDSP_dotpr(queryEmbedding, 1, photo.embedding, 1, &dot, vDSP_Length(queryEmbedding.count))
            let similarity = dot / (queryMag * photo.magnitude)
            scores.append((i, similarity))
        }

        scores.sort { $0.score > $1.score }

        return Array(scores.prefix(limit)).enumerated().map { rank, item in
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
                persons: photo.persons
            )
        }
    }

    func addPhoto(uuid: String, filename: String, date: String, path: String,
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

        // Update in-memory
        var mag: Float = 0
        vDSP_svesq(embedding, 1, &mag, vDSP_Length(embedding.count))
        mag = sqrt(mag)

        photos.append(StoredPhoto(
            uuid: uuid, filename: filename, date: date, path: path,
            derivative: "", title: title, albums: albums, persons: persons,
            embedding: embedding, magnitude: mag
        ))
        uuidSet.insert(uuid)
    }

    // MARK: - Private

    private func createTable() throws {
        guard let db else { throw StoreError.notOpen }
        let sql = """
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
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
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

    enum StoreError: LocalizedError {
        case cannotOpen(String)
        case notOpen
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let p): return "Cannot open database at \(p)"
            case .notOpen: return "Database not open"
            case .queryFailed(let m): return "Database error: \(m)"
            }
        }
    }
}

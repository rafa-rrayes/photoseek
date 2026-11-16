import Foundation

public struct PhotoInfo: Sendable {
    public let uuid: String
    public let filename: String
    public let date: String
    public let path: String

    public init(uuid: String, filename: String, date: String, path: String) {
        self.uuid = uuid
        self.filename = filename
        self.date = date
        self.path = path
    }
}

public struct VideoInfo: Sendable {
    public let uuid: String
    public let filename: String
    public let date: String
    public let path: String
    public let durationSeconds: Double

    public init(uuid: String, filename: String, date: String, path: String, durationSeconds: Double) {
        self.uuid = uuid
        self.filename = filename
        self.date = date
        self.path = path
        self.durationSeconds = durationSeconds
    }
}

public struct VideoBytes: Sendable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

@MainActor
public protocol PhotoProvider {
    /// Returns photos that need indexing (not yet in the store).
    nonisolated func photosToIndex(excluding indexed: Set<String>) async -> [PhotoInfo]

    /// Provides JPEG data suitable for embedding from a photo.
    func imageDataForEmbedding(_ photo: PhotoInfo) async -> Data?

    /// Returns videos that need indexing (not yet in the store).
    nonisolated func videosToIndex(excluding indexed: Set<String>) async -> [VideoInfo]

    /// Provides mp4 bytes (≤ 120s) suitable for embedding from a video.
    func videoBytesForEmbedding(_ video: VideoInfo) async -> VideoBytes?

    /// Library statistics.
    nonisolated func scanLibraryStats() async -> LibraryStats
}

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

@MainActor
public protocol PhotoProvider {
    /// Returns photos that need indexing (not yet in the store).
    func photosToIndex(excluding indexed: Set<String>) async -> [PhotoInfo]

    /// Provides JPEG data suitable for embedding from a photo.
    func imageDataForEmbedding(_ photo: PhotoInfo) async -> Data?

    /// Library statistics.
    func scanLibraryStats() async -> LibraryStats
}

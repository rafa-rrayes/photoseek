import Foundation

public struct LibraryStats: Sendable {
    public var totalPhotos: Int
    public var localAvailable: Int
    public var totalVideos: Int
    public var localAvailableVideos: Int

    public var iCloudOnly: Int { max(totalPhotos - localAvailable, 0) }
    public var iCloudOnlyVideos: Int { max(totalVideos - localAvailableVideos, 0) }

    public init(totalPhotos: Int = 0, localAvailable: Int = 0,
                totalVideos: Int = 0, localAvailableVideos: Int = 0) {
        self.totalPhotos = totalPhotos
        self.localAvailable = localAvailable
        self.totalVideos = totalVideos
        self.localAvailableVideos = localAvailableVideos
    }
}

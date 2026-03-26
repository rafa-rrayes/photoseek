import Foundation

public struct LibraryStats: Sendable {
    public var totalPhotos: Int
    public var localAvailable: Int
    public var iCloudOnly: Int { max(totalPhotos - localAvailable, 0) }

    public init(totalPhotos: Int = 0, localAvailable: Int = 0) {
        self.totalPhotos = totalPhotos
        self.localAvailable = localAvailable
    }
}

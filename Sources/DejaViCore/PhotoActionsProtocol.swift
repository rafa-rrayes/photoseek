import Foundation

@MainActor
public protocol PhotoActionsProtocol {
    func openPhoto(_ uuid: String)
    func openVideo(_ uuid: String)
    func favorite(_ uuids: [String]) async -> String?
    func unfavorite(_ uuids: [String]) async -> String?
    /// Returns true only if the assets were actually deleted (on iOS the user
    /// can cancel the system confirmation dialog).
    @discardableResult
    func deletePhotos(_ uuids: [String]) async -> Bool
    func addToAlbum(_ uuids: [String], albumName: String) async -> String?
    func createAlbumAndAdd(_ uuids: [String], albumName: String) async -> String?
    func fetchAlbumNames() async -> [String]
}

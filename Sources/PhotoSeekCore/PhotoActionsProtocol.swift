import Foundation

@MainActor
public protocol PhotoActionsProtocol {
    func openPhoto(_ uuid: String)
    func favorite(_ uuids: [String]) async -> String?
    func unfavorite(_ uuids: [String]) async -> String?
    func deletePhotos(_ uuids: [String]) async
    func addToAlbum(_ uuids: [String], albumName: String) async -> String?
    func createAlbumAndAdd(_ uuids: [String], albumName: String) async -> String?
    func fetchAlbumNames() async -> [String]
}

import Foundation
import DejaViCore

/// Adapts the existing AppleScript-based PhotosActions to the PhotoActionsProtocol.
@MainActor
struct MacPhotoActionsAdapter: PhotoActionsProtocol {
    func openPhoto(_ uuid: String) {
        PhotosActions.openInPhotos(uuid)
    }

    func openVideo(_ uuid: String) {
        // Cell handles play directly via NSWorkspace; this is a fallback (e.g. AppleScript jump).
        PhotosActions.openInPhotos(uuid)
    }

    func favorite(_ uuids: [String]) async -> String? {
        PhotosActions.favorite(uuids)
    }

    func unfavorite(_ uuids: [String]) async -> String? {
        PhotosActions.unfavorite(uuids)
    }

    func deletePhotos(_ uuids: [String]) async {
        PhotosActions.deletePhotos(uuids)
    }

    func addToAlbum(_ uuids: [String], albumName: String) async -> String? {
        PhotosActions.addToAlbum(uuids, albumName: albumName)
    }

    func createAlbumAndAdd(_ uuids: [String], albumName: String) async -> String? {
        PhotosActions.createAlbumAndAdd(uuids, albumName: albumName)
    }

    func fetchAlbumNames() async -> [String] {
        PhotosActions.fetchAlbumNames()
    }
}

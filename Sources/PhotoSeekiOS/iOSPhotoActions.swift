#if os(iOS)
import Foundation
import Photos
import UIKit
import PhotoSeekCore

@MainActor
struct iOSPhotoActions: PhotoActionsProtocol {

    func openPhoto(_ uuid: String) {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    func favorite(_ uuids: [String]) async -> String? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return "No photos found" }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                assets.enumerateObjects { asset, _, _ in
                    let request = PHAssetChangeRequest(for: asset)
                    request.isFavorite = true
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func unfavorite(_ uuids: [String]) async -> String? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return "No photos found" }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                assets.enumerateObjects { asset, _, _ in
                    let request = PHAssetChangeRequest(for: asset)
                    request.isFavorite = false
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deletePhotos(_ uuids: [String]) async {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return }

        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    func addToAlbum(_ uuids: [String], albumName: String) async -> String? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return "No photos found" }

        // Find the album
        let albumOptions = PHFetchOptions()
        albumOptions.predicate = NSPredicate(format: "title == %@", albumName)
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: albumOptions)
        guard let album = albums.firstObject else { return "Album not found" }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
                request.addAssets(assets)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func createAlbumAndAdd(_ uuids: [String], albumName: String) async -> String? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return "No photos found" }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                createRequest.addAssets(assets)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func fetchAlbumNames() async -> [String] {
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var names: [String] = []
        albums.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle {
                names.append(title)
            }
        }
        return names
    }
}
#endif

#if os(iOS)
import Foundation
import Photos
import UIKit
import AVKit
import AVFoundation
import DejaViCore

@MainActor
struct iOSPhotoActions: PhotoActionsProtocol {

    func openPhoto(_ uuid: String) {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }

    func openVideo(_ uuid: String) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [uuid], options: nil)
        guard let asset = assets.firstObject else { return }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                presentPlayer(with: item)
            }
        }
    }

    func favorite(_ uuids: [String]) async -> String? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return "No items found" }

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
        guard assets.count > 0 else { return "No items found" }

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

    func deletePhotos(_ uuids: [String]) async -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return true
        } catch {
            // Thrown when the user cancels the system confirmation dialog.
            return false
        }
    }

    func addToAlbum(_ uuids: [String], albumName: String) async -> String? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uuids, options: nil)
        guard assets.count > 0 else { return "No items found" }

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
        guard assets.count > 0 else { return "No items found" }

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

@MainActor
private func presentPlayer(with item: AVPlayerItem) {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
          var top = window.rootViewController else { return }

    while let presented = top.presentedViewController {
        top = presented
    }

    let player = AVPlayer(playerItem: item)
    let vc = AVPlayerViewController()
    vc.player = player
    vc.modalPresentationStyle = .fullScreen
    top.present(vc, animated: true) {
        player.play()
    }
}
#endif

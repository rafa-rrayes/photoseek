#if os(iOS)
import Foundation
import Photos
import PhotoSeekCore

@MainActor
final class iOSPhotoProvider: PhotoProvider {

    func photosToIndex(excluding indexed: Set<String>) async -> [PhotoInfo] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)

        var photos: [PhotoInfo] = []
        fetchResult.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            guard !indexed.contains(id) else { return }
            let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
            let date = asset.creationDate?.ISO8601Format() ?? ""
            photos.append(PhotoInfo(uuid: id, filename: filename, date: date, path: ""))
        }
        return photos
    }

    func imageDataForEmbedding(_ photo: PhotoInfo) async -> Data? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [photo.uuid], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        let rawData: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }

        guard let data = rawData else { return nil }
        return EmbeddingPreparer.prepareFromData(data)
    }

    func scanLibraryStats() async -> LibraryStats {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false

        let allPhotos = PHAsset.fetchAssets(with: .image, options: options)
        let totalPhotos = allPhotos.count

        // On iOS, all fetched photos are considered locally available
        // (iCloud photos are downloaded on demand via isNetworkAccessAllowed)
        return LibraryStats(totalPhotos: totalPhotos, localAvailable: totalPhotos)
    }
}
#endif

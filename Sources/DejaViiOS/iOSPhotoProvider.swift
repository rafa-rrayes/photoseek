#if os(iOS)
import Foundation
import Photos
import AVFoundation
import DejaViCore

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

    func videosToIndex(excluding indexed: Set<String>) async -> [VideoInfo] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)

        var videos: [VideoInfo] = []
        fetchResult.enumerateObjects { asset, _, _ in
            let id = asset.localIdentifier
            guard !indexed.contains(id) else { return }
            let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
            let date = asset.creationDate?.ISO8601Format() ?? ""
            videos.append(VideoInfo(
                uuid: id,
                filename: filename,
                date: date,
                path: "",
                durationSeconds: asset.duration
            ))
        }
        return videos
    }

    func videoBytesForEmbedding(_ video: VideoInfo) async -> VideoBytes? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [video.uuid], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat

        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: avAsset)
            }
        }

        guard let urlAsset = avAsset as? AVURLAsset else { return nil }
        guard let prepared = await EmbeddingPreparer.prepareVideoSlice(from: urlAsset.url) else { return nil }
        return VideoBytes(data: prepared.data, mimeType: prepared.mimeType)
    }

    func scanLibraryStats() async -> LibraryStats {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false

        let allPhotos = PHAsset.fetchAssets(with: .image, options: options)
        let allVideos = PHAsset.fetchAssets(with: .video, options: options)

        // On iOS, all fetched items are considered locally available
        // (iCloud assets are downloaded on demand via isNetworkAccessAllowed)
        return LibraryStats(
            totalPhotos: allPhotos.count,
            localAvailable: allPhotos.count,
            totalVideos: allVideos.count,
            localAvailableVideos: allVideos.count
        )
    }
}
#endif

#if os(iOS)
import UIKit
import Photos

actor iOSImageCache {
    static let shared = iOSImageCache()

    private let cachingManager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cachingManager.allowsCachingHighQualityImages = false
        cache.totalCostLimit = 100 * 1024 * 1024
        cache.countLimit = 200
    }

    func thumbnail(for localIdentifier: String, targetSize: CGSize = CGSize(width: 300, height: 300)) async -> UIImage? {
        let key = localIdentifier as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.isSynchronous = false

        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                // Only return the final (non-degraded) image
                guard !isDegraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
}
#endif

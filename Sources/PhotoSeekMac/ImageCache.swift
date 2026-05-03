import AppKit
import ImageIO
import AVFoundation
import PhotoSeekCore

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.totalCostLimit = 100 * 1024 * 1024
        cache.countLimit = 500
    }

    func image(for path: String, targetSize: CGFloat = 300) -> NSImage? {
        let key = "\(path)_\(Int(targetSize))" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: targetSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(nsImage, forKey: key, cost: cgImage.width * cgImage.height * 4)
        return nsImage
    }

    func videoThumbnail(for path: String, targetSize: CGFloat = 300) async -> NSImage? {
        let key = "video:\(path)_\(Int(targetSize))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetSize * 2, height: targetSize * 2)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let cgImage: CGImage? = await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 0.5, preferredTimescale: 600))]) { _, image, _, _, _ in
                continuation.resume(returning: image)
            }
        }

        guard let cg = cgImage else { return nil }
        let nsImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(nsImage, forKey: key, cost: cg.width * cg.height * 4)
        return nsImage
    }

    /// Prepare an image for embedding: resize to max 768px and convert to JPEG.
    nonisolated func prepareForEmbedding(at path: String) -> Data? {
        EmbeddingPreparer.prepareFromFile(at: path)
    }
}

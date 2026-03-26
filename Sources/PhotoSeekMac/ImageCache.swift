import AppKit
import ImageIO
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

    /// Prepare an image for embedding: resize to max 768px and convert to JPEG.
    nonisolated func prepareForEmbedding(at path: String) -> Data? {
        EmbeddingPreparer.prepareFromFile(at: path)
    }

}

import Foundation
import ImageIO
import CoreGraphics

/// Prepare an image for embedding: resize to max 768px and convert to JPEG.
public enum EmbeddingPreparer {

    /// Prepare from a file path (macOS filesystem access).
    public static func prepareFromFile(at path: String) -> Data? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        return prepare(from: source)
    }

    /// Prepare from raw image data (iOS PhotoKit).
    public static func prepareFromData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return prepare(from: source)
    }

    private static func prepare(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 768,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let jpegOpts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(dest, cgImage, jpegOpts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        return mutableData as Data
    }
}

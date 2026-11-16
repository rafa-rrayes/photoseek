import AppKit
import ImageIO
import AVFoundation
import PhotoSeekCore

actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private var videoDerivativeByUUID: [String: String] = [:]
    private var scannedVideoShards: Set<String> = []

    init() {
        cache.totalCostLimit = 100 * 1024 * 1024
        cache.countLimit = 500
    }

    /// Resolve the on-disk poster JPEG that the Photos library generates for a video.
    /// Posters live under `derivatives/masters/<first-hex-char-of-uuid>/<uuid>_*.jpeg`.
    /// We scan each shard once and memoize.
    /// `uuid` may be a PHAsset localIdentifier ("<UUID>/L0/001") — we strip the suffix.
    func videoDerivativePath(forUUID rawUUID: String) -> String? {
        let uuid: String = {
            if let slash = rawUUID.firstIndex(of: "/") {
                return String(rawUUID[..<slash])
            }
            return rawUUID
        }()
        if let cached = videoDerivativeByUUID[uuid] {
            return cached.isEmpty ? nil : cached
        }
        guard let firstChar = uuid.first else { return nil }
        let shard = String(firstChar).uppercased()

        if !scannedVideoShards.contains(shard) {
            scannedVideoShards.insert(shard)
            let libraryPath = PhotosLibraryAccess.shared.libraryURL.path
            let dir = "\(libraryPath)/resources/derivatives/masters/\(shard)"
            if let names = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                for name in names {
                    let lower = name.lowercased()
                    guard lower.hasSuffix(".jpeg") || lower.hasSuffix(".jpg") || lower.hasSuffix(".heic") || lower.hasSuffix(".heif") else { continue }
                    guard let underscoreIdx = name.firstIndex(of: "_") else { continue }
                    let extractedUUID = String(name[..<underscoreIdx])
                    let full = (dir as NSString).appendingPathComponent(name)
                    if let existing = videoDerivativeByUUID[extractedUUID], !existing.isEmpty,
                       let existingSize = try? FileManager.default.attributesOfItem(atPath: existing)[.size] as? Int,
                       let newSize = try? FileManager.default.attributesOfItem(atPath: full)[.size] as? Int,
                       newSize <= existingSize {
                        continue
                    }
                    videoDerivativeByUUID[extractedUUID] = full
                }
            }
        }

        if let resolved = videoDerivativeByUUID[uuid], !resolved.isEmpty {
            return resolved
        }
        videoDerivativeByUUID[uuid] = ""
        return nil
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

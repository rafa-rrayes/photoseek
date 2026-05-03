import Foundation
import ImageIO
import CoreGraphics
import AVFoundation

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

    /// Returns video bytes for the first `maxSeconds` of the given video.
    /// If the source is a Gemini-supported container (mp4 / mov / m4v) within the limit,
    /// the original bytes are passed through unchanged. Otherwise, AVAssetExportSession
    /// trims and re-encodes to mp4 in a temp file.
    public static func prepareVideoSlice(from url: URL, maxSeconds: Double = 120) async -> (data: Data, mimeType: String)? {
        let asset = AVURLAsset(url: url)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            return nil
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        let ext = url.pathExtension.lowercased()
        let passthroughMime: String? = {
            switch ext {
            case "mp4": return "video/mp4"
            case "mov", "qt": return "video/mov"
            case "m4v": return "video/mp4"
            default: return nil
            }
        }()

        if let mime = passthroughMime,
           durationSeconds.isFinite, durationSeconds <= maxSeconds,
           let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            return (data, mime)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            return nil
        }
        session.outputURL = tempURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let cap = min(durationSeconds.isFinite ? durationSeconds : maxSeconds, maxSeconds)
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: cap, preferredTimescale: 600)
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard session.status == .completed,
              let data = try? Data(contentsOf: tempURL, options: .mappedIfSafe) else {
            return nil
        }
        return (data, "video/mp4")
    }
}

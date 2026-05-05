import Foundation
import Photos
import CoreLocation

struct AssetMetadata: Sendable {
    var originalFilename: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSizeBytes: Int64?
    var isFavorite: Bool
    var isHidden: Bool
    var location: CLLocation?
}

enum AssetMetadataLoader {
    private static func bareUUID(_ raw: String) -> String {
        if let slash = raw.firstIndex(of: "/") {
            return String(raw[..<slash])
        }
        return raw
    }

    private static func fetchAsset(_ rawUUID: String) -> PHAsset? {
        let localId = "\(bareUUID(rawUUID))/L0/001"
        let res = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
        return res.firstObject
    }

    static func load(uuid: String) -> AssetMetadata? {
        guard let asset = fetchAsset(uuid) else { return nil }

        var size: Int64?
        var name: String?
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first(where: {
            $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto
        }) ?? resources.first
        if let r = primary {
            name = r.originalFilename
            if let v = r.value(forKey: "fileSize") as? NSNumber {
                size = v.int64Value
            }
        }

        return AssetMetadata(
            originalFilename: name,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSizeBytes: size,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            location: asset.location
        )
    }

    @discardableResult
    static func setFavorite(_ favorited: Bool, uuid: String) async -> Bool {
        guard let asset = fetchAsset(uuid) else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = favorited
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }
    }
}

@MainActor
final class GeocodeCache {
    static let shared = GeocodeCache()
    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()

    func placeName(for uuid: String, location: CLLocation) async -> String? {
        if let cached = cache[uuid] { return cached }
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return nil }
            let city = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea
            let region = p.country
            let resolved: String?
            switch (city, region) {
            case (let c?, let r?): resolved = "\(c), \(r)"
            case (let c?, nil): resolved = c
            case (nil, let r?): resolved = r
            default: resolved = nil
            }
            if let r = resolved {
                cache[uuid] = r
            }
            return resolved
        } catch {
            return nil
        }
    }
}

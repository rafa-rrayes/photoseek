import AppKit
import Photos

enum PhotosActions {
    private static func mediaItemRefs(_ uuids: [String]) -> String {
        uuids.map { "media item id \"\($0)/L0/001\"" }.joined(separator: ", ")
    }

    @discardableResult
    private static func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    static func openInPhotos(_ uuid: String) {
        run("""
            tell application "Photos"
                activate
                spotlight media item id "\(uuid)/L0/001"
            end tell
            """)
    }

    static func favorite(_ uuids: [String]) {
        let refs = mediaItemRefs(uuids)
        run("""
            tell application "Photos"
                set theItems to {\(refs)}
                repeat with anItem in theItems
                    set favorite of anItem to true
                end repeat
            end tell
            """)
    }

    static func unfavorite(_ uuids: [String]) {
        let refs = mediaItemRefs(uuids)
        run("""
            tell application "Photos"
                set theItems to {\(refs)}
                repeat with anItem in theItems
                    set favorite of anItem to false
                end repeat
            end tell
            """)
    }

    static func deletePhotos(_ uuids: [String]) {
        // PhotoKit identifiers use UUID/L0/001 format
        let localIds = uuids.map { "\($0)/L0/001" }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIds, options: nil)
        guard assets.count > 0 else { return }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets)
        }, completionHandler: nil)
        // macOS will show a system confirmation dialog
    }

    static func addToAlbum(_ uuids: [String], albumName: String) {
        let refs = mediaItemRefs(uuids)
        run("""
            tell application "Photos"
                set theAlbum to album "\(albumName)"
                add {\(refs)} to theAlbum
            end tell
            """)
    }

    static func createAlbumAndAdd(_ uuids: [String], albumName: String) {
        let refs = mediaItemRefs(uuids)
        run("""
            tell application "Photos"
                set newAlbum to make new album named "\(albumName)"
                add {\(refs)} to newAlbum
            end tell
            """)
    }

    static func fetchAlbumNames() -> [String] {
        guard let script = NSAppleScript(source: """
            tell application "Photos"
                set albumNames to name of albums
                set output to ""
                repeat with aName in albumNames
                    set output to output & aName & linefeed
                end repeat
                return output
            end tell
            """) else { return [] }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let text = result.stringValue else { return [] }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

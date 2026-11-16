import Foundation

// SwiftPM's generated `Bundle.module` accessor for an executable target on macOS
// looks for the resource bundle at `Bundle.main.bundleURL/<Pkg>_<Tgt>.bundle`,
// i.e. at the .app root. macOS `codesign` rejects any .app with content at the
// root other than `Contents/`, so the shipped app places the bundle in the
// canonical `Contents/Resources/` location and uses this accessor instead.
//
// `swift run` (and tests) keep working via the `Bundle.module` fallback.
enum AppResourceBundle {
    static let bundle: Bundle = {
        let name = "PhotoSeek_PhotoSeekMac.bundle"
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent(name)
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return .module
    }()
}

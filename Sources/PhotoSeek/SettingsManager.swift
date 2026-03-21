import Foundation

@MainActor
@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    var apiKey: String = UserDefaults.standard.string(forKey: "gemini_api_key") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "gemini_api_key") }
    }

    var hasApiKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var databasePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PhotoSeek/photoseek.db").path
    }
}

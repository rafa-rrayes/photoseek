import Foundation
import Security
#if os(macOS)
import ServiceManagement
#endif

@MainActor
@Observable
public final class SettingsManager {
    public static let shared = SettingsManager()

    private static let apiKeyFile = "api-key"
    private static let legacyDefaultsKey = "gemini_api_key"
    private static let legacyKeychainAccount = "gemini-api-key"

    // MARK: - API Key (file-backed, 0600 permissions)

    public var apiKey: String {
        didSet { SecureStorage.save(key: Self.apiKeyFile, value: apiKey) }
    }

    public var hasApiKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    public func removeApiKey() {
        apiKey = ""
        SecureStorage.delete(key: Self.apiKeyFile)
    }

    // MARK: - Index Folders (macOS only, UserDefaults-backed)

    #if os(macOS)
    public var indexFolders: [String] {
        didSet { UserDefaults.standard.set(indexFolders, forKey: "index_folders") }
    }
    #endif

    // MARK: - Last Indexed Date

    public var lastIndexedDate: Date? {
        didSet { UserDefaults.standard.set(lastIndexedDate?.timeIntervalSince1970, forKey: "last_indexed_date") }
    }

    // MARK: - Display

    public var showSimilarityPercent: Bool {
        didSet { UserDefaults.standard.set(showSimilarityPercent, forKey: "show_similarity_percent") }
    }

    // MARK: - Launch at Login (macOS only)

    #if os(macOS)
    private var _isUpdatingLaunchAtLogin = false

    public var launchAtLogin: Bool = false {
        didSet {
            guard !_isUpdatingLaunchAtLogin else { return }
            _isUpdatingLaunchAtLogin = true
            defer { _isUpdatingLaunchAtLogin = false }

            if #available(macOS 13.0, *) {
                do {
                    if launchAtLogin {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Revert without re-triggering didSet
                }
            }
        }
    }
    #endif

    // MARK: - Database Path

    public var databasePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PhotoSeek/photoseek.db").path
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        // API key: load from file, migrate from Keychain or UserDefaults if needed
        if let key = SecureStorage.load(key: Self.apiKeyFile) {
            self.apiKey = key
        } else if let legacyKey = Self.migrateFromKeychain() {
            self.apiKey = legacyKey
            SecureStorage.save(key: Self.apiKeyFile, value: legacyKey)
        } else if let legacyKey = defaults.string(forKey: Self.legacyDefaultsKey), !legacyKey.isEmpty {
            self.apiKey = legacyKey
            SecureStorage.save(key: Self.apiKeyFile, value: legacyKey)
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
        } else {
            self.apiKey = ""
        }

        // Display
        self.showSimilarityPercent = defaults.bool(forKey: "show_similarity_percent")

        // Last indexed date
        let ts = defaults.double(forKey: "last_indexed_date")
        self.lastIndexedDate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil

        #if os(macOS)
        // Index folders
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultFolder = "\(home)/Pictures/Photos Library.photoslibrary/originals"
        self.indexFolders = (defaults.stringArray(forKey: "index_folders")) ?? [defaultFolder]

        // Launch at login: read current state
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        #endif
    }

    // MARK: - Migration

    private static func migrateFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.rafa.photoseek",
            kSecAttrAccount as String: legacyKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        // Clean up Keychain entry after migration
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.rafa.photoseek",
            kSecAttrAccount as String: legacyKeychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        return key
    }
}

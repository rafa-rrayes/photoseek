import Foundation

public enum SecureStorage {
    private static var configDir: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DejaVi").path
    }

    private static func path(for key: String) -> String {
        "\(configDir)/\(key)"
    }

    public static func save(key: String, value: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        let filePath = path(for: key)
        guard let data = value.data(using: .utf8) else { return }
        fm.createFile(atPath: filePath, contents: data, attributes: [.posixPermissions: 0o600])
    }

    public static func load(key: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path(for: key)),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    public static func delete(key: String) {
        try? FileManager.default.removeItem(atPath: path(for: key))
    }
}

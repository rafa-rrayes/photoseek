#if os(macOS)
import Foundation
import AppKit

/// Owns the security-scoped bookmark for the user's Photos Library bundle.
///
/// The macOS app reads the `.photoslibrary` bundle directly from disk (SQLite db,
/// derivatives, originals). That path is TCC-protected, so a Developer ID build
/// cannot read it without either Full Disk Access or an explicit user grant via
/// NSOpenPanel. This helper drives the latter and persists the resulting
/// security-scoped bookmark across launches.
///
/// Reads (`libraryURL`, `canReadLibrary`) are nonisolated so non-MainActor
/// contexts (e.g. `ImageCache` actor) can resolve the path. Mutation
/// (`requestAccess`) runs on MainActor because it presents an NSOpenPanel.
public final class PhotosLibraryAccess: @unchecked Sendable {
    public static let shared = PhotosLibraryAccess()

    private static let bookmarkKey = "photos_library_bookmark_v1"

    private let lock = NSLock()
    private var _resolvedURL: URL?
    private var _isAccessing = false

    private init() {
        resolveStoredBookmark()
    }

    // MARK: - Public API

    /// URL of the Photos Library bundle. Falls back to the conventional location
    /// in `~/Pictures` when no bookmark has been granted yet, so callers can
    /// still construct paths for existence checks.
    public var libraryURL: URL {
        lock.lock(); defer { lock.unlock() }
        if let url = _resolvedURL { return url }
        return Self.defaultLibraryURL
    }

    /// True once the user has granted access via `requestAccess()` (or a previously
    /// stored bookmark resolved successfully on launch).
    public var hasGrantedAccess: Bool {
        lock.lock(); defer { lock.unlock() }
        return _resolvedURL != nil
    }

    /// True when the SQLite database inside the library is readable right now.
    /// Use this for UX gating so we surface a clear "grant access" prompt instead
    /// of silently scanning zero items.
    public var canReadLibrary: Bool {
        let dbPath = libraryURL.appendingPathComponent("database/Photos.sqlite").path
        return FileManager.default.isReadableFile(atPath: dbPath)
    }

    /// Show an open panel asking the user to pick their Photos Library bundle.
    /// On success, persists a security-scoped bookmark and starts accessing it.
    @MainActor
    @discardableResult
    public func requestAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Select your Photos Library so DejaVi can read its contents.\nThis is normally at ~/Pictures/Photos Library.photoslibrary"
        panel.prompt = "Grant Access"

        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        let defaultLib = pictures?.appendingPathComponent("Photos Library.photoslibrary")
        if let lib = defaultLib, FileManager.default.fileExists(atPath: lib.path) {
            panel.directoryURL = pictures
            panel.nameFieldStringValue = lib.lastPathComponent
        } else {
            panel.directoryURL = pictures
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard url.pathExtension == "photoslibrary" else { return false }

        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            replaceResolved(with: url)
            return true
        } catch {
            return false
        }
    }

    /// Drop the persisted bookmark and stop accessing. Useful for diagnostics.
    public func revokeAccess() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        replaceResolved(with: nil)
    }

    // MARK: - Internals

    private static var defaultLibraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/Photos Library.photoslibrary")
    }

    private func resolveStoredBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &stale
            )
            replaceResolved(with: url)
            if stale {
                if let refreshed = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
                }
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        }
    }

    /// Atomically swap the resolved URL, stopping the previous security scope
    /// and starting the new one. Pass `nil` to revoke.
    private func replaceResolved(with newURL: URL?) {
        lock.lock()
        let previous = _resolvedURL
        let wasAccessing = _isAccessing
        _resolvedURL = newURL
        _isAccessing = false
        lock.unlock()

        if wasAccessing, let previous {
            previous.stopAccessingSecurityScopedResource()
        }

        if let newURL {
            let started = newURL.startAccessingSecurityScopedResource()
            lock.lock()
            _isAccessing = started
            lock.unlock()
        }
    }
}
#endif

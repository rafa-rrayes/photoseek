import SwiftUI
import AppKit
import PhotoSeekCore

struct PhotoInfoPopover: View {
    let result: SearchResult
    var onActionCompleted: () -> Void

    @State private var albums: [String] = []
    @State private var mode: Mode = .actions
    @State private var newAlbumName: String = ""
    @State private var creatingNewAlbum = false

    @State private var metadata: AssetMetadata?
    @State private var placeName: String?

    private enum Mode { case actions, albumPicker }

    private var typeLabel: String {
        switch result.mediaType {
        case .photo:
            return "Photo"
        case .video:
            if let s = result.durationSeconds, s > 0 {
                let total = Int(s.rounded())
                return String(format: "Video · %d:%02d", total / 60, total % 60)
            }
            return "Video"
        }
    }

    private var displayFilename: String {
        if let f = metadata?.originalFilename, !f.isEmpty {
            return f
        }
        return result.filename
    }

    private var prettyDate: String {
        guard !result.date.isEmpty else { return "" }
        let parsers: [ISO8601DateFormatter] = {
            let a = ISO8601DateFormatter()
            a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let b = ISO8601DateFormatter()
            b.formatOptions = [.withInternetDateTime]
            return [a, b]
        }()
        for p in parsers {
            if let d = p.date(from: result.date) {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                return f.string(from: d)
            }
        }
        return result.date
    }

    private var dimensionsLabel: String? {
        guard let m = metadata, m.pixelWidth > 0, m.pixelHeight > 0 else { return nil }
        let mp = Double(m.pixelWidth * m.pixelHeight) / 1_000_000
        return String(format: "%d × %d  ·  %.1f MP", m.pixelWidth, m.pixelHeight, mp)
    }

    private var fileSizeLabel: String? {
        guard let bytes = metadata?.fileSizeBytes, bytes > 0 else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private var locationLabel: String? {
        if let name = placeName, !name.isEmpty { return name }
        if let loc = metadata?.location {
            return String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
        }
        return nil
    }

    private var isFavorited: Bool { metadata?.isFavorite ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            switch mode {
            case .actions:
                infoSection
                Divider()
                actionsSection
            case .albumPicker:
                albumPickerSection
            }
        }
        .padding(14)
        .frame(width: 300)
        .task(id: result.uuid) {
            await loadMetadata()
        }
    }

    private func loadMetadata() async {
        let uuid = result.uuid
        let loaded = await Task.detached(priority: .userInitiated) {
            AssetMetadataLoader.load(uuid: uuid)
        }.value
        await MainActor.run {
            self.metadata = loaded
            self.placeName = nil
        }
        if let location = loaded?.location {
            let resolved = await GeocodeCache.shared.placeName(for: uuid, location: location)
            await MainActor.run {
                if self.metadata?.location != nil {
                    self.placeName = resolved
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayFilename)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Text(typeLabel)
                if !prettyDate.isEmpty {
                    Text("·")
                    Text(prettyDate)
                }
                if metadata?.isHidden == true {
                    Text("·")
                    Text("Hidden")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(label: "Match", value: "\(Int((result.score * 100).rounded()))%")
            if let dim = dimensionsLabel {
                infoRow(label: "Dimensions", value: dim)
            }
            if let size = fileSizeLabel {
                infoRow(label: "File Size", value: size)
            }
            if let loc = locationLabel {
                infoRow(label: "Location", value: loc)
            }
            if !result.title.isEmpty {
                infoRow(label: "Title", value: result.title)
            }
            if !result.albums.isEmpty {
                infoRow(label: "Albums", value: result.albums.joined(separator: " · "))
            }
            if !result.persons.isEmpty {
                infoRow(label: "People", value: result.persons.joined(separator: " · "))
            }
            if !result.path.isEmpty {
                infoRow(label: "Path", value: result.path, monospaced: true)
            }
        }
    }

    private func infoRow(label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(monospaced ? 2 : 3)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionsSection: some View {
        VStack(spacing: 4) {
            actionButton("Open in Photos", systemImage: "arrow.up.right.square") {
                PhotosActions.openInPhotos(result.uuid)
                onActionCompleted()
            }
            actionButton(
                isFavorited ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorited ? "heart.fill" : "heart",
                tint: isFavorited ? .pink : .primary
            ) {
                let uuid = result.uuid
                let target = !isFavorited
                Task {
                    _ = await AssetMetadataLoader.setFavorite(target, uuid: uuid)
                    await loadMetadata()
                }
            }
            actionButton("Add to Album…", systemImage: "rectangle.stack.badge.plus") {
                albums = PhotosActions.fetchAlbumNames()
                mode = .albumPicker
            }
            actionButton("Delete", systemImage: "trash", tint: .red) {
                PhotosActions.deletePhotos([result.uuid])
                onActionCompleted()
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(tint)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(.white.opacity(0.05))
        )
    }

    private var albumPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button(action: { mode = .actions; creatingNewAlbum = false; newAlbumName = "" }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer()
            }

            if creatingNewAlbum {
                HStack {
                    TextField("Album name", text: $newAlbumName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button("Create") {
                        guard !newAlbumName.isEmpty else { return }
                        PhotosActions.createAlbumAndAdd([result.uuid], albumName: newAlbumName)
                        onActionCompleted()
                    }
                    .controlSize(.small)
                    .disabled(newAlbumName.isEmpty)
                }
            } else {
                Button(action: { creatingNewAlbum = true }) {
                    Label("New Album…", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(0.05))
                )
            }

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(albums, id: \.self) { album in
                        Button(action: {
                            PhotosActions.addToAlbum([result.uuid], albumName: album)
                            onActionCompleted()
                        }) {
                            Text(album)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.05))
                        )
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
}

/// Overlay that catches right-clicks (and ctrl-clicks, since macOS routes those as rightMouseDown)
/// while letting all other mouse events fall through to the SwiftUI view beneath.
struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = RightClickNSView()
        v.onRightClick = onRightClick
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RightClickNSView)?.onRightClick = onRightClick
    }
}

private final class RightClickNSView: NSView {
    var onRightClick: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }
}

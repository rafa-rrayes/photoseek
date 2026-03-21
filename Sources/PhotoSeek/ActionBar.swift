import SwiftUI

struct ActionBar: View {
    let selectedCount: Int
    var onFavorite: () -> Void
    var onUnfavorite: () -> Void
    var onAddToAlbum: () -> Void
    var onNewAlbum: () -> Void
    var onDelete: () -> Void
    var onClearSelection: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("\(selectedCount) selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onFavorite) {
                Label("Favorite", systemImage: "heart.fill")
            }
            .help("Add to favorites")

            Button(action: onUnfavorite) {
                Label("Unfavorite", systemImage: "heart.slash")
            }
            .help("Remove from favorites")

            Button(action: onAddToAlbum) {
                Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
            }
            .help("Add to existing album")

            Button(action: onNewAlbum) {
                Label("New Album", systemImage: "folder.badge.plus")
            }
            .help("Create album with selected photos")

            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .foregroundStyle(.red)
            .help("Delete selected photos")

            Divider()
                .frame(height: 16)

            Button(action: onClearSelection) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .help("Clear selection")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct AlbumPickerSheet: View {
    let albums: [String]
    var onSelect: (String) -> Void
    var onCreateNew: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newAlbumName = ""
    @State private var showNewAlbum = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add to Album")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showNewAlbum {
                HStack {
                    TextField("Album name", text: $newAlbumName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                    Button("Create") {
                        guard !newAlbumName.isEmpty else { return }
                        onCreateNew(newAlbumName)
                        dismiss()
                    }
                    .controlSize(.small)
                    .disabled(newAlbumName.isEmpty)
                }
            } else {
                Button(action: { showNewAlbum = true }) {
                    Label("Create New Album...", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
            }

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(albums, id: \.self) { album in
                        Button(action: {
                            onSelect(album)
                            dismiss()
                        }) {
                            Text(album)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.05))
                        )
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(16)
        .frame(width: 300)
    }
}

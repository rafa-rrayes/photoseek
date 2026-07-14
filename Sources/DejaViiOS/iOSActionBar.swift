#if os(iOS)
import SwiftUI

struct iOSActionBar: View {
    let selectedCount: Int
    var onFavorite: () -> Void
    var onUnfavorite: () -> Void
    var onAddToAlbum: () -> Void
    var onDelete: () -> Void
    var onClearSelection: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 20) {
                Text("\(selectedCount) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onFavorite) {
                    Image(systemName: "heart.fill")
                }
                .help("Favorite")

                Button(action: onUnfavorite) {
                    Image(systemName: "heart.slash")
                }
                .help("Unfavorite")

                Button(action: onAddToAlbum) {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
                .help("Add to Album")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("Delete")

                Button(action: onClearSelection) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .help("Clear selection")
            }
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}
#endif

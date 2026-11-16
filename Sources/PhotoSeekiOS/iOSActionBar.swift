#if os(iOS)
import SwiftUI

/// Floating glass action bar shown while select mode is active.
/// Action buttons disable until at least one photo is selected.
struct iOSActionBar: View {
    let selectedCount: Int
    var onFavorite: () -> Void
    var onUnfavorite: () -> Void
    var onAddToAlbum: () -> Void
    var onDelete: () -> Void
    var onClearSelection: () -> Void

    private var hasSelection: Bool { selectedCount > 0 }

    var body: some View {
        HStack(spacing: 2) {
            Text(hasSelection ? "\(selectedCount) selected" : "Select photos")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 12)

            Spacer(minLength: 6)

            barButton("heart.fill", label: "Favorite", enabled: hasSelection, action: onFavorite)
            barButton("heart.slash", label: "Unfavorite", enabled: hasSelection, action: onUnfavorite)
            barButton("rectangle.stack.badge.plus", label: "Add to Album", enabled: hasSelection, action: onAddToAlbum)
            barButton("trash", label: "Delete", tint: .red, enabled: hasSelection, action: onDelete)

            Divider()
                .frame(height: 22)
                .padding(.horizontal, 4)

            barButton("xmark", label: "Cancel", size: 14, action: onClearSelection)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func barButton(_ systemImage: String,
                           label: String,
                           tint: Color = .primary,
                           size: CGFloat = 17,
                           enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
#endif

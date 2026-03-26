#if os(iOS)
import SwiftUI
import PhotoSeekCore

struct iOSPhotoCell: View {
    let result: SearchResult
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    @State private var image: UIImage?

    @ViewBuilder
    private var scoreIndicator: some View {
        if SettingsManager.shared.showSimilarityPercent {
            Text("\(Int(result.score * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        } else {
            HStack(spacing: 2) {
                switch result.score {
                case 0.4...:
                    dot(.green); dot(.green); dot(.green)
                case 0.35..<0.4:
                    dot(.yellow); dot(.yellow)
                default:
                    dot(.red)
                }
            }
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            }

            if image != nil {
                VStack(alignment: .leading, spacing: 2) {
                    scoreIndicator
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Selection checkmark
            if isSelectMode {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(.blue)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .fill(.black.opacity(0.4))
                            .frame(width: 22, height: 22)
                        Circle()
                            .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                            .frame(width: 22, height: 22)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.blue, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onTapGesture {
            if isSelectMode {
                onSelect?()
            } else {
                onOpen?()
            }
        }
        .contextMenu {
            Button { onOpen?() } label: {
                Label("Open in Photos", systemImage: "photo")
            }
            Button {
                onSelect?()
            } label: {
                Label(isSelected ? "Deselect" : "Select", systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
            }
        }
        .task(id: result.uuid) {
            // Use localIdentifier (stored in uuid) to load thumbnail
            image = await iOSImageCache.shared.thumbnail(for: result.uuid)
        }
        .onDisappear {
            image = nil // Free memory when scrolled away
        }
    }
}
#endif

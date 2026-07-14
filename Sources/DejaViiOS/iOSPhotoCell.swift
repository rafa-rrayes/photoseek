#if os(iOS)
import SwiftUI
import DejaViCore

struct iOSPhotoCell: View {
    let result: SearchResult
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    var onEnterSelectMode: (() -> Void)?
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

    private var isVideo: Bool { result.mediaType == .video }

    private var durationLabel: String? {
        guard let seconds = result.durationSeconds, seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
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
                HStack(alignment: .bottom) {
                    scoreIndicator
                    Spacer()
                    if let durationLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text(durationLabel)
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    }
                }
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

            if isSelected {
                Rectangle()
                    .fill(.black.opacity(0.25))
            }

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
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.blue, lineWidth: isSelected ? 2.5 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            if isSelectMode {
                onSelect?()
            } else {
                onOpen?()
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            guard !isSelectMode else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onEnterSelectMode?()
        }
        .task(id: result.uuid) {
            image = await iOSImageCache.shared.thumbnail(for: result.uuid)
        }
        .onDisappear {
            image = nil
        }
    }
}
#endif

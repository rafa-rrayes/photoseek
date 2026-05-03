import SwiftUI
import AppKit
import PhotoSeekCore

struct PhotoCell: View {
    let result: SearchResult
    var isSelected: Bool = false
    var isSelectMode: Bool = false
    var onSelect: (() -> Void)?
    @State private var image: NSImage?
    @State private var isHovered = false

    @ViewBuilder
    private var scoreIndicator: some View {
        if SettingsManager.shared.showSimilarityPercent {
            Text("\(Int(result.score * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        } else {
            HStack(spacing: 3) {
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
            .frame(width: 7, height: 7)
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
                Image(nsImage: image)
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
                        Text(durationLabel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            if isSelectMode {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(.blue)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .fill(.black.opacity(0.4))
                            .frame(width: 24, height: 24)
                        Circle()
                            .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.blue, lineWidth: isSelected ? 3 : 0)
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 8 : 2)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .onHover { isHovered = $0 }
        .onTapGesture {
            if isSelectMode {
                onSelect?()
            } else if isVideo, !result.path.isEmpty {
                NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
            } else {
                PhotosActions.openInPhotos(result.uuid)
            }
        }
        .help(result.filename)
        .task(id: result.uuid) {
            if isVideo, !result.path.isEmpty {
                image = await ImageCache.shared.videoThumbnail(for: result.path)
            } else {
                let loadPath = !result.derivative.isEmpty ? result.derivative : result.path
                image = await ImageCache.shared.image(for: loadPath)
            }
        }
        .contextMenu {
            if isVideo {
                Button("Play Video") {
                    if !result.path.isEmpty {
                        NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
                    }
                }
                if FileManager.default.fileExists(atPath: result.path) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.path)])
                    }
                }
            } else {
                Button("Open in Photos") { PhotosActions.openInPhotos(result.uuid) }
                if FileManager.default.fileExists(atPath: result.path) {
                    Button("Open in Preview") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.path)])
                    }
                }
            }
        }
    }
}

import SwiftUI
import AppKit

struct PhotoCell: View {
    let result: SearchResult
    @State private var image: NSImage?
    @State private var isHovered = false

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
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(result.score * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 8 : 2)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { openPhoto() }
        .help(result.filename)
        .task(id: result.uuid) {
            let loadPath = !result.derivative.isEmpty ? result.derivative : result.path
            image = await ImageCache.shared.image(for: loadPath)
        }
        .contextMenu {
            Button("Open in Photos") { openPhoto() }
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

    private func openPhoto() {
        let script = """
            tell application "Photos"
                activate
                spotlight media item id "\(result.uuid)/L0/001"
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

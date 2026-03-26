import SwiftUI
import PhotoSeekCore

struct PhotoGrid: View {
    let results: [SearchResult]
    var selectedUUIDs: Set<String> = []
    var isSelectMode: Bool = false
    var isLoadingMore: Bool = false
    var onSelect: ((String) -> Void)?
    var onReachEnd: (() -> Void)?

    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var dragCurrent: CGPoint = .zero
    @State private var cellFrames: [String: CGRect] = [:]

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(results) { result in
                        PhotoCell(
                            result: result,
                            isSelected: selectedUUIDs.contains(result.uuid),
                            isSelectMode: isSelectMode,
                            onSelect: { onSelect?(result.uuid) }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: CellFramePreferenceKey.self,
                                    value: [result.uuid: geo.frame(in: .named("grid"))]
                                )
                            }
                        )
                        .onAppear {
                            if result.uuid == results.last?.uuid {
                                onReachEnd?()
                            }
                        }
                    }
                }
                .padding(12)
                .animation(.easeOut(duration: 0.2), value: results.map(\.uuid))

                // Drag selection rectangle
                if isSelectMode && isDragging {
                    let rect = dragRect
                    Rectangle()
                        .fill(.blue.opacity(0.15))
                        .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "grid")
            .onPreferenceChange(CellFramePreferenceKey.self) { cellFrames = $0 }
            .gesture(isSelectMode ? dragGesture : nil)

            if isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
    }

    private var dragRect: CGRect {
        let x = min(dragStart.x, dragCurrent.x)
        let y = min(dragStart.y, dragCurrent.y)
        let w = abs(dragCurrent.x - dragStart.x)
        let h = abs(dragCurrent.y - dragStart.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("grid"))
            .onChanged { value in
                if !isDragging {
                    dragStart = value.startLocation
                    isDragging = true
                }
                dragCurrent = value.location

                // Select cells that intersect the drag rect
                let rect = dragRect
                for (uuid, frame) in cellFrames {
                    if rect.intersects(frame) {
                        if !selectedUUIDs.contains(uuid) {
                            onSelect?(uuid)
                        }
                    }
                }
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}

private struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

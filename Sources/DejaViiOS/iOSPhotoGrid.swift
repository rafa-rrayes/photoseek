#if os(iOS)
import SwiftUI
import DejaViCore

struct iOSPhotoGrid: View {
    let results: [SearchResult]
    var selectedUUIDs: Set<String> = []
    var isSelectMode: Bool = false
    var isLoadingMore: Bool = false
    var onSelect: ((String) -> Void)?
    var onEnterSelectMode: ((String) -> Void)?
    var onReachEnd: (() -> Void)?
    var onOpenPhoto: ((String) -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 3)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(results) { result in
                    iOSPhotoCell(
                        result: result,
                        isSelected: selectedUUIDs.contains(result.uuid),
                        isSelectMode: isSelectMode,
                        onSelect: { onSelect?(result.uuid) },
                        onOpen: { onOpenPhoto?(result.uuid) },
                        onEnterSelectMode: { onEnterSelectMode?(result.uuid) }
                    )
                    .onAppear {
                        if result.uuid == results.last?.uuid {
                            onReachEnd?()
                        }
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 6)
            .animation(.easeOut(duration: 0.2), value: results.map(\.uuid))

            if isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}
#endif

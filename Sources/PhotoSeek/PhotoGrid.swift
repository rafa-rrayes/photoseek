import SwiftUI

struct PhotoGrid: View {
    let results: [SearchResult]
    var isLoadingMore: Bool = false
    var onReachEnd: (() -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(results) { result in
                    PhotoCell(result: result)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .onAppear {
                            if result.uuid == results.last?.uuid {
                                onReachEnd?()
                            }
                        }
                }
            }
            .padding(12)
            .animation(.easeOut(duration: 0.2), value: results.map(\.uuid))

            if isLoadingMore {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
    }
}

import SwiftUI
import AppKit

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override var mouseDownCanMoveWindow: Bool { true }
    }
}

struct SearchBar: View {
    @Binding var query: String
    var isLoading: Bool
    var indexedCount: Int
    var isSelectMode: Bool
    var hasResults: Bool
    var onSelectToggle: () -> Void
    var onSettingsTap: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search your photos...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($isFocused)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }

            if hasResults {
                Button(action: onSelectToggle) {
                    Text(isSelectMode ? "Done" : "Select")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelectMode ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help(isSelectMode ? "Exit select mode" : "Select photos")
            }

            Button(action: onSettingsTap) {
                Image(systemName: "gear")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(WindowDragArea())
        .onAppear { isFocused = true }
    }
}

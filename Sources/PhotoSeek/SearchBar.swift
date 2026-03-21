import SwiftUI

struct SearchBar: View {
    @Binding var query: String
    var isLoading: Bool
    var indexedCount: Int
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
        .onAppear { isFocused = true }
    }
}
